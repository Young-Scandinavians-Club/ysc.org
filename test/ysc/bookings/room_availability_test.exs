defmodule Ysc.Bookings.RoomAvailabilityTest do
  use Ysc.DataCase

  alias Ysc.Bookings
  alias Ysc.Bookings.{Room, BookingLocker}

  setup do
    # Create a user
    user =
      %Ysc.Accounts.User{}
      |> Ysc.Accounts.User.registration_changeset(%{
        email: "test@example.com",
        password: "password123password123",
        state: :active,
        first_name: "Test",
        last_name: "User",
        phone_number: "+14155552671"
      })
      |> Repo.insert!()

    # Create a room
    room =
      %Room{}
      |> Room.changeset(%{
        name: "Test Room",
        property: :tahoe,
        capacity_max: 2,
        is_active: true
      })
      |> Repo.insert!()

    {:ok, user: user, room: room}
  end

  test "room_available? returns false when property has buyout", %{
    user: user,
    room: room
  } do
    checkin = ~D[2025-06-01]
    checkout = ~D[2025-06-05]

    # Initially room should be available
    assert Bookings.room_available?(room.id, checkin, checkout)

    # Create a buyout booking
    {:ok, _booking} =
      BookingLocker.create_buyout_booking(
        user.id,
        :tahoe,
        checkin,
        checkout,
        10
      )

    # Now room should NOT be available
    refute Bookings.room_available?(room.id, checkin, checkout)

    # Check overlap dates too
    refute Bookings.room_available?(room.id, ~D[2025-06-02], ~D[2025-06-03])
  end

  test "room_available? returns true for dates outside buyout", %{
    user: user,
    room: room
  } do
    checkin = ~D[2025-06-01]
    checkout = ~D[2025-06-05]

    # Create a buyout booking
    {:ok, _booking} =
      BookingLocker.create_buyout_booking(
        user.id,
        :tahoe,
        checkin,
        checkout,
        10
      )

    # Dates after buyout should be available
    assert Bookings.room_available?(room.id, checkout, ~D[2025-06-07])
  end
end
