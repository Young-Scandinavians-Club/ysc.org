defmodule Ysc.ExpenseReports.QuickbooksWebhookHandler do
  @moduledoc """
  Handles incoming webhook events from QuickBooks related to expense reports.

  Processes BillPayment webhooks to update expense report status to "paid"
  when payments are confirmed in QuickBooks, and Bill Delete/Void webhooks to
  reject the linked expense report when the underlying Bill is removed or
  cancelled in QuickBooks.
  """
  require Ysc.Logging

  @doc """
  Whether a QuickBooks entity/operation pair should be acted on.

  This is the single source of truth for which webhook events matter -
  `YscWeb.QuickbooksWebhookController` calls this to decide whether to
  persist a `WebhookEvent` row at all, and `handle_webhook_event/1` below
  calls it to decide how to dispatch a persisted one. Keeping them on two
  separate lists risked the two drifting apart (an event persisted but never
  dispatched, or dispatched but never persisted).
  """
  def relevant_quickbooks_event?("BillPayment", operation),
    do: operation in ["Create", "Update"]

  def relevant_quickbooks_event?("Bill", operation),
    do: operation in ["Delete", "Void"]

  def relevant_quickbooks_event?(_entity_name, _operation), do: false

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

            cond do
              relevant_quickbooks_event?(entity_name, operation) and
                  entity_name == "BillPayment" ->
                # Queue background job to process the payment
                enqueue_bill_payment_processing(webhook_event.id, entity_id)

              relevant_quickbooks_event?(entity_name, operation) and
                  entity_name == "Bill" ->
                # Queue background job to reject the linked expense report
                enqueue_bill_deleted_processing(webhook_event.id, entity_id)

              true ->
                Ysc.Logging.debug("Skipping unhandled webhook event",
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
    enqueue_processing(
      YscWeb.Workers.QuickbooksBillPaymentProcessorWorker,
      %{
        "webhook_event_id" => webhook_event_id,
        "bill_payment_id" => bill_payment_id
      },
      "BillPayment"
    )
  end

  # Enqueues a background job to reject the expense report linked to a
  # deleted/voided Bill
  defp enqueue_bill_deleted_processing(webhook_event_id, bill_id) do
    enqueue_processing(
      YscWeb.Workers.QuickbooksBillDeletedProcessorWorker,
      %{
        "webhook_event_id" => webhook_event_id,
        "bill_id" => bill_id
      },
      "Bill deletion"
    )
  end

  defp enqueue_processing(worker, args, label) do
    result = args |> worker.new() |> Oban.insert()

    case result do
      {:ok, job} ->
        Ysc.Logging.info("Enqueued #{label} processing job",
          args: args,
          job_id: job.id
        )

        :ok

      {:error, reason} ->
        Ysc.Logging.error("Failed to enqueue #{label} processing job",
          args: args,
          error: inspect(reason),
          extra: %{args: args, error: inspect(reason)}
        )

        {:error, reason}
    end
  end
end
