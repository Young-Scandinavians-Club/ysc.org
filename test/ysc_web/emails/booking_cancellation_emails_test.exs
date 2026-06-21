defmodule YscWeb.Emails.BookingCancellationEmailsTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Decimal
  alias Ysc.Bookings.PendingRefund
  alias Ysc.Ledgers.Payment
  alias Ysc.Repo
  alias YscWeb.Emails.BookingCancellationCabinMasterNotification
  alias YscWeb.Emails.BookingCancellationConfirmation
  alias YscWeb.Emails.BookingCancellationTreasurerNotification

  defp booking_with_user do
    booking_fixture() |> Repo.preload(:user)
  end

  defp payment_stub do
    %Payment{
      reference_id: "PMT-TEST-001",
      amount: Money.new(250_00, :USD)
    }
  end

  defp pending_refund_stub do
    %PendingRefund{
      policy_refund_amount: Money.new(100_00, :USD),
      cancellation_reason: "Policy partial refund",
      applied_rule_days_before_checkin: 14,
      applied_rule_refund_percentage: Decimal.new("50")
    }
  end

  describe "BookingCancellationConfirmation" do
    test "prepare_email_data and render: no refund branch and N/A payment hidden" do
      booking = booking_with_user()

      data =
        BookingCancellationConfirmation.prepare_email_data(
          booking,
          nil,
          nil,
          false,
          "Changed plans"
        )

      assert data.refund.amount == nil
      assert data.payment.reference_id == "N/A"

      html = BookingCancellationConfirmation.render(data)
      assert html =~ "No Refund"
      refute html =~ "Original Payment"
    end

    test "prepare_email_data and render: completed refund (not pending)" do
      booking = booking_with_user()
      refund = Money.new(75_00, :USD)

      data =
        BookingCancellationConfirmation.prepare_email_data(
          booking,
          payment_stub(),
          refund,
          false,
          nil
        )

      html = BookingCancellationConfirmation.render(data)
      assert html =~ "Refund Amount"
      refute html =~ "Refund Pending Review"
      assert html =~ "Payment Details"
    end

    test "prepare_email_data and render: pending refund copy" do
      booking = booking_with_user()

      data =
        BookingCancellationConfirmation.prepare_email_data(
          booking,
          payment_stub(),
          Money.new(10_00, :USD),
          true,
          nil
        )

      html = BookingCancellationConfirmation.render(data)
      assert html =~ "Refund under review"
      assert html =~ "No action is needed on your side"
    end

    test "get_subject/0 and booking_url/1" do
      assert BookingCancellationConfirmation.get_subject() ==
               "Booking Cancellation Confirmed"

      booking = booking_with_user()

      assert BookingCancellationConfirmation.booking_url(booking.id) =~
               "/bookings/"
    end
  end

  describe "BookingCancellationTreasurerNotification" do
    test "prepare_email_data: requires_review false omits review URL and uses financial subject" do
      booking = booking_with_user()

      data =
        BookingCancellationTreasurerNotification.prepare_email_data(
          booking,
          payment_stub(),
          nil,
          "User requested"
        )

      refute data.requires_review
      assert data.review_url == nil
      assert data.pending_refund == nil

      html = BookingCancellationTreasurerNotification.render(data)
      assert html =~ "Processed Automatically"
      refute html =~ "Review Refund Request"

      assert BookingCancellationTreasurerNotification.get_subject(false) =~
               "Financial Notification"
    end

    test "prepare_email_data: pending refund enables review, refund details, and action subject" do
      booking = booking_with_user()
      pr = pending_refund_stub()

      data =
        BookingCancellationTreasurerNotification.prepare_email_data(
          booking,
          payment_stub(),
          pr,
          nil
        )

      assert data.requires_review
      assert data.review_url =~ "pending_refunds"
      assert data.pending_refund.applied_rule_refund_percentage == 50.0

      html = BookingCancellationTreasurerNotification.render(data)
      assert html =~ "Review Required"
      assert html =~ "Policy Refund Amount"
      assert html =~ "50"
      assert html =~ "14+ days before check-in"
      assert html =~ "Review Refund Request"

      assert BookingCancellationTreasurerNotification.get_subject(true) =~
               "Action Required"
    end

    test "admin_bookings_url/1 maps clear_lake property" do
      url =
        BookingCancellationTreasurerNotification.admin_bookings_url(:clear_lake)

      assert url =~ "property=clear_lake"
    end
  end

  describe "BookingCancellationCabinMasterNotification" do
    test "render: guest line covers adults-only, children-only, and singular labels" do
      user = user_fixture(%{first_name: "Bo", last_name: "Carlsson"})

      booking =
        booking_fixture(%{user_id: user.id, guests_count: 1, children_count: 0})

      booking = Repo.preload(booking, :user)

      data =
        BookingCancellationCabinMasterNotification.prepare_email_data(
          booking,
          payment_stub(),
          nil,
          "Testing"
        )

      html = BookingCancellationCabinMasterNotification.render(data)
      assert html =~ "1 adult"
      assert html =~ "Total: 1 guest"

      booking2 =
        booking_fixture(%{
          user_id: user.id,
          guests_count: 2,
          children_count: 2
        })
        |> Repo.preload(:user)

      html2 =
        BookingCancellationCabinMasterNotification.prepare_email_data(
          booking2,
          payment_stub(),
          nil,
          nil
        )
        |> BookingCancellationCabinMasterNotification.render()

      assert html2 =~ "2 adults"
      assert html2 =~ "2 children"
      assert html2 =~ "Total: 4 guests"

      booking3 =
        booking_fixture(%{
          user_id: user.id,
          guests_count: 0,
          children_count: 1
        })
        |> Repo.preload(:user)

      html3 =
        BookingCancellationCabinMasterNotification.prepare_email_data(
          booking3,
          nil,
          nil,
          nil
        )
        |> BookingCancellationCabinMasterNotification.render()

      assert html3 =~ "1 child"
    end

    test "get_subject/1 notification vs action titles" do
      assert BookingCancellationCabinMasterNotification.get_subject(false) =~
               "Notification"

      assert BookingCancellationCabinMasterNotification.get_subject(true) =~
               "Action Required"
    end
  end
end
