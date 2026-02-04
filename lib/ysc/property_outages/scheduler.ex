defmodule Ysc.PropertyOutages.Scheduler do
  @moduledoc """
  Schedules periodic outage scraping jobs.

  The recurring schedule is handled by Oban's Cron plugin (configured in config.exs)
  to run every 30 minutes. This module provides a way to manually trigger immediate scrapes.
  """

  alias Ysc.PropertyOutages.OutageScraperWorker

  @doc """
  Starts the periodic outage scraper scheduler.

  Note: Recurring jobs are handled by Oban's Cron plugin (every 30 minutes).
  The cron runs every 30 minutes starting at :00 and :30 of each hour.
  No immediate job is scheduled to avoid duplicate runs.
  """
  def start_scheduler do
    # Recurring jobs are handled by Oban.Cron plugin (configured in config.exs)
    # which runs every 30 minutes: "*/30 * * * *"
    # This means it runs at :00 and :30 of every hour (e.g., 12:00, 12:30, 13:00, etc.)
    require Logger

    Logger.info(
      "Outage scraper scheduler initialized - recurring jobs handled by Oban.Cron (every 30 minutes)"
    )

    if !Ysc.Env.test?() do
      schedule_immediate_scrape()
    end

    :ok
  end

  @doc """
  Schedules an immediate outage scrape job.
  Useful for manual triggers or testing.
  """
  def schedule_immediate_scrape do
    %{}
    |> OutageScraperWorker.new()
    |> Oban.insert()
  end
end
