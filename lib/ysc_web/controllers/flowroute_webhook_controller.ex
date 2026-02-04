defmodule YscWeb.FlowrouteWebhookController do
  @moduledoc """
  Controller for handling FlowRoute webhooks (inbound SMS and delivery receipts).
  """
  use YscWeb, :controller

  require Logger
  alias Ysc.Sms
  alias Ysc.Accounts

  @doc """
  Handles inbound SMS webhook from FlowRoute.
  """
  def handle_inbound_sms(conn, params) do
    Logger.info("Received FlowRoute inbound SMS webhook",
      payload: inspect(params)
    )

    try do
      # Extract data from webhook payload
      data = get_in(params, ["data"])
      attributes = get_in(data, ["attributes"])
      message_id = get_in(data, ["id"])

      if is_nil(message_id) or is_nil(attributes) do
        Logger.warning("Invalid inbound SMS webhook payload",
          payload: inspect(params)
        )

        send_resp(conn, 400, "Invalid payload")
      else
        # Parse timestamp
        timestamp =
          case get_in(attributes, ["timestamp"]) do
            nil ->
              nil

            timestamp_str ->
              case DateTime.from_iso8601(timestamp_str) do
                {:ok, dt, _} -> dt
                _ -> nil
              end
          end

        # Convert direction and status to enum atoms
        direction =
          normalize_direction(get_in(attributes, ["direction"]) || "inbound")

        status = normalize_received_status(get_in(attributes, ["status"]))

        # Create SMS received record
        attrs = %{
          provider: :flowroute,
          provider_message_id: message_id,
          from: get_in(attributes, ["from"]),
          to: get_in(attributes, ["to"]),
          body: get_in(attributes, ["body"]),
          is_mms: get_in(attributes, ["is_mms"]) || false,
          direction: direction,
          message_type: get_in(attributes, ["message_type"]),
          message_encoding: get_in(attributes, ["message_encoding"]),
          status: status,
          amount_display: get_in(attributes, ["amount_display"]),
          amount_nanodollars:
            parse_nanodollars(get_in(attributes, ["amount_nanodollars"])),
          message_callback_url: get_in(attributes, ["message_callback_url"]),
          provider_timestamp: timestamp,
          raw_payload: params
        }

        case Sms.create_sms_received(attrs) do
          {:ok, sms_received} ->
            Logger.info("Created SMS received record",
              provider: sms_received.provider,
              provider_message_id: sms_received.provider_message_id,
              from: sms_received.from,
              to: sms_received.to
            )

            # Try to match to user
            Sms.match_sms_received_to_user(sms_received)

            # Handle opt-in/opt-out/help messages
            handle_sms_command(sms_received)

            send_resp(conn, 200, "OK")

          {:error, changeset} ->
            Logger.warning("Failed to create SMS received record",
              provider: :flowroute,
              provider_message_id: message_id,
              errors: inspect(changeset.errors)
            )

            send_resp(conn, 400, "Failed to process")
        end
      end
    rescue
      error ->
        Logger.warning("Error processing inbound SMS webhook",
          error: Exception.message(error),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{payload: params}
        )

        send_resp(conn, 500, "Internal error")
    end
  end

  @doc """
  Handles delivery receipt (DLR) webhook from FlowRoute.
  """
  def handle_delivery_receipt(conn, params) do
    Logger.info("Received FlowRoute delivery receipt webhook",
      payload: inspect(params)
    )

    try do
      # Extract data from webhook payload
      data = get_in(params, ["data"])
      attributes = get_in(data, ["attributes"])
      message_id = get_in(data, ["id"])

      if is_nil(message_id) or is_nil(attributes) do
        Logger.warning("Invalid delivery receipt webhook payload",
          payload: inspect(params)
        )

        send_resp(conn, 400, "Invalid payload")
      else
        # Parse timestamp
        timestamp =
          case get_in(attributes, ["timestamp"]) do
            nil ->
              nil

            timestamp_str ->
              case DateTime.from_iso8601(timestamp_str) do
                {:ok, dt, _} -> dt
                _ -> nil
              end
          end

        # Convert status to enum atom
        status =
          normalize_delivery_receipt_status(get_in(attributes, ["status"]))

        # Create delivery receipt record
        attrs = %{
          provider: :flowroute,
          provider_message_id: message_id,
          body: get_in(attributes, ["body"]),
          level: get_in(attributes, ["level"]),
          status: status,
          status_code: get_in(attributes, ["status_code"]),
          status_code_description:
            get_in(attributes, ["status_code_description"]),
          provider_timestamp: timestamp,
          raw_payload: params
        }

        case Sms.create_delivery_receipt(attrs) do
          {:ok, delivery_receipt} ->
            Logger.info("Created delivery receipt record",
              provider: delivery_receipt.provider,
              provider_message_id: delivery_receipt.provider_message_id,
              status: delivery_receipt.status,
              status_code: delivery_receipt.status_code
            )

            # Try to link to SMS message
            Sms.link_delivery_receipt_to_message(delivery_receipt)

            # Update SMS message status if linked
            if delivery_receipt.sms_message_id do
              update_sms_message_status_from_dlr(delivery_receipt)
            end

            send_resp(conn, 200, "OK")

          {:error, changeset} ->
            Logger.warning("Failed to create delivery receipt record",
              provider: :flowroute,
              provider_message_id: message_id,
              errors: inspect(changeset.errors)
            )

            send_resp(conn, 400, "Failed to process")
        end
      end
    rescue
      error ->
        Logger.error("Error processing delivery receipt webhook",
          error: Exception.message(error),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{payload: params}
        )

        send_resp(conn, 500, "Internal error")
    end
  end

  # Private functions

  defp parse_nanodollars(nil), do: nil

  defp parse_nanodollars(value) when is_binary(value),
    do: String.to_integer(value)

  defp parse_nanodollars(value) when is_integer(value), do: value
  defp parse_nanodollars(_), do: nil

  defp update_sms_message_status_from_dlr(delivery_receipt) do
    # Map DLR status to SMS message status enum
    new_status =
      case delivery_receipt.status do
        :delivered -> :delivered
        :failed -> :failed
        :message_buffered -> :buffered
        :message_sent -> :sent
        _ -> :sent
      end

    if delivery_receipt.sms_message_id do
      case Ysc.Repo.get(Ysc.Sms.SmsMessage, delivery_receipt.sms_message_id) do
        nil -> :ok
        sms_message -> Sms.update_sms_message_status(sms_message, new_status)
      end
    else
      :ok
    end
  end

  # Normalize direction string to enum atom
  defp normalize_direction("inbound"), do: :inbound
  defp normalize_direction("outbound"), do: :outbound
  defp normalize_direction(_), do: :inbound

  # Normalize received status string to enum atom
  defp normalize_received_status(nil), do: nil
  defp normalize_received_status("delivered"), do: :delivered
  defp normalize_received_status("failed"), do: :failed
  defp normalize_received_status("pending"), do: :pending
  defp normalize_received_status(_), do: nil

  # Normalize delivery receipt status string to enum atom
  defp normalize_delivery_receipt_status("delivered"), do: :delivered
  defp normalize_delivery_receipt_status("failed"), do: :failed

  defp normalize_delivery_receipt_status("message buffered"),
    do: :message_buffered

  defp normalize_delivery_receipt_status("message sent"), do: :message_sent
  defp normalize_delivery_receipt_status("pending"), do: :pending

  defp normalize_delivery_receipt_status(status) when is_atom(status),
    do: status

  defp normalize_delivery_receipt_status(_), do: :pending

  # Handle SMS commands (START, SUBSCRIBE, STOP, HELP)
  defp handle_sms_command(sms_received) do
    body = normalize_message_body(sms_received.body)

    case body do
      "START" ->
        handle_opt_in(sms_received)

      "SUBSCRIBE" ->
        handle_opt_in(sms_received)

      "STOP" ->
        handle_opt_out(sms_received)

      "HELP" ->
        handle_help(sms_received)

      _ ->
        # Not a command, do nothing
        :ok
    end
  end

  # Normalize message body for command matching
  defp normalize_message_body(nil), do: ""

  defp normalize_message_body(body) when is_binary(body) do
    body
    |> String.trim()
    |> String.upcase()
  end

  # Handle opt-in (START/SUBSCRIBE)
  defp handle_opt_in(sms_received) do
    case Accounts.get_user_by_phone_number(sms_received.from) do
      nil ->
        Logger.info("Opt-in request from unknown phone number",
          phone_number: sms_received.from,
          provider_message_id: sms_received.provider_message_id
        )

        # Still send the opt-in message even if user not found
        send_opt_in_response(sms_received.from, sms_received.to)

      user ->
        Logger.info("Processing opt-in request",
          user_id: user.id,
          phone_number: sms_received.from,
          provider_message_id: sms_received.provider_message_id
        )

        # Enable both SMS notification preferences
        case Accounts.update_notification_preferences(user, %{
               "account_notifications_sms" => "true",
               "event_notifications_sms" => "true"
             }) do
          {:ok, _updated_user} ->
            Logger.info("User opted in to SMS notifications",
              user_id: user.id,
              phone_number: sms_received.from
            )

            send_opt_in_response(sms_received.from, sms_received.to)

          {:error, changeset} ->
            Logger.error("Failed to update notification preferences for opt-in",
              user_id: user.id,
              phone_number: sms_received.from,
              errors: inspect(changeset.errors)
            )

            Sentry.capture_message("Failed to process SMS opt-in",
              level: :error,
              extra: %{
                user_id: user.id,
                phone_number: sms_received.from,
                errors: inspect(changeset.errors)
              }
            )

            # Still send response even if update failed
            send_opt_in_response(sms_received.from, sms_received.to)
        end
    end
  end

  # Handle opt-out (STOP)
  defp handle_opt_out(sms_received) do
    case Accounts.get_user_by_phone_number(sms_received.from) do
      nil ->
        Logger.info("Opt-out request from unknown phone number",
          phone_number: sms_received.from,
          provider_message_id: sms_received.provider_message_id
        )

        # Still send the opt-out message even if user not found
        send_opt_out_response(sms_received.from, sms_received.to)

      user ->
        Logger.info("Processing opt-out request",
          user_id: user.id,
          phone_number: sms_received.from,
          provider_message_id: sms_received.provider_message_id
        )

        # Disable both SMS notification preferences
        case Accounts.update_notification_preferences(user, %{
               "account_notifications_sms" => "false",
               "event_notifications_sms" => "false"
             }) do
          {:ok, _updated_user} ->
            Logger.info("User opted out of SMS notifications",
              user_id: user.id,
              phone_number: sms_received.from
            )

            send_opt_out_response(sms_received.from, sms_received.to)

          {:error, changeset} ->
            Logger.error(
              "Failed to update notification preferences for opt-out",
              user_id: user.id,
              phone_number: sms_received.from,
              errors: inspect(changeset.errors)
            )

            Sentry.capture_message("Failed to process SMS opt-out",
              level: :error,
              extra: %{
                user_id: user.id,
                phone_number: sms_received.from,
                errors: inspect(changeset.errors)
              }
            )

            # Still send response even if update failed
            send_opt_out_response(sms_received.from, sms_received.to)
        end
    end
  end

  # Handle help request
  defp handle_help(sms_received) do
    Logger.info("Processing help request",
      phone_number: sms_received.from,
      provider_message_id: sms_received.provider_message_id
    )

    send_help_response(sms_received.from, sms_received.to)
  end

  # Send opt-in response
  defp send_opt_in_response(to, from) do
    message =
      "Young Scandinavians Club: You are now subscribed to YSC account alerts. Msg frequency varies. Msg&Data rates may apply. Reply HELP for help, STOP to cancel."

    send_response_sms(to, from, message, "sms_opt_in_response")
  end

  # Send opt-out response
  defp send_opt_out_response(to, from) do
    message =
      "Young Scandinavians Club: You have successfully unsubscribed from alerts. You will receive no further messages. Reply START to resubscribe."

    send_response_sms(to, from, message, "sms_opt_out_response")
  end

  # Send help response
  defp send_help_response(to, from) do
    message =
      "Young Scandinavians Club: For help with account alerts, email info@ysc.org. Msg frequency varies. Msg&Data rates may apply. Reply STOP to cancel."

    send_response_sms(to, from, message, "sms_help_response")
  end

  # Send response SMS
  defp send_response_sms(to, from, body, template) do
    idempotency_key =
      "sms_response_#{template}_#{to}_#{System.system_time(:second)}"

    attrs = %{
      message_type: :sms,
      idempotency_key: idempotency_key,
      message_template: template,
      params: %{from: from}
    }

    case Ysc.Messages.run_send_sms_idempotent(to, body, attrs) do
      {:ok, %{id: _message_id}} ->
        Logger.info("Sent SMS response",
          template: template,
          to: to,
          from: from
        )

      {:error, reason} ->
        Logger.error("Failed to send SMS response",
          template: template,
          to: to,
          from: from,
          error: reason
        )

        Sentry.capture_message("Failed to send SMS response",
          level: :error,
          extra: %{
            template: template,
            to: to,
            from: from,
            error: inspect(reason)
          }
        )
    end
  end
end
