defmodule Ysc.GoogleWallet do
  @moduledoc """
  Context module for generating Google Wallet passes.

  Generates "Add to Google Wallet" save URLs for event tickets and membership cards.
  Unlike Apple Wallet (which serves a binary file), Google Wallet uses a signed JWT
  embedded in a redirect URL. When the user taps the link, Google reads the JWT,
  creates the pass, and adds it to their Wallet app.

  Two pass types are supported:
  - **EventTicket**: one EventTicketClass per event, one EventTicketObject per ticket holder
  - **Generic** (membership): one GenericClass globally, one GenericObject per member

  Both classes and objects are embedded in the JWT ("fat JWT" approach) — Google creates
  or updates them automatically when the user first saves the pass.

  For updating existing passes (e.g. after membership renewal), `update_membership_object/2`
  sends a PATCH request to the Google Wallet REST API using a Goth OAuth2 bearer token.
  """

  import Ecto.Query, warn: false

  require Ysc.Logging

  alias Ysc.Repo
  alias Ysc.Events.Ticket
  alias Ysc.Scanning.QrToken
  alias Ysc.GoogleWallet.Credentials
  alias Ysc.Subscriptions

  @save_url_base "https://pay.google.com/gp/v/save"
  @wallet_api_base "https://walletobjects.googleapis.com/walletobjects/v1"
  @google_jwt_audience "google"

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Returns true if Google Wallet credentials are configured."
  def configured?, do: Credentials.configured?()

  @doc """
  Returns true for `:ticket` and `:membership` — both use the same service account.
  Accepts a type atom for symmetry with `Ysc.AppleWallet.configured?/1`.
  """
  def configured?(:ticket), do: Credentials.configured?()
  def configured?(:membership), do: Credentials.configured?()
  def configured?(_), do: false

  @doc """
  Generates a Google Wallet save URL for an event ticket.

  Loads the ticket (must be confirmed and belong to the given user), builds the
  EventTicketClass and EventTicketObject payloads, signs a JWT, and returns the
  save URL.

  Returns `{:ok, url}` or `{:error, :not_configured | :not_found | reason}`.
  """
  def generate_ticket_save_url(ticket_id, user_id) do
    with {:creds, {:ok, creds}} <- {:creds, Credentials.get_credentials()},
         {:ticket, %Ticket{} = ticket} <-
           {:ticket, load_ticket(ticket_id, user_id)},
         {:ok, jwt} <- sign_ticket_jwt(ticket, creds) do
      {:ok, "#{@save_url_base}/#{jwt}"}
    else
      {:creds, {:error, :not_configured}} ->
        {:error, :not_configured}

      {:ticket, nil} ->
        {:error, :not_found}

      {:error, reason} ->
        Ysc.Logging.error("Google Wallet: failed to generate ticket save URL",
          ticket_id: ticket_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Generates a Google Wallet save URL for a membership card.

  Builds the GenericClass and GenericObject payloads for the user, signs a JWT,
  and returns the save URL.

  Includes `validTimeInterval` in the object when the user has an active
  subscription with a known `current_period_end`, so the expiry date is visible
  on the card immediately after the user first adds it — regardless of whether a
  renewal PATCH has been issued yet.

  Returns `{:ok, url}` or `{:error, :not_configured | reason}`.
  """
  def generate_membership_save_url(user) do
    membership_info = membership_wallet_info(user)

    with {:creds, {:ok, creds}} <- {:creds, Credentials.get_credentials()},
         {:ok, jwt} <- sign_membership_jwt(user, creds, membership_info) do
      {:ok, "#{@save_url_base}/#{jwt}"}
    else
      {:creds, {:error, :not_configured}} ->
        {:error, :not_configured}

      {:error, reason} ->
        Ysc.Logging.error(
          "Google Wallet: failed to generate membership save URL",
          user_id: user.id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Updates an existing Google Wallet membership object via the REST API.

  Uses a Goth OAuth2 bearer token to PATCH the GenericObject for the given user,
  updating only the specified fields (e.g. expiration date after renewal).

  Returns `:ok` or `{:error, reason}`.
  """
  def update_membership_object(user_id, attrs) do
    with {:creds, {:ok, creds}} <- {:creds, Credentials.get_credentials()},
         {:token, {:ok, %Goth.Token{token: token, type: token_type}}} <-
           {:token, Goth.fetch(Ysc.Goth)} do
      object_id = membership_object_id(creds.issuer_id, user_id)
      url = "#{@wallet_api_base}/genericObject/#{URI.encode(object_id)}"

      case Req.patch(url,
             json: attrs,
             headers: [{"authorization", "#{token_type} #{token}"}]
           ) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok

        {:ok, %{status: 404}} ->
          # User has not yet added the membership pass to Google Wallet — not an error
          :ok

        {:ok, %{status: status, body: body}} ->
          Ysc.Logging.error("Google Wallet: membership object update failed",
            user_id: user_id,
            status: status,
            body: inspect(body)
          )

          {:error, {:api_error, status}}

        {:error, reason} ->
          Ysc.Logging.error(
            "Google Wallet: membership object update request failed",
            user_id: user_id,
            error: inspect(reason)
          )

          {:error, reason}
      end
    else
      {:creds, {:error, :not_configured}} ->
        {:error, :not_configured}

      {:token, {:error, reason}} ->
        Ysc.Logging.error("Google Wallet: failed to fetch Goth token",
          user_id: user_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — ticket JWT
  # ---------------------------------------------------------------------------

  defp load_ticket(ticket_id, user_id) do
    Ticket
    |> where(
      [t],
      t.id == ^ticket_id and t.user_id == ^user_id and t.status == :confirmed
    )
    |> preload([:ticket_tier, :registration, event: :cover_image])
    |> Repo.one()
  end

  defp sign_ticket_jwt(ticket, creds) do
    event = ticket.event
    issuer_id = creds.issuer_id

    ticket_class = build_event_ticket_class(event, issuer_id)
    ticket_object = build_event_ticket_object(ticket, issuer_id)

    payload = %{
      "eventTicketClasses" => [ticket_class],
      "eventTicketObjects" => [ticket_object]
    }

    sign_jwt(payload, creds)
  end

  defp build_event_ticket_class(event, issuer_id) do
    logo_url =
      YscWeb.Endpoint.url() <>
        YscWeb.Endpoint.static_path("/images/ysc_logo.webp")

    %{
      "id" => event_class_id(issuer_id, event.reference_id),
      "issuerName" => "Young Scandinavians Club",
      "reviewStatus" => "UNDER_REVIEW",
      "eventName" => localized_string(event.title),
      "venue" => build_venue(event),
      "logo" => %{
        "sourceUri" => %{"uri" => logo_url},
        "contentDescription" => localized_string("Young Scandinavians Club")
      },
      "heroImage" => event_hero_image(event)
    }
    |> compact()
  end

  defp event_hero_image(%{
         cover_image: %{optimized_image_path: path},
         title: title
       })
       when not is_nil(path) do
    %{
      "sourceUri" => %{"uri" => absolute_image_url(path)},
      "contentDescription" => localized_string(title)
    }
  end

  defp event_hero_image(%{cover_image: %{raw_image_path: path}, title: title})
       when not is_nil(path) do
    %{
      "sourceUri" => %{"uri" => absolute_image_url(path)},
      "contentDescription" => localized_string(title)
    }
  end

  defp event_hero_image(_event), do: nil

  defp absolute_image_url("http://" <> _ = url), do: url
  defp absolute_image_url("https://" <> _ = url), do: url
  defp absolute_image_url(path), do: YscWeb.Endpoint.url() <> path

  defp build_venue(%{location_name: name, place_id: place_id})
       when not is_nil(name) and is_binary(place_id) and place_id != "" do
    %{
      "name" => localized_string(String.trim(name)),
      "placeId" => String.trim(place_id)
    }
  end

  defp build_venue(%{location_name: name, address: address})
       when not is_nil(name) and is_binary(address) and address != "" do
    %{
      "name" => localized_string(String.trim(name)),
      "address" => localized_string(String.trim(address))
    }
  end

  defp build_venue(_event), do: nil

  defp build_event_ticket_object(ticket, issuer_id) do
    event = ticket.event
    qr_token = QrToken.sign_ticket(ticket.id)

    holder_name =
      case ticket.registration do
        %{first_name: first, last_name: last} when not is_nil(first) ->
          "#{first} #{last}"

        _ ->
          nil
      end

    text_modules =
      [
        %{
          "header" => "Reference",
          "body" => ticket.reference_id,
          "id" => "reference"
        },
        if(event.start_date,
          do: %{
            "header" => "Date",
            "body" => format_event_date(event.start_date, event.start_time),
            "id" => "date"
          }
        )
      ]
      |> Enum.reject(&is_nil/1)

    %{
      "id" => ticket_object_id(issuer_id, ticket.id),
      "classId" => event_class_id(issuer_id, event.reference_id),
      "state" => "ACTIVE",
      "ticketHolderName" => holder_name,
      "ticketNumber" => ticket.reference_id,
      "ticketType" => localized_string(ticket.ticket_tier.name),
      "barcode" => %{
        "type" => "QR_CODE",
        "value" => qr_token,
        "alternateText" => ticket.reference_id
      },
      "textModulesData" => text_modules
    }
    |> compact()
  end

  # ---------------------------------------------------------------------------
  # Private — membership JWT
  # ---------------------------------------------------------------------------

  defp sign_membership_jwt(user, creds, membership_info) do
    issuer_id = creds.issuer_id
    membership_class = build_generic_class(issuer_id)
    membership_object = build_generic_object(user, issuer_id, membership_info)

    payload = %{
      "genericClasses" => [membership_class],
      "genericObjects" => [membership_object]
    }

    sign_jwt(payload, creds)
  end

  defp build_generic_class(issuer_id) do
    logo_url =
      YscWeb.Endpoint.url() <>
        YscWeb.Endpoint.static_path("/images/ysc_logo.webp")

    %{
      "id" => membership_class_id(issuer_id),
      "issuerName" => "Young Scandinavians Club",
      "reviewStatus" => "UNDER_REVIEW",
      "hexBackgroundColor" => "#1b1b52",
      "logo" => %{
        "sourceUri" => %{"uri" => logo_url},
        "contentDescription" => localized_string("Young Scandinavians Club")
      }
    }
  end

  defp build_generic_object(user, issuer_id, membership_info) do
    qr_token = QrToken.sign_membership(user.id)
    member_name = "#{user.first_name} #{user.last_name}"

    %{state: pass_state, period_start: period_start, period_end: period_end} =
      membership_info

    valid_time_interval =
      case {period_start, period_end} do
        {_, %DateTime{} = dt_end} ->
          interval = %{"end" => %{"date" => DateTime.to_iso8601(dt_end)}}

          case period_start do
            %DateTime{} = dt_start ->
              Map.put(interval, "start", %{
                "date" => DateTime.to_iso8601(dt_start)
              })

            _ ->
              interval
          end

        _ ->
          nil
      end

    %{
      "id" => membership_object_id(issuer_id, user.id),
      "classId" => membership_class_id(issuer_id),
      "state" => pass_state,
      "cardTitle" => localized_string("Young Scandinavians Club"),
      "header" => localized_string(member_name),
      "subheader" => localized_string("Member"),
      "barcode" => %{
        "type" => "QR_CODE",
        "value" => qr_token,
        "alternateText" => "YSC Member"
      },
      "validTimeInterval" => valid_time_interval
    }
    |> compact()
  end

  defp membership_wallet_info(user) do
    case Subscriptions.get_active_subscription(user) do
      %{
        current_period_start: period_start,
        current_period_end: %DateTime{} = period_end
      } ->
        %{state: "ACTIVE", period_start: period_start, period_end: period_end}

      %{} ->
        # Active subscription exists but has no period_end (e.g. lifetime membership)
        %{state: "ACTIVE", period_start: nil, period_end: nil}

      nil ->
        %{state: "INACTIVE", period_start: nil, period_end: nil}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — JWT signing
  # ---------------------------------------------------------------------------

  defp sign_jwt(payload, creds) do
    signer = Joken.Signer.create("RS256", %{"pem" => creds.private_key})

    claims = %{
      "iss" => creds.client_email,
      "aud" => @google_jwt_audience,
      "typ" => "savetowallet",
      "iat" => System.os_time(:second),
      "payload" => payload
    }

    case Joken.generate_and_sign(%{}, claims, signer) do
      {:ok, jwt, _claims} ->
        {:ok, jwt}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — object ID helpers
  # ---------------------------------------------------------------------------

  defp event_class_id(issuer_id, event_reference_id),
    do: "#{issuer_id}.event-#{event_reference_id}"

  defp ticket_object_id(issuer_id, ticket_id),
    do: "#{issuer_id}.ticket-#{ticket_id}"

  defp membership_class_id(issuer_id),
    do: "#{issuer_id}.ysc-membership"

  defp membership_object_id(issuer_id, user_id),
    do: "#{issuer_id}.membership-#{user_id}"

  # ---------------------------------------------------------------------------
  # Private — helpers
  # ---------------------------------------------------------------------------

  defp localized_string(value) do
    %{
      "defaultValue" => %{
        "language" => "en-US",
        "value" => value
      }
    }
  end

  defp format_event_date(nil, _time), do: "TBD"

  defp format_event_date(start_date, start_time) do
    date_str = Calendar.strftime(start_date, "%a, %b %-d, %Y")

    if start_time do
      "#{date_str} at #{Calendar.strftime(start_time, "%-I:%M %p")}"
    else
      date_str
    end
  end

  defp compact(map) when is_map(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
