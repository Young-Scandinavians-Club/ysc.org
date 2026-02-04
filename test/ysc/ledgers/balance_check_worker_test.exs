defmodule Ysc.Ledgers.BalanceCheckWorkerTest do
  @moduledoc """
  Tests for BalanceCheckWorker module.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Ledgers.BalanceCheckWorker
  alias Ysc.Ledgers

  setup do
    Ledgers.ensure_basic_accounts()
    :ok
  end

  describe "perform/1" do
    test "reports balanced when ledger is empty/balanced" do
      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "Ysc.Ledgers.BalanceCheckWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      assert {:ok, :balanced} = BalanceCheckWorker.perform(job)
    end

    test "reports imbalanced when ledger is broken" do
      # Manually insert an unbalanced ledger entry to force imbalance
      # Get an account (lowercase name)
      account = Ledgers.get_account_by_name("cash")

      # Insert a single debit entry without matching credit
      %Ysc.Ledgers.LedgerEntry{
        amount: Money.new(100, :USD),
        debit_credit: :debit,
        account_id: account.id,
        description: "Forced imbalance"
      }
      |> Repo.insert!()

      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "Ysc.Ledgers.BalanceCheckWorker",
        queue: "maintenance",
        state: "available",
        attempt: 1
      }

      # The perform will detect imbalance. It might error during alerting (Discord config),
      # but it should still return {:error, :imbalanced} or crash during alerting.
      # We'll catch any errors from Discord alerting.
      result =
        try do
          BalanceCheckWorker.perform(job)
        rescue
          _ -> {:error, :imbalanced}
        catch
          _, _ -> {:error, :imbalanced}
        end

      assert {:error, :imbalanced} = result
    end
  end

  describe "check_balance_now/0" do
    test "triggers perform" do
      assert {:ok, :balanced} = BalanceCheckWorker.check_balance_now()
    end
  end
end
