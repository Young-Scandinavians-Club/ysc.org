defmodule YscWeb.SesWebhookController do
  @moduledoc """
  Handles incoming AWS SNS notifications for SES email tracking events.

  AWS SES sends open, click, bounce, and complaint events to an SNS topic,
  which then HTTP POSTs them to this endpoint. SNS also sends a
  SubscriptionConfirmation request when the endpoint is first registered.

  Event flow:
  1. SES fires an event (open/click/bounce/complaint)
  2. SNS wraps it and POSTs to POST /webhooks/ses
  3. This controller verifies the SNS signature, checks the environment tag,
     stores the event, and handles side effects (e.g. hard bounce → unsubscribe)

  Environment filtering: since prod and sandbox share the same SES Configuration
  Set and SNS topic, every incoming event includes an "env" tag. Events whose
  "env" tag doesn't match the current environment are silently acknowledged and
  discarded to prevent cross-environment side effects.

  Content-type handling: SNS sends `text/plain; charset=UTF-8` for HTTP
  subscriptions, which Plug.Parsers does not parse. This controller handles
  both the parsed case (application/json, used in tests) and the raw-body
  case (text/plain, used in production SNS).
  """
  use YscWeb, :controller

  require Ysc.Logging

  alias Ysc.Newsletter
  alias Ysc.SNS.SignatureVerifier

  @doc """
  Handles SNS HTTP POST notifications.
  """
  def webhook(conn, params) do
    with {:ok, sns_message} <- resolve_sns_message(conn, params),
         :ok <- verify_sns_signature(sns_message) do
      message_type =
        conn |> get_req_header("x-amz-sns-message-type") |> List.first()

      handle_message(conn, sns_message, message_type)
    else
      {:error, :signature_verification_failed} ->
        Ysc.Logging.warning("SES webhook: SNS signature verification failed")
        send_resp(conn, 403, "Forbidden")

      {:error, reason} ->
        Ysc.Logging.warning("SES webhook: failed to parse SNS message",
          reason: inspect(reason)
        )

        send_resp(conn, 400, "Bad Request")
    end
  end

  # When Plug.Parsers has already parsed the body (JSON content-type), use params directly.
  # When SNS sends text/plain (which Plug.Parsers skips), read and decode the raw body.
  defp resolve_sns_message(_conn, params) when map_size(params) > 0 do
    {:ok, params}
  end

  defp resolve_sns_message(conn, _params) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, _conn} -> Jason.decode(body)
      {:more, _partial, _conn} -> {:error, :body_too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_message(conn, sns_message, "SubscriptionConfirmation") do
    subscribe_url = sns_message["SubscribeURL"]

    if is_binary(subscribe_url) do
      case Req.get(subscribe_url) do
        {:ok, %Req.Response{status: status}} when status in 200..299 ->
          Ysc.Logging.info("SES webhook: SNS subscription confirmed",
            topic_arn: sns_message["TopicArn"]
          )

        {:ok, %Req.Response{status: status}} ->
          Ysc.Logging.warning(
            "SES webhook: SNS subscription confirmation returned non-2xx",
            status: status
          )

        {:error, reason} ->
          Ysc.Logging.warning(
            "SES webhook: SNS subscription confirmation request failed",
            reason: inspect(reason)
          )
      end
    else
      Ysc.Logging.warning(
        "SES webhook: SubscriptionConfirmation missing SubscribeURL"
      )
    end

    send_resp(conn, 200, "OK")
  end

  defp handle_message(conn, sns_message, "Notification") do
    case Jason.decode(sns_message["Message"] || "{}") do
      {:ok, ses_event} ->
        process_ses_event(ses_event)

      {:error, reason} ->
        Ysc.Logging.warning("SES webhook: failed to decode SES event JSON",
          reason: inspect(reason),
          message: sns_message["Message"]
        )
    end

    send_resp(conn, 200, "OK")
  end

  defp handle_message(conn, _sns_message, type) do
    Ysc.Logging.info("SES webhook: ignoring SNS message type", type: type)
    send_resp(conn, 200, "OK")
  end

  defp process_ses_event(ses_event) do
    tags = extract_tags(ses_event)
    event_env = Map.get(tags, "env")
    current_env = to_string(Ysc.Env.current())

    if event_env != current_env do
      Ysc.Logging.info(
        "SES webhook: skipping event from different environment",
        event_env: event_env,
        current_env: current_env
      )

      :ok
    else
      do_process_ses_event(ses_event, tags)
    end
  end

  defp do_process_ses_event(ses_event, tags) do
    event_type =
      ses_event
      |> Map.get("eventType", "")
      |> String.downcase()

    recipients = get_in(ses_event, ["mail", "destination"]) || []
    email = List.first(recipients) || ""

    event_attrs = build_event_attrs(event_type, email, tags, ses_event)

    case Newsletter.record_email_event(event_attrs) do
      {:ok, _event} ->
        handle_event_side_effects(event_type, email, ses_event)

      {:error, changeset} ->
        Ysc.Logging.warning("SES webhook: failed to record email event",
          errors: inspect(changeset.errors),
          event_type: event_type,
          email: email
        )
    end
  end

  defp build_event_attrs(event_type, email, tags, ses_event) do
    %{
      event_type: event_type,
      email: email,
      environment: Map.get(tags, "env", ""),
      template: Map.get(tags, "template"),
      edition_id: Map.get(tags, "edition_id"),
      subscriber_id: Map.get(tags, "subscriber_id"),
      user_id: Map.get(tags, "user_id"),
      bounce_type: get_in(ses_event, ["bounce", "bounceType"]),
      bounce_sub_type: get_in(ses_event, ["bounce", "bounceSubType"]),
      link_url: get_click_url(ses_event),
      raw_payload: ses_event,
      event_timestamp: parse_event_timestamp(ses_event)
    }
  end

  defp handle_event_side_effects("bounce", email, ses_event) do
    bounce_type = get_in(ses_event, ["bounce", "bounceType"])

    if bounce_type == "Permanent" do
      Ysc.Logging.info("SES webhook: hard bounce received, unsubscribing",
        email: email,
        bounce_sub_type: get_in(ses_event, ["bounce", "bounceSubType"])
      )

      case Newsletter.handle_hard_bounce(email) do
        {:ok, :not_subscribed} ->
          :ok

        {:ok, subscriber} ->
          Ysc.Logging.info(
            "SES webhook: subscriber unsubscribed due to hard bounce",
            email: email,
            subscriber_id: subscriber.id
          )

        {:error, reason} ->
          Ysc.Logging.error("SES webhook: failed to unsubscribe hard bounce",
            email: email,
            error: inspect(reason)
          )
      end
    end
  end

  defp handle_event_side_effects(_event_type, _email, _ses_event), do: :ok

  # SES tags come back as a map where each value is a list of strings.
  # e.g. %{"env" => ["prod"], "user_id" => ["abc123"]}
  # We flatten each list to a single string value.
  defp extract_tags(ses_event) do
    case get_in(ses_event, ["mail", "tags"]) do
      map when is_map(map) ->
        Map.new(map, fn {k, v} ->
          value = if is_list(v), do: List.first(v), else: v
          {k, value}
        end)

      _ ->
        %{}
    end
  end

  defp get_click_url(ses_event) do
    get_in(ses_event, ["click", "link"])
  end

  defp parse_event_timestamp(ses_event) do
    timestamp_str =
      get_in(ses_event, ["mail", "timestamp"]) ||
        get_in(ses_event, ["open", "timestamp"]) ||
        get_in(ses_event, ["click", "timestamp"]) ||
        get_in(ses_event, ["bounce", "timestamp"]) ||
        get_in(ses_event, ["complaint", "timestamp"])

    case timestamp_str do
      nil ->
        nil

      ts ->
        case DateTime.from_iso8601(ts) do
          {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
          _ -> nil
        end
    end
  end

  defp verify_sns_signature(sns_message) do
    if Application.get_env(:ysc, :sns_skip_signature_verification, false) do
      :ok
    else
      case SignatureVerifier.verify(sns_message) do
        :ok -> :ok
        {:error, _reason} -> {:error, :signature_verification_failed}
      end
    end
  end
end
