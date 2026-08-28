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

  describe "count_label/3" do
    test "singular and plural units" do
      assert BookingDisplay.count_label(1, "night", "nights") == "1 night"
      assert BookingDisplay.count_label(4, "night", "nights") == "4 nights"
      assert BookingDisplay.count_label(nil, "guest", "guests") == "0 guests"
    end
  end

  describe "nights_label/1" do
    test "formats stay length" do
      assert BookingDisplay.nights_label(1) == "1 night"
      assert BookingDisplay.nights_label(0) == "0 nights"
      assert BookingDisplay.nights_label(3) == "3 nights"
    end

    test "capitalizes the unit for badges" do
      assert BookingDisplay.nights_label(1, capitalize: true) == "1 Night"
      assert BookingDisplay.nights_label(2, capitalize: true) == "2 Nights"
    end

    test "coerces string and nil counts" do
      assert BookingDisplay.nights_label("1") == "1 night"
      assert BookingDisplay.nights_label(nil) == "0 nights"
    end

    test "treats negative, blank, and non-numeric counts as zero" do
      assert BookingDisplay.nights_label(-3) == "0 nights"
      assert BookingDisplay.nights_label("-2") == "0 nights"
      assert BookingDisplay.nights_label("abc") == "0 nights"
      assert BookingDisplay.nights_label(:unknown) == "0 nights"
      assert BookingDisplay.count_label(-1, "guest", "guests") == "0 guests"
    end
  end

  describe "adults_label/1 and children_label/1" do
    test "formats adult and child counts" do
      assert BookingDisplay.adults_label(1) == "1 adult"
      assert BookingDisplay.adults_label(2) == "2 adults"
      assert BookingDisplay.children_label(1) == "1 child"
      assert BookingDisplay.children_label(3) == "3 children"
    end
  end

  describe "people_label/1" do
    test "formats combined headcount" do
      assert BookingDisplay.people_label(1) == "1 guest"
      assert BookingDisplay.people_label(4) == "4 guests"
    end
  end

  describe "season_rate_label/1" do
    test "keeps a real season name" do
      assert BookingDisplay.season_rate_label("Summer") == "Summer"
    end

    test "does not show Unnamed season when the name is missing" do
      assert BookingDisplay.season_rate_label(nil) == "Season rate"
      assert BookingDisplay.season_rate_label("") == "Season rate"
      assert BookingDisplay.season_rate_label("   ") == "Season rate"
    end
  end

  describe "guests_label/3" do
    test "joins adults and children with a comma by default" do
      assert BookingDisplay.guests_label(2, 1) == "2 adults, 1 child"
      assert BookingDisplay.guests_label(1, 0) == "1 adult"
      assert BookingDisplay.guests_label(0, 0) == "0 adults"
    end

    test "accepts a compact separator" do
      assert BookingDisplay.guests_label(2, 1, separator: " • ") ==
               "2 adults • 1 child"
    end

    test "omits zero adults when requested" do
      assert BookingDisplay.guests_label(0, 1, omit_zero_adults: true) ==
               "1 child"

      assert BookingDisplay.guests_label(0, 0, omit_zero_adults: true) ==
               "0 adults"
    end

    test "appends a total when requested" do
      assert BookingDisplay.guests_label(1, 0, include_total: true) ==
               "1 adult (Total: 1 guest)"

      assert BookingDisplay.guests_label(2, 2, include_total: true) ==
               "2 adults, 2 children (Total: 4 guests)"
    end
  end

  describe "guests_total_label/2" do
    test "formats combined headcount as a Total prefix" do
      assert BookingDisplay.guests_total_label(1, 0) == "Total: 1 guest"
      assert BookingDisplay.guests_total_label(2, 1) == "Total: 3 guests"
    end
  end
end
