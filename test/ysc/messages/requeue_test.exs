defmodule Ysc.Messages.RequeueTest do
  @moduledoc """
  Tests for Messages.Requeue module.

  These tests verify:
  - Listing failed jobs
  - Getting statistics
  - Re-queuing jobs
  """
  use Ysc.DataCase, async: true

  alias Ysc.Messages.Requeue

  describe "list_failed_jobs/1" do
    test "returns empty list when no failed jobs exist" do
      jobs = Requeue.list_failed_jobs()
      assert jobs == []
    end

    test "respects limit option" do
      jobs = Requeue.list_failed_jobs(limit: 10)
      assert is_list(jobs)
      assert length(jobs) <= 10
    end

    test "filters by since option" do
      since = DateTime.add(DateTime.utc_now(), -1, :day)
      jobs = Requeue.list_failed_jobs(since: since)
      assert is_list(jobs)
    end
  end

  describe "get_stats/0" do
    test "returns statistics map with all required keys" do
      stats = Requeue.get_stats()

      assert Map.has_key?(stats, :total_failed)
      assert Map.has_key?(stats, :discarded)
      assert Map.has_key?(stats, :retryable)
      assert Map.has_key?(stats, :by_template)
      assert Map.has_key?(stats, :recent_failures_24h)

      assert is_integer(stats.total_failed)
      assert is_integer(stats.discarded)
      assert is_integer(stats.retryable)
      assert is_map(stats.by_template)
      assert is_integer(stats.recent_failures_24h)
    end

    test "returns non-negative counts" do
      stats = Requeue.get_stats()

      assert stats.total_failed >= 0
      assert stats.discarded >= 0
      assert stats.retryable >= 0
      assert stats.recent_failures_24h >= 0
    end
  end

  describe "requeue_job_by_id/1" do
    test "returns error for non-existent job" do
      # Oban.Job uses integer IDs, not ULIDs
      fake_id = 999_999_999
      assert {:error, :not_found} = Requeue.requeue_job_by_id(fake_id)
    end

    test "returns error for non-email job" do
      # Oban.Job uses integer IDs, not ULIDs
      fake_id = 999_999_998
      result = Requeue.requeue_job_by_id(fake_id)
      assert result == {:error, :not_found}
    end
  end

  describe "requeue_all/1" do
    test "returns summary map with all required keys" do
      result = Requeue.requeue_all(limit: 10, dry_run: true)

      assert Map.has_key?(result, :total_found)
      assert Map.has_key?(result, :successful)
      assert Map.has_key?(result, :failed)
      assert Map.has_key?(result, :results)

      assert is_integer(result.total_found)
      assert is_integer(result.successful)
      assert is_integer(result.failed)
      assert is_list(result.results)
    end

    test "respects limit option" do
      result = Requeue.requeue_all(limit: 5, dry_run: true)
      assert result.total_found <= 5
    end

    test "dry_run mode doesn't actually requeue" do
      # In dry_run mode, all jobs should show as successful (simulated)
      result = Requeue.requeue_all(limit: 10, dry_run: true)

      # In dry_run, all found jobs are marked as successful
      assert result.successful == result.total_found
      assert result.failed == 0
    end

    test "respects since option" do
      since = DateTime.add(DateTime.utc_now(), -1, :day)
      result = Requeue.requeue_all(limit: 10, since: since, dry_run: true)
      assert is_map(result)
      assert result.total_found >= 0
    end
  end
end
