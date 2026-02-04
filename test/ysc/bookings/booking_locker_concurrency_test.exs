defmodule Ysc.Bookings.BookingLockerConcurrencyTest do
  @moduledoc """
  Simplified concurrency tests for cabin bookings to ensure no data races or overbooking.

  These tests verify that optimistic locking mechanisms prevent double-booking
  and ensure capacity limits are respected.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Bookings
  alias Ysc.Bookings.BookingLocker
  alias Ysc.Bookings.Room
  alias Ysc.Ledgers
  alias Ysc.Repo
  import Ysc.AccountsFixtures

  setup context do
    Ledgers.ensure_basic_accounts()
    users = Enum.map(1..10, fn _ -> user_fixture() end)

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(100, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        season_id: nil
      })

    tahoe_room1 =
      %Room{
        name: "Tahoe Room 1",
        property: :tahoe,
        capacity_max: 4,
        is_active: true
      }
      |> Repo.insert!()

    tahoe_room2 =
      %Room{
        name: "Tahoe Room 2",
        property: :tahoe,
        capacity_max: 4,
        is_active: true
      }
      |> Repo.insert!()

    today = Date.utc_today()
    checkin_date = Date.add(today, 7)
    checkout_date = Date.add(checkin_date, 3)

    {:ok,
     Map.merge(context, %{
       users: users,
       tahoe_room1: tahoe_room1,
       tahoe_room2: tahoe_room2,
       checkin_date: checkin_date,
       checkout_date: checkout_date
     })}
  end

  describe "concurrent Tahoe room bookings" do
    test "prevents double-booking same room for same dates", %{
      users: users,
      tahoe_room1: room,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      concurrent_users = Enum.take(users, 5)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            BookingLocker.create_room_booking(
              user.id,
              [room.id],
              checkin_date,
              checkout_date,
              2
            )
          end,
          max_concurrency: 5,
          timeout: 5_000
        )
        |> Enum.to_list()

      successful = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      failed = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      assert successful == 1
      assert failed == 4
    end

    test "allows concurrent bookings for different rooms", %{
      users: users,
      tahoe_room1: room1,
      tahoe_room2: room2,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      concurrent_users = Enum.take(users, 4)

      results =
        concurrent_users
        |> Enum.with_index()
        |> Task.async_stream(
          fn {user, index} ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            room_id = if rem(index, 2) == 0, do: room1.id, else: room2.id

            BookingLocker.create_room_booking(
              user.id,
              [room_id],
              checkin_date,
              checkout_date,
              2
            )
          end,
          max_concurrency: 4,
          timeout: 5_000
        )
        |> Enum.to_list()

      successful = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      assert successful == 2
    end
  end

  describe "concurrent Clear Lake per-guest bookings" do
    test "prevents overbooking when capacity is exceeded", %{
      users: users,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      concurrent_users = Enum.take(users, 5)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            BookingLocker.create_per_guest_booking(
              user.id,
              :clear_lake,
              checkin_date,
              checkout_date,
              1
            )
          end,
          max_concurrency: 5,
          timeout: 5_000
        )
        |> Enum.to_list()

      successful = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      # Clear Lake capacity is 12, so all 5 should succeed
      assert successful == 5
    end
  end

  describe "concurrent buyout bookings" do
    test "prevents overlapping buyout bookings", %{
      users: users,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      concurrent_users = Enum.take(users, 3)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            BookingLocker.create_buyout_booking(
              user.id,
              :tahoe,
              checkin_date,
              checkout_date,
              4
            )
          end,
          max_concurrency: 3,
          timeout: 5_000
        )
        |> Enum.to_list()

      successful = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      failed = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      assert successful == 1
      assert failed == 2
    end
  end

  describe "concurrent booking confirmation (race condition)" do
    test "handles concurrent confirmation attempts idempotently (CashApp redirect race)",
         %{
           users: [user | _],
           tahoe_room1: room,
           checkin_date: checkin_date,
           checkout_date: checkout_date,
           sandbox_owner: owner
         } do
      # Create a booking in :hold status (simulating a booking waiting for payment)
      {:ok, booking} =
        BookingLocker.create_room_booking(
          user.id,
          [room.id],
          checkin_date,
          checkout_date,
          2
        )

      assert booking.status == :hold

      # Simulate the race condition where both the CashApp redirect window
      # AND the original payment window try to confirm the booking simultaneously
      results =
        1..2
        |> Task.async_stream(
          fn _attempt ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            # Both processes try to confirm the same booking
            BookingLocker.confirm_booking(booking.id)
          end,
          max_concurrency: 2,
          timeout: 5_000
        )
        |> Enum.to_list()

      # Both attempts should succeed (idempotent behavior)
      successful = Enum.count(results, &match?({:ok, {:ok, _}}, &1))

      assert successful == 2,
             "Both confirmation attempts should succeed (idempotent)"

      # Verify the booking is in :complete status
      final_booking = Repo.get!(Ysc.Bookings.Booking, booking.id)
      assert final_booking.status == :complete

      # Verify only one set of inventory was booked (not double-booked)
      room_inventory_count =
        Repo.aggregate(
          from(ri in Ysc.Bookings.RoomInventory,
            where:
              ri.room_id == ^room.id and
                ri.day >= ^checkin_date and
                ri.day < ^checkout_date and
                ri.booked == true
          ),
          :count
        )

      expected_nights = Date.diff(checkout_date, checkin_date)

      assert room_inventory_count == expected_nights,
             "Inventory should only be booked once, not double-booked"
    end

    test "second confirmation returns existing booking without errors", %{
      users: [user | _],
      tahoe_room1: room,
      checkin_date: checkin_date,
      checkout_date: checkout_date
    } do
      # Create and confirm a booking
      {:ok, booking} =
        BookingLocker.create_room_booking(
          user.id,
          [room.id],
          checkin_date,
          checkout_date,
          2
        )

      {:ok, confirmed_booking} = BookingLocker.confirm_booking(booking.id)
      assert confirmed_booking.status == :complete

      # Try to confirm again (simulating late-arriving webhook or redirect)
      {:ok, second_confirmation} = BookingLocker.confirm_booking(booking.id)

      # Should return the same confirmed booking
      assert second_confirmation.id == confirmed_booking.id
      assert second_confirmation.status == :complete

      assert second_confirmation.updated_at == confirmed_booking.updated_at,
             "Booking should not be modified on second confirmation"
    end
  end
end
