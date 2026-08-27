defmodule YscWeb.TimeZoneTest do
  use ExUnit.Case, async: true

  alias YscWeb.TimeZone

  describe "from_name/1" do
    test "keeps a valid IANA timezone" do
      assert TimeZone.from_name("America/New_York") == "America/New_York"
    end

    test "falls back to Pacific time for blank, nil, and unknown names" do
      assert TimeZone.from_name(nil) == "America/Los_Angeles"
      assert TimeZone.from_name("") == "America/Los_Angeles"
      assert TimeZone.from_name("Not/AZone") == "America/Los_Angeles"
    end
  end

  describe "today/1" do
    test "returns the calendar date in the given zone" do
      assert TimeZone.today("UTC") == DateTime.to_date(DateTime.utc_now())
    end
  end

  describe "shift/2" do
    test "shifts a UTC instant into the given zone" do
      shifted = TimeZone.shift(~U[2024-12-01 06:00:00Z], "America/New_York")

      assert shifted.time_zone == "America/New_York"
      assert DateTime.to_date(shifted) == ~D[2024-12-01]
      assert DateTime.to_time(shifted) == ~T[01:00:00]
    end

    test "falls back to Pacific time for an invalid zone" do
      shifted = TimeZone.shift(~U[2024-12-01 06:00:00Z], "Not/AZone")

      assert shifted.time_zone == "America/Los_Angeles"
      assert DateTime.to_date(shifted) == ~D[2024-11-30]
    end
  end
end
