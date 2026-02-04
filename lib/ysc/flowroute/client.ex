defmodule Ysc.Flowroute.Client do
  @moduledoc """
  FlowRoute API client for sending SMS messages.

  This client handles Basic Auth authentication and provides functions to send
  SMS messages via the FlowRoute API.

  ## Configuration

  The following environment variables are required:
  - `FLOWROUTE_ACCESS_KEY` - Your FlowRoute API access key (username)
  - `FLOWROUTE_SECRET_KEY` - Your FlowRoute API secret key (password)
  - `FLOWROUTE_FROM_NUMBER` - Your FlowRoute phone number (international format with `+` prefix, e.g., "+12061231234", or 11-digit North American format, e.g., "12061231234")

  Optional environment variables:
  - `FLOWROUTE_FORCE_ENABLE` - Set to `"true"` or `"1"` to force SMS sending on even in dev/test environments

  ## Usage

      alias Ysc.Flowroute.Client

      # Send an SMS
      Client.send_sms(
        to: "12065551234",
        body: "Hello, this is a test message"
      )

  ## Environment Behavior

  In lower environments (dev, test, sandbox), the client operates as a no-op:
  - No actual API requests are sent
  - A fake successful response is returned
  - This prevents accidental SMS sends during development

  You can force SMS sending on in lower environments by setting `FLOWROUTE_FORCE_ENABLE=true`
  or `FLOWROUTE_FORCE_ENABLE=1`. This is useful for testing actual SMS delivery.

  ## SMS Limitations

  - You can only send SMS from a phone number registered on your FlowRoute account
  - Maximum sending rate: 5 SMS per second
  - FlowRoute cannot guarantee delivery to phone numbers not enabled for SMS
  - Smart quotes are known to cause errors - use neutral (vertical) quotes
  """

  require Logger

  @api_base_url "https://api.flowroute.com/v2.1"
  @api_endpoint "/messages"

  @doc """
  Sends an SMS message via FlowRoute.

  ## Parameters

    - `to` (required) - Recipient phone number in international format with `+` prefix (e.g., "+12065551234") or 11-digit North American format (e.g., "12065551234")
    - `body` (required) - Message content
    - `from` (optional) - Sender phone number. Defaults to configured `FLOWROUTE_FROM_NUMBER`
    - `is_mms` (optional) - Whether this is an MMS message (default: false)
    - `media_urls` (optional) - Array of media URLs for MMS (default: [])
    - `user_id` (optional) - User ID for linking to user
    - `message_idempotency_id` (optional) - Message idempotency entry ID for linking

  ## Returns

    - `{:ok, %{id: message_id}}` - Success with message record ID
    - `{:error, reason}` - Error with reason

  ## Examples

      # Send SMS with default from number
      {:ok, %{id: "mdr2-39cadeace66e11e7aff806cd7f24ba2d"}} =
        Client.send_sms(
          to: "+12065551234",
          body: "Hello from YSC!"
        )

      # Send SMS with custom from number
      {:ok, %{id: "mdr2-..."}} =
        Client.send_sms(
          to: "+12065551234",
          from: "+12061231234",
          body: "Hello from YSC!"
        )
  """
  @spec send_sms(keyword()) :: {:ok, map()} | {:error, atom() | String.t()}
  def send_sms(opts) do
    # In noop environments (dev, test, sandbox), skip from_number config requirement
    # but still validate phone format and body to catch bugs early
    if noop_environment?() do
      with {:ok, to_raw} <- Keyword.fetch(opts, :to),
           {:ok, body} <- Keyword.fetch(opts, :body),
           {:ok, to} <- normalize_phone_number(to_raw),
           :ok <- validate_body(body) do
        # Use provided from number, configured from number, or a default fake number for noop mode
        from_raw =
          Keyword.get(opts, :from) ||
            case get_from_number(opts) do
              {:ok, number} -> number
              _ -> "+12061231234"
            end

        # Normalize and validate from number format but don't require it to be configured
        case normalize_phone_number(from_raw) do
          {:ok, from} ->
            handle_noop_response(to, from, body, opts)

          {:error, reason} ->
            {:error, reason}
        end
      else
        :error ->
          {:error, :missing_required_parameter}

        {:error, reason} ->
          {:error, reason}
      end
    else
      # In production, validate everything including from_number configuration
      with {:ok, to_raw} <- Keyword.fetch(opts, :to),
           {:ok, body} <- Keyword.fetch(opts, :body),
           {:ok, from_raw} <- get_from_number(opts),
           {:ok, to} <- normalize_phone_number(to_raw),
           {:ok, from} <- normalize_phone_number(from_raw),
           :ok <- validate_body(body) do
        is_mms = Keyword.get(opts, :is_mms, false)
        media_urls = Keyword.get(opts, :media_urls, [])
        send_sms_request(to, from, body, is_mms, media_urls, opts)
      else
        :error ->
          {:error, :missing_required_parameter}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Private functions

  defp send_sms_request(to, from, body, is_mms, media_urls, opts) do
    with {:ok, access_key} <- get_access_key(),
         {:ok, secret_key} <- get_secret_key() do
      url = "#{@api_base_url}#{@api_endpoint}"
      headers = build_headers(access_key, secret_key)
      request_body = build_request_body(to, from, body, is_mms, media_urls)

      Logger.info("Sending SMS via FlowRoute",
        to: to,
        from: from,
        body_length: String.length(body),
        is_mms: is_mms
      )

      request = Finch.build(:post, url, headers, Jason.encode!(request_body))

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: 202, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, %{"data" => %{"id" => message_id}}} ->
              Logger.info("Successfully sent SMS via FlowRoute",
                to: to,
                from: from,
                message_id: message_id
              )

              # Store SMS message in database
              store_sms_message(
                message_id,
                to,
                from,
                body,
                is_mms,
                media_urls,
                opts
              )

              {:ok, %{id: message_id}}

            {:ok, data} ->
              Logger.warning("Unexpected FlowRoute response format",
                to: to,
                from: from,
                response: inspect(data)
              )

              message_id = extract_message_id(data)

              store_sms_message(
                message_id,
                to,
                from,
                body,
                is_mms,
                media_urls,
                opts
              )

              {:ok, %{id: message_id}}

            {:error, error} ->
              Logger.error("Failed to parse FlowRoute response",
                to: to,
                from: from,
                error: inspect(error),
                response_body: response_body
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          Logger.error("FlowRoute API returned error status",
            to: to,
            from: from,
            status: status,
            response: response_body
          )

          error_reason = parse_error_response(response_body)
          {:error, error_reason}

        {:error, error} ->
          Logger.error("Failed to send SMS via FlowRoute",
            to: to,
            from: from,
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  defp handle_noop_response(to, from, body, opts) do
    # Generate a fake message ID in the same format as FlowRoute
    fake_message_id = "mdr2-#{generate_fake_id()}"

    Logger.info("FlowRoute SMS no-op (lower environment)",
      to: to,
      from: from,
      body_length: String.length(body),
      fake_message_id: fake_message_id,
      environment: get_environment()
    )

    # Store SMS message in database even in no-op mode
    is_mms = Keyword.get(opts, :is_mms, false)
    media_urls = Keyword.get(opts, :media_urls, [])
    store_sms_message(fake_message_id, to, from, body, is_mms, media_urls, opts)

    {:ok, %{id: fake_message_id}}
  end

  defp build_headers(access_key, secret_key) do
    # Basic Auth: Base64(access_key:secret_key)
    auth_header = Base.encode64("#{access_key}:#{secret_key}")

    [
      {"Content-Type", "application/vnd.api+json"},
      {"Accept", "application/vnd.api+json"},
      {"Authorization", "Basic #{auth_header}"}
    ]
  end

  defp build_request_body(to, from, body, is_mms, media_urls) do
    attributes = %{
      "to" => to,
      "from" => from,
      "body" => body
    }

    attributes =
      if is_mms do
        attributes
        |> Map.put("is_mms", "true")
        |> Map.put("media_urls", media_urls)
      else
        attributes
      end

    %{
      "data" => %{
        "type" => "message",
        "attributes" => attributes
      }
    }
  end

  defp store_sms_message(message_id, to, from, body, is_mms, media_urls, opts) do
    try do
      attrs = %{
        provider: :flowroute,
        provider_message_id: message_id,
        to: to,
        from: from,
        body: body,
        is_mms: is_mms,
        media_urls: media_urls,
        status: :sent,
        user_id: Keyword.get(opts, :user_id),
        message_idempotency_id: Keyword.get(opts, :message_idempotency_id)
      }

      case Ysc.Sms.create_sms_message(attrs) do
        {:ok, _sms_message} ->
          Logger.debug("Stored SMS message in database",
            provider: :flowroute,
            provider_message_id: message_id
          )

        {:error, changeset} ->
          # Log but don't fail - this is not critical
          Logger.warning("Failed to store SMS message in database",
            provider: :flowroute,
            provider_message_id: message_id,
            errors: inspect(changeset.errors)
          )
      end
    rescue
      error ->
        # Log but don't fail - this is not critical
        Logger.warning("Error storing SMS message in database",
          provider: :flowroute,
          provider_message_id: message_id,
          error: Exception.message(error)
        )
    end
  end

  defp get_access_key do
    case Application.get_env(:ysc, :flowroute)[:access_key] do
      nil -> {:error, :flowroute_access_key_not_configured}
      key when is_binary(key) -> {:ok, key}
      _ -> {:error, :flowroute_access_key_not_configured}
    end
  end

  defp get_secret_key do
    case Application.get_env(:ysc, :flowroute)[:secret_key] do
      nil -> {:error, :flowroute_secret_key_not_configured}
      key when is_binary(key) -> {:ok, key}
      _ -> {:error, :flowroute_secret_key_not_configured}
    end
  end

  defp get_from_number(opts) do
    case Keyword.get(opts, :from) do
      nil ->
        case Application.get_env(:ysc, :flowroute)[:from_number] do
          nil -> {:error, :flowroute_from_number_not_configured}
          number when is_binary(number) -> {:ok, number}
          _ -> {:error, :flowroute_from_number_not_configured}
        end

      from ->
        {:ok, from}
    end
  end

  defp normalize_phone_number(number) when is_binary(number) do
    # Remove any whitespace
    number = String.trim(number)

    cond do
      # Already in international format with +
      String.starts_with?(number, "+") ->
        # Validate it has at least a country code (minimum 2 digits after +)
        if Regex.match?(~r/^\+\d{2,}$/, number) do
          {:ok, number}
        else
          {:error, :invalid_phone_number_format}
        end

      # 11-digit North American format (e.g., 12065551234) - add +
      Regex.match?(~r/^1\d{10}$/, number) ->
        {:ok, "+#{number}"}

      # 10-digit North American format (e.g., 2065551234) - add +1
      Regex.match?(~r/^\d{10}$/, number) ->
        {:ok, "+1#{number}"}

      true ->
        {:error, :invalid_phone_number_format}
    end
  end

  defp normalize_phone_number(_), do: {:error, :invalid_phone_number_format}

  defp validate_body(body) when is_binary(body) do
    if String.length(body) > 0 do
      :ok
    else
      {:error, :empty_message_body}
    end
  end

  defp validate_body(_), do: {:error, :invalid_message_body}

  defp parse_error_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"errors" => [%{"detail" => detail} | _]}} ->
        detail

      {:ok, %{"errors" => errors}} when is_list(errors) ->
        Enum.map_join(errors, ", ", &Map.get(&1, "detail", "Unknown error"))

      {:ok, data} ->
        inspect(data)

      {:error, _} ->
        response_body
    end
  end

  defp extract_message_id(data) do
    case get_in(data, ["data", "id"]) do
      nil -> "mdr2-unknown"
      id -> id
    end
  end

  defp noop_environment? do
    # Check if SMS sending is forced on via environment variable
    case System.get_env("FLOWROUTE_FORCE_ENABLE") do
      "true" ->
        false

      "1" ->
        false

      _ ->
        env = get_environment()
        env in [:dev, :test, :sandbox, :development]
    end
  end

  defp get_environment do
    Ysc.Env.current()
  end

  defp generate_fake_id do
    # Generate a fake ID similar to FlowRoute's format
    # Format: mdr2-{hex_string}
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
    |> String.downcase()
  end
end
