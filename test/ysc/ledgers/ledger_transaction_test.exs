defmodule Ysc.Ledgers.LedgerTransactionTest do
  @moduledoc """
  Tests for LedgerTransaction schema.

  These tests verify:
  - Transaction type enum validation
  - Transaction status enum validation
  - Money type handling for total_amount
  - Payment and refund associations
  - Required fields enforcement
  - Database constraints
  """
  use Ysc.DataCase, async: true

  alias Ysc.Ledgers.LedgerTransaction
  alias Ysc.Repo

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    user = Ysc.AccountsFixtures.user_fixture()

    %{user: user}
  end

  describe "changeset/2" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        type: :payment,
        total_amount: Money.new(10_000, :USD),
        status: :pending
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)

      assert changeset.valid?
      assert changeset.changes.type == :payment
      assert changeset.changes.total_amount == Money.new(10_000, :USD)
      assert changeset.changes.status == :pending
    end

    test "creates valid changeset with payment association", %{user: user} do
      payment = Ysc.LedgersFixtures.payment_fixture(user_id: user.id)

      attrs = %{
        type: :payment,
        total_amount: Money.new(10_000, :USD),
        status: :completed,
        payment_id: payment.id
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)

      assert changeset.valid?
      assert changeset.changes.payment_id == payment.id
    end

    test "creates valid changeset with refund association", %{user: user} do
      payment = Ysc.LedgersFixtures.payment_fixture(user_id: user.id)
      refund = Ysc.LedgersFixtures.refund_fixture(payment: payment)

      attrs = %{
        type: :refund,
        total_amount: Money.new(5000, :USD),
        status: :completed,
        refund_id: refund.id
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)

      assert changeset.valid?
      assert changeset.changes.refund_id == refund.id
    end

    test "requires type" do
      attrs = %{
        total_amount: Money.new(10_000, :USD),
        status: :pending
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:type] != nil
    end

    test "requires total_amount" do
      attrs = %{
        type: :payment,
        status: :pending
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:total_amount] != nil
    end

    test "requires status" do
      attrs = %{
        type: :payment,
        total_amount: Money.new(10_000, :USD)
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:status] != nil
    end
  end

  describe "transaction type enum" do
    test "accepts all valid transaction types" do
      transaction_types = [:payment, :refund, :fee, :adjustment, :payout]

      for type <- transaction_types do
        attrs = %{
          type: type,
          total_amount: Money.new(10_000, :USD),
          status: :pending
        }

        changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)

        assert changeset.valid?,
               "Expected transaction type #{type} to be valid"
      end
    end

    test "rejects invalid transaction type" do
      attrs = %{
        type: :invalid_type,
        total_amount: Money.new(10_000, :USD),
        status: :pending
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)
      refute changeset.valid?
    end
  end

  describe "transaction status enum" do
    test "accepts pending status" do
      attrs = %{
        type: :payment,
        total_amount: Money.new(10_000, :USD),
        status: :pending
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == :pending
    end

    test "accepts completed status" do
      attrs = %{
        type: :payment,
        total_amount: Money.new(10_000, :USD),
        status: :completed
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == :completed
    end

    test "accepts reversed status" do
      attrs = %{
        type: :payment,
        total_amount: Money.new(10_000, :USD),
        status: :reversed
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == :reversed
    end

    test "rejects invalid status" do
      attrs = %{
        type: :payment,
        total_amount: Money.new(10_000, :USD),
        status: :invalid_status
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)
      refute changeset.valid?
    end
  end

  describe "Money type handling" do
    test "handles positive amounts" do
      attrs = %{
        type: :payment,
        total_amount: Money.new(10_000, :USD),
        status: :completed
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)
      {:ok, transaction} = Repo.insert(changeset)

      assert transaction.total_amount == Money.new(10_000, :USD)
    end

    test "handles zero amounts" do
      attrs = %{
        type: :adjustment,
        total_amount: Money.new(0, :USD),
        status: :completed
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)
      {:ok, transaction} = Repo.insert(changeset)

      assert transaction.total_amount == Money.new(0, :USD)
    end

    test "handles large amounts" do
      attrs = %{
        type: :payout,
        total_amount: Money.new(10_000_000, :USD),
        status: :completed
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)
      {:ok, transaction} = Repo.insert(changeset)

      assert transaction.total_amount == Money.new(10_000_000, :USD)

      assert Money.to_decimal(transaction.total_amount) ==
               Decimal.new("10000000")
    end

    test "maintains precision for fractional amounts" do
      attrs = %{
        type: :payment,
        total_amount: Money.new(12_345, :USD),
        status: :completed
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)
      {:ok, transaction} = Repo.insert(changeset)

      assert transaction.total_amount == Money.new(12_345, :USD)
      assert Money.to_decimal(transaction.total_amount) == Decimal.new("12345")
    end
  end

  describe "database constraints" do
    test "enforces foreign key constraint on payment_id" do
      invalid_payment_id = Ecto.ULID.generate()

      attrs = %{
        type: :payment,
        total_amount: Money.new(10_000, :USD),
        status: :completed,
        payment_id: invalid_payment_id
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)
      {:error, changeset_error} = Repo.insert(changeset)

      assert changeset_error.errors[:payment_id] != nil
    end

    test "enforces foreign key constraint on refund_id" do
      invalid_refund_id = Ecto.ULID.generate()

      attrs = %{
        type: :refund,
        total_amount: Money.new(5000, :USD),
        status: :completed,
        refund_id: invalid_refund_id
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)
      {:error, changeset_error} = Repo.insert(changeset)

      assert changeset_error.errors[:refund_id] != nil
    end

    test "can insert and retrieve transaction" do
      attrs = %{
        type: :fee,
        total_amount: Money.new(320, :USD),
        status: :completed
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)
      {:ok, transaction} = Repo.insert(changeset)

      retrieved = Repo.get(LedgerTransaction, transaction.id)

      assert retrieved.type == :fee
      assert retrieved.total_amount == Money.new(320, :USD)
      assert retrieved.status == :completed
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "can retrieve transaction with preloaded payment", %{user: user} do
      payment = Ysc.LedgersFixtures.payment_fixture(user_id: user.id)

      # Get the transaction associated with the payment
      transaction =
        LedgerTransaction
        |> Repo.get_by(payment_id: payment.id)

      retrieved =
        LedgerTransaction
        |> Repo.get(transaction.id)
        |> Repo.preload(:payment)

      assert retrieved.payment.id == payment.id
      assert retrieved.type == :payment
    end

    test "can retrieve transaction with preloaded refund", %{user: user} do
      payment = Ysc.LedgersFixtures.payment_fixture(user_id: user.id)

      {:ok, {refund, transaction, _entries}} =
        Ysc.Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(5000, :USD),
          external_refund_id: "re_test_#{System.unique_integer()}",
          reason: "Customer request"
        })

      retrieved =
        LedgerTransaction
        |> Repo.get(transaction.id)
        |> Repo.preload(:refund)

      assert retrieved.refund.id == refund.id
      assert retrieved.type == :refund
    end
  end

  describe "transaction lifecycle" do
    test "can create pending transaction and update to completed" do
      attrs = %{
        type: :payment,
        total_amount: Money.new(10_000, :USD),
        status: :pending
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)
      {:ok, transaction} = Repo.insert(changeset)

      assert transaction.status == :pending

      # Update to completed
      update_changeset =
        LedgerTransaction.changeset(transaction, %{status: :completed})

      {:ok, updated_transaction} = Repo.update(update_changeset)

      assert updated_transaction.status == :completed
      assert updated_transaction.id == transaction.id
    end

    test "can create completed transaction and reverse it" do
      attrs = %{
        type: :payment,
        total_amount: Money.new(10_000, :USD),
        status: :completed
      }

      changeset = LedgerTransaction.changeset(%LedgerTransaction{}, attrs)
      {:ok, transaction} = Repo.insert(changeset)

      assert transaction.status == :completed

      # Reverse transaction
      update_changeset =
        LedgerTransaction.changeset(transaction, %{status: :reversed})

      {:ok, reversed_transaction} = Repo.update(update_changeset)

      assert reversed_transaction.status == :reversed
      assert reversed_transaction.id == transaction.id
    end
  end
end
