defmodule Ysc.Bookings.BlackoutListCacheTest do
  use Ysc.DataCase, async: false

  @moduletag process_caches: true

  alias Ysc.Bookings.{Blackout, BlackoutListCache}
  alias Ysc.Repo

  setup do
    BlackoutListCache.invalidate()
    Cachex.clear(:ysc_cache)
    :ok
  end

  test "list/3 caches overlapping blackouts" do
    start_date = ~D[2026-06-01]
    end_date = ~D[2026-06-30]

    {:ok, blackout} =
      %Blackout{}
      |> Blackout.changeset(%{
        property: :tahoe,
        start_date: ~D[2026-06-10],
        end_date: ~D[2026-06-12],
        reason: "Maintenance"
      })
      |> Repo.insert()

    first = BlackoutListCache.list(:tahoe, start_date, end_date)
    second = BlackoutListCache.list(:tahoe, start_date, end_date)

    assert Enum.any?(first, &(&1.id == blackout.id))
    assert Enum.map(first, & &1.id) == Enum.map(second, & &1.id)
  end

  test "invalidate refetches after blackout create" do
    start_date = ~D[2026-07-01]
    end_date = ~D[2026-07-31]

    BlackoutListCache.list(:clear_lake, start_date, end_date)

    {:ok, _} =
      Ysc.Bookings.create_blackout(%{
        property: :clear_lake,
        start_date: ~D[2026-07-15],
        end_date: ~D[2026-07-16],
        reason: "Closed"
      })

    blackouts = BlackoutListCache.list(:clear_lake, start_date, end_date)
    assert blackouts != []
  end
end
