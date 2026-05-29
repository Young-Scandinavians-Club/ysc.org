defmodule Ysc.Bookings.ModificationDateAvailabilityTest do
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Bookings

  alias Ysc.Bookings.{
    Booking,
    BookingLocker,
    ModificationDateAvailability,
    RoomCategory
  }

  alias Ysc.Ledgers
  alias Ysc.Repo

  setup do
    Ledgers.ensure_basic_accounts()

    user =
      user_fixture()
      |> Ecto.Changeset.change(state: :active)
      |> Repo.update!()

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(100, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        season_id: nil
      })

    %{user: user}
  end

  defp create_room! do
    {:ok, category} =
      %RoomCategory{}
      |> RoomCategory.changeset(%{name: "Availability test category"})
      |> Repo.insert()

    {:ok, room} =
      Bookings.create_room(%{
        name: "Availability test room",
        property: :tahoe,
        room_category_id: category.id,
        capacity_max: 4
      })

    room
  end

  defp complete_room_booking!(user, room, checkin, checkout) do
    assert {:ok, total, _} =
             Bookings.calculate_booking_price(
               :tahoe,
               checkin,
               checkout,
               :room,
               room_id: room.id,
               guests_count: 2
             )

    assert {:ok, %Booking{} = booking} =
             BookingLocker.create_admin_booking(
               %{
                 user_id: user.id,
                 property: :tahoe,
                 checkin_date: checkin,
                 checkout_date: checkout,
                 booking_mode: :room,
                 guests_count: 2,
                 total_price: total
               },
               rooms: [room],
               skip_email: true,
               skip_reminders: true
             )

    Repo.preload(booking, [:rooms, :user])
  end

  test "checkout_date_tooltips marks overlapping checkout dates unavailable", %{
    user: user
  } do
    room = create_room!()

    other_user =
      user_fixture()
      |> Ecto.Changeset.change(state: :active)
      |> Repo.update!()

    base = Date.utc_today() |> Date.add(120) |> first_monday_on_or_after()
    checkin = base
    checkout = Date.add(checkin, 2)

    booking = complete_room_booking!(user, room, checkin, checkout)

    _other =
      complete_room_booking!(
        other_user,
        room,
        Date.add(checkin, 1),
        Date.add(checkout, 2)
      )

    calendar = ModificationDateAvailability.calendar_context(booking)

    tooltips =
      ModificationDateAvailability.checkout_date_tooltips(
        booking,
        checkin,
        calendar.max_date,
        calendar.today,
        calendar.seasons
      )

    extended_checkout = Date.add(checkout, 1)
    assert Map.has_key?(tooltips, Date.to_iso8601(extended_checkout))
  end

  test "checkin_date_tooltips allows dates with valid checkout options", %{
    user: user
  } do
    room = create_room!()
    base = Date.utc_today() |> Date.add(130) |> first_monday_on_or_after()
    checkin = base
    checkout = Date.add(checkin, 2)

    booking = complete_room_booking!(user, room, checkin, checkout)
    calendar = ModificationDateAvailability.calendar_context(booking)
    checkin = first_monday_on_or_after(calendar.min_date)
    assert Date.compare(checkin, calendar.min_date) != :lt
    assert Date.compare(checkin, calendar.max_date) != :gt

    tooltips =
      ModificationDateAvailability.checkin_date_tooltips(
        booking,
        calendar.min_date,
        calendar.max_date,
        calendar.today,
        calendar.seasons
      )

    refute Map.has_key?(tooltips, Date.to_iso8601(checkin))
  end

  defp first_monday_on_or_after(date) do
    days_until_monday = rem(8 - Date.day_of_week(date, :monday), 7)
    Date.add(date, days_until_monday)
  end
end
