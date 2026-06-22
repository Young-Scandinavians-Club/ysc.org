defmodule YscWeb.BookingUserMessagesTest do
  use ExUnit.Case, async: true

  alias YscWeb.BookingUserMessages

  test "reservation not found message" do
    assert BookingUserMessages.reservation_not_found() =~
             "couldn't find this reservation"

    assert BookingUserMessages.reservation_not_found() =~ "info@ysc.org"
  end

  test "checkout not found message" do
    assert BookingUserMessages.checkout_not_found() =~
             "start a new booking from the cabin page"
  end

  test "modification messages" do
    assert BookingUserMessages.modification_acknowledgment_required() =~
             "check the box at the bottom"

    assert BookingUserMessages.modification_forfeiture_title() =~
             "will not get a refund"

    assert BookingUserMessages.modification_forfeiture_body() =~
             "cannot get a refund later"

    assert BookingUserMessages.modification_forfeiture_acknowledgment() =~
             "will not receive a refund"
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
             "every guest"

    assert BookingUserMessages.checkout_guest_info_step_continue_payment() =~
             "hold on these dates expires soon"

    assert BookingUserMessages.checkout_guest_info_step_continue_complimentary() =~
             "hold on these dates expires soon"

    refute BookingUserMessages.checkout_guest_info_step_continue_payment() =~
             "reservation timer"

    assert BookingUserMessages.checkout_payment_step_pay() =~ "payment details"
  end

  test "cabin availability error copy" do
    assert BookingUserMessages.insufficient_capacity_error() =~
             "open spots at the cabin"

    refute BookingUserMessages.insufficient_capacity_error() =~ "capacity"

    assert BookingUserMessages.insufficient_capacity_error(
             include_guest_count: true
           ) =~
             "group size"

    assert BookingUserMessages.property_unavailable_error() =~ "isn't available"
    refute BookingUserMessages.property_unavailable_error() =~ "property"

    assert BookingUserMessages.insufficient_capacity_summary() =~
             "Not enough space"

    assert BookingUserMessages.property_unavailable_summary() =~
             "Cabin unavailable"

    assert BookingUserMessages.membership_required_link_text() ==
             "Membership page"

    assert BookingUserMessages.membership_required_message_html(
             "/users/membership"
           ) =~
             "Membership page"
  end
end
