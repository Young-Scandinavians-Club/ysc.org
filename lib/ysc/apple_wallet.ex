defmodule Ysc.AppleWallet do
  @moduledoc """
  Context module for generating Apple Wallet (.pkpass) passes.

  Generates event ticket passes and membership card passes signed
  with the Apple-issued certificates managed by `Ysc.AppleWallet.CertManager`.
  """

  # Passbook.generate/7 has a catch-all clause typed as {:error, :invalid_data} which
  # Dialyzer uses as the return type because it cannot resolve :zip.create through the
  # Erlang boundary. Suppress the resulting false-positive pattern_match warnings.
  @dialyzer {:nowarn_function,
             generate_ticket_pass: 2, generate_membership_pass: 1}

  # Register @sobelow_skip so the Elixir compiler does not warn about the attribute
  # being unused (Sobelow consumes it from the source AST, not via Elixir reflection).
  Module.register_attribute(__MODULE__, :sobelow_skip, accumulate: true)

  import Ecto.Query, warn: false

  require Ysc.Logging

  alias Ysc.Repo
  alias Ysc.Events.Ticket
  alias Ysc.Scanning.QrToken
  alias Ysc.AppleWallet.CertManager

  # Resolve under priv at runtime — Application.app_dir in module attributes is
  # expanded at compile time and would bake in the builder's _build/... path,
  # which does not exist inside a release image.

  @doc """
  Returns true if the given pass type is configured and ready to generate passes.
  """
  def configured?(type), do: CertManager.configured?(type)

  @doc """
  Generates an Apple Wallet event ticket pass for a given ticket.

  Returns `{:ok, binary}` where binary is the .pkpass file contents,
  or `{:error, reason}`.
  """
  # File.read/rm operate on a path returned by Passbook.generate, always within System.tmp_dir!()
  @sobelow_skip ["Traversal.FileModule"]
  def generate_ticket_pass(ticket_id, user_id) do
    with {:certs, {:ok, certs}} <- {:certs, CertManager.get_ticket_certs()},
         {:ticket, %Ticket{} = ticket} <-
           {:ticket, load_ticket(ticket_id, user_id)},
         {:ok, pkpass_path} <- build_ticket_pass(ticket, certs) do
      result =
        try do
          File.read(pkpass_path)
        after
          File.rm(pkpass_path)
        end

      case result do
        {:ok, binary} ->
          {:ok, binary}

        {:error, reason} ->
          Ysc.Logging.error("Apple Wallet: failed to read ticket pkpass",
            ticket_id: ticket_id,
            error: reason
          )

          {:error, reason}
      end
    else
      {:certs, {:error, :not_configured}} ->
        {:error, :not_configured}

      {:ticket, nil} ->
        {:error, :not_found}

      {:error, reason} ->
        Ysc.Logging.error("Apple Wallet: failed to generate ticket pass",
          ticket_id: ticket_id,
          error: reason
        )

        {:error, reason}
    end
  end

  @doc """
  Generates an Apple Wallet membership card pass for a given user.

  Returns `{:ok, binary}` where binary is the .pkpass file contents,
  or `{:error, reason}`.
  """
  # File.read/rm operate on a path returned by Passbook.generate, always within System.tmp_dir!()
  @sobelow_skip ["Traversal.FileModule"]
  def generate_membership_pass(user) do
    with {:certs, {:ok, certs}} <- {:certs, CertManager.get_membership_certs()},
         {:ok, pkpass_path} <- build_membership_pass(user, certs) do
      result =
        try do
          File.read(pkpass_path)
        after
          File.rm(pkpass_path)
        end

      case result do
        {:ok, binary} ->
          {:ok, binary}

        {:error, reason} ->
          Ysc.Logging.error("Apple Wallet: failed to read membership pkpass",
            user_id: user.id,
            error: reason
          )

          {:error, reason}
      end
    else
      {:certs, {:error, :not_configured}} ->
        {:error, :not_configured}

      {:error, reason} ->
        Ysc.Logging.error("Apple Wallet: failed to generate membership pass",
          user_id: user.id,
          error: reason
        )

        {:error, reason}
    end
  end

  # --- Private ---

  defp load_ticket(ticket_id, user_id) do
    Ticket
    |> where(
      [t],
      t.id == ^ticket_id and t.user_id == ^user_id and t.status == :confirmed
    )
    |> preload([:ticket_tier, :registration, event: :cover_image])
    |> Repo.one()
  end

  # File.rm cleanup operates on paths generated internally via System.tmp_dir!() in download_image_to_tmp/1
  @sobelow_skip ["Traversal.FileModule"]
  defp build_ticket_pass(ticket, certs) do
    config = Application.get_env(:ysc, :apple_wallet) || []
    ticket_config = Keyword.get(config, :ticket) || %{}
    pass_type_id = Map.get(ticket_config, :pass_type_id, "")
    team_id = Keyword.get(config, :team_id, "")
    org_name = Keyword.get(config, :org_name, "YSC")

    event = ticket.event
    qr_token = QrToken.sign_ticket(ticket.id)

    holder_name =
      case ticket.registration do
        %{first_name: first, last_name: last} when not is_nil(first) ->
          "#{first} #{last}"

        _ ->
          nil
      end

    event_date = format_event_date_for_pass(event.start_date, event.start_time)

    secondary_fields =
      [
        %Passbook.LowerLevel.Field{
          key: "date",
          label: "Date",
          value: event_date
        },
        if(event.location_name,
          do: %Passbook.LowerLevel.Field{
            key: "location",
            label: "Location",
            value: event.location_name
          }
        )
      ]
      |> Enum.reject(&is_nil/1)

    auxiliary_fields =
      [
        %Passbook.LowerLevel.Field{
          key: "tier",
          label: "Ticket Type",
          value: ticket.ticket_tier.name
        },
        if(holder_name,
          do: %Passbook.LowerLevel.Field{
            key: "holder",
            label: "Ticket Holder",
            value: holder_name
          }
        )
      ]
      |> Enum.reject(&is_nil/1)

    back_fields =
      [
        %Passbook.LowerLevel.Field{
          key: "reference",
          label: "Reference",
          value: ticket.reference_id
        },
        if(event.address,
          do: %Passbook.LowerLevel.Field{
            key: "address",
            label: "Address",
            value: event.address
          }
        )
      ]
      |> Enum.reject(&is_nil/1)

    pass = %Passbook.Pass{
      description: event.title,
      organization_name: org_name,
      pass_type_identifier: pass_type_id,
      serial_number: ticket.id,
      team_identifier: team_id,
      background_color: "rgb(4, 120, 87)",
      foreground_color: "rgb(255, 255, 255)",
      label_color: "rgb(255, 255, 255)",
      logo_text: org_name,
      barcode: %Passbook.LowerLevel.Barcode{
        format: :qr,
        message: qr_token,
        alt_text: ticket.reference_id
      },
      event_ticket: %Passbook.PassStructure{
        primary_fields: [
          %Passbook.LowerLevel.Field{
            key: "event",
            label: "Event",
            value: event.title
          }
        ],
        secondary_fields: secondary_fields,
        auxiliary_fields: auxiliary_fields,
        back_fields: back_fields
      }
    }

    base_files = [
      "icon.png": apple_wallet_icon("icon.png"),
      "icon@2x.png": apple_wallet_icon("icon@2x.png"),
      "icon@3x.png": apple_wallet_icon("icon@3x.png"),
      "logo.png": apple_wallet_icon("logo.png"),
      "logo@2x.png": apple_wallet_icon("logo@2x.png")
    ]

    {strip_files, strip_tmp_paths} = build_strip_files(event.cover_image)
    icon_files = base_files ++ strip_files

    result =
      passbook_generate(
        pass,
        icon_files,
        certs,
        "ticket-#{ticket.reference_id}"
      )

    Enum.each(strip_tmp_paths, &File.rm/1)
    result
  end

  defp build_membership_pass(user, certs) do
    config = Application.get_env(:ysc, :apple_wallet) || []
    membership_config = Keyword.get(config, :membership) || %{}
    pass_type_id = Map.get(membership_config, :pass_type_id, "")
    team_id = Keyword.get(config, :team_id, "")
    org_name = Keyword.get(config, :org_name, "YSC")

    qr_token = QrToken.sign_membership(user.id)
    member_name = "#{user.first_name} #{user.last_name}"

    pass = %Passbook.Pass{
      description: "#{org_name} Membership",
      organization_name: org_name,
      pass_type_identifier: pass_type_id,
      serial_number: user.id,
      team_identifier: team_id,
      background_color: "rgb(24, 24, 27)",
      foreground_color: "rgb(255, 255, 255)",
      label_color: "rgb(161, 161, 170)",
      logo_text: org_name,
      barcode: %Passbook.LowerLevel.Barcode{
        format: :qr,
        message: qr_token,
        alt_text: "#{org_name} Member"
      },
      generic: %Passbook.PassStructure{
        primary_fields: [
          %Passbook.LowerLevel.Field{
            key: "member",
            label: "Member",
            value: member_name
          }
        ],
        secondary_fields: [
          %Passbook.LowerLevel.Field{
            key: "org",
            label: "Organization",
            value: org_name
          }
        ]
      }
    }

    icon_files = [
      "icon.png": apple_wallet_icon("icon.png"),
      "icon@2x.png": apple_wallet_icon("icon@2x.png"),
      "icon@3x.png": apple_wallet_icon("icon@3x.png"),
      "logo.png": apple_wallet_icon("logo.png"),
      "logo@2x.png": apple_wallet_icon("logo@2x.png")
    ]

    passbook_generate(pass, icon_files, certs, "membership-#{user.id}")
  end

  defp passbook_generate(pass, icon_files, certs, pass_name) do
    case Application.get_env(:ysc, :apple_wallet_passbook_generator) do
      mod when is_atom(mod) ->
        mod.generate(pass, icon_files, certs, pass_name)

      _ ->
        Passbook.generate(
          pass,
          icon_files,
          certs.wwdr,
          certs.cert,
          certs.key,
          certs.password,
          target_path: System.tmp_dir!() <> "/",
          pass_name: pass_name
        )
    end
  end

  defp apple_wallet_icon(filename) when is_binary(filename) do
    Path.join([:code.priv_dir(:ysc), "apple_wallet", "icons", filename])
  end

  # Downloads the event cover image and returns strip file entries for the pass.
  # Returns {files_keyword_list, tmp_paths_to_cleanup}.
  # Uses optimized_image_path for @2x and thumbnail_path for @1x when available.
  defp build_strip_files(nil), do: {[], []}

  defp build_strip_files(%Ysc.Media.Image{} = cover_image) do
    optimized_url = cover_image.optimized_image_path
    thumbnail_url = cover_image.thumbnail_path

    case download_image_to_tmp(optimized_url || thumbnail_url) do
      {:ok, path_2x} ->
        case download_image_to_tmp(thumbnail_url || optimized_url) do
          {:ok, path_1x} ->
            {[
               "strip.png": path_1x,
               "strip@2x.png": path_2x
             ], [path_1x, path_2x]}

          :error ->
            {["strip@2x.png": path_2x], [path_2x]}
        end

      :error ->
        {[], []}
    end
  end

  @strip_download_timeout_ms 2_000

  defp download_image_to_tmp(nil), do: :error

  # tmp_path is constructed from System.tmp_dir!() + random hex, not user input
  @sobelow_skip ["Traversal.FileModule"]
  defp download_image_to_tmp(url) do
    task =
      Task.async(fn ->
        Req.get(url, receive_timeout: @strip_download_timeout_ms)
      end)

    req_result =
      case Task.yield(task, @strip_download_timeout_ms) || Task.shutdown(task) do
        {:ok, result} -> result
        _ -> :timeout
      end

    case req_result do
      {:ok, %{status: 200, body: body}}
      when is_binary(body) and byte_size(body) > 0 ->
        tmp_path =
          Path.join(
            System.tmp_dir!(),
            "aw_strip_#{:crypto.strong_rand_bytes(8) |> Base.encode16()}.png"
          )

        case File.write(tmp_path, body) do
          :ok -> {:ok, tmp_path}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp format_event_date_for_pass(nil, _time), do: "TBD"

  defp format_event_date_for_pass(start_date, start_time) do
    date_str = Calendar.strftime(start_date, "%a, %b %-d, %Y")

    if start_time do
      "#{date_str} at #{Calendar.strftime(start_time, "%-I:%M %p")}"
    else
      date_str
    end
  end
end
