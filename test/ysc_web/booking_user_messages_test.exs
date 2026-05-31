defmodule YscWeb.BookingUserMessagesTest do
  use ExUnit.Case, async: true

  alias YscWeb.BookingUserMessages

  test "reservation not found message" do
    assert BookingUserMessages.reservation_not_found() =~ "couldn't find this reservation"
    assert BookingUserMessages.reservation_not_found() =~ "info@ysc.org"
  end

  test "checkout not found message" do
    assert BookingUserMessages.checkout_not_found() =~ "start a new booking from the cabin page"
  end

  test "modification messages" do
    assert BookingUserMessages.modification_acknowledgment_required() =~
             "check the box at the bottom"

    assert BookingUserMessages.modification_forfeiture_title() =~
             "changing your dates affects refunds"
  end

  test "clear lake blackout message" do
    assert BookingUserMessages.clear_lake_blackout_date("2026-06-01") =~
             "isn't open for bookings on 2026-06-01"
  end

  test "checkout step copy" do
    assert BookingUserMessages.checkout_guest_info_step_enter_guests() =~ "every guest"
    assert BookingUserMessages.checkout_guest_info_step_continue_payment() =~ "payment"
    assert BookingUserMessages.checkout_payment_step_pay() =~ "secure payment"
  end
end
