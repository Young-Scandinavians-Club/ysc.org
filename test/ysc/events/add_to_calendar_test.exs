defmodule Ysc.Events.AddToCalendarTest do
  use ExUnit.Case, async: true

  alias Ysc.Events.AddToCalendar

  describe "timezone/0" do
    test "is Pacific" do
      assert AddToCalendar.timezone() == "America/Los_Angeles"
    end
  end

  describe "date/1" do
    test "formats Date, DateTime, and NaiveDateTime as ISO calendar days" do
      assert AddToCalendar.date(~D[2026-10-16]) == "2026-10-16"

      assert AddToCalendar.date(~U[2026-10-16 00:00:00Z]) == "2026-10-16"

      assert AddToCalendar.date(~N[2026-10-16 18:30:00]) == "2026-10-16"
    end

    test "returns nil for missing or unknown values" do
      assert AddToCalendar.date(nil) == nil
      assert AddToCalendar.date("2026-10-16") == nil
    end
  end

  describe "end_time/1" do
    test "returns the explicit end time" do
      event = %{start_time: ~T[19:00:00], end_time: ~T[22:30:00]}
      assert AddToCalendar.end_time(event) == ~T[22:30:00]
    end

    test "defaults to three hours after start when end_time is missing" do
      event = %{start_time: ~T[19:00:00], end_time: nil}
      assert AddToCalendar.end_time(event) == ~T[22:00:00]
    end

    test "wraps the default duration past midnight" do
      event = %{start_time: ~T[22:30:00], end_time: nil}
      assert AddToCalendar.end_time(event) == ~T[01:30:00]
    end

    test "returns nil when there is no start or end time" do
      assert AddToCalendar.end_time(%{start_time: nil, end_time: nil}) == nil
    end
  end

  describe "end_date/1" do
    test "returns the explicit end_date when end_time is set" do
      event = %{
        start_date: ~U[2026-10-16 00:00:00Z],
        start_time: ~T[19:00:00],
        end_date: ~U[2026-10-17 00:00:00Z],
        end_time: ~T[22:00:00]
      }

      assert AddToCalendar.end_date(event) == ~U[2026-10-17 00:00:00Z]
    end

    test "returns start_date for a same-day default duration" do
      start_date = ~U[2026-10-16 00:00:00Z]

      event = %{
        start_date: start_date,
        start_time: ~T[19:00:00],
        end_date: nil,
        end_time: nil
      }

      assert AddToCalendar.end_date(event) == start_date
    end

    test "rolls to the next calendar day when the default duration wraps midnight" do
      event = %{
        start_date: ~U[2026-10-16 00:00:00Z],
        start_time: ~T[22:30:00],
        end_date: nil,
        end_time: nil
      }

      assert AddToCalendar.end_date(event) == ~D[2026-10-17]
    end

    test "rolls overnight from a %Date{} start_date" do
      event = %{
        start_date: ~D[2026-10-16],
        start_time: ~T[23:00:00],
        end_date: nil,
        end_time: nil
      }

      assert AddToCalendar.end_date(event) == ~D[2026-10-17]
    end

    test "ignores a leftover end_date when inferring the default duration" do
      event = %{
        start_date: ~U[2026-10-16 00:00:00Z],
        start_time: ~T[19:00:00],
        end_date: ~U[2026-10-20 00:00:00Z],
        end_time: nil
      }

      assert AddToCalendar.end_date(event) == ~U[2026-10-16 00:00:00Z]
    end

    test "returns end_date when there is no start_time" do
      end_date = ~U[2026-10-18 00:00:00Z]

      event = %{
        start_date: ~U[2026-10-16 00:00:00Z],
        start_time: nil,
        end_date: end_date,
        end_time: nil
      }

      assert AddToCalendar.end_date(event) == end_date
    end
  end
end
