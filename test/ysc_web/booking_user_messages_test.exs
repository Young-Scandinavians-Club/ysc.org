defmodule YscWeb.BookingUserMessagesTest do
  use ExUnit.Case, async: true

  alias YscWeb.BookingUserMessages

  test "reservation not found message" do
    assert BookingUserMessages.reservation_not_found() =~
             "couldn't find this booking"

    refute BookingUserMessages.reservation_not_found() =~ "reservation"

    assert BookingUserMessages.reservation_not_found() =~ "info@ysc.org"
  end

  test "checkout not found message" do
    assert BookingUserMessages.checkout_not_found() =~
             "couldn't find this booking"

    assert BookingUserMessages.checkout_not_found() =~
             "start a new booking from the cabin page"

    refute BookingUserMessages.checkout_not_found() =~ "reservation"
  end

  test "modification messages" do
    assert BookingUserMessages.modification_acknowledgment_required() =~
             "check the box at the bottom"

    assert BookingUserMessages.modification_forfeiture_title() =~
             "No refunds"

    assert BookingUserMessages.modification_forfeiture_body() =~
             "cannot get a refund later"

    assert BookingUserMessages.modification_forfeiture_acknowledgment() =~
             "non-refundable"
  end

  test "clear lake blackout message" do
    assert BookingUserMessages.clear_lake_blackout_date("2026-06-01") =~
             "isn't open for bookings on 2026-06-01"
  end

  test "unavailable blackout dates message" do
    assert BookingUserMessages.unavailable_blackout_dates() =~
             "aren't available for booking"

    refute BookingUserMessages.unavailable_blackout_dates() =~ "blackout"
  end

  test "checkout step copy" do
    assert BookingUserMessages.checkout_guest_info_step_enter_guests() =~
             "everyone else staying with you"

    assert BookingUserMessages.checkout_guest_info_step_enter_guests() =~
             "already included in the booking"

    assert BookingUserMessages.checkout_guest_info_step_continue_payment() =~
             "held temporarily"

    assert BookingUserMessages.checkout_guest_info_step_continue_complimentary() =~
             "held temporarily"

    refute BookingUserMessages.checkout_guest_info_step_continue_payment() =~
             "reservation timer"

    refute BookingUserMessages.checkout_guest_info_step_continue_payment() =~
             "hold on these dates"

    assert BookingUserMessages.checkout_payment_step_pay() =~ "payment details"

    assert BookingUserMessages.checkout_payment_step_confirm_complimentary() =~
             "Confirm booking"

    refute BookingUserMessages.checkout_payment_step_confirm_complimentary() =~
             "reservation"

    assert BookingUserMessages.checkout_confirmation_email_step() =~
             "confirmation email"

    assert BookingUserMessages.checkout_cabin_access_step() =~
             "cabin access details"

    assert BookingUserMessages.checkout_manage_booking_step() =~
             "My Bookings & Payments"
  end

  test "cabin availability error copy" do
    assert BookingUserMessages.insufficient_capacity_error() =~
             "open spots at the cabin"

    refute BookingUserMessages.insufficient_capacity_error() =~ "capacity"
    refute BookingUserMessages.insufficient_capacity_error() =~ "reserve"

    assert BookingUserMessages.insufficient_capacity_error(
             include_guest_count: true
           ) =~
             "group size"

    assert BookingUserMessages.property_unavailable_error() =~ "isn't available"
    refute BookingUserMessages.property_unavailable_error() =~ "property"
    refute BookingUserMessages.property_unavailable_error() =~ "reserve"

    assert BookingUserMessages.property_unavailable_error() =~
             "book the whole cabin"

    assert BookingUserMessages.insufficient_capacity_summary() =~
             "Not enough space"

    assert BookingUserMessages.property_unavailable_summary() =~
             "Cabin unavailable"

    assert BookingUserMessages.membership_required_link_text() ==
             "Manage Membership"

    assert BookingUserMessages.membership_required_message_html(
             "/users/membership"
           ) =~
             "Manage Membership"

    assert BookingUserMessages.membership_required_plain_message() =~
             "active YSC membership"

    refute BookingUserMessages.membership_required_plain_message() =~ "<a"

    assert BookingUserMessages.application_pending_approval_message() =~
             "still being reviewed"

    assert BookingUserMessages.application_pending_approval_message() =~
             "after your application is approved"
  end

  test "checkout hold expired messages" do
    assert BookingUserMessages.checkout_hold_expired() =~ "hold on these dates"
    assert BookingUserMessages.checkout_hold_expired() =~ "start a new booking"
    assert BookingUserMessages.checkout_hold_expired_toast() =~ "cabin page"
  end

  test "checkout error messages include contact email" do
    assert BookingUserMessages.checkout_pricing_load_failed() =~ "info@ysc.org"
    assert BookingUserMessages.checkout_payment_setup_failed() =~ "info@ysc.org"
    assert BookingUserMessages.checkout_cancel_failed() =~ "info@ysc.org"

    assert BookingUserMessages.checkout_booking_confirmation_failed() =~
             "info@ysc.org"

    assert BookingUserMessages.checkout_payment_confirmation_failed() =~
             "not charged twice"

    refute BookingUserMessages.checkout_payment_confirmation_failed() =~
             "contact us"
  end

  test "modification redirect error messages" do
    assert BookingUserMessages.modification_redirect_hold_expired() =~
             "original booking is unchanged"

    assert BookingUserMessages.modification_redirect_hold_expired() =~
             "info@ysc.org"

    refute BookingUserMessages.modification_redirect_hold_expired() =~
             "reservation hold"

    assert BookingUserMessages.modification_redirect_ledger_payment_failed() =~
             "My Bookings & Payments"

    assert BookingUserMessages.modification_redirect_update_failed() =~
             "couldn't update your booking"

    assert BookingUserMessages.modification_finalize_failed() =~
             "couldn't save your new dates"

    assert BookingUserMessages.modification_after_payment_recovery_suffix() =~
             "booking reference"

    refute BookingUserMessages.modification_after_payment_recovery_suffix() =~
             "confirmation number"

    assert BookingUserMessages.cancel_refund_error({:payment_not_found, nil}) =~
             "booking reference"

    refute BookingUserMessages.cancel_refund_error({:payment_not_found, nil}) =~
             "confirmation number"

    assert BookingUserMessages.cancel_refund_error({:calculation_failed, nil}) =~
             "couldn't calculate your refund"

    assert BookingUserMessages.cancel_refund_error({:refund_failed, nil}) =~
             "refund couldn't be processed automatically"

    assert BookingUserMessages.cancel_refund_error(
             {:pending_refund_failed, nil}
           ) =~
             "couldn't submit your refund for review"

    assert BookingUserMessages.cancel_refund_error({:cancellation_failed, nil}) =~
             "couldn't cancel your booking"

    refute BookingUserMessages.cancel_refund_error({:payment_not_found, nil}) =~
             "reservation"

    refute BookingUserMessages.modification_forfeiture_body() =~ "reservation"

    refute BookingUserMessages.modification_acknowledgment_required() =~
             "reservation"
  end

  test "booking creation failed message" do
    message = BookingUserMessages.booking_creation_failed()

    assert message =~ "couldn't complete your booking"
    assert message =~ "not been charged"
    assert message =~ "info@ysc.org"
  end
end
