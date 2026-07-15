defmodule YscWeb.DateDisplayTest do
  use ExUnit.Case, async: true

  alias YscWeb.DateDisplay

  describe "format_date_long/1" do
    test "formats Date values" do
      assert DateDisplay.format_date_long(~D[2024-06-15]) == "June 15, 2024"
    end

    test "formats DateTime values using the UTC calendar date" do
      dt = ~U[2024-06-15 23:30:00Z]

      assert DateDisplay.format_date_long(dt) == "June 15, 2024"
    end

    test "returns empty string for nil and invalid values by default" do
      assert DateDisplay.format_date_long(nil) == ""
      assert DateDisplay.format_date_long("invalid") == ""
    end

    test "accepts a custom default for nil and invalid values" do
      assert DateDisplay.format_date_long(nil, "TBD") == "TBD"
      assert DateDisplay.format_date_long(%{}, "—") == "—"
    end
  end

  describe "format_date_short/1" do
    test "formats Date values without zero-padded day" do
      assert DateDisplay.format_date_short(~D[2024-03-05]) == "Mar 5"
    end

    test "formats DateTime values using the UTC calendar date" do
      dt = ~U[2024-03-05 18:00:00Z]

      assert DateDisplay.format_date_short(dt) == "Mar 5"
    end

    test "returns empty string for nil and invalid values" do
      assert DateDisplay.format_date_short(nil) == ""
      assert DateDisplay.format_date_short(123) == ""
    end
  end

  describe "format_datetime_display/1" do
    test "formats Date values" do
      assert DateDisplay.format_datetime_display(~D[2024-12-01]) ==
               "Dec 1, 2024"
    end

    test "formats DateTime values using the UTC calendar date" do
      dt = ~U[2024-12-01 06:00:00Z]

      assert DateDisplay.format_datetime_display(dt) == "Dec 1, 2024"
    end

    test "returns empty string for nil and invalid values" do
      assert DateDisplay.format_datetime_display(nil) == ""
      assert DateDisplay.format_datetime_display(:atom) == ""
    end
  end

  describe "format_datetime_at/1" do
    test "formats DateTime values without timezone conversion" do
      dt = ~U[2024-06-15 15:30:00Z]

      assert DateDisplay.format_datetime_at(dt) == "June 15, 2024 at 03:30 PM"
    end

    test "returns empty string for nil and invalid values" do
      assert DateDisplay.format_datetime_at(nil) == ""
      assert DateDisplay.format_datetime_at(~D[2024-06-15]) == ""
    end

    test "accepts a custom default" do
      assert DateDisplay.format_datetime_at(nil, "—") == "—"
    end
  end

  describe "format_in_zone/2" do
    test "formats Date values as long dates" do
      assert DateDisplay.format_in_zone(~D[2024-06-15], "America/Los_Angeles") ==
               "June 15, 2024"
    end

    test "formats DateTime values in the given timezone" do
      dt = ~U[2024-06-15 22:30:00Z]

      assert DateDisplay.format_in_zone(dt, "America/Los_Angeles") ==
               "June 15, 2024 at 03:30 PM PDT"
    end

    test "returns default for nil and invalid values" do
      assert DateDisplay.format_in_zone(nil, "America/Los_Angeles") == ""

      assert DateDisplay.format_in_zone("invalid", "America/Los_Angeles", "—") ==
               "—"
    end
  end
end
