defmodule Ysc.History.TimelineTest do
  use ExUnit.Case, async: true

  alias Ysc.History.Timeline

  describe "years_since_founding/0" do
    test "rounds down to the nearest five-year anniversary" do
      year = Date.utc_today().year
      years_elapsed = year - 1950
      expected = div(years_elapsed, 5) * 5

      assert Timeline.years_since_founding() == expected
    end
  end

  describe "events/0" do
    test "returns a non-empty timeline with expected entry types" do
      events = Timeline.events()

      assert [_ | _] = events
      assert Enum.any?(events, &(&1.type == :decade))
      assert Enum.any?(events, &(&1.type == :featured))
      assert Enum.any?(events, &(&1.type == :milestone))

      founding =
        Enum.find(events, fn event ->
          event.type == :featured and event.year == "1950"
        end)

      assert founding.title =~ "Beginning"
      assert founding.tags == ["founding", "club leadership"]
    end
  end
end
