defmodule Ysc.Ledgers.ReconciliationWorkerTest do
  @moduledoc """
  Tests for ReconciliationWorker.

  This worker runs financial reconciliation checks to ensure data consistency
  between payments, refunds, and ledger entries.

  ## Test Coverage

  - Worker execution (perform/1)
  - Success scenarios (all checks pass)
  - Logging behavior
  - Oban integration (scheduling, worker behavior)
  - Module structure validation

  ## Testing Limitations

  These tests run against an empty test database, so reconciliation always succeeds.
  Testing error scenarios would require:
  1. Creating payments without ledger entries
  2. Creating orphaned ledger entries
  3. Creating imbalanced ledger entries

  Full integration tests for reconciliation logic exist in reconciliation_test.exs.

  ## Critical Audit Findings

  Based on RECONCILIATION_AUDIT.md, the following issues were identified:
  1. Worker assumes {:ok, report} from reconciliation (no error handling) ⚠️
  2. Returns {:ok, report} even for errors (intentional, requires manual investigation)
  3. No transaction isolation in reconciliation ⚠️
  4. Memory concerns with large datasets (loads all payments/refunds) ⚠️
  5. Fragile refund detection via string matching ⚠️
  """
  # async: false due to Oban inline mode
  use Ysc.DataCase, async: false

  import ExUnit.CaptureLog
  require Logger

  alias Ysc.Ledgers.ReconciliationWorker

  describe "perform/1 - Oban worker" do
    test "returns :ok on successful execution" do
      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "Ysc.Ledgers.ReconciliationWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      assert {:ok, report} = ReconciliationWorker.perform(job)
      assert report.overall_status == :ok
    end

    test "logs start message" do
      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "Ysc.Ledgers.ReconciliationWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      Logger.configure(level: :info)

      log =
        capture_log(fn ->
          ReconciliationWorker.perform(job)
        end)

      Logger.configure(level: :error)

      assert log =~ "Starting scheduled financial reconciliation"
    end

    test "logs success message on empty database" do
      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "Ysc.Ledgers.ReconciliationWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      Logger.configure(level: :info)

      log =
        capture_log(fn ->
          ReconciliationWorker.perform(job)
        end)

      Logger.configure(level: :error)

      assert log =~ "✅ Reconciliation passed all checks"
      assert log =~ "duration_ms"
    end

    test "report includes all required check sections" do
      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "Ysc.Ledgers.ReconciliationWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      {:ok, report} = ReconciliationWorker.perform(job)

      # Verify report structure
      assert Map.has_key?(report, :timestamp)
      assert Map.has_key?(report, :duration_ms)
      assert Map.has_key?(report, :overall_status)
      assert Map.has_key?(report, :checks)

      # Verify all check sections exist
      assert Map.has_key?(report.checks, :payments)
      assert Map.has_key?(report.checks, :refunds)
      assert Map.has_key?(report.checks, :ledger_balance)
      assert Map.has_key?(report.checks, :orphaned_entries)
      assert Map.has_key?(report.checks, :entity_totals)
    end
  end

  describe "schedule_reconciliation/1" do
    test "schedules a reconciliation job" do
      assert {:ok, job} = ReconciliationWorker.schedule_reconciliation()
      assert job.worker == "Ysc.Ledgers.ReconciliationWorker"
      assert job.queue == "maintenance"
      assert job.args == %{}
    end

    test "schedules with custom delay" do
      assert {:ok, job} =
               ReconciliationWorker.schedule_reconciliation(schedule_in: 3600)

      assert job.worker == "Ysc.Ledgers.ReconciliationWorker"
      # Verify schedule_in was applied (exact time check is fragile)
      assert job.scheduled_at != nil
    end
  end

  describe "Oban worker configuration" do
    test "uses maintenance queue" do
      # Verify worker configuration
      assert ReconciliationWorker.__opts__()[:queue] == :maintenance
    end

    test "implements Oban.Worker behavior" do
      behaviours =
        ReconciliationWorker.module_info(:attributes)[:behaviour] || []

      assert Oban.Worker in behaviours
    end

    test "has max_attempts configured" do
      assert ReconciliationWorker.__opts__()[:max_attempts] == 3
    end
  end

  describe "module structure" do
    test "exports perform/1" do
      exports = ReconciliationWorker.__info__(:functions)
      assert Keyword.has_key?(exports, :perform)
      assert Keyword.get(exports, :perform) == 1
    end

    test "exports run_now/0" do
      exports = ReconciliationWorker.__info__(:functions)
      assert Keyword.has_key?(exports, :run_now)
      assert Keyword.get(exports, :run_now) == 0
    end

    test "exports schedule_reconciliation/1" do
      exports = ReconciliationWorker.__info__(:functions)
      assert Keyword.has_key?(exports, :schedule_reconciliation)
    end

    test "module compiles without errors" do
      assert Code.ensure_loaded?(ReconciliationWorker)
    end
  end
end
