defmodule Ysc.Bookings.BookingRoomTest do
  @moduledoc """
  Tests for BookingRoom join table.

  These tests verify:
  - Many-to-many association between Bookings and Rooms
  - Foreign key constraints
  - Database operations
  - Join table behavior

  Note: BookingRoom is a simple join table with no changeset validations.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Bookings.{BookingRoom, Booking, Room}
  alias Ysc.Repo

  # Helper to create a booking for testing
  defp create_booking do
    user = user_fixture()

    attrs = %{
      user_id: user.id,
      checkin_date: ~D[2024-08-05],
      checkout_date: ~D[2024-08-07],
      property: :tahoe,
      booking_mode: :room
    }

    {:ok, booking} =
      %Booking{}
      |> Booking.changeset(attrs, skip_validation: true)
      |> Repo.insert()

    booking
  end

  # Helper to create a room for testing
  defp create_room(attrs \\ %{}) do
    default_attrs = %{
      name: "Test Room #{System.unique_integer()}",
      property: :tahoe,
      capacity_max: 2
    }

    attrs = Map.merge(default_attrs, attrs)

    {:ok, room} =
      %Room{}
      |> Room.changeset(attrs)
      |> Repo.insert()

    room
  end

  describe "join table operations" do
    test "can create a booking_room association" do
      booking = create_booking()
      room = create_room()

      {:ok, booking_room} =
        %BookingRoom{
          booking_id: booking.id,
          room_id: room.id
        }
        |> Repo.insert()

      assert booking_room.booking_id == booking.id
      assert booking_room.room_id == room.id
      assert booking_room.inserted_at != nil
      assert booking_room.updated_at != nil
    end

    test "can retrieve booking_room by id" do
      booking = create_booking()
      room = create_room()

      {:ok, booking_room} =
        %BookingRoom{
          booking_id: booking.id,
          room_id: room.id
        }
        |> Repo.insert()

      retrieved = Repo.get(BookingRoom, booking_room.id)

      assert retrieved.booking_id == booking.id
      assert retrieved.room_id == room.id
    end

    test "can preload booking from booking_room" do
      booking = create_booking()
      room = create_room()

      {:ok, booking_room} =
        %BookingRoom{
          booking_id: booking.id,
          room_id: room.id
        }
        |> Repo.insert()

      booking_room_with_booking = Repo.preload(booking_room, :booking)

      assert booking_room_with_booking.booking.id == booking.id
    end

    test "can preload room from booking_room" do
      booking = create_booking()
      room = create_room()

      {:ok, booking_room} =
        %BookingRoom{
          booking_id: booking.id,
          room_id: room.id
        }
        |> Repo.insert()

      booking_room_with_room = Repo.preload(booking_room, :room)

      assert booking_room_with_room.room.id == room.id
    end

    test "can associate multiple rooms with one booking" do
      booking = create_booking()
      room1 = create_room(%{name: "Room 1"})
      room2 = create_room(%{name: "Room 2"})
      room3 = create_room(%{name: "Room 3"})

      {:ok, _} =
        %BookingRoom{booking_id: booking.id, room_id: room1.id}
        |> Repo.insert()

      {:ok, _} =
        %BookingRoom{booking_id: booking.id, room_id: room2.id}
        |> Repo.insert()

      {:ok, _} =
        %BookingRoom{booking_id: booking.id, room_id: room3.id}
        |> Repo.insert()

      # Query all booking_rooms for this booking
      booking_rooms =
        BookingRoom
        |> Ecto.Query.where(booking_id: ^booking.id)
        |> Repo.all()

      assert length(booking_rooms) == 3
    end

    test "can associate multiple bookings with one room" do
      room = create_room()
      booking1 = create_booking()
      booking2 = create_booking()
      booking3 = create_booking()

      {:ok, _} =
        %BookingRoom{booking_id: booking1.id, room_id: room.id}
        |> Repo.insert()

      {:ok, _} =
        %BookingRoom{booking_id: booking2.id, room_id: room.id}
        |> Repo.insert()

      {:ok, _} =
        %BookingRoom{booking_id: booking3.id, room_id: room.id}
        |> Repo.insert()

      # Query all booking_rooms for this room
      booking_rooms =
        BookingRoom
        |> Ecto.Query.where(room_id: ^room.id)
        |> Repo.all()

      assert length(booking_rooms) == 3
    end
  end

  describe "foreign key constraints" do
    test "enforces foreign key constraint on booking_id" do
      room = create_room()
      invalid_booking_id = Ecto.ULID.generate()

      assert_raise Ecto.ConstraintError, fn ->
        %BookingRoom{
          booking_id: invalid_booking_id,
          room_id: room.id
        }
        |> Repo.insert!()
      end
    end

    test "enforces foreign key constraint on room_id" do
      booking = create_booking()
      invalid_room_id = Ecto.ULID.generate()

      assert_raise Ecto.ConstraintError, fn ->
        %BookingRoom{
          booking_id: booking.id,
          room_id: invalid_room_id
        }
        |> Repo.insert!()
      end
    end
  end

  describe "cascading deletes" do
    test "deleting booking deletes associated booking_rooms" do
      booking = create_booking()
      room1 = create_room(%{name: "Room 1"})
      room2 = create_room(%{name: "Room 2"})

      {:ok, br1} =
        %BookingRoom{booking_id: booking.id, room_id: room1.id}
        |> Repo.insert()

      {:ok, br2} =
        %BookingRoom{booking_id: booking.id, room_id: room2.id}
        |> Repo.insert()

      # Delete the booking
      Repo.delete(booking)

      # Verify booking_rooms are deleted
      assert Repo.get(BookingRoom, br1.id) == nil
      assert Repo.get(BookingRoom, br2.id) == nil

      # Verify rooms still exist
      assert Repo.get(Room, room1.id) != nil
      assert Repo.get(Room, room2.id) != nil
    end

    test "room deletion is prevented when booking_rooms exist (RESTRICT constraint)" do
      room = create_room()
      booking = create_booking()

      {:ok, _booking_room} =
        %BookingRoom{booking_id: booking.id, room_id: room.id}
        |> Repo.insert()

      # Attempting to delete the room should fail due to RESTRICT constraint
      # Can raise either Postgrex.Error or Ecto.ConstraintError depending on Ecto's internal state
      error =
        try do
          Repo.delete!(room)

          flunk(
            "Expected either Postgrex.Error or Ecto.ConstraintError to be raised"
          )
        rescue
          e in [Postgrex.Error, Ecto.ConstraintError] -> e
        end

      assert error.__struct__ in [Postgrex.Error, Ecto.ConstraintError]

      # Verify room still exists
      assert Repo.get(Room, room.id) != nil
    end
  end

  describe "typical scenarios" do
    test "single room booking" do
      booking = create_booking()
      room = create_room(%{name: "Standard Room"})

      {:ok, _booking_room} =
        %BookingRoom{
          booking_id: booking.id,
          room_id: room.id
        }
        |> Repo.insert()

      # Verify association
      booking_with_rooms = Repo.preload(booking, :rooms)
      assert length(booking_with_rooms.rooms) == 1
      assert hd(booking_with_rooms.rooms).id == room.id
    end

    test "multi-room booking (family booking)" do
      booking = create_booking()
      room1 = create_room(%{name: "Parent Room", capacity_max: 2})
      room2 = create_room(%{name: "Kids Room", capacity_max: 4})

      {:ok, _} =
        %BookingRoom{booking_id: booking.id, room_id: room1.id}
        |> Repo.insert()

      {:ok, _} =
        %BookingRoom{booking_id: booking.id, room_id: room2.id}
        |> Repo.insert()

      # Verify both rooms are associated
      booking_with_rooms = Repo.preload(booking, :rooms)
      assert length(booking_with_rooms.rooms) == 2

      room_ids = Enum.map(booking_with_rooms.rooms, & &1.id)
      assert room1.id in room_ids
      assert room2.id in room_ids
    end

    test "same room booked for different dates" do
      room = create_room(%{name: "Popular Room"})

      # Different bookings for the same room
      booking1 = create_booking()
      booking2 = create_booking()

      {:ok, _} =
        %BookingRoom{booking_id: booking1.id, room_id: room.id}
        |> Repo.insert()

      {:ok, _} =
        %BookingRoom{booking_id: booking2.id, room_id: room.id}
        |> Repo.insert()

      # Verify room has multiple bookings
      room_with_bookings = Repo.preload(room, :bookings)
      assert length(room_with_bookings.bookings) == 2
    end
  end
end
