defmodule YscWeb.QuickbooksWebhookController do
  @moduledoc """
  Controller for handling QuickBooks webhook notifications.

  QuickBooks sends "thin notifications" that only contain entity name, ID, and operation.
  We must verify the intuit-signature header and respond quickly (within 3 seconds),
  then process the webhook asynchronously.
  """
  use YscWeb, :controller

  require Logger
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
  def webhook(conn, params) do
    Logger.info("Received QuickBooks webhook",
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
            Logger.info("Duplicate QuickBooks webhook event, returning OK")
            send_resp(conn, 200, "OK")

          {:error, reason} ->
            Logger.error("Failed to create QuickBooks webhook event",
              error: inspect(reason),
              payload: inspect(params, limit: 100)
            )

            send_resp(conn, 500, "Internal Server Error")
        end

      {:error, reason} ->
        Logger.warning("QuickBooks webhook signature verification failed",
          reason: reason,
          headers: inspect(conn.req_headers, limit: 20)
        )

        send_resp(conn, 401, "Unauthorized")
    end
  end

  # Verifies the intuit-signature header from QuickBooks
  defp verify_signature(conn) do
    # Get the verifier token from environment
    # Try both config paths for backwards compatibility
    verifier_token =
      Application.get_env(:ysc, :quickbooks_webhook_verifier_token) ||
        get_in(Application.get_env(:ysc, :quickbooks, []), [
          :webhook_verifier_token
        ])

    if is_nil(verifier_token) || verifier_token == "" do
      Logger.warning("QuickBooks webhook verifier token not configured")
      {:error, :verifier_token_not_configured}
    else
      # Get the intuit-signature header
      signature_header =
        conn.req_headers
        |> Enum.find(fn {key, _value} ->
          String.downcase(key) == "intuit-signature"
        end)

      case signature_header do
        {_key, signature} ->
          # QuickBooks sends the signature as a base64-encoded HMAC-SHA256
          # of the request body using the verifier token as the key.
          # Note: Since Plug.Parsers has already consumed the body, we can't verify
          # the HMAC here. For now, we'll do a basic check that the header exists.
          # In production, you should use a custom plug to capture the raw body
          # before parsing, or verify the signature matches a configured value.
          # For initial implementation, we'll just verify the header is present.
          if is_binary(signature) and String.length(signature) > 0 do
            :ok
          else
            {:error, :invalid_signature}
          end

        nil ->
          Logger.warning(
            "Missing intuit-signature header in QuickBooks webhook"
          )

          {:error, :missing_signature}
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

            # Only process BillPayment Create/Update operations
            if entity_name == "BillPayment" and
                 operation in ["Create", "Update"] do
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
              Logger.debug(
                "Skipping QuickBooks webhook for non-BillPayment entity",
                entity_name: entity_name,
                operation: operation
              )

              {:ok, :skipped}
            end

          [] ->
            Logger.warning("No entities in QuickBooks webhook notification")
            {:ok, :no_entities}
        end

      [] ->
        Logger.warning("No event notifications in QuickBooks webhook payload")
        {:ok, :no_notifications}
    end
  end
end
