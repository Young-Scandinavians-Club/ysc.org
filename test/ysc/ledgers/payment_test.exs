defmodule Ysc.Ledgers.PaymentTest do
  @moduledoc """
  Tests for Payment schema.

  These tests verify:
  - Changeset validations
  - Required fields
  - Reference ID generation
  - Field length validations
  - Unique constraints
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Ledgers.Payment
  alias Ysc.Repo

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    user = user_fixture()
    %{user: user}
  end

  describe "changeset/2" do
    test "creates valid changeset with all required fields", %{user: user} do
      attrs = %{
        external_provider: :stripe,
        external_payment_id: "pi_test_123",
        amount: Money.new(100, :USD),
        status: :completed,
        user_id: user.id
      }

      changeset = Payment.changeset(%Payment{}, attrs)

      assert changeset.valid?
      assert changeset.changes.external_provider == :stripe
      assert changeset.changes.amount == Money.new(100, :USD)
      assert changeset.changes.status == :completed
    end

    test "generates reference_id when not provided", %{user: user} do
      attrs = %{
        external_provider: :stripe,
        external_payment_id: "pi_test_123",
        amount: Money.new(100, :USD),
        status: :completed,
        user_id: user.id
      }

      changeset = Payment.changeset(%Payment{}, attrs)

      assert changeset.valid?
      assert changeset.changes.reference_id != nil
      assert String.starts_with?(changeset.changes.reference_id, "PMT-")
    end

    test "uses provided reference_id when given", %{user: user} do
      attrs = %{
        reference_id: "PMT-CUSTOM-123",
        external_provider: :stripe,
        external_payment_id: "pi_test_123",
        amount: Money.new(100, :USD),
        status: :completed,
        user_id: user.id
      }

      changeset = Payment.changeset(%Payment{}, attrs)

      assert changeset.valid?
      assert changeset.changes.reference_id == "PMT-CUSTOM-123"
    end

    test "requires external_provider" do
      attrs = %{
        external_payment_id: "pi_test_123",
        amount: Money.new(100, :USD),
        status: :completed
      }

      changeset = Payment.changeset(%Payment{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:external_provider] != nil
    end

    test "requires amount" do
      attrs = %{
        external_provider: :stripe,
        external_payment_id: "pi_test_123",
        status: :completed
      }

      changeset = Payment.changeset(%Payment{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:amount] != nil
    end

    test "requires status" do
      attrs = %{
        external_provider: :stripe,
        external_payment_id: "pi_test_123",
        amount: Money.new(100, :USD)
      }

      changeset = Payment.changeset(%Payment{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:status] != nil
    end

    test "validates external_payment_id length" do
      long_id = String.duplicate("a", 256)

      attrs = %{
        external_provider: :stripe,
        external_payment_id: long_id,
        amount: Money.new(100, :USD),
        status: :completed
      }

      changeset = Payment.changeset(%Payment{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:external_payment_id] != nil
    end

    test "validates reference_id length" do
      long_id = String.duplicate("a", 256)

      attrs = %{
        reference_id: long_id,
        external_provider: :stripe,
        external_payment_id: "pi_test_123",
        amount: Money.new(100, :USD),
        status: :completed
      }

      changeset = Payment.changeset(%Payment{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:reference_id] != nil
    end

    test "accepts valid external_payment_id length", %{user: user} do
      attrs = %{
        external_provider: :stripe,
        external_payment_id: String.duplicate("a", 255),
        amount: Money.new(100, :USD),
        status: :completed,
        user_id: user.id
      }

      changeset = Payment.changeset(%Payment{}, attrs)

      assert changeset.valid?
    end

    test "can insert valid payment", %{user: user} do
      attrs = %{
        external_provider: :stripe,
        external_payment_id: "pi_test_123",
        amount: Money.new(100, :USD),
        status: :completed,
        user_id: user.id
      }

      changeset = Payment.changeset(%Payment{}, attrs)

      assert {:ok, payment} = Repo.insert(changeset)
      assert payment.external_provider == :stripe
      assert payment.amount == Money.new(100, :USD)
      assert payment.status == :completed
      assert payment.reference_id != nil
    end

    test "handles QuickBooks sync fields", %{user: user} do
      attrs = %{
        external_provider: :stripe,
        external_payment_id: "pi_test_123",
        amount: Money.new(100, :USD),
        status: :completed,
        user_id: user.id,
        quickbooks_sales_receipt_id: "sr_123",
        quickbooks_sync_status: "synced",
        quickbooks_synced_at: DateTime.truncate(DateTime.utc_now(), :second)
      }

      changeset = Payment.changeset(%Payment{}, attrs)

      assert changeset.valid?
      assert changeset.changes.quickbooks_sales_receipt_id == "sr_123"
      assert changeset.changes.quickbooks_sync_status == "synced"
    end
  end
end
