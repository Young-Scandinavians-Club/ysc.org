defmodule YscWeb.Workers.QuickbooksBillPaymentProcessorWorker do
  @moduledoc """
  Oban worker for processing QuickBooks BillPayment webhook events.

  This worker:
  1. Fetches the BillPayment details from QuickBooks API
  2. Finds the linked Bill (expense report) using the LinkedTxn field
  3. Updates the expense report status to "paid"
  """
  require Logger
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Ysc.Webhooks
  alias Ysc.ExpenseReports
  alias Ysc.Repo
  import Ecto.Query

  defp client do
    Application.get_env(:ysc, :quickbooks_client, Ysc.Quickbooks.Client)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "webhook_event_id" => webhook_event_id,
          "bill_payment_id" => bill_payment_id
        }
      }) do
    Logger.info("Processing QuickBooks BillPayment",
      webhook_event_id: webhook_event_id,
      bill_payment_id: bill_payment_id
    )

    # Lock the webhook event for processing
    case Webhooks.lock_webhook_event(webhook_event_id) do
      {:ok, webhook_event} ->
        process_bill_payment(webhook_event, bill_payment_id)

      {:error, :not_found} ->
        Logger.warning("Webhook event not found",
          webhook_event_id: webhook_event_id
        )

        {:error, :webhook_not_found}

      {:error, :already_processing} ->
        Logger.info("Webhook event already being processed, skipping",
          webhook_event_id: webhook_event_id
        )

        :ok
    end
  end

  defp process_bill_payment(webhook_event, bill_payment_id) do
    # Fetch the BillPayment from QuickBooks
    case client().get_bill_payment(bill_payment_id) do
      {:ok, bill_payment} ->
        Logger.info("Retrieved BillPayment from QuickBooks",
          bill_payment_id: bill_payment_id,
          bill_payment: inspect(bill_payment, limit: 50)
        )

        # Extract the linked Bill ID from LinkedTxn
        linked_txns = Map.get(bill_payment, "LinkedTxn", [])

        case find_linked_bill(linked_txns) do
          {:ok, bill_id} ->
            Logger.info("Found linked Bill",
              bill_id: bill_id,
              bill_payment_id: bill_payment_id
            )

            # Find the expense report with this QuickBooks bill ID
            case find_expense_report_by_bill_id(bill_id) do
              {:ok, expense_report} ->
                Logger.info("Found expense report for Bill",
                  expense_report_id: expense_report.id,
                  bill_id: bill_id,
                  current_status: expense_report.status
                )

                # Preload expense_items association if not already loaded
                # (required for changeset validation)
                expense_report =
                  if Ecto.assoc_loaded?(expense_report.expense_items) do
                    expense_report
                  else
                    Repo.preload(expense_report, :expense_items)
                  end

                # Update the expense report status to "paid"
                case ExpenseReports.mark_expense_report_as_paid(expense_report) do
                  {:ok, updated_report} ->
                    Logger.info("Successfully marked expense report as paid",
                      expense_report_id: updated_report.id,
                      bill_id: bill_id,
                      bill_payment_id: bill_payment_id
                    )

                    # Mark webhook event as processed
                    Webhooks.update_webhook_state(webhook_event, :processed)

                    :ok

                  {:error, changeset} ->
                    Logger.error("Failed to mark expense report as paid",
                      expense_report_id: expense_report.id,
                      errors: inspect(changeset.errors)
                    )

                    # Mark webhook event as failed
                    Webhooks.update_webhook_state(webhook_event, :failed)

                    Sentry.capture_message(
                      "Failed to mark expense report as paid",
                      level: :error,
                      extra: %{
                        expense_report_id: expense_report.id,
                        bill_id: bill_id,
                        errors: inspect(changeset.errors)
                      }
                    )

                    {:error, :update_failed}
                end

              {:error, :not_found} ->
                Logger.warning("No expense report found for QuickBooks Bill",
                  bill_id: bill_id,
                  bill_payment_id: bill_payment_id
                )

                # Mark webhook event as processed (we can't do anything about it)
                Webhooks.update_webhook_state(webhook_event, :processed)

                :ok

              {:error, reason} ->
                Logger.warning("Error finding expense report",
                  bill_id: bill_id,
                  error: reason
                )

                # Mark webhook event as failed
                Webhooks.update_webhook_state(webhook_event, :failed)

                {:error, reason}
            end

          {:error, :no_linked_bill} ->
            Logger.warning("BillPayment has no linked Bill",
              bill_payment_id: bill_payment_id
            )

            # Mark webhook event as processed (nothing to do)
            Webhooks.update_webhook_state(webhook_event, :processed)

            :ok
        end

      {:error, reason} ->
        Logger.warning("Failed to fetch BillPayment from QuickBooks",
          bill_payment_id: bill_payment_id,
          error: inspect(reason)
        )

        # Mark webhook event as failed
        Webhooks.update_webhook_state(webhook_event, :failed)

        unless reason == :not_found do
          Sentry.capture_message("Failed to fetch BillPayment from QuickBooks",
            level: :error,
            extra: %{
              bill_payment_id: bill_payment_id,
              error: inspect(reason)
            }
          )
        end

        {:error, :fetch_failed}
    end
  end

  # Finds the linked Bill ID from LinkedTxn array
  defp find_linked_bill(linked_txns) when is_list(linked_txns) do
    # LinkedTxn format: [%{"TxnId" => "123", "TxnType" => "Bill"}]
    bill_txn =
      Enum.find(linked_txns, fn txn ->
        Map.get(txn, "TxnType") == "Bill"
      end)

    case bill_txn do
      %{"TxnId" => bill_id} ->
        {:ok, bill_id}

      _ ->
        {:error, :no_linked_bill}
    end
  end

  defp find_linked_bill(_), do: {:error, :no_linked_bill}

  # Finds an expense report by its QuickBooks bill ID
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
