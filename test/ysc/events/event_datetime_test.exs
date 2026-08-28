defmodule Ysc.Events.EventDateTimeTest do
  use ExUnit.Case, async: true

  alias Ysc.Events.Event
  alias Ysc.Events.EventDateTime

  describe "combine/2" do
    test "combines Date and Pacific Time into a UTC DateTime" do
      # 10:00 Pacific on 2024-12-01 is PST (UTC-8) -> 18:00 UTC.
      assert EventDateTime.combine(~D[2024-12-01], ~T[10:00:00]) ==
               ~U[2024-12-01 18:00:00Z]
    end

    test "combines DateTime and Time using the date portion" do
      date = ~U[2024-12-01 15:30:00Z]

      assert EventDateTime.combine(date, ~T[10:00:00]) ==
               ~U[2024-12-01 18:00:00Z]
    end

    test "uses the Pacific offset in effect for the date (PDT vs PST)" do
      # 10:00 Pacific on 2024-07-01 is PDT (UTC-7) -> 17:00 UTC.
      assert EventDateTime.combine(~D[2024-07-01], ~T[10:00:00]) ==
               ~U[2024-07-01 17:00:00Z]
    end

    test "returns nil when either argument is nil" do
      assert EventDateTime.combine(nil, ~T[10:00:00]) == nil
      assert EventDateTime.combine(~D[2024-12-01], nil) == nil
    end
  end

  describe "start_datetime/1" do
    test "returns combined start datetime for an event" do
      event = %Event{
        start_date: ~U[2024-12-01 00:00:00Z],
        start_time: ~T[18:00:00]
      }

      # 18:00 Pacific (PST, UTC-8) on 2024-12-01 -> 02:00 UTC the next day.
      assert EventDateTime.start_datetime(event) == ~U[2024-12-02 02:00:00Z]
    end

    test "returns nil when start date or time is missing" do
      assert EventDateTime.start_datetime(%Event{
               start_date: nil,
               start_time: ~T[18:00:00]
             }) ==
               nil

      assert EventDateTime.start_datetime(%Event{
               start_date: ~U[2024-12-01 00:00:00Z],
               start_time: nil
             }) == nil
    end
  end

  describe "in_future?/1" do
    test "returns true when event start is in the future" do
      event = %Event{
        start_date: DateTime.add(DateTime.utc_now(), 7, :day),
        start_time: ~T[18:00:00]
      }

      assert EventDateTime.in_future?(event)
    end

    test "returns false when event start is in the past or unknown" do
      past_event = %Event{
        start_date: DateTime.add(DateTime.utc_now(), -7, :day),
        start_time: ~T[18:00:00]
      }

      assert EventDateTime.in_future?(past_event) == false

      assert EventDateTime.in_future?(%Event{start_date: nil, start_time: nil}) ==
               false
    end
  end

  describe "in_past?/1" do
    test "returns true when event start date is in the past without a time" do
      event = %Event{
        start_date: DateTime.add(DateTime.utc_now(), -1, :day),
        start_time: nil
      }

      assert EventDateTime.in_past?(event)
    end

    test "returns true when combined start datetime is in the past" do
      event = %Event{
        start_date: DateTime.add(DateTime.utc_now(), -7, :day),
        start_time: ~T[18:00:00]
      }

      assert EventDateTime.in_past?(event)
    end

    test "returns false when event has no start date or is in the future" do
      future_event = %Event{
        start_date: DateTime.add(DateTime.utc_now(), 7, :day),
        start_time: ~T[18:00:00]
      }

      assert EventDateTime.in_past?(%Event{start_date: nil}) == false
      assert EventDateTime.in_past?(future_event) == false
    end
  end

  describe "format_pass_datetime/2" do
    test "returns TBD when start date is nil" do
      assert EventDateTime.format_pass_datetime(nil, ~T[15:30:00]) == "TBD"
    end

    test "formats date without time" do
      assert EventDateTime.format_pass_datetime(~D[2024-03-15], nil) ==
               "Fri, Mar 15, 2024"
    end

    test "formats DateTime start date without time" do
      assert EventDateTime.format_pass_datetime(~U[2024-03-15 12:00:00Z], nil) ==
               "Fri, Mar 15, 2024"
    end

    test "formats date with time" do
      assert EventDateTime.format_pass_datetime(~D[2024-03-15], ~T[15:30:00]) ==
               "Fri, Mar 15, 2024 at 3:30 PM"
    end
  end
end
