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

    test "falls back to Pacific time for blank, nil, and unknown names" do
      pacific_today = TimeZone.today("America/Los_Angeles")

      assert TimeZone.today(nil) == pacific_today
      assert TimeZone.today("") == pacific_today
      assert TimeZone.today("Not/AZone") == pacific_today
    end
  end

  describe "at/3" do
    test "builds a Pacific wall-clock instant" do
      dt = TimeZone.at(~D[2024-06-15], ~T[13:00:00])

      assert dt.time_zone == "America/Los_Angeles"
      assert DateTime.to_date(dt) == ~D[2024-06-15]
      assert DateTime.to_time(dt) == ~T[13:00:00]
    end

    test "accepts an explicit timezone" do
      dt = TimeZone.at(~D[2024-06-15], ~T[13:00:00], "America/New_York")

      assert dt.time_zone == "America/New_York"
      assert DateTime.to_time(dt) == ~T[13:00:00]
    end
  end

  describe "at/3 on DST boundaries" do
    test "resolves an ambiguous fall-back time to the earlier (PDT) instant" do
      # 2026-11-01 01:30 happens twice in Pacific time.
      assert TimeZone.at_utc(~D[2026-11-01], ~T[01:30:00]) ==
               ~U[2026-11-01 08:30:00Z]
    end

    test "resolves a skipped spring-forward time to the instant before the gap" do
      # 2026-03-08 02:30 never happens in Pacific time.
      assert TimeZone.at_utc(~D[2026-03-08], ~T[02:30:00]) ==
               ~U[2026-03-08 09:59:59.999999Z]
    end
  end

  describe "at_utc/3" do
    test "converts Pacific daylight time to UTC" do
      # June is PDT (UTC-7)
      assert TimeZone.at_utc(~D[2024-06-15], ~T[13:00:00]) ==
               ~U[2024-06-15 20:00:00Z]
    end

    test "converts Pacific standard time to UTC" do
      # January is PST (UTC-8)
      assert TimeZone.at_utc(~D[2024-01-15], ~T[13:00:00]) ==
               ~U[2024-01-15 21:00:00Z]
    end

    test "matches check-in and check-out reminder wall-clock times" do
      assert TimeZone.at_utc(~D[2024-06-15], ~T[08:00:00]) ==
               ~U[2024-06-15 15:00:00Z]

      assert TimeZone.at_utc(~D[2024-06-15], ~T[18:00:00]) ==
               ~U[2024-06-16 01:00:00Z]
    end

    test "accepts an explicit timezone" do
      assert TimeZone.at_utc(~D[2024-06-15], ~T[13:00:00], "America/New_York") ==
               ~U[2024-06-15 17:00:00Z]
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

  describe "format_datetime_local/2" do
    test "formats a UTC instant as a Pacific datetime-local value" do
      # June is PDT (UTC-7)
      assert TimeZone.format_datetime_local(~U[2024-06-15 20:00:00Z]) ==
               "2024-06-15T13:00"

      # January is PST (UTC-8)
      assert TimeZone.format_datetime_local(~U[2024-01-15 20:00:00Z]) ==
               "2024-01-15T12:00"
    end

    test "accepts an explicit timezone" do
      assert TimeZone.format_datetime_local(
               ~U[2024-06-15 20:00:00Z],
               "America/New_York"
             ) == "2024-06-15T16:00"
    end

    test "falls back to Pacific time for an invalid zone" do
      assert TimeZone.format_datetime_local(
               ~U[2024-06-15 20:00:00Z],
               "Not/AZone"
             ) == "2024-06-15T13:00"
    end

    test "returns empty string for nil and passes through formatted binaries" do
      assert TimeZone.format_datetime_local(nil) == ""

      assert TimeZone.format_datetime_local("2024-06-15T13:00") ==
               "2024-06-15T13:00"
    end
  end

  describe "parse_datetime_local/2" do
    test "parses a Pacific datetime-local value as UTC" do
      assert {:ok, dt} = TimeZone.parse_datetime_local("2024-06-15T13:00")
      assert dt == ~U[2024-06-15 20:00:00Z]

      assert {:ok, dt} = TimeZone.parse_datetime_local("2024-01-15T12:00")
      assert dt == ~U[2024-01-15 20:00:00Z]
    end

    test "accepts an explicit timezone" do
      assert {:ok, dt} =
               TimeZone.parse_datetime_local(
                 "2024-06-15T16:00",
                 "America/New_York"
               )

      assert dt == ~U[2024-06-15 20:00:00Z]
    end

    test "round-trips a UTC instant through format then parse" do
      original = ~U[2024-06-15 20:00:00Z]
      formatted = TimeZone.format_datetime_local(original)

      assert {:ok, parsed} = TimeZone.parse_datetime_local(formatted)
      assert DateTime.compare(parsed, original) == :eq
    end

    test "does not raise on DST boundaries" do
      assert {:ok, ~U[2026-11-01 08:30:00Z]} =
               TimeZone.parse_datetime_local("2026-11-01T01:30")

      assert {:ok, ~U[2026-03-08 09:59:59.999999Z]} =
               TimeZone.parse_datetime_local("2026-03-08T02:30")
    end

    test "returns error for invalid or non-binary values" do
      assert {:error, _} = TimeZone.parse_datetime_local("not-a-datetime")
      assert {:error, _} = TimeZone.parse_datetime_local("")
      assert {:error, :invalid_format} = TimeZone.parse_datetime_local(nil)
      assert {:error, :invalid_format} = TimeZone.parse_datetime_local(123)
    end
  end
end
