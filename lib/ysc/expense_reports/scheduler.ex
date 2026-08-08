defmodule Ysc.ExpenseReports.Scheduler do
  @moduledoc """
  Schedules expense report QuickBooks sync jobs.

  The recurring schedule is handled by Oban's Cron plugin (configured in config.exs)
  to run every 6 hours. This module provides a way to manually trigger an immediate sync.
  """

  alias YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker

  @doc """
  Starts the expense report sync scheduler.
  This should be called during application startup.

  Note: Recurring jobs are handled by Oban's Cron plugin (every 6 hours).
  No immediate job is scheduled on boot - the next cron tick covers it.
  """
  def start_scheduler do
    require Ysc.Logging

    Ysc.Logging.info(
      "Expense report QuickBooks sync scheduler initialized - recurring jobs handled by Oban.Cron (every 6 hours)"
    )

    :ok
  end

  @doc """
  Schedules an immediate expense report sync job.
  Useful for manual triggers or testing.
  """
  def schedule_immediate_sync do
    %{}
    |> QuickbooksSyncExpenseReportBackupWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, job} ->
        require Ysc.Logging

        Ysc.Logging.debug("Scheduled expense report QuickBooks sync job",
          job_id: job.id
        )

        {:ok, job}

      {:error, reason} ->
        require Ysc.Logging

        Ysc.Logging.error(
          "Failed to schedule expense report QuickBooks sync job",
          error: inspect(reason)
        )

        {:error, reason}
    end
  end
end
