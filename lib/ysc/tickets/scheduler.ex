defmodule Ysc.Tickets.Scheduler do
  @moduledoc """
  Schedules periodic ticket timeout checks.

  This module ensures that timeout workers are scheduled to run periodically
  to clean up expired ticket orders.
  """

  alias Ysc.Tickets.TimeoutWorker

  @doc """
  Starts the periodic timeout scheduler.
  This should be called during application startup.
  """
  def start_scheduler do
    # Schedule the first timeout check immediately
    schedule_next_timeout_check()

    # Schedule periodic checks every 5 minutes
    schedule_periodic_checks()
  end

  @doc """
  Schedules the next timeout check to run in 5 minutes.
  """
  def schedule_next_timeout_check do
    TimeoutWorker.schedule_timeout_check()
  end

  ## Private Functions

  defp schedule_periodic_checks do
    # Schedule a job to run every 5 minutes
    %{action: :schedule_next}
    # 5 minutes
    |> TimeoutWorker.new(schedule_in: 5 * 60)
    |> Oban.insert()
  end
end
