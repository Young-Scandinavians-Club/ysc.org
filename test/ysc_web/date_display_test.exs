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
      assert DateDisplay.format_pacific_date_short(~U[2024-03-05 06:00:00Z]) ==
               "Mar 4"

      assert DateDisplay.format_pacific_date_short(~U[2024-03-05 10:00:00Z]) ==
               "Mar 5"
    end

    test "returns empty string for nil and invalid values" do
      assert DateDisplay.format_pacific_date_short(nil) == ""
      assert DateDisplay.format_pacific_date_short(:atom) == ""
    end

    test "accepts a custom default" do
      assert DateDisplay.format_pacific_date_short(nil, "—") == "—"
    end

    test "the default argument only applies to nil/invalid values, not Date values" do
      assert DateDisplay.format_pacific_date_short(~D[2024-03-05], "—") ==
               "Mar 5"
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

  describe "format_sale_window_range/2" do
    test "shows Pacific calendar dates for tier sale windows" do
      tier = %{
        start_date: ~U[2026-08-10 07:00:00Z],
        end_date: ~U[2026-08-15 06:59:59Z]
      }

      assert DateDisplay.format_sale_window_range(tier, with_year: true) ==
               "Aug 10 – Aug 14, 2026"
    end

    test "returns default when tier has no sale start date" do
      tier = %{start_date: nil, end_date: ~U[2026-08-15 06:59:59Z]}

      assert DateDisplay.format_sale_window_range(tier, default: "Always") ==
               "Always"
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

  describe "event_day_label/1" do
    test "uses the stored calendar date, not a Pacific timezone shift" do
      today_pacific =
        DateTime.now!("America/Los_Angeles")
        |> DateTime.to_date()

      # Midnight UTC of tomorrow is still "tomorrow" as a wall-clock event date,
      # even though that instant is still "today" in Pacific time.
      tomorrow = Date.add(today_pacific, 1)
      start_date = DateTime.new!(tomorrow, ~T[00:00:00], "Etc/UTC")

      assert DateDisplay.event_day_label(%{start_date: start_date}) == :tomorrow
      refute DateDisplay.event_day_label(%{start_date: start_date}) == :today
    end

    test "returns :today for today's Pacific wall-clock date" do
      today_pacific =
        DateTime.now!("America/Los_Angeles")
        |> DateTime.to_date()

      start_date = DateTime.new!(today_pacific, ~T[00:00:00], "Etc/UTC")

      assert DateDisplay.event_day_label(%{start_date: start_date}) == :today
    end

    test "returns nil when start_date is missing" do
      assert DateDisplay.event_day_label(%{}) == nil
      assert DateDisplay.event_day_label(%{start_date: nil}) == nil
    end

    test "does not treat another timezone's today as the event day" do
      pacific_today =
        DateTime.now!("America/Los_Angeles")
        |> DateTime.to_date()

      auckland_today = DateTime.now!("Pacific/Auckland") |> DateTime.to_date()
      start_date = DateTime.new!(auckland_today, ~T[00:00:00], "Etc/UTC")

      label = DateDisplay.event_day_label(%{start_date: start_date})

      if Date.compare(auckland_today, pacific_today) == :eq do
        assert label == :today
      else
        refute label == :today
      end
    end
  end

  describe "days_until_event/1" do
    test "does not shift midnight UTC onto the previous Pacific calendar day" do
      today =
        DateTime.now!("America/Los_Angeles")
        |> DateTime.to_date()

      two_days_out = Date.add(today, 2)
      start_date = DateTime.new!(two_days_out, ~T[00:00:00], "Etc/UTC")
      event = %{start_date: start_date}

      assert DateDisplay.days_until_event(event) == 2
      assert DateDisplay.event_day_label(event) == nil
      assert DateDisplay.relative_days_phrase(2) == "In 2 days"
    end

    test "returns 0 for today's stored calendar date" do
      today =
        DateTime.now!("America/Los_Angeles")
        |> DateTime.to_date()

      event = %{start_date: DateTime.new!(today, ~T[00:00:00], "Etc/UTC")}

      assert DateDisplay.days_until_event(event) == 0
      assert DateDisplay.relative_days_phrase(0) == "Today"
    end
  end

  describe "days_until_cabin_checkin/1" do
    test "counts Pacific calendar days until cabin check-in" do
      today =
        DateTime.now!("America/Los_Angeles")
        |> DateTime.to_date()

      assert DateDisplay.days_until_cabin_checkin(%{
               checkin_date: Date.add(today, 2)
             }) == 2

      assert DateDisplay.days_until_cabin_checkin(%{
               checkin_date: Date.add(today, -1)
             }) == :started
    end

    test "returns nil when check-in date is missing" do
      assert DateDisplay.days_until_cabin_checkin(%{}) == nil
      assert DateDisplay.days_until_cabin_checkin(%{checkin_date: nil}) == nil
    end
  end

  describe "event_start_datetime/1" do
    test "combines the stored calendar date with Pacific wall-clock time" do
      start_date = ~U[2026-08-28 00:00:00Z]
      event = %{start_date: start_date, start_time: ~T[19:00:00]}

      dt = DateDisplay.event_start_datetime(event)

      assert DateTime.to_date(dt) == ~D[2026-08-28]
      assert DateTime.to_time(dt) == ~T[19:00:00]
      assert dt.time_zone == "America/Los_Angeles"
    end
  end

  describe "format_date_in_zone/2" do
    test "shifts UTC instants into the given timezone" do
      assert DateDisplay.format_date_in_zone(
               ~U[2024-12-01 06:00:00Z],
               "America/Los_Angeles"
             ) == "Nov 30, 2024"

      assert DateDisplay.format_date_in_zone(
               ~U[2024-12-01 06:00:00Z],
               "UTC"
             ) == "Dec 1, 2024"
    end

    test "formats Date values without shifting and falls back for nil" do
      assert DateDisplay.format_date_in_zone(~D[2024-12-01], "UTC") ==
               "Dec 1, 2024"

      assert DateDisplay.format_date_in_zone(nil, "UTC") == ""
      assert DateDisplay.format_date_in_zone("nope", "UTC", "TBD") == "TBD"
    end

    test "falls back to Pacific when the timezone is invalid" do
      assert DateDisplay.format_date_in_zone(
               ~U[2024-12-01 06:00:00Z],
               "Not/A/Zone"
             ) == "Nov 30, 2024"
    end
  end

  describe "format_date_short_in_zone/2" do
    test "shifts UTC instants into the given timezone" do
      assert DateDisplay.format_date_short_in_zone(
               ~U[2024-12-01 06:00:00Z],
               "America/Los_Angeles"
             ) == "Nov 30"

      assert DateDisplay.format_date_short_in_zone(~D[2024-03-05], "UTC") ==
               "Mar 5"

      assert DateDisplay.format_date_short_in_zone(nil, "UTC") == ""
    end
  end

  describe "calendar_date/1" do
    test "extracts a calendar date from supported types" do
      assert DateDisplay.calendar_date(~U[2026-08-28 00:00:00Z]) ==
               ~D[2026-08-28]

      assert DateDisplay.calendar_date(~D[2026-08-28]) == ~D[2026-08-28]

      assert DateDisplay.calendar_date(~N[2026-08-28 12:00:00]) ==
               ~D[2026-08-28]

      assert DateDisplay.calendar_date(nil) == nil
      assert DateDisplay.calendar_date("nope") == nil
    end
  end

  describe "relative_days_phrase/1" do
    test "covers today, tomorrow, future, and invalid values" do
      assert DateDisplay.relative_days_phrase(0) == "Today"
      assert DateDisplay.relative_days_phrase(1) == "Tomorrow"
      assert DateDisplay.relative_days_phrase(4) == "In 4 days"
      assert DateDisplay.relative_days_phrase(-1) == ""
      assert DateDisplay.relative_days_phrase(nil) == ""
    end
  end
end
