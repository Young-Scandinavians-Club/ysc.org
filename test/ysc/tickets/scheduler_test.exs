defmodule Ysc.Tickets.SchedulerTest do
  @moduledoc """
  Tests for Ysc.Tickets.Scheduler.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Tickets.Scheduler

  describe "scheduler" do
    test "start_scheduler/0 schedules immediate and periodic checks" do
      # In :inline mode, jobs execute immediately
      # We just verify that start_scheduler returns successfully
      assert {:ok, _job} = Scheduler.start_scheduler()
    end

    test "schedule_next_timeout_check/0 schedules a job" do
      # Returns {:ok, job} from TimeoutWorker.schedule_timeout_check
      assert {:ok, job} = Scheduler.schedule_next_timeout_check()
      assert job.worker == "Ysc.Tickets.TimeoutWorker"
    end
  end
end
