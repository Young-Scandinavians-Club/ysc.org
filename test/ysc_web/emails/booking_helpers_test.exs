defmodule YscWeb.Emails.BookingHelpersTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Decimal
  alias Ysc.Bookings.PendingRefund
  alias Ysc.Ledgers.Payment
  alias Ysc.Repo
  alias YscWeb.Emails.BookingHelpers
  alias YscWeb.Emails.Helpers

  @booking %{
    id: "booking-1",
    reference_id: "BK-TEST-001",
    property: :tahoe,
    checkin_date: ~D[2026-10-10],
    checkout_date: ~D[2026-10-12],
    guests_count: 2,
    children_count: nil,
    user: %{first_name: "Anna", last_name: "Berg", email: "anna@example.com"}
  }

  describe "booking_summary/1" do
    test "formats property, dates, and treats nil children as 0" do
      assert BookingHelpers.booking_summary(@booking) == %{
               reference_id: "BK-TEST-001",
               property: "Tahoe",
               checkin_date: "October 10, 2026",
               checkout_date: "October 12, 2026",
               guests_count: 2,
               children_count: 0
             }
    end

    test "keeps an explicit children_count" do
      summary =
        BookingHelpers.booking_summary(%{@booking | children_count: 3})

      assert summary.children_count == 3
      assert summary.property == "Tahoe"
    end
  end

  describe "payment_summary/1" do
    test "returns N/A fields when payment is nil" do
      assert BookingHelpers.payment_summary(nil) == %{
               reference_id: "N/A",
               amount: "N/A"
             }
    end

    test "formats reference and amount" do
      payment = %{
        reference_id: "PMT-TEST-001",
        amount: Money.new(:USD, "250.00")
      }

      assert BookingHelpers.payment_summary(payment) == %{
               reference_id: "PMT-TEST-001",
               amount: "$250.00"
             }
    end
  end

  describe "member_links/1" do
    test "builds greeting, receipt URL, and property reply-to" do
      links = BookingHelpers.member_links(@booking)

      assert links.first_name == "Anna"
      assert links.booking_url == Helpers.booking_receipt_url("booking-1")
      assert links.cabin_email == Ysc.EmailConfig.booking_reply_to(:tahoe)
    end
  end

  describe "staff_user_summary/1" do
    test "joins name and includes email" do
      assert BookingHelpers.staff_user_summary(@booking.user) == %{
               name: "Anna Berg",
               email: "anna@example.com"
             }
    end
  end

  describe "normalize_previous_details/1" do
    test "reads atom keys and defaults children_count" do
      previous =
        BookingHelpers.normalize_previous_details(%{
          checkin_date: ~D[2026-10-01],
          checkout_date: ~D[2026-10-03],
          guests_count: 2
        })

      assert previous.checkin_date == ~D[2026-10-01]
      assert previous.children_count == 0
      assert previous.total_price == nil
      assert previous.additional_payment == nil
    end

    test "reads string keys" do
      previous =
        BookingHelpers.normalize_previous_details(%{
          "checkin_date" => ~D[2026-10-01],
          "checkout_date" => ~D[2026-10-03],
          "guests_count" => 4,
          "children_count" => 1,
          "total_price" => Money.new(:USD, "150.00")
        })

      assert previous.guests_count == 4
      assert previous.children_count == 1
      assert Money.equal?(previous.total_price, Money.new(:USD, "150.00"))
    end
  end

  describe "previous_stay_summary/1" do
    test "formats dates and keeps guest counts" do
      previous =
        BookingHelpers.normalize_previous_details(%{
          checkin_date: ~D[2026-10-01],
          checkout_date: ~D[2026-10-03],
          guests_count: 2,
          children_count: 1
        })

      assert BookingHelpers.previous_stay_summary(previous) == %{
               checkin_date: "October 01, 2026",
               checkout_date: "October 03, 2026",
               guests_count: 2,
               children_count: 1
             }
    end
  end

  describe "stay_changes/2" do
    test "flags date and guest changes" do
      previous =
        BookingHelpers.normalize_previous_details(%{
          checkin_date: ~D[2026-10-01],
          checkout_date: ~D[2026-10-03],
          guests_count: 1,
          children_count: 0
        })

      changes = BookingHelpers.stay_changes(@booking, previous)

      assert changes.dates_changed
      assert changes.guests_changed
    end

    test "is unchanged when stay fields match" do
      previous =
        BookingHelpers.normalize_previous_details(%{
          checkin_date: @booking.checkin_date,
          checkout_date: @booking.checkout_date,
          guests_count: @booking.guests_count,
          children_count: 0
        })

      changes = BookingHelpers.stay_changes(@booking, previous)

      refute changes.dates_changed
      refute changes.guests_changed
    end
  end

  describe "staff_cancellation_email_data/4" do
    test "builds the shared staff payload without a pending refund" do
      booking = booking_fixture() |> Repo.preload(:user)

      payment = %Payment{
        reference_id: "PMT-1",
        amount: Money.new(:USD, "250.00")
      }

      data =
        BookingHelpers.staff_cancellation_email_data(
          booking,
          payment,
          nil,
          "User requested"
        )

      refute data.requires_review
      assert data.review_url == nil
      assert data.pending_refund == nil
      assert data.cancellation.reason == "User requested"
      assert data.booking.reference_id == booking.reference_id
      assert data.booking.property == "Tahoe"
      assert data.payment.reference_id == "PMT-1"
      assert data.payment.amount == "$250.00"
      assert data.user.email == booking.user.email
      assert data.booking_url =~ "/admin/bookings/#{booking.id}"
    end

    test "includes pending refund review fields" do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id}) |> Repo.preload(:user)

      pending_refund = %PendingRefund{
        policy_refund_amount: Money.new(:USD, "100.00"),
        cancellation_reason: "Policy partial refund",
        applied_rule_days_before_checkin: 14,
        applied_rule_refund_percentage: Decimal.new("50")
      }

      data =
        BookingHelpers.staff_cancellation_email_data(
          booking,
          nil,
          pending_refund,
          nil
        )

      assert data.requires_review
      assert data.review_url =~ "pending_refunds"
      assert data.pending_refund.policy_refund_amount == "$100.00"
      assert data.pending_refund.applied_rule_days_before_checkin == 14
      assert data.pending_refund.applied_rule_refund_percentage == 50.0
      assert data.cancellation.reason == "Policy partial refund"
      assert data.payment.reference_id == "N/A"
    end

    test "raises when booking is nil" do
      assert_raise ArgumentError, ~r/Booking cannot be nil/, fn ->
        BookingHelpers.staff_cancellation_email_data(nil)
      end
    end
  end
end
