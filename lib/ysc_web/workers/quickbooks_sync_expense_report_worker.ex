defmodule YscWeb.Workers.QuickbooksSyncExpenseReportWorker do
  @moduledoc """
  Oban worker for syncing ExpenseReport records to QuickBooks.

  This worker processes expense reports asynchronously and creates Bills in QuickBooks.
  """

  require Logger
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Ysc.ExpenseReports
  alias Ysc.ExpenseReports.QuickbooksSync
  alias Ysc.Repo
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"expense_report_id" => expense_report_id}}) do
    Logger.info("Starting QuickBooks sync for expense report",
      expense_report_id: expense_report_id
    )

    # Convert expense_report_id string to ULID if needed
    expense_report_id_ulid =
      case Ecto.ULID.cast(expense_report_id) do
        {:ok, ulid} -> ulid
        _ -> expense_report_id
      end

    # Lock the expense report record to prevent concurrent processing
    # Preload associations needed for sync within the transaction
    case Repo.transaction(fn ->
           from(er in ExpenseReports.ExpenseReport,
             where: er.id == ^expense_report_id_ulid,
             lock: "FOR UPDATE NOWAIT"
           )
           |> Repo.one()
           |> case do
             nil ->
               nil

             expense_report ->
               preloaded =
                 expense_report
                 |> Repo.preload([
                   :expense_items,
                   :income_items,
                   :address,
                   :bank_account,
                   :event
                 ])
                 |> Repo.preload(user: :billing_address)

               Logger.debug("Preloaded expense report associations",
                 expense_report_id: preloaded.id,
                 user_loaded: Ecto.assoc_loaded?(preloaded.user),
                 expense_items_count:
                   if(Ecto.assoc_loaded?(preloaded.expense_items),
                     do: length(preloaded.expense_items),
                     else: :not_loaded
                   ),
                 income_items_count:
                   if(Ecto.assoc_loaded?(preloaded.income_items),
                     do: length(preloaded.income_items),
                     else: :not_loaded
                   )
               )

               preloaded
           end
         end) do
      {:ok, nil} ->
        Logger.warning("Expense report not found for QuickBooks sync",
          expense_report_id: expense_report_id
        )

        # Not found is expected sometimes (e.g. stale job); don't retry.
        {:discard, :expense_report_not_found}

      {:ok, expense_report} ->
        # Idempotency check: If bill_id exists, don't sync again (prevents duplicate bills)
        # This check happens after acquiring the lock to ensure we have the latest data
        if expense_report.quickbooks_bill_id do
          Logger.info(
            "Expense report already has QuickBooks bill ID, skipping sync (idempotency)",
            expense_report_id: expense_report_id,
            bill_id: expense_report.quickbooks_bill_id,
            sync_status: expense_report.quickbooks_sync_status
          )

          :ok
        else
          # Check if already synced (double-check after acquiring lock)
          # This prevents duplicate exports if the report was synced between job creation and execution
          cond do
            expense_report.quickbooks_sync_status == "synced" ->
              Logger.info(
                "Expense report already synced to QuickBooks (checked after lock)",
                expense_report_id: expense_report_id,
                sync_status: expense_report.quickbooks_sync_status
              )

              :ok

            # Allow retry for "failed" status, but skip other unexpected statuses
            expense_report.quickbooks_sync_status != "pending" &&
              expense_report.quickbooks_sync_status != "failed" &&
                expense_report.quickbooks_sync_status != nil ->
              Logger.warning(
                "Expense report has unexpected sync status, skipping",
                expense_report_id: expense_report_id,
                sync_status: expense_report.quickbooks_sync_status
              )

              :ok

            true ->
              # If status is "failed", log that we're retrying
              if expense_report.quickbooks_sync_status == "failed" do
                Logger.info(
                  "Retrying QuickBooks sync for previously failed expense report",
                  expense_report_id: expense_report_id,
                  previous_error: expense_report.quickbooks_sync_error
                )
              end

              case QuickbooksSync.sync_expense_report(expense_report) do
                {:ok, bill} ->
                  Logger.info(
                    "Successfully synced expense report to QuickBooks",
                    expense_report_id: expense_report_id,
                    bill_id: Map.get(bill, "Id")
                  )

                  :ok

                {:error, reason} ->
                  Logger.warning("Failed to sync expense report to QuickBooks",
                    expense_report_id: expense_report_id,
                    error: inspect(reason)
                  )

                  Sentry.capture_message(
                    "QuickBooks expense report sync worker failed",
                    level: :error,
                    extra: %{
                      expense_report_id: expense_report_id,
                      error: inspect(reason)
                    },
                    tags: %{
                      quickbooks_worker: "sync_expense_report",
                      error_type: "sync_failed"
                    }
                  )

                  # Oban will retry based on max_attempts
                  {:error, reason}
              end
          end
        end

      {:error, %Postgrex.Error{postgres: %{code: :lock_not_available}}} ->
        # Another worker is processing this expense report
        Logger.info("Expense report is locked by another worker, skipping",
          expense_report_id: expense_report_id
        )

        :ok

      {:error, reason} ->
        Logger.warning("Failed to lock expense report for QuickBooks sync",
          expense_report_id: expense_report_id,
          error: inspect(reason)
        )

        # Report to Sentry (only for non-lock errors)
        unless match?(
                 %Postgrex.Error{postgres: %{code: :lock_not_available}},
                 reason
               ) do
          Sentry.capture_message(
            "Failed to lock expense report for QuickBooks sync",
            level: :error,
            extra: %{
              expense_report_id: expense_report_id,
              error: inspect(reason)
            },
            tags: %{
              quickbooks_worker: "sync_expense_report",
              error_type: "lock_failed"
            }
          )
        end

        {:error, reason}
    end
  end
end
