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

  describe "UTC datetime labels without timezone conversion" do
    setup do
      [dt: ~U[2024-03-15 14:30:45Z]]
    end

    test "format_utc_datetime/1", %{dt: dt} do
      assert DateTimeDisplay.format_utc_datetime(dt) == "Mar 15, 2024 14:30 UTC"
    end

    test "format_utc_datetime_at/1", %{dt: dt} do
      assert DateTimeDisplay.format_utc_datetime_at(dt) ==
               "Mar 15, 2024 at 14:30 UTC"
    end

    test "format_utc_datetime_short/1", %{dt: dt} do
      assert DateTimeDisplay.format_utc_datetime_short(dt) ==
               "Mar 15 at 14:30 UTC"
    end

    test "format_utc_datetime_long/1", %{dt: dt} do
      assert DateTimeDisplay.format_utc_datetime_long(dt) ==
               "March 15, 2024 14:30:45 UTC"
    end

    test "format_utc_time/1", %{dt: dt} do
      assert DateTimeDisplay.format_utc_time(dt) == "14:30:45 UTC"
    end

    test "format_utc_iso/1", %{dt: dt} do
      assert DateTimeDisplay.format_utc_iso(dt) == "2024-03-15 14:30:45 UTC"
    end

    test "format_utc_iso_minute/1", %{dt: dt} do
      assert DateTimeDisplay.format_utc_iso_minute(dt) == "2024-03-15 14:30 UTC"
    end

    test "returns em dash for nil and invalid values" do
      assert DateTimeDisplay.format_utc_datetime(nil) == "—"
      assert DateTimeDisplay.format_utc_time("invalid") == "—"
    end
  end

  describe "calendar date labels without timezone conversion" do
    test "format_date_month_year/1" do
      date = ~D[2024-03-15]

      assert DateTimeDisplay.format_date_month_year(date) == "March 2024"

      assert DateTimeDisplay.format_date_month_year(~U[2024-03-15 12:00:00Z]) ==
               "March 2024"
    end

    test "format_calendar_date_long/1" do
      date = ~D[2024-03-15]

      assert DateTimeDisplay.format_calendar_date_long(date) == "March 15, 2024"
    end

    test "format_month_day/1" do
      date = ~D[2024-03-05]

      assert DateTimeDisplay.format_month_day(date) == "Mar 05"
    end

    test "returns em dash for nil and invalid values" do
      assert DateTimeDisplay.format_date_month_year(nil) == "—"
      assert DateTimeDisplay.format_calendar_date_long(nil) == "—"
      assert DateTimeDisplay.format_month_day(nil) == "—"
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
