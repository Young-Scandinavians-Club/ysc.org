defmodule Mix.Tasks.CheckQuickbooksSync do
  @moduledoc """
  Check QuickBooks sync status for expense reports and manually trigger sync if needed.

  Usage:
    mix check_quickbooks_sync
    mix check_quickbooks_sync --expense-report-id 01KBGH7PKBK5J056WX9QPZN4P4
    mix check_quickbooks_sync --trigger 01KBGH7PKBK5J056WX9QPZN4P4
  """

  use Mix.Task
  require Logger

  @shortdoc "Check QuickBooks sync status for expense reports"

  alias Ysc.Repo
  alias Ysc.ExpenseReports
  alias YscWeb.Workers.QuickbooksSyncExpenseReportWorker
  import Ecto.Query

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [expense_report_id: :string, trigger: :string]
      )

    Mix.Task.run("app.start")

    expense_report_id =
      Keyword.get(opts, :expense_report_id) || Keyword.get(opts, :trigger)

    if expense_report_id do
      check_and_trigger(expense_report_id, Keyword.has_key?(opts, :trigger))
    else
      list_pending_reports()
    end
  end

  defp check_and_trigger(expense_report_id, should_trigger) do
    Logger.info("=== Checking Expense Report: #{expense_report_id} ===")

    # Get the expense report
    case Repo.get(ExpenseReports.ExpenseReport, expense_report_id) do
      nil ->
        Logger.error("Expense report not found: #{expense_report_id}")

      expense_report ->
        Logger.info("Expense Report Status:")
        Logger.info("  ID: #{expense_report.id}")
        Logger.info("  Status: #{expense_report.status}")

        Logger.info(
          "  QuickBooks Sync Status: #{expense_report.quickbooks_sync_status}"
        )

        Logger.info(
          "  QuickBooks Bill ID: #{inspect(expense_report.quickbooks_bill_id)}"
        )

        Logger.info(
          "  QuickBooks Vendor ID: #{inspect(expense_report.quickbooks_vendor_id)}"
        )

        Logger.info(
          "  Last Sync Attempt: #{inspect(expense_report.quickbooks_last_sync_attempt_at)}"
        )

        Logger.info(
          "  Synced At: #{inspect(expense_report.quickbooks_synced_at)}"
        )

        # Check for Oban jobs
        Logger.info("")
        Logger.info("=== Checking Oban Jobs ===")

        jobs =
          from(j in Oban.Job,
            where:
              j.worker == "YscWeb.Workers.QuickbooksSyncExpenseReportWorker",
            where:
              fragment(
                "?->>'expense_report_id' = ?",
                j.args,
                ^expense_report_id
              ),
            order_by: [desc: j.inserted_at]
          )
          |> Repo.all()

        if Enum.empty?(jobs) do
          Logger.warning("No Oban jobs found for this expense report")
        else
          Logger.info("Found #{length(jobs)} job(s):")

          Enum.each(jobs, fn job ->
            Logger.info("  Job ID: #{job.id}")
            Logger.info("    State: #{job.state}")
            Logger.info("    Queue: #{job.queue}")
            Logger.info("    Attempt: #{job.attempt}/#{job.max_attempts}")
            Logger.info("    Inserted: #{job.inserted_at}")
            Logger.info("    Scheduled: #{job.scheduled_at}")

            if job.attempted_at,
              do: Logger.info("    Attempted: #{job.attempted_at}")

            if job.errors, do: Logger.info("    Errors: #{inspect(job.errors)}")
          end)
        end

        if should_trigger do
          Logger.info("")
          Logger.info("=== Triggering QuickBooks Sync ===")

          case QuickbooksSyncExpenseReportWorker.new(%{
                 "expense_report_id" => expense_report_id
               })
               |> Oban.insert() do
            {:ok, job} ->
              Logger.info("Successfully enqueued QuickBooks sync job",
                job_id: job.id,
                queue: job.queue
              )

            {:error, reason} ->
              Logger.error("Failed to enqueue QuickBooks sync job",
                error: inspect(reason)
              )
          end
        end
    end
  end

  defp list_pending_reports do
    Logger.info("=== Pending QuickBooks Sync Reports ===")

    pending_reports =
      from(er in ExpenseReports.ExpenseReport,
        where: er.quickbooks_sync_status == "pending",
        where: er.status == "submitted",
        order_by: [desc: er.inserted_at],
        limit: 10
      )
      |> Repo.all()

    if Enum.empty?(pending_reports) do
      Logger.info("No pending expense reports found")
    else
      Logger.info("Found #{length(pending_reports)} pending report(s):")

      Enum.each(pending_reports, fn report ->
        Logger.info("  ID: #{report.id}")
        Logger.info("    Purpose: #{report.purpose}")
        Logger.info("    Created: #{report.inserted_at}")
        Logger.info("    Status: #{report.status}")
      end)
    end
  end
end
