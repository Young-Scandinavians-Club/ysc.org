defmodule YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker do
  @moduledoc """
  Oban worker that runs periodically to find and export ExpenseReports that haven't been
  synced to QuickBooks yet.

  This worker:
  1. Finds all expense reports with status="submitted" and quickbooks_sync_status="pending" (or nil)
  2. Checks if there's already an Oban job enqueued for each report
  3. Enqueues sync jobs for any reports that don't have jobs already

  This ensures that any expense reports that failed to sync initially, or were created
  before the sync system was in place, will eventually be synced.

  Scheduled to run every 6 hours via Oban.Plugins.Cron.
  """

  require Logger
  use Oban.Worker, queue: :maintenance

  alias Ysc.Repo
  alias Ysc.ExpenseReports.ExpenseReport
  alias YscWeb.Workers.QuickbooksSyncExpenseReportWorker
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.info("Starting QuickBooks expense report backup sync job")

    count = enqueue_unsynced_expense_reports()

    Logger.info("QuickBooks expense report backup sync job completed",
      expense_reports_enqueued: count
    )

    :ok
  end

  defp enqueue_unsynced_expense_reports do
    # Use a transaction with row-level locking to prevent duplicate processing
    # FOR UPDATE SKIP LOCKED will skip any reports currently being processed by another worker
    Repo.transaction(fn ->
      # Find and lock expense reports that are submitted but not synced
      # FOR UPDATE SKIP LOCKED ensures we only process reports that aren't currently locked
      # Include "failed" status to allow retries
      unsynced_reports =
        from(er in ExpenseReport,
          where: er.status == "submitted",
          where:
            is_nil(er.quickbooks_sync_status) or
              er.quickbooks_sync_status == "pending" or
              er.quickbooks_sync_status == "failed",
          where: is_nil(er.quickbooks_bill_id),
          lock: "FOR UPDATE SKIP LOCKED",
          select: er.id,
          limit: 1000,
          order_by: [asc: er.inserted_at]
        )
        |> Repo.all()

      total_count = length(unsynced_reports)

      if total_count > 0 do
        Logger.info("Found unsynced expense reports (after locking)",
          count: total_count
        )

        # Get all existing jobs for these expense reports to avoid duplicates
        # Check for jobs in all active states including "executing" (currently running)
        existing_job_expense_report_ids =
          from(j in Oban.Job,
            where:
              j.worker == "YscWeb.Workers.QuickbooksSyncExpenseReportWorker",
            where:
              j.state in ["available", "executing", "retryable", "scheduled"],
            select: fragment("?->>'expense_report_id'", j.args)
          )
          |> Repo.all()
          |> Enum.map(&String.trim/1)
          |> MapSet.new()

        # Filter out reports that already have jobs
        reports_to_sync =
          unsynced_reports
          |> Enum.reject(fn report_id ->
            report_id_str = to_string(report_id)
            MapSet.member?(existing_job_expense_report_ids, report_id_str)
          end)

        enqueued_count = length(reports_to_sync)

        if enqueued_count > 0 do
          Logger.info("Enqueueing sync jobs for expense reports",
            total_unsynced: total_count,
            already_queued: total_count - enqueued_count,
            newly_enqueued: enqueued_count
          )

          # Mark reports as pending and enqueue jobs atomically
          Enum.each(reports_to_sync, fn expense_report_id ->
            # Update status to "pending" to mark that we're processing it
            # This happens within the transaction, so it's atomic
            from(er in ExpenseReport,
              where: er.id == ^expense_report_id
            )
            |> Repo.update_all(set: [quickbooks_sync_status: "pending"])

            # Enqueue the sync job
            case QuickbooksSyncExpenseReportWorker.new(%{
                   "expense_report_id" => to_string(expense_report_id)
                 })
                 |> Oban.insert() do
              {:ok, job} ->
                Logger.debug("Enqueued QuickBooks sync for expense report",
                  expense_report_id: expense_report_id,
                  job_id: job.id
                )

              {:error, reason} ->
                Logger.error(
                  "Failed to enqueue QuickBooks sync for expense report",
                  expense_report_id: expense_report_id,
                  error: inspect(reason)
                )

                Sentry.capture_message(
                  "Failed to enqueue QuickBooks sync for expense report in backup worker",
                  level: :error,
                  extra: %{
                    expense_report_id: expense_report_id,
                    error: inspect(reason)
                  },
                  tags: %{
                    quickbooks_worker: "backup_sync_expense_report",
                    error_type: "enqueue_failed"
                  }
                )
            end
          end)
        else
          Logger.info("All unsynced expense reports already have jobs enqueued",
            total_unsynced: total_count
          )
        end

        enqueued_count
      else
        Logger.info("No unsynced expense reports found")
        0
      end
    end)
    |> case do
      {:ok, count} ->
        count

      {:error, reason} ->
        Logger.error("Failed to enqueue unsynced expense reports",
          error: inspect(reason)
        )

        0
    end
  end
end
