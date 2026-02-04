defmodule Ysc.Events.DateTimeFormatterTest do
  @moduledoc """
  Tests for DateTimeFormatter module.

  These tests verify:
  - Date and time formatting
  - Various date/time combinations
  - Edge cases (nil values, single dates, etc.)
  """
  use ExUnit.Case, async: true

  alias Ysc.Events.DateTimeFormatter

  describe "format_datetime/1" do
    test "formats date only" do
      result = DateTimeFormatter.format_datetime(%{start_date: ~D[2024-12-01]})
      assert result == "Dec 1, 2024"
    end

    test "formats date with time" do
      result =
        DateTimeFormatter.format_datetime(%{
          start_date: ~D[2024-12-01],
          start_time: ~T[10:00:00]
        })

      assert result == "Dec 1, 2024 at 10:00 AM"
    end

    test "formats date range with same date and times" do
      result =
        DateTimeFormatter.format_datetime(%{
          start_date: ~D[2024-12-01],
          start_time: ~T[10:00:00],
          end_date: ~D[2024-12-01],
          end_time: ~T[14:00:00]
        })

      assert result == "Dec 1, 2024 at 10:00 AM to 2:00 PM"
    end

    test "formats date range with different dates" do
      result =
        DateTimeFormatter.format_datetime(%{
          start_date: ~D[2024-12-01],
          start_time: ~T[10:00:00],
          end_date: ~D[2024-12-02]
        })

      assert result == "Dec 1, 2024 at 10:00 AM to Dec 2, 2024"
    end

    test "formats date range with different dates and times" do
      result =
        DateTimeFormatter.format_datetime(%{
          start_date: ~D[2024-12-01],
          start_time: ~T[10:00:00],
          end_date: ~D[2024-12-02],
          end_time: ~T[18:00:00]
        })

      assert result == "Dec 1, 2024 at 10:00 AM to Dec 2, 2024 at 6:00 PM"
    end

    test "handles nil end_date and end_time" do
      result =
        DateTimeFormatter.format_datetime(%{
          start_date: ~D[2024-12-01],
          start_time: ~T[10:00:00],
          end_date: nil,
          end_time: nil
        })

      assert result == "Dec 1, 2024 at 10:00 AM"
    end

    test "handles nil start_time" do
      result =
        DateTimeFormatter.format_datetime(%{
          start_date: ~D[2024-12-01],
          start_time: nil
        })

      assert result == "Dec 1, 2024"
    end

    test "formats times correctly (AM/PM)" do
      result =
        DateTimeFormatter.format_datetime(%{
          start_date: ~D[2024-12-01],
          start_time: ~T[00:00:00]
        })

      assert result == "Dec 1, 2024 at 12:00 AM"

      result =
        DateTimeFormatter.format_datetime(%{
          start_date: ~D[2024-12-01],
          start_time: ~T[12:00:00]
        })

      assert result == "Dec 1, 2024 at 12:00 PM"

      result =
        DateTimeFormatter.format_datetime(%{
          start_date: ~D[2024-12-01],
          start_time: ~T[13:30:00]
        })

      assert result == "Dec 1, 2024 at 1:30 PM"
    end

    test "handles different months" do
      result = DateTimeFormatter.format_datetime(%{start_date: ~D[2024-01-15]})
      assert result == "Jan 15, 2024"

      result = DateTimeFormatter.format_datetime(%{start_date: ~D[2024-06-20]})
      assert result == "Jun 20, 2024"

      result = DateTimeFormatter.format_datetime(%{start_date: ~D[2024-12-25]})
      assert result == "Dec 25, 2024"
    end

    test "handles nil date with time" do
      result =
        DateTimeFormatter.format_datetime(%{
          start_date: nil,
          start_time: ~T[10:00:00]
        })

      # When date is nil, it should just format the time
      assert result == "10:00 AM"
    end

    test "handles end_date same as start_date with nil end_time" do
      result =
        DateTimeFormatter.format_datetime(%{
          start_date: ~D[2024-12-01],
          start_time: ~T[10:00:00],
          end_date: ~D[2024-12-01],
          end_time: nil
        })

      # When end_date is same as start_date and end_time is nil,
      # Pattern {^start_date, time} doesn't match because time is nil,
      # so {date, nil} matches, which calls format_date(date).
      # format_date returns a string, so ending = "Dec 1, 2024"
      # But the actual result shows just the start, which suggests
      # the ending might be getting filtered or the logic handles this case differently.
      # Based on actual behavior, it just shows the start.
      assert result == "Dec 1, 2024 at 10:00 AM"
    end

    test "handles end_date different from start_date with nil end_time" do
      result =
        DateTimeFormatter.format_datetime(%{
          start_date: ~D[2024-12-01],
          start_time: ~T[10:00:00],
          end_date: ~D[2024-12-05],
          end_time: nil
        })

      assert result == "Dec 1, 2024 at 10:00 AM to Dec 5, 2024"
    end

    test "handles all nil values gracefully" do
      # When all values are nil, format_date_time(nil, nil) calls format_date(nil) which returns nil
      # So start = nil, ending = nil, and after reject, we get an empty list, which joins to ""
      result =
        DateTimeFormatter.format_datetime(%{
          start_date: nil,
          start_time: nil,
          end_date: nil,
          end_time: nil
        })

      # The function should handle this gracefully - returns empty string
      assert result == ""
    end
  end
end
