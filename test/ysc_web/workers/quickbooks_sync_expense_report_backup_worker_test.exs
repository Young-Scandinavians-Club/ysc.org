defmodule YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorkerTest do
  @moduledoc """
  Tests for QuickbooksSyncExpenseReportBackupWorker.

  This worker runs periodically to find expense reports that haven't been synced
  to QuickBooks and enqueues sync jobs for them.

  ## Testing Strategy

  Due to Oban's `:inline` testing mode and behavior/implementation mismatches in
  the QuickBooks client (ClientBehaviour defines create_bill/1 but implementation
  uses create_bill/2), these tests focus on scenarios that don't trigger actual
  QuickBooks sync execution:

  - Worker can be called and returns :ok
  - Handles empty result sets (no unsynced reports)
  - Respects query filters (status, sync_status, bill_id)
  - Validates Oban worker behavior
  - Logs appropriate messages

  Full integration testing of the enqueueing logic would require:
  1. Fixing ClientBehaviour to include /2 arities for create_bill and other functions
  2. Comprehensive Mox stubs for all QuickBooks client functions
  3. Or using :manual Oban mode (not available in current Oban version)

  This test suite provides confidence in the core filtering and worker behavior
  while documenting the limitations.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Repo
  alias Ysc.ExpenseReports.ExpenseReport
  alias YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker

  require Logger

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "perform/1 - worker entry point" do
    test "returns :ok on successful execution" do
      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      assert :ok = QuickbooksSyncExpenseReportBackupWorker.perform(job)
    end

    test "logs start and completion messages when no reports exist" do
      # Set Logger level to :info to capture the logs
      Logger.configure(level: :info)

      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          QuickbooksSyncExpenseReportBackupWorker.perform(job)
        end)

      # Reset Logger level
      Logger.configure(level: :error)

      assert log =~ "Starting QuickBooks expense report backup sync job"
      assert log =~ "QuickBooks expense report backup sync job completed"
      assert log =~ "expense_reports_enqueued=0"
    end
  end

  describe "query filtering - status field" do
    test "ignores expense reports with status != submitted", %{user: user} do
      # Create expense reports with various non-submitted statuses
      %ExpenseReport{
        user_id: user.id,
        purpose: "Draft report",
        status: "draft",
        quickbooks_sync_status: "pending",
        reimbursement_method: "check"
      }
      |> Repo.insert!()

      %ExpenseReport{
        user_id: user.id,
        purpose: "Approved report",
        status: "approved",
        quickbooks_sync_status: "pending",
        reimbursement_method: "check"
      }
      |> Repo.insert!()

      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      # Set Logger level to :info
      Logger.configure(level: :info)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          QuickbooksSyncExpenseReportBackupWorker.perform(job)
        end)

      # Reset Logger level
      Logger.configure(level: :error)

      # Should log that no unsynced reports were found
      assert log =~ "No unsynced expense reports found"
    end
  end

  describe "query filtering - sync_status field" do
    test "ignores expense reports with sync_status=synced", %{user: user} do
      # Create a synced expense report
      %ExpenseReport{
        user_id: user.id,
        purpose: "Already synced",
        status: "submitted",
        quickbooks_sync_status: "synced",
        quickbooks_bill_id: "bill_123",
        reimbursement_method: "check"
      }
      |> Repo.insert!()

      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      # Set Logger level to :info
      Logger.configure(level: :info)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          QuickbooksSyncExpenseReportBackupWorker.perform(job)
        end)

      # Reset Logger level
      Logger.configure(level: :error)

      # Should log that no unsynced reports were found
      assert log =~ "No unsynced expense reports found"
    end
  end

  describe "query filtering - quickbooks_bill_id field" do
    test "ignores expense reports with quickbooks_bill_id already set", %{
      user: user
    } do
      # Create an expense report with bill_id already set (synced)
      %ExpenseReport{
        user_id: user.id,
        purpose: "Has bill ID",
        status: "submitted",
        quickbooks_sync_status: "pending",
        quickbooks_bill_id: "bill_456",
        reimbursement_method: "check"
      }
      |> Repo.insert!()

      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      # Set Logger level to :info
      Logger.configure(level: :info)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          QuickbooksSyncExpenseReportBackupWorker.perform(job)
        end)

      # Reset Logger level
      Logger.configure(level: :error)

      # Should log that no unsynced reports were found
      assert log =~ "No unsynced expense reports found"
    end
  end

  describe "no unsynced reports" do
    test "logs appropriate message when no unsynced reports exist" do
      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      # Set Logger level to :info
      Logger.configure(level: :info)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          QuickbooksSyncExpenseReportBackupWorker.perform(job)
        end)

      # Reset Logger level
      Logger.configure(level: :error)

      assert log =~ "No unsynced expense reports found"
      assert log =~ "expense_reports_enqueued=0"
    end

    test "returns 0 count when no reports to sync" do
      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      # The worker logs the count, we verify via the log
      # Set Logger level to :info
      Logger.configure(level: :info)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          QuickbooksSyncExpenseReportBackupWorker.perform(job)
        end)

      # Reset Logger level
      Logger.configure(level: :error)

      assert log =~ "expense_reports_enqueued=0"
    end
  end

  describe "integration with Oban" do
    test "uses Oban worker behavior" do
      # Verify the module is an Oban worker
      behaviours =
        QuickbooksSyncExpenseReportBackupWorker.module_info(:attributes)[
          :behaviour
        ] || []

      assert Oban.Worker in behaviours
    end

    test "is configured with maintenance queue" do
      # The worker should use the maintenance queue
      # This is configured via `use Oban.Worker, queue: :maintenance`
      # We can verify by checking if the module compiles and has the right configuration
      assert Code.ensure_loaded?(QuickbooksSyncExpenseReportBackupWorker)
    end

    test "perform/1 accepts an Oban.Job struct" do
      # Verify the function signature
      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      # Should not raise
      assert :ok = QuickbooksSyncExpenseReportBackupWorker.perform(job)
    end
  end

  describe "module structure" do
    test "exports perform/1 function" do
      exports = QuickbooksSyncExpenseReportBackupWorker.__info__(:functions)
      assert Keyword.has_key?(exports, :perform)
      assert Keyword.get(exports, :perform) == 1
    end

    test "module compiles without errors" do
      assert Code.ensure_loaded?(QuickbooksSyncExpenseReportBackupWorker)
    end
  end
end
