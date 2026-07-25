defmodule YscWeb.Admin.DateTimeDisplayTest do
  use ExUnit.Case, async: true

  alias YscWeb.Admin.DateTimeDisplay

  describe "format_utc_date/1" do
    test "formats UTC datetime in Pacific timezone" do
      # 2024-03-16 02:30 UTC is still 2024-03-15 in Pacific
      dt = ~U[2024-03-16 02:30:00Z]

      assert DateTimeDisplay.format_utc_date(dt) == "Mar 15, 2024"
    end

    test "returns em dash for nil and invalid values" do
      assert DateTimeDisplay.format_utc_date(nil) == "—"
      assert DateTimeDisplay.format_utc_date("invalid") == "—"
    end
  end

  describe "format_utc_date_long/1" do
    test "formats UTC datetime with long month name" do
      dt = ~U[2024-06-15 12:00:00Z]

      assert DateTimeDisplay.format_utc_date_long(dt) == "June 15, 2024"
    end

    test "returns em dash for nil and invalid values" do
      assert DateTimeDisplay.format_utc_date_long(nil) == "—"
      assert DateTimeDisplay.format_utc_date_long(123) == "—"
    end
  end

  describe "format_event_date/1" do
    test "formats UTC calendar date without timezone shift" do
      dt = ~U[2024-03-16 02:30:00Z]

      assert DateTimeDisplay.format_event_date(dt) == "Mar 16, 2024"
    end

    test "returns em dash for nil and invalid values" do
      assert DateTimeDisplay.format_event_date(nil) == "—"
      assert DateTimeDisplay.format_event_date(%{}) == "—"
    end
  end

  describe "format_datetime_compact/1" do
    test "formats stored UTC datetime without timezone conversion" do
      dt = ~U[2024-03-16 14:30:00Z]

      assert DateTimeDisplay.format_datetime_compact(dt) == "Mar 16, 2024 14:30"
    end

    test "returns empty string for nil and invalid values" do
      assert DateTimeDisplay.format_datetime_compact(nil) == ""
      assert DateTimeDisplay.format_datetime_compact(%{}) == ""
    end
  end
end
