defmodule Ysc.Bookings.RoomsListCacheTest do
  use Ysc.DataCase, async: false

  @moduletag process_caches: true

  alias Ysc.Bookings.{Room, RoomsListCache}
  alias Ysc.Repo

  setup do
    RoomsListCache.invalidate()
    Cachex.clear(:ysc_cache)
    :ok
  end

  defp insert_room!(attrs) do
    {:ok, room} =
      %Room{}
      |> Room.changeset(
        Map.merge(
          %{
            name: "Room #{System.unique_integer()}",
            property: :tahoe,
            capacity_min: 1,
            capacity_max: 2,
            is_active: true
          },
          attrs
        )
      )
      |> Repo.insert()

    room
  end

  test "list/1 caches rooms per property" do
    room = insert_room!(%{property: :tahoe, name: "Cached Room"})

    rooms1 = RoomsListCache.list(:tahoe)
    rooms2 = RoomsListCache.list(:tahoe)

    assert Enum.any?(rooms1, &(&1.id == room.id))
    assert Enum.map(rooms1, & &1.id) == Enum.map(rooms2, & &1.id)
  end

  test "invalidate refetches after room update via Bookings API" do
    room = insert_room!(%{property: :clear_lake, name: "Lake Room"})

    RoomsListCache.list(:clear_lake)

    {:ok, _} =
      Ysc.Bookings.update_room(room, %{name: "Renamed Lake Room"})

    rooms = RoomsListCache.list(:clear_lake)

    assert Enum.any?(
             rooms,
             &(&1.id == room.id and &1.name == "Renamed Lake Room")
           )
  end
end
