defmodule Ysc.ExpenseReports.Scheduler do
  @moduledoc """
  Schedules expense report QuickBooks sync jobs on startup.

  This module ensures that the expense report backup sync worker runs on application
  startup to catch any expense reports that need to be synced to QuickBooks.
  """

  alias YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker

  @doc """
  Starts the expense report sync scheduler.
  This should be called during application startup.
  """
  def start_scheduler do
    require Logger

    Logger.info(
      "Expense report QuickBooks sync scheduler initialized - enqueueing initial sync job"
    )

    schedule_immediate_sync()
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
        require Logger

        Logger.debug("Scheduled expense report QuickBooks sync job",
          job_id: job.id
        )

        {:ok, job}

      {:error, reason} ->
        require Logger

        Logger.error("Failed to schedule expense report QuickBooks sync job",
          error: inspect(reason)
        )

        {:error, reason}
    end
  end
end
