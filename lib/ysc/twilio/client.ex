defmodule Ysc.Twilio.Client do
  @moduledoc """
  Twilio API client for sending SMS to international (Nordic) numbers.

  FlowRoute is cheaper but only delivers to US/Canadian numbers, so numbers in
  Sweden, Norway, Denmark, Finland and Iceland are routed through Twilio. See
  `Ysc.Extensions.PhoneNumber.sms_provider/1` for the routing decision.

  ## Configuration

  - `TWILIO_ACCOUNT_SID` - Twilio Account SID (`AC...`)
  - `TWILIO_AUTH_TOKEN` - Twilio Auth Token

  Sender (one of, the messaging service wins when both are set):
  - `TWILIO_MESSAGING_SERVICE_SID` - Messaging Service SID (`MG...`)
  - `TWILIO_SENDER` - Alphanumeric sender ID (e.g. `YSC`) or a Twilio number in
    E.164 format

  Optional:
  - `TWILIO_FORCE_ENABLE` - `"true"` or `"1"` forces real sends in dev/test/sandbox

  ## Environment Behavior

  In lower environments (dev, test, sandbox) the client is a no-op: no request
  is made and a fake `SM...` id is returned. Set `TWILIO_FORCE_ENABLE=true` to
  send for real.
  """

  require Ysc.Logging

  @api_base_url "https://api.twilio.com/2010-04-01"

  @doc """
  Sends an SMS via Twilio.

  ## Options

    - `:to` (required) - Recipient in E.164 format (`+46701234567`); a missing
      `+` is added since the notifier passes digits only
    - `:body` (required) - Message content
    - `:from` (optional) - Sender override, otherwise configured sender
    - `:user_id` (optional) - Linked user
    - `:message_idempotency_id` (optional) - Linked idempotency entry

  Returns `{:ok, %{id: sid}}` or `{:error, reason}`.
  """
  @spec send_sms(keyword()) :: {:ok, map()} | {:error, atom() | String.t()}
  def send_sms(opts) do
    with {:ok, to_raw} <- fetch_opt(opts, :to),
         {:ok, body} <- fetch_opt(opts, :body),
         {:ok, to} <- normalize_phone_number(to_raw),
         :ok <- validate_body(body) do
      if noop_environment?() do
        handle_noop_response(to, body, opts)
      else
        send_sms_request(to, body, opts)
      end
    end
  end

  defp fetch_opt(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :missing_required_parameter}
    end
  end

  defp send_sms_request(to, body, opts) do
    with {:ok, account_sid} <- get_config(:account_sid),
         {:ok, auth_token} <- get_config(:auth_token),
         {:ok, sender_param} <- sender_param(opts) do
      form = [{"To", to}, {"Body", body}, sender_param]

      Ysc.Logging.info("Sending SMS via Twilio",
        to: to,
        body_length: String.length(body)
      )

      request_opts =
        [
          url: "#{@api_base_url}/Accounts/#{account_sid}/Messages.json",
          method: :post,
          form: form,
          auth: {:basic, "#{account_sid}:#{auth_token}"},
          retry: false,
          receive_timeout: 10_000
        ] ++ Application.get_env(:ysc, :twilio_req_options, [])

      case Req.request(request_opts) do
        {:ok, %Req.Response{status: status, body: %{"sid" => sid} = resp}}
        when status in [200, 201] ->
          Ysc.Logging.info("Successfully sent SMS via Twilio",
            to: to,
            message_id: sid,
            status: resp["status"]
          )

          from = resp["from"] || sender_value(sender_param)
          store_sms_message(sid, to, from, body, opts)
          {:ok, %{id: sid}}

        {:ok, %Req.Response{status: status, body: resp}} ->
          Ysc.Logging.error("Twilio API returned error status",
            to: to,
            status: status,
            twilio_code: error_code(resp),
            response: inspect(resp)
          )

          {:error, parse_error_response(resp)}

        {:error, error} ->
          Ysc.Logging.error("Failed to send SMS via Twilio",
            to: to,
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  defp handle_noop_response(to, body, opts) do
    fake_id = "SM" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

    Ysc.Logging.info("Twilio SMS no-op (lower environment)",
      to: to,
      body_length: String.length(body),
      fake_message_id: fake_id,
      environment: Ysc.Env.current()
    )

    store_sms_message(fake_id, to, noop_sender(opts), body, opts)
    {:ok, %{id: fake_id}}
  end

  # In noop mode the sender may not be configured; fall back to a placeholder.
  defp noop_sender(opts) do
    case sender_param(opts) do
      {:ok, param} -> sender_value(param)
      _ -> "twilio-noop"
    end
  end

  defp store_sms_message(message_id, to, from, body, opts) do
    attrs = %{
      provider: :twilio,
      provider_message_id: message_id,
      to: to,
      from: from,
      body: body,
      is_mms: false,
      media_urls: [],
      status: :sent,
      user_id: Keyword.get(opts, :user_id),
      message_idempotency_id: Keyword.get(opts, :message_idempotency_id)
    }

    case Ysc.Sms.create_sms_message(attrs) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Ysc.Logging.warning("Failed to store Twilio SMS message in database",
          provider_message_id: message_id,
          errors: inspect(changeset.errors)
        )
    end
  rescue
    error ->
      Ysc.Logging.warning("Error storing Twilio SMS message in database",
        provider_message_id: message_id,
        error: Exception.message(error)
      )
  end

  defp sender_param(opts) do
    cond do
      from = Keyword.get(opts, :from) ->
        {:ok, {"From", from}}

      sid = config(:messaging_service_sid) ->
        {:ok, {"MessagingServiceSid", sid}}

      sender = config(:sender) ->
        {:ok, {"From", sender}}

      true ->
        {:error, :twilio_sender_not_configured}
    end
  end

  defp sender_value({_key, value}), do: value

  defp get_config(key) do
    case config(key) do
      nil -> {:error, :"twilio_#{key}_not_configured"}
      value -> {:ok, value}
    end
  end

  defp config(key) do
    case Application.get_env(:ysc, :twilio, [])[key] do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp normalize_phone_number(number) when is_binary(number) do
    number = String.trim(number)

    number =
      if String.starts_with?(number, "+"), do: number, else: "+" <> number

    # E.164: up to 15 digits, country code never starts with 0
    if Regex.match?(~r/^\+[1-9]\d{7,14}$/, number) do
      {:ok, number}
    else
      {:error, :invalid_phone_number_format}
    end
  end

  defp normalize_phone_number(_), do: {:error, :invalid_phone_number_format}

  defp validate_body(body) when is_binary(body) and body != "", do: :ok

  defp validate_body(body) when is_binary(body),
    do: {:error, :empty_message_body}

  defp validate_body(_), do: {:error, :invalid_message_body}

  defp error_code(%{"code" => code}), do: code
  defp error_code(_), do: nil

  defp parse_error_response(%{"message" => message}), do: message
  defp parse_error_response(other), do: inspect(other)

  defp noop_environment? do
    case System.get_env("TWILIO_FORCE_ENABLE") do
      v when v in ["true", "1"] ->
        false

      _ ->
        Application.get_env(:ysc, :twilio_force_noop, false) or
          Ysc.Env.current() in [:dev, :test, :sandbox, :development]
    end
  end
end
