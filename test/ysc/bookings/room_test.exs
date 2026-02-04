defmodule Ysc.Bookings.RoomTest do
  @moduledoc """
  Tests for Room schema.

  These tests verify:
  - Required field validation (name, property, capacity_max)
  - Property enum validation
  - Capacity constraints (1-12 guests)
  - Minimum billable occupancy
  - Single bed flag and bed counts
  - Active/inactive status
  - String length validations
  - Database operations and associations
  - billable_people/2 function
  """
  use Ysc.DataCase, async: true

  alias Ysc.Bookings.Room
  alias Ysc.Repo

  describe "changeset/2" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        name: "Tahoe Room 1",
        property: :tahoe,
        capacity_max: 4
      }

      changeset = Room.changeset(%Room{}, attrs)

      assert changeset.valid?
      assert changeset.changes.name == "Tahoe Room 1"
      assert changeset.changes.property == :tahoe
      assert changeset.changes.capacity_max == 4
    end

    test "requires name" do
      attrs = %{
        property: :tahoe,
        capacity_max: 4
      }

      changeset = Room.changeset(%Room{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:name] != nil
    end

    test "requires property" do
      attrs = %{
        name: "Test Room",
        capacity_max: 4
      }

      changeset = Room.changeset(%Room{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:property] != nil
    end

    test "requires capacity_max" do
      attrs = %{
        name: "Test Room",
        property: :tahoe
      }

      changeset = Room.changeset(%Room{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:capacity_max] != nil
    end

    test "validates name maximum length (255 characters)" do
      long_name = String.duplicate("a", 256)

      attrs = %{
        name: long_name,
        property: :tahoe,
        capacity_max: 4
      }

      changeset = Room.changeset(%Room{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:name] != nil
    end

    test "accepts name with exactly 255 characters" do
      valid_name = String.duplicate("a", 255)

      attrs = %{
        name: valid_name,
        property: :tahoe,
        capacity_max: 4
      }

      changeset = Room.changeset(%Room{}, attrs)

      assert changeset.valid?
    end

    test "validates description maximum length (1000 characters)" do
      long_description = String.duplicate("a", 1001)

      attrs = %{
        name: "Test Room",
        description: long_description,
        property: :tahoe,
        capacity_max: 4
      }

      changeset = Room.changeset(%Room{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:description] != nil
    end

    test "accepts description with exactly 1000 characters" do
      valid_description = String.duplicate("a", 1000)

      attrs = %{
        name: "Test Room",
        description: valid_description,
        property: :tahoe,
        capacity_max: 4
      }

      changeset = Room.changeset(%Room{}, attrs)

      assert changeset.valid?
    end
  end

  describe "property enum" do
    test "accepts tahoe property" do
      attrs = %{
        name: "Tahoe Room",
        property: :tahoe,
        capacity_max: 4
      }

      changeset = Room.changeset(%Room{}, attrs)

      assert changeset.valid?
      assert changeset.changes.property == :tahoe
    end

    test "accepts clear_lake property" do
      attrs = %{
        name: "Clear Lake Room",
        property: :clear_lake,
        capacity_max: 4
      }

      changeset = Room.changeset(%Room{}, attrs)

      assert changeset.valid?
      assert changeset.changes.property == :clear_lake
    end

    test "rejects invalid property" do
      attrs = %{
        name: "Invalid Room",
        property: :invalid_property,
        capacity_max: 4
      }

      changeset = Room.changeset(%Room{}, attrs)

      refute changeset.valid?
    end
  end

  describe "capacity_max validation" do
    test "accepts capacity_max of 1" do
      attrs = %{
        name: "Single Room",
        property: :tahoe,
        capacity_max: 1
      }

      changeset = Room.changeset(%Room{}, attrs)

      assert changeset.valid?
    end

    test "accepts capacity_max of 12" do
      attrs = %{
        name: "Large Room",
        property: :tahoe,
        capacity_max: 12
      }

      changeset = Room.changeset(%Room{}, attrs)

      assert changeset.valid?
    end

    test "rejects capacity_max of 0" do
      attrs = %{
        name: "Invalid Room",
        property: :tahoe,
        capacity_max: 0
      }

      changeset = Room.changeset(%Room{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:capacity_max] != nil
    end

    test "rejects capacity_max greater than 12" do
      attrs = %{
        name: "Too Large Room",
        property: :tahoe,
        capacity_max: 13
      }

      changeset = Room.changeset(%Room{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:capacity_max] != nil
    end
  end

  describe "min_billable_occupancy validation" do
    test "defaults to 1 when not provided" do
      attrs = %{
        name: "Test Room",
        property: :tahoe,
        capacity_max: 4
      }

      changeset = Room.changeset(%Room{}, attrs)
      {:ok, room} = Repo.insert(changeset)

      assert room.min_billable_occupancy == 1
    end

    test "accepts custom min_billable_occupancy" do
      attrs = %{
        name: "Family Room",
        property: :tahoe,
        capacity_max: 4,
        min_billable_occupancy: 2
      }

      changeset = Room.changeset(%Room{}, attrs)
      {:ok, room} = Repo.insert(changeset)

      assert room.min_billable_occupancy == 2
    end

    test "rejects min_billable_occupancy less than 1" do
      attrs = %{
        name: "Invalid Room",
        property: :tahoe,
        capacity_max: 4,
        min_billable_occupancy: 0
      }

      changeset = Room.changeset(%Room{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:min_billable_occupancy] != nil
    end
  end

  describe "single bed flag" do
    test "defaults is_single_bed to false" do
      attrs = %{
        name: "Standard Room",
        property: :tahoe,
        capacity_max: 2
      }

      changeset = Room.changeset(%Room{}, attrs)
      {:ok, room} = Repo.insert(changeset)

      assert room.is_single_bed == false
    end

    test "accepts is_single_bed as true" do
      attrs = %{
        name: "Single Bed Room",
        property: :tahoe,
        capacity_max: 1,
        is_single_bed: true
      }

      changeset = Room.changeset(%Room{}, attrs)
      {:ok, room} = Repo.insert(changeset)

      assert room.is_single_bed == true
    end
  end

  describe "active status" do
    test "defaults is_active to true" do
      attrs = %{
        name: "Active Room",
        property: :tahoe,
        capacity_max: 2
      }

      changeset = Room.changeset(%Room{}, attrs)
      {:ok, room} = Repo.insert(changeset)

      assert room.is_active == true
    end

    test "accepts is_active as false" do
      attrs = %{
        name: "Inactive Room",
        property: :tahoe,
        capacity_max: 2,
        is_active: false
      }

      changeset = Room.changeset(%Room{}, attrs)
      {:ok, room} = Repo.insert(changeset)

      assert room.is_active == false
    end
  end

  describe "bed counts" do
    test "defaults all bed counts to 0" do
      attrs = %{
        name: "Test Room",
        property: :tahoe,
        capacity_max: 2
      }

      changeset = Room.changeset(%Room{}, attrs)
      {:ok, room} = Repo.insert(changeset)

      assert room.single_beds == 0
      assert room.queen_beds == 0
      assert room.king_beds == 0
    end

    test "accepts custom bed counts" do
      attrs = %{
        name: "Multi-Bed Room",
        property: :tahoe,
        capacity_max: 6,
        single_beds: 2,
        queen_beds: 1,
        king_beds: 1
      }

      changeset = Room.changeset(%Room{}, attrs)
      {:ok, room} = Repo.insert(changeset)

      assert room.single_beds == 2
      assert room.queen_beds == 1
      assert room.king_beds == 1
    end

    test "rejects negative single_beds count" do
      attrs = %{
        name: "Invalid Room",
        property: :tahoe,
        capacity_max: 2,
        single_beds: -1
      }

      changeset = Room.changeset(%Room{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:single_beds] != nil
    end

    test "rejects negative queen_beds count" do
      attrs = %{
        name: "Invalid Room",
        property: :tahoe,
        capacity_max: 2,
        queen_beds: -1
      }

      changeset = Room.changeset(%Room{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:queen_beds] != nil
    end

    test "rejects negative king_beds count" do
      attrs = %{
        name: "Invalid Room",
        property: :tahoe,
        capacity_max: 2,
        king_beds: -1
      }

      changeset = Room.changeset(%Room{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:king_beds] != nil
    end
  end

  describe "database operations" do
    test "can insert and retrieve complete room" do
      attrs = %{
        name: "Premium Suite",
        description: "Luxury room with mountain views",
        property: :tahoe,
        capacity_max: 4,
        min_billable_occupancy: 2,
        is_single_bed: false,
        is_active: true,
        single_beds: 0,
        queen_beds: 1,
        king_beds: 1
      }

      changeset = Room.changeset(%Room{}, attrs)
      {:ok, room} = Repo.insert(changeset)

      retrieved = Repo.get(Room, room.id)

      assert retrieved.name == "Premium Suite"
      assert retrieved.description == "Luxury room with mountain views"
      assert retrieved.property == :tahoe
      assert retrieved.capacity_max == 4
      assert retrieved.min_billable_occupancy == 2
      assert retrieved.is_single_bed == false
      assert retrieved.is_active == true
      assert retrieved.single_beds == 0
      assert retrieved.queen_beds == 1
      assert retrieved.king_beds == 1
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end
  end

  describe "billable_people/2" do
    test "returns guest count when above min_billable_occupancy" do
      room = %Room{min_billable_occupancy: 2, capacity_max: 5}

      assert Room.billable_people(room, 3) == 3
    end

    test "returns min_billable_occupancy when guest count below minimum" do
      room = %Room{min_billable_occupancy: 2, capacity_max: 5}

      assert Room.billable_people(room, 1) == 2
    end

    test "returns guest count when equal to min_billable_occupancy" do
      room = %Room{min_billable_occupancy: 2, capacity_max: 5}

      assert Room.billable_people(room, 2) == 2
    end

    test "handles single occupancy minimum (default)" do
      room = %Room{min_billable_occupancy: 1, capacity_max: 2}

      assert Room.billable_people(room, 1) == 1
    end

    test "returns nil for invalid inputs" do
      room = %Room{min_billable_occupancy: 2, capacity_max: 5}

      assert Room.billable_people(room, "invalid") == nil
      assert Room.billable_people(%{}, 3) == nil
    end
  end

  describe "typical room scenarios" do
    test "standard 2-person room" do
      attrs = %{
        name: "Standard Double",
        description: "Standard room with one queen bed",
        property: :tahoe,
        capacity_max: 2,
        min_billable_occupancy: 1,
        queen_beds: 1
      }

      changeset = Room.changeset(%Room{}, attrs)
      {:ok, room} = Repo.insert(changeset)

      assert room.capacity_max == 2
      assert Room.billable_people(room, 1) == 1
      assert Room.billable_people(room, 2) == 2
    end

    test "family room with minimum 2 occupancy" do
      attrs = %{
        name: "Family Suite",
        description: "Large room for families",
        property: :tahoe,
        capacity_max: 5,
        min_billable_occupancy: 2,
        queen_beds: 2
      }

      changeset = Room.changeset(%Room{}, attrs)
      {:ok, room} = Repo.insert(changeset)

      # Billing reflects minimum occupancy even if only 1 guest
      assert Room.billable_people(room, 1) == 2
      assert Room.billable_people(room, 3) == 3
    end

    test "single occupancy room" do
      attrs = %{
        name: "Single Room",
        description: "Room with single bed",
        property: :tahoe,
        capacity_max: 1,
        is_single_bed: true,
        single_beds: 1
      }

      changeset = Room.changeset(%Room{}, attrs)
      {:ok, room} = Repo.insert(changeset)

      assert room.is_single_bed == true
      assert room.capacity_max == 1
    end

    test "inactive room (under renovation)" do
      attrs = %{
        name: "Renovation Room",
        property: :tahoe,
        capacity_max: 2,
        is_active: false
      }

      changeset = Room.changeset(%Room{}, attrs)
      {:ok, room} = Repo.insert(changeset)

      assert room.is_active == false
    end
  end
end
