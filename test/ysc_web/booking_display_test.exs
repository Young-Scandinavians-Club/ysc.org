defmodule YscWeb.BookingDisplayTest do
  use ExUnit.Case, async: true

  alias YscWeb.BookingDisplay

  describe "status_badge_type/1" do
    test "maps known booking statuses for member views" do
      assert BookingDisplay.status_badge_type(:complete) == "green"
      assert BookingDisplay.status_badge_type(:hold) == "yellow"
      assert BookingDisplay.status_badge_type(:canceled) == "red"
      assert BookingDisplay.status_badge_type(:refunded) == "red"
      assert BookingDisplay.status_badge_type(:draft) == "gray"
    end
  end

  describe "status_label/1" do
    test "maps known booking statuses to member-friendly labels" do
      assert BookingDisplay.status_label(:hold) == "Awaiting payment"
      assert BookingDisplay.status_label(:complete) == "Confirmed"
      assert BookingDisplay.status_label(:canceled) == "Cancelled"
      assert BookingDisplay.status_label(:refunded) == "Refunded"
    end

    test "title-cases unknown statuses" do
      assert BookingDisplay.status_label(:draft) == "Draft"
    end
  end

  describe "payment_status_badge_type/1" do
    test "maps known payment statuses for member views" do
      assert BookingDisplay.payment_status_badge_type(:completed) == "green"
      assert BookingDisplay.payment_status_badge_type(:pending) == "yellow"
      assert BookingDisplay.payment_status_badge_type(:refunded) == "red"
      assert BookingDisplay.payment_status_badge_type(:failed) == "gray"
    end
  end

  describe "payment_status_label/1" do
    test "maps known payment statuses to member-friendly labels" do
      assert BookingDisplay.payment_status_label(:completed) == "Completed"
      assert BookingDisplay.payment_status_label(:pending) == "Pending"
      assert BookingDisplay.payment_status_label(:refunded) == "Refunded"
    end

    test "title-cases unknown statuses" do
      assert BookingDisplay.payment_status_label(:failed) == "Failed"
    end
  end
end
