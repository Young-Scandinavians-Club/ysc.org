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
end
