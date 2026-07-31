defmodule YscWeb.Workers.QuickbooksBillDeletedProcessorWorker do
  @moduledoc """
  Oban worker for processing QuickBooks Bill Delete/Void webhook events.

  When a Bill is deleted or voided in QuickBooks, the expense report it was
  synced to no longer has a valid corresponding record on the QuickBooks
  side. This worker finds the linked expense report by `quickbooks_bill_id`
  and marks it "rejected" (with a system note distinguishing it from an
  admin rejection) so the two stay in sync.

  Note: unlike the BillPayment worker, this does not call the QuickBooks API
  first - a deleted Bill generally can't be re-fetched, so we act directly
  on the entity ID from the webhook notification.
  """
  require Ysc.Logging
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Ysc.Webhooks
  alias Ysc.ExpenseReports
  alias Ysc.Repo
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "webhook_event_id" => webhook_event_id,
          "bill_id" => bill_id
        }
      }) do
    Ysc.Logging.info("Processing QuickBooks Bill deletion/void",
      webhook_event_id: webhook_event_id,
      bill_id: bill_id
    )

    case Webhooks.lock_webhook_event(webhook_event_id) do
      {:ok, webhook_event} ->
        process_bill_deletion(webhook_event, bill_id)

      {:error, :not_found} ->
        Ysc.Logging.warning("Webhook event not found",
          webhook_event_id: webhook_event_id
        )

        {:error, :webhook_not_found}

      {:error, :already_processing} ->
        Ysc.Logging.info("Webhook event already being processed, skipping",
          webhook_event_id: webhook_event_id
        )

        :ok
    end
  end

  defp process_bill_deletion(webhook_event, bill_id) do
    case find_expense_report_by_bill_id(bill_id) do
      {:ok, expense_report} ->
        Ysc.Logging.info("Found expense report for deleted/voided Bill",
          expense_report_id: expense_report.id,
          bill_id: bill_id,
          current_status: expense_report.status
        )

        reject_expense_report(webhook_event, expense_report, bill_id)

      {:error, :not_found} ->
        Ysc.Logging.warning(
          "No expense report found for deleted/voided QuickBooks Bill",
          bill_id: bill_id
        )

        # Nothing to do - mark processed so we don't retry forever.
        Webhooks.update_webhook_state(webhook_event, :processed)
        :ok
    end
  end

  defp reject_expense_report(webhook_event, expense_report, bill_id) do
    cond do
      expense_report.status == "rejected" ->
        Ysc.Logging.info(
          "Expense report already rejected, skipping (idempotent)",
          expense_report_id: expense_report.id,
          bill_id: bill_id
        )

        Webhooks.update_webhook_state(webhook_event, :processed)
        :ok

      expense_report.status == "paid" ->
        # The Bill was deleted/voided after we'd already recorded it as
        # paid. That's a real conflict worth a human looking at rather than
        # something we should silently resolve either way - log loudly and
        # leave the status as-is.
        Ysc.Logging.error(
          "QuickBooks Bill deleted/voided for an expense report already marked paid - needs manual review",
          expense_report_id: expense_report.id,
          bill_id: bill_id
        )

        Webhooks.update_webhook_state(webhook_event, :processed)
        :ok

      true ->
        expense_report =
          if Ecto.assoc_loaded?(expense_report.expense_items) do
            expense_report
          else
            Repo.preload(expense_report, :expense_items)
          end

        case ExpenseReports.mark_expense_report_as_rejected_due_to_quickbooks_deletion(
               expense_report,
               bill_id
             ) do
          {:ok, updated_report} ->
            Ysc.Logging.info(
              "Successfully rejected expense report following QuickBooks Bill deletion/void",
              expense_report_id: updated_report.id,
              bill_id: bill_id
            )

            Webhooks.update_webhook_state(webhook_event, :processed)
            :ok

          {:error, changeset} ->
            Ysc.Logging.error(
              "Failed to reject expense report following QuickBooks Bill deletion/void",
              expense_report_id: expense_report.id,
              bill_id: bill_id,
              errors: inspect(changeset.errors)
            )

            Webhooks.update_webhook_state(webhook_event, :failed)
            {:error, :update_failed}
        end
    end
  end

  defp find_expense_report_by_bill_id(bill_id) do
    query =
      from(er in ExpenseReports.ExpenseReport,
        where: er.quickbooks_bill_id == ^bill_id
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      expense_report -> {:ok, expense_report}
    end
  end
end
