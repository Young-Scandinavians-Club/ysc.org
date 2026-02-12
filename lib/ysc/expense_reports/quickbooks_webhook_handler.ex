defmodule Ysc.ExpenseReports.QuickbooksWebhookHandler do
  @moduledoc """
  Handles incoming webhook events from QuickBooks related to expense reports.

  Processes BillPayment webhooks to update expense report status to "paid"
  when payments are initiated in QuickBooks.
  """
  require Ysc.Logging

  @doc """
  Processes a QuickBooks webhook event.

  This function is called by the webhook processor to handle BillPayment events.
  """
  def handle_webhook_event(webhook_event) do
    Ysc.Logging.info("Processing QuickBooks webhook event",
      webhook_id: webhook_event.id,
      event_type: webhook_event.event_type,
      event_id: webhook_event.event_id
    )

    # Extract entity information from the webhook payload
    payload = webhook_event.payload
    event_notifications = Map.get(payload, "eventNotifications", [])

    case event_notifications do
      [notification | _] ->
        data_change_event = Map.get(notification, "dataChangeEvent", %{})
        entities = Map.get(data_change_event, "entities", [])

        case entities do
          [entity | _] ->
            entity_name = Map.get(entity, "name")
            entity_id = Map.get(entity, "id")
            operation = Map.get(entity, "operation")

            if entity_name == "BillPayment" and
                 operation in ["Create", "Update"] do
              # Queue background job to process the payment
              enqueue_bill_payment_processing(webhook_event.id, entity_id)
            else
              Ysc.Logging.debug("Skipping non-BillPayment webhook event",
                entity_name: entity_name,
                operation: operation
              )

              :ok
            end

          [] ->
            Ysc.Logging.warning("No entities in QuickBooks webhook event",
              webhook_id: webhook_event.id
            )

            :ok
        end

      [] ->
        Ysc.Logging.warning(
          "No event notifications in QuickBooks webhook event",
          webhook_id: webhook_event.id
        )

        :ok
    end
  end

  # Enqueues a background job to process the BillPayment
  defp enqueue_bill_payment_processing(webhook_event_id, bill_payment_id) do
    job =
      %{
        "webhook_event_id" => webhook_event_id,
        "bill_payment_id" => bill_payment_id
      }
      |> YscWeb.Workers.QuickbooksBillPaymentProcessorWorker.new()
      |> Oban.insert()

    case job do
      {:ok, job} ->
        Ysc.Logging.info("Enqueued BillPayment processing job",
          webhook_event_id: webhook_event_id,
          bill_payment_id: bill_payment_id,
          job_id: job.id
        )

        :ok

      {:error, reason} ->
        Ysc.Logging.error("Failed to enqueue BillPayment processing job",
          webhook_event_id: webhook_event_id,
          bill_payment_id: bill_payment_id,
          error: inspect(reason),
          extra: %{
            webhook_event_id: webhook_event_id,
            bill_payment_id: bill_payment_id,
            error: inspect(reason)
          }
        )

        {:error, reason}
    end
  end
end
