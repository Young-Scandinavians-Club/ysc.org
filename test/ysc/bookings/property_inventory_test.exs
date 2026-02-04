defmodule Ysc.Bookings.PropertyInventoryTest do
  @moduledoc """
  Tests for Ysc.Bookings.PropertyInventory.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Bookings.PropertyInventory

  describe "changeset/2" do
    test "validates required fields" do
      changeset = PropertyInventory.changeset(%PropertyInventory{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).property
      assert "can't be blank" in errors_on(changeset).day
    end

    test "validates capacity numbers" do
      attrs = %{
        property: :tahoe,
        day: Date.utc_today(),
        capacity_total: -1,
        capacity_held: 0,
        capacity_booked: 0
      }

      changeset = PropertyInventory.changeset(%PropertyInventory{}, attrs)
      refute changeset.valid?

      assert "must be greater than or equal to 0" in errors_on(changeset).capacity_total
    end

    test "validates valid attributes" do
      attrs = %{
        property: :tahoe,
        day: Date.utc_today(),
        capacity_total: 10,
        capacity_held: 5,
        capacity_booked: 0,
        buyout_held: false,
        buyout_booked: false
      }

      changeset = PropertyInventory.changeset(%PropertyInventory{}, attrs)
      assert changeset.valid?
    end
  end
end
