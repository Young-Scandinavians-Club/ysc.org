defmodule Ysc.Bookings.TooltipSeasonQueriesTest do
  use Ysc.DataCase, async: false

  alias Ysc.Bookings.{Season, SeasonCache, SeasonHelpers}
  alias Ysc.Repo

  setup do
    SeasonCache.invalidate()
    Cachex.clear(:ysc_cache)
    :ok
  end

  test "date_selectable? with preloaded seasons does not query seasons table" do
    {:ok, _} =
      %Season{}
      |> Season.changeset(%{
        name: "Tooltip Season",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-10-31],
        advance_booking_days: 45
      })
      |> Repo.insert()

    seasons = SeasonCache.get_all_for_property(:tahoe)
    today = ~D[2025-06-01]
    dates = Date.range(today, Date.add(today, 60)) |> Enum.to_list()

    {_results, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          Enum.each(dates, fn date ->
            assert SeasonHelpers.date_selectable?(:tahoe, date, today, seasons) in [
                     true,
                     false
                   ]
          end)
        end,
        pattern: ~r/FROM "seasons"/i
      )

    assert query_count == 0
  end
end
