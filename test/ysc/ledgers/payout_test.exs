defmodule Ysc.Ledgers.PayoutTest do
  @moduledoc """
  Tests for Payout schema.

  These tests verify:
  - Stripe payout ID validation
  - Amount and status validation
  - Payment/refund associations
  - Date validations
  - QuickBooks sync fields
  - Currency handling
  - Unique constraints
  """
  use Ysc.DataCase, async: true

  alias Ysc.Ledgers.Payout
  alias Ysc.Repo

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    user = Ysc.AccountsFixtures.user_fixture()

    %{user: user}
  end

  describe "changeset/2" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        stripe_payout_id: "po_test_123",
        amount: Money.new(100_000, :USD),
        currency: "usd",
        status: "paid"
      }

      changeset = Payout.changeset(%Payout{}, attrs)

      assert changeset.valid?
      assert changeset.changes.stripe_payout_id == "po_test_123"
      assert changeset.changes.amount == Money.new(100_000, :USD)
      assert changeset.changes.currency == "usd"
      assert changeset.changes.status == "paid"
    end

    test "creates valid changeset with optional fields" do
      arrival_date = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        stripe_payout_id: "po_test_123",
        amount: Money.new(100_000, :USD),
        fee_total: Money.new(500, :USD),
        currency: "usd",
        status: "paid",
        arrival_date: arrival_date,
        description: "Monthly payout",
        metadata: %{"batch_id" => "batch_001"}
      }

      changeset = Payout.changeset(%Payout{}, attrs)

      assert changeset.valid?
      assert changeset.changes.fee_total == Money.new(500, :USD)
      assert changeset.changes.arrival_date == arrival_date
      assert changeset.changes.description == "Monthly payout"
      assert changeset.changes.metadata == %{"batch_id" => "batch_001"}
    end

    test "requires stripe_payout_id" do
      attrs = %{
        amount: Money.new(100_000, :USD),
        currency: "usd",
        status: "paid"
      }

      changeset = Payout.changeset(%Payout{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:stripe_payout_id] != nil
    end

    test "requires amount" do
      attrs = %{
        stripe_payout_id: "po_test_123",
        currency: "usd",
        status: "paid"
      }

      changeset = Payout.changeset(%Payout{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:amount] != nil
    end

    test "requires currency" do
      attrs = %{
        stripe_payout_id: "po_test_123",
        amount: Money.new(100_000, :USD),
        status: "paid"
      }

      changeset = Payout.changeset(%Payout{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:currency] != nil
    end

    test "requires status" do
      attrs = %{
        stripe_payout_id: "po_test_123",
        amount: Money.new(100_000, :USD),
        currency: "usd"
      }

      changeset = Payout.changeset(%Payout{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:status] != nil
    end

    test "validates stripe_payout_id maximum length" do
      long_id = String.duplicate("a", 256)

      attrs = %{
        stripe_payout_id: long_id,
        amount: Money.new(100_000, :USD),
        currency: "usd",
        status: "paid"
      }

      changeset = Payout.changeset(%Payout{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:stripe_payout_id] != nil
    end

    test "accepts stripe_payout_id with exactly 255 characters" do
      valid_id = String.duplicate("a", 255)

      attrs = %{
        stripe_payout_id: valid_id,
        amount: Money.new(100_000, :USD),
        currency: "usd",
        status: "paid"
      }

      changeset = Payout.changeset(%Payout{}, attrs)

      assert changeset.valid?
    end

    test "validates description maximum length" do
      long_description = String.duplicate("a", 1001)

      attrs = %{
        stripe_payout_id: "po_test_123",
        amount: Money.new(100_000, :USD),
        currency: "usd",
        status: "paid",
        description: long_description
      }

      changeset = Payout.changeset(%Payout{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:description] != nil
    end

    test "accepts description with exactly 1000 characters" do
      valid_description = String.duplicate("a", 1000)

      attrs = %{
        stripe_payout_id: "po_test_123",
        amount: Money.new(100_000, :USD),
        currency: "usd",
        status: "paid",
        description: valid_description
      }

      changeset = Payout.changeset(%Payout{}, attrs)

      assert changeset.valid?
    end
  end

  describe "QuickBooks sync fields" do
    test "accepts QuickBooks sync fields" do
      synced_at = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        stripe_payout_id: "po_test_123",
        amount: Money.new(100_000, :USD),
        currency: "usd",
        status: "paid",
        quickbooks_deposit_id: "dep_123",
        quickbooks_sync_status: "synced",
        quickbooks_synced_at: synced_at,
        quickbooks_last_sync_attempt_at: synced_at
      }

      changeset = Payout.changeset(%Payout{}, attrs)

      assert changeset.valid?
      assert changeset.changes.quickbooks_deposit_id == "dep_123"
      assert changeset.changes.quickbooks_sync_status == "synced"
      assert changeset.changes.quickbooks_synced_at == synced_at
    end

    test "accepts QuickBooks sync error information" do
      attrs = %{
        stripe_payout_id: "po_test_123",
        amount: Money.new(100_000, :USD),
        currency: "usd",
        status: "paid",
        quickbooks_sync_status: "failed",
        quickbooks_sync_error: %{
          "code" => "invalid_account",
          "message" => "Account not found"
        }
      }

      changeset = Payout.changeset(%Payout{}, attrs)

      assert changeset.valid?

      assert changeset.changes.quickbooks_sync_error == %{
               "code" => "invalid_account",
               "message" => "Account not found"
             }
    end

    test "accepts QuickBooks response data" do
      attrs = %{
        stripe_payout_id: "po_test_123",
        amount: Money.new(100_000, :USD),
        currency: "usd",
        status: "paid",
        quickbooks_response: %{
          "id" => "123",
          "txn_date" => "2024-01-15"
        }
      }

      changeset = Payout.changeset(%Payout{}, attrs)

      assert changeset.valid?
      assert changeset.changes.quickbooks_response["id"] == "123"
    end
  end

  describe "Money type handling" do
    test "handles amount with proper precision" do
      attrs = %{
        stripe_payout_id: "po_test_123",
        amount: Money.new(123_456, :USD),
        currency: "usd",
        status: "paid"
      }

      changeset = Payout.changeset(%Payout{}, attrs)
      {:ok, payout} = Repo.insert(changeset)

      assert payout.amount == Money.new(123_456, :USD)
      assert Money.to_decimal(payout.amount) == Decimal.new("123456")
    end

    test "handles fee_total with proper precision" do
      attrs = %{
        stripe_payout_id: "po_test_123",
        amount: Money.new(100_000, :USD),
        fee_total: Money.new(520, :USD),
        currency: "usd",
        status: "paid"
      }

      changeset = Payout.changeset(%Payout{}, attrs)
      {:ok, payout} = Repo.insert(changeset)

      assert payout.fee_total == Money.new(520, :USD)
      assert Money.to_decimal(payout.fee_total) == Decimal.new("520")
    end

    test "handles large payout amounts" do
      attrs = %{
        stripe_payout_id: "po_test_123",
        amount: Money.new(5_000_000, :USD),
        currency: "usd",
        status: "paid"
      }

      changeset = Payout.changeset(%Payout{}, attrs)
      {:ok, payout} = Repo.insert(changeset)

      assert payout.amount == Money.new(5_000_000, :USD)
      assert Money.to_decimal(payout.amount) == Decimal.new("5000000")
    end
  end

  describe "payout status values" do
    test "accepts common Stripe payout statuses" do
      statuses = ["paid", "pending", "in_transit", "canceled", "failed"]

      for status <- statuses do
        attrs = %{
          stripe_payout_id: "po_test_#{status}",
          amount: Money.new(100_000, :USD),
          currency: "usd",
          status: status
        }

        changeset = Payout.changeset(%Payout{}, attrs)
        {:ok, payout} = Repo.insert(changeset)

        assert payout.status == status
      end
    end
  end

  describe "database constraints" do
    test "enforces unique constraint on stripe_payout_id" do
      attrs = %{
        stripe_payout_id: "po_unique_test",
        amount: Money.new(100_000, :USD),
        currency: "usd",
        status: "paid"
      }

      changeset = Payout.changeset(%Payout{}, attrs)
      {:ok, _payout1} = Repo.insert(changeset)

      # Try to insert another payout with the same stripe_payout_id
      changeset2 = Payout.changeset(%Payout{}, attrs)
      {:error, changeset_error} = Repo.insert(changeset2)

      assert changeset_error.errors[:stripe_payout_id] != nil
      {message, _} = changeset_error.errors[:stripe_payout_id]
      assert message =~ "has already been taken"
    end

    test "can insert and retrieve complete payout" do
      arrival_date = DateTime.utc_now() |> DateTime.truncate(:second)
      synced_at = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        stripe_payout_id: "po_complete_test",
        amount: Money.new(100_000, :USD),
        fee_total: Money.new(500, :USD),
        currency: "usd",
        status: "paid",
        arrival_date: arrival_date,
        description: "Complete payout test",
        metadata: %{"test" => "data"},
        quickbooks_deposit_id: "dep_123",
        quickbooks_sync_status: "synced",
        quickbooks_synced_at: synced_at
      }

      changeset = Payout.changeset(%Payout{}, attrs)
      {:ok, payout} = Repo.insert(changeset)

      retrieved = Repo.get(Payout, payout.id)

      assert retrieved.stripe_payout_id == "po_complete_test"
      assert retrieved.amount == Money.new(100_000, :USD)
      assert retrieved.fee_total == Money.new(500, :USD)
      assert retrieved.currency == "usd"
      assert retrieved.status == "paid"
      assert retrieved.arrival_date == arrival_date
      assert retrieved.description == "Complete payout test"
      assert retrieved.metadata == %{"test" => "data"}
      assert retrieved.quickbooks_deposit_id == "dep_123"
      assert retrieved.quickbooks_sync_status == "synced"
      assert retrieved.quickbooks_synced_at == synced_at
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end
  end

  describe "payment association" do
    test "can associate payout with payment record", %{user: user} do
      payment = Ysc.LedgersFixtures.payment_fixture(user_id: user.id)

      attrs = %{
        stripe_payout_id: "po_payment_test",
        amount: Money.new(100_000, :USD),
        currency: "usd",
        status: "paid",
        payment_id: payment.id
      }

      changeset = Payout.changeset(%Payout{}, attrs)
      {:ok, payout} = Repo.insert(changeset)

      retrieved =
        Payout
        |> Repo.get(payout.id)
        |> Repo.preload(:payment)

      assert retrieved.payment.id == payment.id
    end
  end
end
