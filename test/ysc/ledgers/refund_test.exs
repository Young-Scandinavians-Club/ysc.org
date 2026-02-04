defmodule Ysc.Ledgers.RefundTest do
  @moduledoc """
  Tests for Refund schema.

  These tests verify:
  - Changeset validations
  - Required fields
  - Reference ID generation
  - Field length validations
  - Foreign key constraints
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Ledgers.{Payment, Refund}
  alias Ysc.Repo

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    user = user_fixture()

    # Create a payment to reference
    payment =
      %Payment{
        external_provider: :stripe,
        external_payment_id: "pi_test_123",
        amount: Money.new(100, :USD),
        status: :completed,
        user_id: user.id
      }
      |> Payment.changeset(%{})
      |> Repo.insert!()

    %{user: user, payment: payment}
  end

  describe "changeset/2" do
    test "creates valid changeset with all required fields", %{
      user: user,
      payment: payment
    } do
      attrs = %{
        external_provider: :stripe,
        external_refund_id: "re_test_123",
        amount: Money.new(50, :USD),
        status: :completed,
        payment_id: payment.id,
        user_id: user.id,
        reason: "Customer requested refund"
      }

      changeset = Refund.changeset(%Refund{}, attrs)

      assert changeset.valid?
      assert changeset.changes.external_provider == :stripe
      assert changeset.changes.amount == Money.new(50, :USD)
      assert changeset.changes.status == :completed
      assert changeset.changes.payment_id == payment.id
    end

    test "generates reference_id when not provided", %{
      user: user,
      payment: payment
    } do
      attrs = %{
        external_provider: :stripe,
        external_refund_id: "re_test_123",
        amount: Money.new(50, :USD),
        status: :completed,
        payment_id: payment.id,
        user_id: user.id
      }

      changeset = Refund.changeset(%Refund{}, attrs)

      assert changeset.valid?
      assert changeset.changes.reference_id != nil
      assert String.starts_with?(changeset.changes.reference_id, "RFD-")
    end

    test "uses provided reference_id when given", %{
      user: user,
      payment: payment
    } do
      attrs = %{
        reference_id: "RFD-CUSTOM-123",
        external_provider: :stripe,
        external_refund_id: "re_test_123",
        amount: Money.new(50, :USD),
        status: :completed,
        payment_id: payment.id,
        user_id: user.id
      }

      changeset = Refund.changeset(%Refund{}, attrs)

      assert changeset.valid?
      assert changeset.changes.reference_id == "RFD-CUSTOM-123"
    end

    test "requires external_provider" do
      attrs = %{
        external_refund_id: "re_test_123",
        amount: Money.new(50, :USD),
        status: :completed,
        payment_id: Ecto.ULID.generate()
      }

      changeset = Refund.changeset(%Refund{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:external_provider] != nil
    end

    test "requires amount" do
      attrs = %{
        external_provider: :stripe,
        external_refund_id: "re_test_123",
        status: :completed,
        payment_id: Ecto.ULID.generate()
      }

      changeset = Refund.changeset(%Refund{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:amount] != nil
    end

    test "requires status" do
      attrs = %{
        external_provider: :stripe,
        external_refund_id: "re_test_123",
        amount: Money.new(50, :USD),
        payment_id: Ecto.ULID.generate()
      }

      changeset = Refund.changeset(%Refund{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:status] != nil
    end

    test "requires payment_id" do
      attrs = %{
        external_provider: :stripe,
        external_refund_id: "re_test_123",
        amount: Money.new(50, :USD),
        status: :completed
      }

      changeset = Refund.changeset(%Refund{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:payment_id] != nil
    end

    test "validates external_refund_id length" do
      long_id = String.duplicate("a", 256)

      attrs = %{
        external_provider: :stripe,
        external_refund_id: long_id,
        amount: Money.new(50, :USD),
        status: :completed,
        payment_id: Ecto.ULID.generate()
      }

      changeset = Refund.changeset(%Refund{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:external_refund_id] != nil
    end

    test "validates reference_id length" do
      long_id = String.duplicate("a", 256)

      attrs = %{
        reference_id: long_id,
        external_provider: :stripe,
        external_refund_id: "re_test_123",
        amount: Money.new(50, :USD),
        status: :completed,
        payment_id: Ecto.ULID.generate()
      }

      changeset = Refund.changeset(%Refund{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:reference_id] != nil
    end

    test "validates reason length", %{payment: payment} do
      long_reason = String.duplicate("a", 1001)

      attrs = %{
        external_provider: :stripe,
        external_refund_id: "re_test_123",
        amount: Money.new(50, :USD),
        status: :completed,
        payment_id: payment.id,
        reason: long_reason
      }

      changeset = Refund.changeset(%Refund{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:reason] != nil
    end

    test "accepts valid reason length", %{user: user, payment: payment} do
      reason = String.duplicate("a", 1000)

      attrs = %{
        external_provider: :stripe,
        external_refund_id: "re_test_123",
        amount: Money.new(50, :USD),
        status: :completed,
        payment_id: payment.id,
        user_id: user.id,
        reason: reason
      }

      changeset = Refund.changeset(%Refund{}, attrs)

      assert changeset.valid?
    end

    test "can insert valid refund", %{user: user, payment: payment} do
      attrs = %{
        external_provider: :stripe,
        external_refund_id: "re_test_123",
        amount: Money.new(50, :USD),
        status: :completed,
        payment_id: payment.id,
        user_id: user.id,
        reason: "Customer requested refund"
      }

      changeset = Refund.changeset(%Refund{}, attrs)

      assert {:ok, refund} = Repo.insert(changeset)
      assert refund.external_provider == :stripe
      assert refund.amount == Money.new(50, :USD)
      assert refund.status == :completed
      assert refund.payment_id == payment.id
      assert refund.reference_id != nil
    end

    test "handles QuickBooks sync fields", %{user: user, payment: payment} do
      attrs = %{
        external_provider: :stripe,
        external_refund_id: "re_test_123",
        amount: Money.new(50, :USD),
        status: :completed,
        payment_id: payment.id,
        user_id: user.id,
        quickbooks_sales_receipt_id: "sr_123",
        quickbooks_sync_status: "synced",
        quickbooks_synced_at: DateTime.truncate(DateTime.utc_now(), :second)
      }

      changeset = Refund.changeset(%Refund{}, attrs)

      assert changeset.valid?
      assert changeset.changes.quickbooks_sales_receipt_id == "sr_123"
      assert changeset.changes.quickbooks_sync_status == "synced"
    end
  end
end
