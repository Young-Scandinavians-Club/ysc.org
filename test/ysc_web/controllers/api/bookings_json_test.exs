defmodule YscWeb.Api.BookingsJSONTest do
  @moduledoc """
  Unit tests for `YscWeb.Api.BookingsJSON` rendering helpers.
  """
  use ExUnit.Case, async: true

  alias Ysc.Bookings.Booking
  alias Ysc.Bookings.BookingGuest
  alias Ysc.Bookings.CheckIn
  alias Ysc.Bookings.CheckInVehicle
  alias Ysc.Bookings.Room
  alias Ysc.Accounts.User
  alias YscWeb.Api.BookingsJSON

  describe "index/1" do
    test "maps bookings with nil member and falls back for non-list associations" do
      booking = %Booking{
        id: Ecto.ULID.generate(),
        reference_id: "BKG-JSON-1",
        property: :tahoe,
        status: :confirmed,
        checkin_date: ~D[2025-06-01],
        checkout_date: ~D[2025-06-05],
        guests_count: 2,
        children_count: 1,
        checked_in: nil,
        booking_mode: :member,
        user: nil,
        rooms: :not_a_list,
        booking_guests: :not_a_list,
        check_ins: []
      }

      assert %{data: [row]} = BookingsJSON.index(%{bookings: [booking]})

      assert row[:member] == nil
      assert row[:rooms] == []
      assert row[:guests] == []
      assert row[:check_ins] == []
      assert row[:checked_in] == false
    end

    test "includes member avatar and room details when associations are present" do
      user = %User{
        id: Ecto.ULID.generate(),
        email: "member@example.com",
        first_name: "Mo",
        last_name: "River",
        most_connected_country: "US"
      }

      room = %Room{
        id: Ecto.ULID.generate(),
        name: "Loft"
      }

      booking = %Booking{
        id: Ecto.ULID.generate(),
        reference_id: "BKG-JSON-2",
        property: :clear_lake,
        status: :confirmed,
        checkin_date: ~D[2025-07-01],
        checkout_date: ~D[2025-07-04],
        guests_count: 3,
        children_count: 0,
        checked_in: true,
        booking_mode: :member,
        user: user,
        rooms: [room],
        booking_guests: [],
        check_ins: []
      }

      assert %{data: [row]} = BookingsJSON.index(%{bookings: [booking]})

      assert row[:member][:first_name] == "Mo"
      refute Map.has_key?(row[:member], :email)
      assert row[:rooms] == [%{id: to_string(room.id), name: "Loft"}]
    end
  end

  describe "calendar/1" do
    test "groups bookings by date within the requested window" do
      id = Ecto.ULID.generate()

      booking = %Booking{
        id: id,
        reference_id: "BKG-CAL",
        property: :tahoe,
        status: :confirmed,
        checkin_date: ~D[2025-08-01],
        checkout_date: ~D[2025-08-05],
        guests_count: 1,
        children_count: 0,
        checked_in: false,
        booking_mode: :member,
        user: nil,
        rooms: [],
        booking_guests: [],
        check_ins: []
      }

      start_date = ~D[2025-08-02]
      end_date = ~D[2025-08-04]

      assert %{data: data, start_date: "2025-08-02", end_date: "2025-08-04"} =
               BookingsJSON.calendar(%{
                 bookings: [booking],
                 start_date: start_date,
                 end_date: end_date
               })

      assert map_size(data) == 3

      assert Enum.all?(
               ["2025-08-02", "2025-08-03", "2025-08-04"],
               &Map.has_key?(data, &1)
             )

      [row] = data["2025-08-03"]
      assert row[:id] == to_string(id)
    end

    test "excludes bookings that do not overlap the calendar range" do
      booking = %Booking{
        id: Ecto.ULID.generate(),
        reference_id: "BKG-OUT",
        property: :tahoe,
        status: :confirmed,
        checkin_date: ~D[2020-01-01],
        checkout_date: ~D[2020-01-02],
        guests_count: 1,
        children_count: 0,
        checked_in: false,
        booking_mode: :member,
        user: nil,
        rooms: [],
        booking_guests: [],
        check_ins: []
      }

      assert %{data: data} =
               BookingsJSON.calendar(%{
                 bookings: [booking],
                 start_date: ~D[2025-01-01],
                 end_date: ~D[2025-01-31]
               })

      assert data == %{}
    end
  end

  describe "check-ins and vehicles" do
    test "renders check-ins and nested vehicles" do
      vehicle = %CheckInVehicle{
        id: Ecto.ULID.generate(),
        type: "car",
        color: "Blue",
        make: "Subaru"
      }

      check_in = %CheckIn{
        id: Ecto.ULID.generate(),
        checked_in_at: ~U[2025-06-01T18:00:00Z],
        rules_agreed: true,
        check_in_vehicles: [vehicle]
      }

      guest = %BookingGuest{
        id: Ecto.ULID.generate(),
        first_name: "G",
        last_name: "One",
        is_booking_user: true
      }

      booking = %Booking{
        id: Ecto.ULID.generate(),
        reference_id: "BKG-CI",
        property: :tahoe,
        status: :confirmed,
        checkin_date: ~D[2025-06-01],
        checkout_date: ~D[2025-06-03],
        guests_count: 1,
        children_count: 0,
        checked_in: true,
        booking_mode: :member,
        user: nil,
        rooms: [],
        booking_guests: [guest],
        check_ins: [check_in]
      }

      assert %{data: [row]} = BookingsJSON.index(%{bookings: [booking]})

      [ci] = row[:check_ins]
      assert ci[:checked_in_at] == DateTime.to_iso8601(check_in.checked_in_at)
      assert ci[:rules_agreed] == true

      [v] = ci[:vehicles]
      assert v[:make] == "Subaru"
    end

    test "check-in without vehicles key yields empty vehicles list" do
      check_in = %{
        id: Ecto.ULID.generate(),
        checked_in_at: nil,
        rules_agreed: false
      }

      booking = %Booking{
        id: Ecto.ULID.generate(),
        reference_id: "BKG-NOV",
        property: :tahoe,
        status: :confirmed,
        checkin_date: ~D[2025-06-01],
        checkout_date: ~D[2025-06-02],
        guests_count: 1,
        children_count: 0,
        checked_in: false,
        booking_mode: :guest,
        user: nil,
        rooms: [],
        booking_guests: [],
        check_ins: [check_in]
      }

      assert %{data: [row]} = BookingsJSON.index(%{bookings: [booking]})
      [ci] = row[:check_ins]
      assert ci[:vehicles] == []
    end
  end
end
