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

  alias Ysc.Ledgers.ReconciliationWorker
  alias Ysc.Ledgers
  alias Ysc.Ledgers.Reconciliation
  alias Ysc.Ledgers.{LedgerEntry, LedgerTransaction, Payment, Refund}
  alias Ysc.Repo

  import Ysc.AccountsFixtures

  describe "perform/1 - payment discrepancies" do
    setup do
      Ledgers.ensure_basic_accounts()
      %{user: user_fixture()}
    end

    test "returns {:ok, report} with payment discrepancies when payment has no ledger transaction",
         %{user: user} do
      assert {:ok, _} =
               %Payment{}
               |> Payment.changeset(%{
                 user_id: user.id,
                 external_provider: :stripe,
                 external_payment_id:
                   "pi_orphan_#{System.unique_integer([:positive])}",
                 amount: Money.new(1_000, :USD),
                 status: :completed,
                 payment_date: DateTime.utc_now() |> DateTime.truncate(:second)
               })
               |> Repo.insert()

      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "Ysc.Ledgers.ReconciliationWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      assert {:ok, report} = ReconciliationWorker.perform(job)
      assert report.overall_status == :error
      assert report.checks.payments.discrepancies_count >= 1
    end
  end

  describe "perform/1 - reconciliation discrepancies" do
    setup do
      Ledgers.ensure_basic_accounts()
      %{user: user_fixture()}
    end

    test "returns {:ok, report} with overall_status :error when ledger is imbalanced",
         %{
           user: user
         } do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_provider: :stripe,
          external_payment_id: "pi_worker_imbalance_#{System.unique_integer()}",
          payment_date: DateTime.truncate(DateTime.utc_now(), :second),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "Test payment for worker imbalance",
          property: :general,
          payment_method_id: nil
        })

      stripe_account = Ledgers.get_account_by_name("stripe_account")

      Repo.insert!(%LedgerEntry{
        account_id: stripe_account.id,
        amount: Money.new(5000, :USD),
        description: "Test imbalance entry",
        payment_id: payment.id,
        debit_credit: :debit
      })

      assert {:ok, report} = Reconciliation.run_full_reconciliation()
      assert report.overall_status == :error

      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "Ysc.Ledgers.ReconciliationWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      assert {:ok, worker_report} = ReconciliationWorker.perform(job)
      assert worker_report.overall_status == :error
    end
  end

  describe "perform/1 - alert section builders (Discord + formatted alert body)" do
    setup do
      Ledgers.ensure_basic_accounts()
      %{user: user_fixture()}
    end

    test "runs when membership entity totals diverge from payments", %{
      user: user
    } do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_provider: :stripe,
          external_payment_id:
            "pi_worker_entity_#{System.unique_integer([:positive])}",
          payment_date: DateTime.truncate(DateTime.utc_now(), :second),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "Entity mismatch for worker",
          property: :general,
          payment_method_id: nil
        })

      membership_revenue = Ledgers.get_account_by_name("membership_revenue")

      Repo.insert!(%LedgerEntry{
        account_id: membership_revenue.id,
        amount: Money.new(5000, :USD),
        description: "Extra revenue for worker test",
        payment_id: payment.id,
        related_entity_type: :membership,
        debit_credit: :credit
      })

      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "Ysc.Ledgers.ReconciliationWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      assert {:ok, report} = ReconciliationWorker.perform(job)
      assert report.overall_status == :error
      assert report.checks.entity_totals.status == :error
      assert report.checks.entity_totals.memberships.match == false
    end

    test "runs when a refund has a transaction but no refund ledger entries", %{
      user: user
    } do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_provider: :stripe,
          external_payment_id:
            "pi_worker_refund_#{System.unique_integer([:positive])}",
          payment_date: DateTime.truncate(DateTime.utc_now(), :second),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "Refund discrepancy worker test",
          property: :general,
          payment_method_id: nil
        })

      refund =
        Repo.insert!(%Refund{
          user_id: user.id,
          payment_id: payment.id,
          amount: Money.new(5000, :USD),
          external_provider: :stripe,
          external_refund_id:
            "re_worker_no_entries_#{System.unique_integer([:positive])}",
          status: :completed,
          reason: "test"
        })

      Repo.insert!(%LedgerTransaction{
        type: :refund,
        refund_id: refund.id,
        payment_id: payment.id,
        total_amount: refund.amount,
        status: :completed
      })

      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "Ysc.Ledgers.ReconciliationWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      assert {:ok, report} = ReconciliationWorker.perform(job)
      assert report.overall_status == :error
      assert report.checks.refunds.discrepancies_count == 1
      assert report.checks.payments.discrepancies_count == 0
    end

    test "runs when a ledger entry references a deleted payment (orphaned entry)",
         %{user: user} do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_provider: :stripe,
          external_payment_id:
            "pi_worker_orphan_#{System.unique_integer([:positive])}",
          payment_date: DateTime.truncate(DateTime.utc_now(), :second),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "Orphan scenario",
          property: :general,
          payment_method_id: nil
        })

      orphaned_payment_id = payment.id
      payment_uuid = to_uuid(orphaned_payment_id)

      with_trigger_disabled(fn ->
        Ecto.Adapters.SQL.query!(
          Repo,
          "DELETE FROM ledger_entries WHERE payment_id = $1",
          [payment_uuid]
        )
      end)

      Ecto.Adapters.SQL.query!(
        Repo,
        "DELETE FROM ledger_transactions WHERE payment_id = $1",
        [payment_uuid]
      )

      Ecto.Adapters.SQL.query!(
        Repo,
        "DELETE FROM payments WHERE id = $1",
        [payment_uuid]
      )

      Ecto.Adapters.SQL.query!(
        Repo,
        "SET session_replication_role = 'replica'"
      )

      stripe_account = Ledgers.get_account_by_name("stripe_account")

      Ecto.Adapters.SQL.query!(
        Repo,
        "INSERT INTO ledger_entries (id, account_id, amount, description, payment_id, debit_credit, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, ROW('USD', 5000), 'Worker orphan entry', $2, 'debit', NOW(), NOW())",
        [
          to_uuid(stripe_account.id),
          payment_uuid
        ]
      )

      Ecto.Adapters.SQL.query!(
        Repo,
        "SET session_replication_role = 'origin'"
      )

      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "Ysc.Ledgers.ReconciliationWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      assert {:ok, report} = ReconciliationWorker.perform(job)
      assert report.overall_status == :error
      assert report.checks.orphaned_entries.status == :error
      assert report.checks.orphaned_entries.orphaned_entries_count >= 1

      assert Enum.any?(report.checks.orphaned_entries.orphaned_entries, fn e ->
               e.payment_id == orphaned_payment_id
             end)
    end
  end

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

  describe "run_now/0" do
    test "runs reconciliation and returns {:ok, report}" do
      assert {:ok, report} = ReconciliationWorker.run_now()
      assert report.overall_status == :ok
      assert Map.has_key?(report, :checks)
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

    test "schedule_in: 0 inserts a job for immediate availability" do
      assert {:ok, job} =
               ReconciliationWorker.schedule_reconciliation(schedule_in: 0)

      assert job.worker == "Ysc.Ledgers.ReconciliationWorker"
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

  defp to_uuid(ulid) do
    {:ok, binary} = Ecto.ULID.dump(ulid)
    binary
  end

  defp with_trigger_disabled(func) do
    Ecto.Adapters.SQL.query!(
      Repo,
      "ALTER TABLE ledger_entries DISABLE TRIGGER ledger_entries_append_only_trigger"
    )

    try do
      func.()
    after
      Ecto.Adapters.SQL.query!(
        Repo,
        "ALTER TABLE ledger_entries ENABLE TRIGGER ledger_entries_append_only_trigger"
      )
    end
  end
end
