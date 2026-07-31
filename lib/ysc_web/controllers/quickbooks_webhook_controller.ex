defmodule YscWeb.QuickbooksWebhookController do
  @moduledoc """
  Controller for handling QuickBooks webhook notifications.

  QuickBooks sends "thin notifications" that only contain entity name, ID, and operation.
  We must verify the intuit-signature header and respond quickly (within 3 seconds),
  then process the webhook asynchronously.

  Two event types are acted on:
  - `BillPayment` Create/Update - a payment was recorded against a Bill.
  - `Bill` Delete/Void - the underlying Bill was removed or cancelled in
    QuickBooks, so the linked expense report should be rejected to keep
    things in sync.

  Note: QuickBooks apps must explicitly opt in to receiving `Void`
  notifications in the Intuit developer dashboard - they aren't sent by
  default even if the entity type is subscribed.
  """
  use YscWeb, :controller

  require Ysc.Logging
  alias Ysc.Webhooks
  alias Ysc.ExpenseReports.QuickbooksWebhookHandler

  @doc """
  Handles incoming webhook notifications from QuickBooks.

  QuickBooks webhook payload format:
  {
    "eventNotifications": [
      {
        "realmId": "company_id",
        "dataChangeEvent": {
          "entities": [
            {
              "name": "BillPayment",
              "id": "123",
              "operation": "Create"
            }
          ]
        }
      }
    ]
  }
  """
  @dialyzer {:nowarn_function, webhook: 2}
  def webhook(conn, params) do
    Ysc.Logging.info("Received QuickBooks webhook",
      payload: inspect(params, limit: 100)
    )

    # Verify the intuit-signature header
    case verify_signature(conn) do
      :ok ->
        # Create webhook event and queue for background processing
        # We respond quickly and process asynchronously
        case create_webhook_event(params) do
          {:ok, webhook_event} when is_struct(webhook_event) ->
            # Process the webhook event asynchronously
            # The handler will enqueue a worker to process the BillPayment
            # In test mode, run synchronously to avoid database connection issues
            if Ysc.Env.test?() do
              QuickbooksWebhookHandler.handle_webhook_event(webhook_event)
            else
              Task.start(fn ->
                QuickbooksWebhookHandler.handle_webhook_event(webhook_event)
              end)
            end

            # Respond with 200 OK immediately (within 3 seconds requirement)
            send_resp(conn, 200, "OK")

          {:ok, _skipped_or_other} ->
            # Webhook was skipped (non-BillPayment entity, no entities, etc.)
            # Just respond with 200 OK
            send_resp(conn, 200, "OK")

          {:error, %Ysc.Webhooks.DuplicateWebhookEventError{}} ->
            # Duplicate webhook - already processed, return 200 OK
            Ysc.Logging.info("Duplicate QuickBooks webhook event, returning OK")
            send_resp(conn, 200, "OK")
        end

      {:error, reason} ->
        Ysc.Logging.warning("QuickBooks webhook signature verification failed",
          reason: reason,
          headers: inspect(conn.req_headers, limit: 20)
        )

        send_resp(conn, 401, "Unauthorized")
    end
  end

  # Verifies the intuit-signature header from QuickBooks using HMAC-SHA256.
  # QuickBooks signs the raw request body with the webhook verifier token and
  # base64-encodes the result. The raw body is captured by CacheRawBody before
  # Plug.Parsers consumes it.
  defp verify_signature(conn) do
    verifier_token =
      Application.get_env(:ysc, :quickbooks_webhook_verifier_token) ||
        get_in(Application.get_env(:ysc, :quickbooks, []), [
          :webhook_verifier_token
        ])

    if is_nil(verifier_token) || verifier_token == "" do
      Ysc.Logging.warning("QuickBooks webhook verifier token not configured")
      {:error, :verifier_token_not_configured}
    else
      raw_body = conn.private[:raw_body] || ""

      signature =
        conn.req_headers
        |> Enum.find_value(fn {key, value} ->
          if String.downcase(key) == "intuit-signature", do: value
        end)

      if is_nil(signature) || signature == "" do
        Ysc.Logging.warning(
          "Missing intuit-signature header in QuickBooks webhook"
        )

        {:error, :missing_signature}
      else
        expected =
          :crypto.mac(:hmac, :sha256, verifier_token, raw_body)
          |> Base.encode64()

        if Plug.Crypto.secure_compare(expected, signature) do
          :ok
        else
          {:error, :invalid_signature}
        end
      end
    end
  end

  # Creates a webhook event in the database for background processing
  defp create_webhook_event(params) do
    # Extract event information from QuickBooks webhook payload
    event_notifications = Map.get(params, "eventNotifications", [])

    # Process each event notification
    # For now, we'll create one webhook event per notification
    # In practice, QuickBooks typically sends one notification per webhook
    case event_notifications do
      [notification | _] ->
        data_change_event = Map.get(notification, "dataChangeEvent", %{})
        entities = Map.get(data_change_event, "entities", [])
        realm_id = Map.get(notification, "realmId")

        # Process the first entity (QuickBooks typically sends one entity per notification)
        case entities do
          [entity | _] ->
            entity_name = Map.get(entity, "name")
            entity_id = Map.get(entity, "id")
            operation = Map.get(entity, "operation")

            # Create a unique event ID for idempotency
            # Format: realmId:entityName:entityId:operation
            event_id = "#{realm_id}:#{entity_name}:#{entity_id}:#{operation}"

            # Only process:
            # - BillPayment Create/Update (payment recorded against a Bill)
            # - Bill Delete/Void (the underlying Bill was removed/cancelled
            #   in QuickBooks, so the linked expense report should be
            #   rejected to keep things in sync)
            if relevant_quickbooks_event?(entity_name, operation) do
              try do
                webhook_event =
                  Webhooks.create_webhook_event!(%{
                    provider: "quickbooks",
                    event_id: event_id,
                    event_type: "#{entity_name}.#{operation}",
                    payload: params
                  })

                {:ok, webhook_event}
              rescue
                Ysc.Webhooks.DuplicateWebhookEventError ->
                  {:error, %Ysc.Webhooks.DuplicateWebhookEventError{}}
              end
            else
              Ysc.Logging.debug(
                "Skipping QuickBooks webhook for unhandled entity/operation",
                entity_name: entity_name,
                operation: operation
              )

              {:ok, :skipped}
            end

          [] ->
            Ysc.Logging.warning(
              "No entities in QuickBooks webhook notification"
            )

            {:ok, :no_entities}
        end

      [] ->
        Ysc.Logging.warning(
          "No event notifications in QuickBooks webhook payload"
        )

        {:ok, :no_notifications}
    end
  end

  defp relevant_quickbooks_event?("BillPayment", operation),
    do: operation in ["Create", "Update"]

  defp relevant_quickbooks_event?("Bill", operation),
    do: operation in ["Delete", "Void"]

  defp relevant_quickbooks_event?(_entity_name, _operation), do: false
end
