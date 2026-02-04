defmodule Ysc.Bookings.RoomInventoryTest do
  @moduledoc """
  Tests for Ysc.Bookings.RoomInventory.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Bookings.RoomInventory

  describe "changeset/2" do
    test "validates required fields" do
      changeset = RoomInventory.changeset(%RoomInventory{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).room_id
      assert "can't be blank" in errors_on(changeset).day
    end

    test "validates valid attributes" do
      attrs = %{
        room_id: Ecto.ULID.generate(),
        day: Date.utc_today(),
        held: true,
        booked: false
      }

      changeset = RoomInventory.changeset(%RoomInventory{}, attrs)
      assert changeset.valid?
    end
  end
end
