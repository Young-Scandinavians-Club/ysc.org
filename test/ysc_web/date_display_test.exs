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

  describe "format_event_date_range/2" do
    test "formats a single date without year" do
      assert DateDisplay.format_event_date_range(%{start_date: ~D[2024-03-05]}) ==
               "Mar 5"
    end

    test "formats a multi-day range within the same year" do
      assert DateDisplay.format_event_date_range(%{
               start_date: ~D[2024-03-05],
               end_date: ~D[2024-03-07]
             }) == "Mar 5 – Mar 7"
    end

    test "formats a multi-day range across years" do
      assert DateDisplay.format_event_date_range(%{
               start_date: ~D[2025-12-30],
               end_date: ~D[2026-01-02]
             }) == "Dec 30, 2025 – Jan 2, 2026"
    end

    test "includes year for single-day labels when requested" do
      assert DateDisplay.format_event_date_range(%{start_date: ~D[2024-03-05]},
               with_year: true
             ) == "Mar 5, 2024"
    end

    test "includes year on the end of same-year ranges when requested" do
      assert DateDisplay.format_event_date_range(
               %{
                 start_date: ~D[2024-03-05],
                 end_date: ~D[2024-03-07]
               },
               with_year: true
             ) == "Mar 5 – Mar 7, 2024"
    end

    test "returns default when start date is missing" do
      assert DateDisplay.format_event_date_range(%{start_date: nil},
               default: "TBD"
             ) ==
               "TBD"
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

  describe "format_pacific_date/1" do
    test "formats Date values without conversion" do
      assert DateDisplay.format_pacific_date(~D[2024-12-01]) == "Dec 1, 2024"
    end

    test "formats UTC DateTime values using the Pacific calendar date" do
      # Late UTC evening still counts as the same Pacific calendar day.
      assert DateDisplay.format_pacific_date(~U[2024-12-01 06:00:00Z]) ==
               "Nov 30, 2024"

      assert DateDisplay.format_pacific_date(~U[2024-12-01 08:00:00Z]) ==
               "Dec 1, 2024"
    end

    test "returns empty string for nil and invalid values" do
      assert DateDisplay.format_pacific_date(nil) == ""
      assert DateDisplay.format_pacific_date(:atom) == ""
    end

    test "accepts a custom default" do
      assert DateDisplay.format_pacific_date(nil, "—") == "—"
    end
  end

  describe "format_pacific_date_short/1" do
    test "formats Date values as short month/day labels" do
      assert DateDisplay.format_pacific_date_short(~D[2024-03-05]) == "Mar 5"
    end

    test "shifts DateTime values to Pacific before formatting" do
      assert DateDisplay.format_pacific_date_short(~U[2024-03-05 06:00:00Z]) == "Mar 4"
      assert DateDisplay.format_pacific_date_short(~U[2024-03-05 10:00:00Z]) == "Mar 5"
    end

    test "returns empty string for nil and invalid values" do
      assert DateDisplay.format_pacific_date_short(nil) == ""
      assert DateDisplay.format_pacific_date_short(:atom) == ""
    end

    test "accepts a custom default" do
      assert DateDisplay.format_pacific_date_short(nil, "—") == "—"
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
