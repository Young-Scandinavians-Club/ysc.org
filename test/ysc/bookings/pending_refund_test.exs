defmodule Ysc.Bookings.PendingRefundTest do
  @moduledoc """
  Tests for PendingRefund schema.

  These tests verify:
  - Required field validation (booking_id, payment_id, policy_refund_amount, status)
  - Money type field handling
  - Status enum validation (pending, approved, rejected)
  - Admin review fields (admin_notes, reviewed_by_id, reviewed_at)
  - Refund rule tracking fields
  - Database operations
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Bookings.{PendingRefund, Booking}
  alias Ysc.Ledgers.Payment
  alias Ysc.Repo

  # Helper to create a booking for testing
  defp create_booking do
    user = user_fixture()

    attrs = %{
      user_id: user.id,
      checkin_date: ~D[2024-08-05],
      checkout_date: ~D[2024-08-07],
      property: :tahoe,
      booking_mode: :room
    }

    {:ok, booking} =
      %Booking{}
      |> Booking.changeset(attrs, skip_validation: true)
      |> Repo.insert()

    # Preload user for tests that need it
    Repo.preload(booking, :user)
  end

  # Helper to create a payment for testing
  defp create_payment(user_id) when is_binary(user_id) do
    attrs = %{
      user_id: user_id,
      amount: Money.new(50_000, :USD),
      external_provider: :stripe,
      external_payment_id: "pi_test_#{System.unique_integer()}",
      status: :completed
    }

    {:ok, payment} =
      %Payment{}
      |> Payment.changeset(attrs)
      |> Repo.insert()

    payment
  end

  describe "changeset/2" do
    test "creates valid changeset with required fields" do
      booking = create_booking()
      payment = create_payment(booking.user.id)

      attrs = %{
        booking_id: booking.id,
        payment_id: payment.id,
        policy_refund_amount: Money.new(25_000, :USD),
        status: :approved
      }

      changeset = PendingRefund.changeset(%PendingRefund{}, attrs)

      assert changeset.valid?
      assert changeset.changes.booking_id == booking.id
      assert changeset.changes.payment_id == payment.id
      assert changeset.changes.policy_refund_amount == Money.new(25_000, :USD)
      assert changeset.changes.status == :approved
    end

    test "requires booking_id" do
      user = user_fixture()
      payment = create_payment(user.id)

      attrs = %{
        payment_id: payment.id,
        policy_refund_amount: Money.new(25_000, :USD),
        status: :pending
      }

      changeset = PendingRefund.changeset(%PendingRefund{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:booking_id] != nil
    end

    test "requires payment_id" do
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        policy_refund_amount: Money.new(25_000, :USD),
        status: :pending
      }

      changeset = PendingRefund.changeset(%PendingRefund{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:payment_id] != nil
    end

    test "requires policy_refund_amount" do
      booking = create_booking()
      payment = create_payment(booking.user.id)

      attrs = %{
        booking_id: booking.id,
        payment_id: payment.id,
        status: :pending
      }

      changeset = PendingRefund.changeset(%PendingRefund{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:policy_refund_amount] != nil
    end

    test "allows default status (defaults to :pending)" do
      booking = create_booking()
      payment = create_payment(booking.user.id)

      attrs = %{
        booking_id: booking.id,
        payment_id: payment.id,
        policy_refund_amount: Money.new(25_000, :USD)
      }

      changeset = PendingRefund.changeset(%PendingRefund{}, attrs)

      # Status defaults to :pending if not provided
      assert changeset.valid?
      pending_refund = %PendingRefund{}
      assert pending_refund.status == :pending
    end

    test "accepts all status enum values" do
      booking = create_booking()
      payment = create_payment(booking.user.id)

      for status_value <- [:pending, :approved, :rejected] do
        attrs = %{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: Money.new(25_000, :USD),
          status: status_value
        }

        changeset = PendingRefund.changeset(%PendingRefund{}, attrs)

        assert changeset.valid?
        # When status is :pending (default), it won't be in changes
        if status_value != :pending do
          assert changeset.changes.status == status_value
        end
      end
    end

    test "rejects invalid status value" do
      booking = create_booking()
      payment = create_payment(booking.user.id)

      attrs = %{
        booking_id: booking.id,
        payment_id: payment.id,
        policy_refund_amount: Money.new(25_000, :USD),
        status: :invalid_status
      }

      changeset = PendingRefund.changeset(%PendingRefund{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:status] != nil
    end

    test "accepts optional admin_refund_amount" do
      booking = create_booking()
      payment = create_payment(booking.user.id)

      attrs = %{
        booking_id: booking.id,
        payment_id: payment.id,
        policy_refund_amount: Money.new(25_000, :USD),
        admin_refund_amount: Money.new(30_000, :USD),
        status: :pending
      }

      changeset = PendingRefund.changeset(%PendingRefund{}, attrs)

      assert changeset.valid?
      assert changeset.changes.admin_refund_amount == Money.new(30_000, :USD)
    end

    test "accepts optional cancellation_reason" do
      booking = create_booking()
      payment = create_payment(booking.user.id)

      attrs = %{
        booking_id: booking.id,
        payment_id: payment.id,
        policy_refund_amount: Money.new(25_000, :USD),
        status: :pending,
        cancellation_reason: "Family emergency"
      }

      changeset = PendingRefund.changeset(%PendingRefund{}, attrs)

      assert changeset.valid?
      assert changeset.changes.cancellation_reason == "Family emergency"
    end

    test "accepts optional admin_notes" do
      booking = create_booking()
      payment = create_payment(booking.user.id)

      attrs = %{
        booking_id: booking.id,
        payment_id: payment.id,
        policy_refund_amount: Money.new(25_000, :USD),
        status: :pending,
        admin_notes: "Approved due to special circumstances"
      }

      changeset = PendingRefund.changeset(%PendingRefund{}, attrs)

      assert changeset.valid?

      assert changeset.changes.admin_notes ==
               "Approved due to special circumstances"
    end

    test "accepts optional reviewed_by_id and reviewed_at" do
      booking = create_booking()
      payment = create_payment(booking.user.id)
      admin = user_fixture()
      reviewed_at = DateTime.utc_now()

      attrs = %{
        booking_id: booking.id,
        payment_id: payment.id,
        policy_refund_amount: Money.new(25_000, :USD),
        status: :approved,
        reviewed_by_id: admin.id,
        reviewed_at: reviewed_at
      }

      changeset = PendingRefund.changeset(%PendingRefund{}, attrs)

      assert changeset.valid?
      assert changeset.changes.reviewed_by_id == admin.id
    end

    test "accepts refund rule tracking fields" do
      booking = create_booking()
      payment = create_payment(booking.user.id)

      attrs = %{
        booking_id: booking.id,
        payment_id: payment.id,
        policy_refund_amount: Money.new(25_000, :USD),
        status: :pending,
        applied_rule_days_before_checkin: 14,
        applied_rule_refund_percentage: Decimal.new("50.00")
      }

      changeset = PendingRefund.changeset(%PendingRefund{}, attrs)

      assert changeset.valid?
      assert changeset.changes.applied_rule_days_before_checkin == 14

      assert Decimal.equal?(
               changeset.changes.applied_rule_refund_percentage,
               Decimal.new("50.00")
             )
    end
  end

  describe "database operations" do
    test "can insert and retrieve pending refund" do
      booking = create_booking()
      payment = create_payment(booking.user.id)

      attrs = %{
        booking_id: booking.id,
        payment_id: payment.id,
        policy_refund_amount: Money.new(25_000, :USD),
        status: :pending
      }

      changeset = PendingRefund.changeset(%PendingRefund{}, attrs)
      {:ok, pending_refund} = Repo.insert(changeset)

      retrieved = Repo.get(PendingRefund, pending_refund.id)

      assert retrieved.booking_id == booking.id
      assert retrieved.payment_id == payment.id
      assert retrieved.policy_refund_amount == Money.new(25_000, :USD)
      assert retrieved.status == :pending
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "can preload booking association" do
      booking = create_booking()
      payment = create_payment(booking.user.id)

      {:ok, pending_refund} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: Money.new(25_000, :USD),
          status: :pending
        })
        |> Repo.insert()

      pending_refund_with_booking = Repo.preload(pending_refund, :booking)

      assert pending_refund_with_booking.booking.id == booking.id
    end

    test "can preload payment association" do
      booking = create_booking()
      payment = create_payment(booking.user.id)

      {:ok, pending_refund} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: Money.new(25_000, :USD),
          status: :pending
        })
        |> Repo.insert()

      pending_refund_with_payment = Repo.preload(pending_refund, :payment)

      assert pending_refund_with_payment.payment.id == payment.id
    end

    test "can update pending refund status" do
      booking = create_booking()
      payment = create_payment(booking.user.id)

      {:ok, pending_refund} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: Money.new(25_000, :USD),
          status: :pending
        })
        |> Repo.insert()

      # Approve the refund
      {:ok, updated} =
        pending_refund
        |> PendingRefund.changeset(%{status: :approved})
        |> Repo.update()

      assert updated.status == :approved
    end
  end

  describe "typical pending refund scenarios" do
    test "cancellation with 50% refund" do
      booking = create_booking()
      payment = create_payment(booking.user.id)

      {:ok, pending_refund} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: Money.new(25_000, :USD),
          status: :pending,
          cancellation_reason: "Schedule conflict",
          applied_rule_days_before_checkin: 14,
          applied_rule_refund_percentage: Decimal.new("50.00")
        })
        |> Repo.insert()

      # Verify 50% refund
      assert pending_refund.policy_refund_amount == Money.new(25_000, :USD)

      assert Decimal.equal?(
               pending_refund.applied_rule_refund_percentage,
               Decimal.new("50.00")
             )
    end

    test "admin adjusts refund amount" do
      booking = create_booking()
      payment = create_payment(booking.user.id)
      admin = user_fixture()

      {:ok, pending_refund} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: Money.new(25_000, :USD),
          status: :pending
        })
        |> Repo.insert()

      # Admin increases refund due to special circumstances
      {:ok, updated} =
        pending_refund
        |> PendingRefund.changeset(%{
          admin_refund_amount: Money.new(40_000, :USD),
          admin_notes: "Increased refund due to property maintenance issue",
          reviewed_by_id: admin.id,
          reviewed_at: DateTime.utc_now(),
          status: :approved
        })
        |> Repo.update()

      assert updated.admin_refund_amount == Money.new(40_000, :USD)
      assert updated.policy_refund_amount == Money.new(25_000, :USD)
      assert updated.status == :approved
    end

    test "rejected refund request" do
      booking = create_booking()
      payment = create_payment(booking.user.id)
      admin = user_fixture()

      {:ok, pending_refund} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: Money.new(25_000, :USD),
          status: :pending,
          cancellation_reason: "Changed mind"
        })
        |> Repo.insert()

      # Admin rejects refund
      {:ok, updated} =
        pending_refund
        |> PendingRefund.changeset(%{
          status: :rejected,
          admin_notes: "Cancellation does not meet refund policy criteria",
          reviewed_by_id: admin.id,
          reviewed_at: DateTime.utc_now()
        })
        |> Repo.update()

      assert updated.status == :rejected
      assert String.contains?(updated.admin_notes, "does not meet")
    end

    test "multiple pending refunds for different bookings" do
      booking1 = create_booking()
      booking2 = create_booking()
      payment1 = create_payment(booking1.user.id)
      payment2 = create_payment(booking2.user.id)

      {:ok, _pr1} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking1.id,
          payment_id: payment1.id,
          policy_refund_amount: Money.new(25_000, :USD),
          status: :pending
        })
        |> Repo.insert()

      {:ok, _pr2} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking2.id,
          payment_id: payment2.id,
          policy_refund_amount: Money.new(15_000, :USD),
          status: :pending
        })
        |> Repo.insert()

      # Query all pending refunds
      pending_refunds =
        PendingRefund
        |> Ecto.Query.where(status: :pending)
        |> Repo.all()

      assert length(pending_refunds) == 2
    end
  end
end
