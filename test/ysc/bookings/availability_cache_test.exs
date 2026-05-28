defmodule Ysc.Bookings.AvailabilityCacheTest do
  use Ysc.DataCase, async: false

  @moduletag process_caches: true

  alias Ysc.Bookings.AvailabilityCache

  setup do
    AvailabilityCache.invalidate()
    :ok
  end

  test "subscribe receives invalidation broadcast" do
    AvailabilityCache.subscribe()
    AvailabilityCache.invalidate()

    assert_receive :availability_cache_invalidated
  end

  test "returns availability map for date range" do
    start_date = Date.utc_today()
    end_date = Date.add(start_date, 7)

    result1 =
      AvailabilityCache.get_clear_lake_daily_availability(start_date, end_date)

    result2 =
      AvailabilityCache.get_clear_lake_daily_availability(start_date, end_date)

    assert is_map(result1)
    assert Map.keys(result1) == Map.keys(result2)
  end

  test "invalidate clears cached month payload" do
    start_date = Date.utc_today()
    end_date = Date.add(start_date, 3)

    AvailabilityCache.get_clear_lake_daily_availability(start_date, end_date)
    AvailabilityCache.invalidate()

    {_result, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          AvailabilityCache.get_clear_lake_daily_availability(
            start_date,
            end_date
          )
        end,
        pattern: ~r/FROM "bookings"/i
      )

    assert query_count >= 1
  end
end
