defmodule Mix.Tasks.CheckQuickbooksSync do
  @moduledoc """
  Check QuickBooks sync status for expense reports and manually trigger sync if needed.

  Usage:
    mix check_quickbooks_sync
    mix check_quickbooks_sync --expense-report-id 01KBGH7PKBK5J056WX9QPZN4P4
    mix check_quickbooks_sync --trigger 01KBGH7PKBK5J056WX9QPZN4P4
  """

  use Mix.Task
  require Ysc.Logging

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
    Ysc.Logging.info("=== Checking Expense Report: #{expense_report_id} ===")

    # Get the expense report
    case Repo.get(ExpenseReports.ExpenseReport, expense_report_id) do
      nil ->
        Ysc.Logging.error("Expense report not found: #{expense_report_id}")

      expense_report ->
        Ysc.Logging.info("Expense Report Status:")
        Ysc.Logging.info("  ID: #{expense_report.id}")
        Ysc.Logging.info("  Status: #{expense_report.status}")

        Ysc.Logging.info(
          "  QuickBooks Sync Status: #{expense_report.quickbooks_sync_status}"
        )

        Ysc.Logging.info(
          "  QuickBooks Bill ID: #{inspect(expense_report.quickbooks_bill_id)}"
        )

        Ysc.Logging.info(
          "  QuickBooks Vendor ID: #{inspect(expense_report.quickbooks_vendor_id)}"
        )

        Ysc.Logging.info(
          "  Last Sync Attempt: #{inspect(expense_report.quickbooks_last_sync_attempt_at)}"
        )

        Ysc.Logging.info(
          "  Synced At: #{inspect(expense_report.quickbooks_synced_at)}"
        )

        # Check for Oban jobs
        Ysc.Logging.info("")
        Ysc.Logging.info("=== Checking Oban Jobs ===")

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
          Ysc.Logging.warning("No Oban jobs found for this expense report")
        else
          Ysc.Logging.info("Found #{length(jobs)} job(s):")

          Enum.each(jobs, fn job ->
            Ysc.Logging.info("  Job ID: #{job.id}")
            Ysc.Logging.info("    State: #{job.state}")
            Ysc.Logging.info("    Queue: #{job.queue}")
            Ysc.Logging.info("    Attempt: #{job.attempt}/#{job.max_attempts}")
            Ysc.Logging.info("    Inserted: #{job.inserted_at}")
            Ysc.Logging.info("    Scheduled: #{job.scheduled_at}")

            if job.attempted_at,
              do: Ysc.Logging.info("    Attempted: #{job.attempted_at}")

            if job.errors,
              do: Ysc.Logging.info("    Errors: #{inspect(job.errors)}")
          end)
        end

        if should_trigger do
          Ysc.Logging.info("")
          Ysc.Logging.info("=== Triggering QuickBooks Sync ===")

          case QuickbooksSyncExpenseReportWorker.new(%{
                 "expense_report_id" => expense_report_id
               })
               |> Oban.insert() do
            {:ok, job} ->
              Ysc.Logging.info("Successfully enqueued QuickBooks sync job",
                job_id: job.id,
                queue: job.queue
              )

            {:error, reason} ->
              Ysc.Logging.error("Failed to enqueue QuickBooks sync job",
                error: inspect(reason)
              )
          end
        end
    end
  end

  defp list_pending_reports do
    Ysc.Logging.info("=== Pending QuickBooks Sync Reports ===")

    pending_reports =
      from(er in ExpenseReports.ExpenseReport,
        where: er.quickbooks_sync_status == "pending",
        where: er.status == "submitted",
        order_by: [desc: er.inserted_at],
        limit: 10
      )
      |> Repo.all()

    if Enum.empty?(pending_reports) do
      Ysc.Logging.info("No pending expense reports found")
    else
      Ysc.Logging.info("Found #{length(pending_reports)} pending report(s):")

      Enum.each(pending_reports, fn report ->
        Ysc.Logging.info("  ID: #{report.id}")
        Ysc.Logging.info("    Purpose: #{report.purpose}")
        Ysc.Logging.info("    Created: #{report.inserted_at}")
        Ysc.Logging.info("    Status: #{report.status}")
      end)
    end
  end
end
