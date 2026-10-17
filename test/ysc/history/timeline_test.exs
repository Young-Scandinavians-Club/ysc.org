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
      refute Enum.any?(events, &(&1.type == :decade))
      assert Enum.any?(events, &(&1.type == :featured))
      assert Enum.any?(events, &(&1.type == :milestone))

      founding =
        Enum.find(events, fn event ->
          event.type == :featured and event.year == "1950"
        end)

      assert founding.title =~ "Beginning"
      assert founding.tags == ["founding", "club leadership"]
    end

    test "is in chronological order by first year" do
      years =
        Timeline.events()
        |> Enum.map(fn event ->
          {year, _} = Integer.parse(event.year)
          year
        end)

      assert years == Enum.sort(years)
    end
  end

  describe "decades/0" do
    test "groups every event under the decade its first year falls in" do
      decades = Timeline.decades()

      assert hd(decades).label == "1950s"
      assert hd(decades).id == "decade-1950s"

      assert Enum.sum(Enum.map(decades, &length(&1.events))) ==
               length(Timeline.events())

      for %{label: label, events: events} <- decades, event <- events do
        {year, _} = Integer.parse(event.year)
        assert "#{div(year, 10) * 10}s" == label
      end
    end

    test "places late-decade entries under the right decade" do
      by_label = Map.new(Timeline.decades(), &{&1.label, &1})

      years_in = fn label -> Enum.map(by_label[label].events, & &1.year) end

      assert "1974" in years_in.("1970s")
      refute "1974" in years_in.("1960s")
      assert "1980" in years_in.("1980s")
      assert "1985" in years_in.("1980s")
      assert "1988" in years_in.("1980s")
      refute "1985" in years_in.("1990s")
    end
  end
end
