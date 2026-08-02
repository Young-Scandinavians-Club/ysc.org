defmodule Ysc.Tickets.Scheduler do
  @moduledoc """
  Schedules periodic ticket timeout checks.

  The recurring schedule is handled by Oban's Cron plugin (configured in config.exs)
  to run every 5 minutes. This module provides a way to manually trigger an immediate check.
  """

  alias Ysc.Tickets.TimeoutWorker

  @doc """
  Starts the periodic timeout scheduler.
  This should be called during application startup.

  Note: Recurring jobs are handled by Oban's Cron plugin (every 5 minutes).
  No immediate job is scheduled on boot - the next cron tick covers it.
  """
  def start_scheduler do
    :ok
  end

  @doc """
  Schedules an immediate timeout check.
  Useful for manual triggers or testing.
  """
  def schedule_next_timeout_check do
    TimeoutWorker.schedule_timeout_check()
  end
end
