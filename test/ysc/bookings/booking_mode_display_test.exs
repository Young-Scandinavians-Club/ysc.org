defmodule Ysc.Bookings.BookingModeDisplayTest do
  use ExUnit.Case, async: true

  alias Ysc.Bookings.BookingModeDisplay

  describe "label/1" do
    test "formats known booking modes" do
      assert BookingModeDisplay.label(:room) == "Room Booking"
      assert BookingModeDisplay.label(:day) == "Day Booking"
      assert BookingModeDisplay.label(:buyout) == "Entire cabin"
      assert BookingModeDisplay.label("room") == "Room Booking"
      assert BookingModeDisplay.label("day") == "Day Booking"
      assert BookingModeDisplay.label("buyout") == "Entire cabin"
    end

    test "title-cases unknown atoms" do
      assert BookingModeDisplay.label(:custom) == "Custom"
    end

    test "returns passthrough strings" do
      assert BookingModeDisplay.label("Custom Label") == "Custom Label"
    end
  end

  describe "stay_type_label/1" do
    test "formats known booking modes for member UIs" do
      assert BookingModeDisplay.stay_type_label(:buyout) == "Entire cabin"
      assert BookingModeDisplay.stay_type_label(:room) == "Individual room(s)"
      assert BookingModeDisplay.stay_type_label(:day) == "Shared cabin"
      assert BookingModeDisplay.stay_type_label("buyout") == "Entire cabin"
      assert BookingModeDisplay.stay_type_label("room") == "Individual room(s)"
      assert BookingModeDisplay.stay_type_label("day") == "Shared cabin"
    end

    test "falls back to Shared cabin for unknown or missing modes" do
      assert BookingModeDisplay.stay_type_label(:custom) == "Shared cabin"
      assert BookingModeDisplay.stay_type_label(nil) == "Shared cabin"
      assert BookingModeDisplay.stay_type_label("other") == "Shared cabin"
    end

    test "uses different copy from email label/1 for room and day" do
      assert BookingModeDisplay.label(:room) == "Room Booking"
      assert BookingModeDisplay.stay_type_label(:room) == "Individual room(s)"
      assert BookingModeDisplay.label(:day) == "Day Booking"
      assert BookingModeDisplay.stay_type_label(:day) == "Shared cabin"

      assert BookingModeDisplay.label(:buyout) ==
               BookingModeDisplay.stay_type_label(:buyout)
    end
  end

  describe "buyout?/1" do
    test "detects buyout modes" do
      assert BookingModeDisplay.buyout?(:buyout)
      assert BookingModeDisplay.buyout?("buyout")
    end

    test "returns false for other modes" do
      refute BookingModeDisplay.buyout?(:room)
      refute BookingModeDisplay.buyout?(:day)
      refute BookingModeDisplay.buyout?("room")
      refute BookingModeDisplay.buyout?(nil)
    end
  end
end
