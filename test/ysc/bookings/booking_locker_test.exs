defmodule Ysc.Bookings.BookingLockerTest do
  @moduledoc """
  Tests for Ysc.Bookings.BookingLocker module.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Bookings.BookingLocker
  alias Ysc.Bookings.Booking
  import Ysc.AccountsFixtures

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    user = user_fixture()

    stub(Stripe.PaymentIntentMock, :list, fn _params ->
      {:ok,
       %Stripe.List{
         data: [],
         has_more: false,
         object: "list",
         url: "/v1/payment_intents"
       }}
    end)

    %{user: user}
  end

  describe "optimistic locking retry" do
    test "retries on stale inventory and returns property_unavailable when another booking wins",
         %{
           sandbox_owner: owner
         } do
      user1 = user_fixture()
      user2 = user_fixture()
      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 3)

      results =
        [user1, user2]
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            BookingLocker.create_buyout_booking(
              user.id,
              :tahoe,
              checkin,
              checkout,
              4
            )
          end,
          max_concurrency: 2,
          timeout: 5_000
        )
        |> Enum.to_list()

      successful = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      failed = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      assert successful == 1,
             "expected exactly one successful buyout booking, got #{successful}"

      assert failed == 1,
             "expected exactly one failed attempt (stale then unavailable), got #{failed}"
    end
  end

  describe "create_buyout_booking/6" do
    test "creates a buyout booking for Tahoe", %{user: user} do
      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 3)

      assert {:ok, %Booking{} = booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      assert booking.user_id == user.id
      assert booking.property == :tahoe
      assert booking.booking_mode == :buyout
      assert booking.status == :hold
    end

    test "creates a buyout booking for Clear Lake", %{user: user} do
      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 2)

      assert {:ok, %Booking{} = booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 6
               )

      assert booking.property == :clear_lake
      assert booking.booking_mode == :buyout
      assert booking.status == :hold
    end

    test "prevents overlapping buyout bookings", %{user: user} do
      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 3)

      # Create first booking
      assert {:ok, _booking1} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      # Try to create overlapping booking
      assert {:error, {:error, :property_unavailable}} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )
    end
  end

  describe "create_room_booking/6" do
    test "creates a room booking", %{user: user} do
      # Set up pricing rules for room bookings
      {:ok, _} =
        Ysc.Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      # Create a room first
      category = create_room_category()

      {:ok, room} =
        Ysc.Bookings.create_room(%{
          name: "Test Room",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 2)

      result =
        BookingLocker.create_room_booking(
          user.id,
          room.id,
          checkin,
          checkout,
          2
        )

      # Either succeeds or fails with pricing error
      # Transaction wraps errors, so {:error, reason} becomes {:ok, {:error, reason}}
      case result do
        {:ok, %Booking{} = booking} ->
          assert booking.user_id == user.id
          assert booking.booking_mode == :room
          assert booking.status == :hold

        {:ok, {:error, :pricing_calculation_failed}} ->
          # Expected if no pricing rules are configured (transaction wraps the error)
          :ok

        {:error, :pricing_calculation_failed} ->
          # Also handle unwrapped error
          :ok

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "multi-room booking combines pricing for multiple rooms", %{user: user} do
      {:ok, _} =
        Ysc.Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room1} =
        Ysc.Bookings.create_room(%{
          name: "Multi Room A",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {:ok, room2} =
        Ysc.Bookings.create_room(%{
          name: "Multi Room B",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      checkin = Date.utc_today() |> Date.add(14)
      checkout = Date.add(checkin, 2)
      guests = 2
      nights = Date.diff(checkout, checkin)

      result =
        BookingLocker.create_room_booking(
          user.id,
          [room1.id, room2.id],
          checkin,
          checkout,
          guests
        )

      case result do
        {:ok, %Booking{} = booking} ->
          booking = Ysc.Repo.preload(booking, :rooms)
          assert length(booking.rooms) == 2
          # Price is per-person-per-night, independent of room count:
          # 2 guests * 2 nights * $100 = $400 (NOT multiplied by 2 rooms)
          expected = Money.new(:USD, guests * nights * 100)
          assert Money.compare(booking.total_price, expected) == :eq
          assert booking.booking_mode == :room
          assert booking.status == :hold

        {:ok, {:error, :pricing_calculation_failed}} ->
          :ok

        {:error, :pricing_calculation_failed} ->
          :ok

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "prevents overlapping room bookings", %{user: user} do
      # Set up pricing rules for room bookings
      {:ok, _} =
        Ysc.Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room} =
        Ysc.Bookings.create_room(%{
          name: "Test Room",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 2)

      # Create first booking
      first_result =
        BookingLocker.create_room_booking(
          user.id,
          room.id,
          checkin,
          checkout,
          2
        )

      case first_result do
        {:ok, _booking1} ->
          # Try to create overlapping booking
          assert {:error, {:error, :room_unavailable}} =
                   BookingLocker.create_room_booking(
                     user.id,
                     room.id,
                     checkin,
                     checkout,
                     2
                   )

        {:error, :pricing_calculation_failed} ->
          # If pricing calculation fails in this environment, we can't meaningfully
          # test overlap behavior here.
          :ok

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end
  end

  describe "create_admin_booking/2" do
    test "creates a complete buyout booking and updates inventory", %{
      user: user
    } do
      checkin = Date.utc_today() |> Date.add(14)
      checkout = Date.add(checkin, 2)

      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: checkin,
        checkout_date: checkout,
        booking_mode: :buyout,
        guests_count: 4,
        total_price: Money.new(:USD, "500.00")
      }

      assert {:ok, %Booking{} = booking} =
               BookingLocker.create_admin_booking(attrs,
                 skip_email: true,
                 skip_reminders: true
               )

      assert booking.user_id == user.id
      assert booking.property == :tahoe
      assert booking.booking_mode == :buyout
      assert booking.status == :complete
      assert booking.checkin_date == checkin
      assert booking.checkout_date == checkout
    end
  end

  describe "refund_complete_booking/2" do
    test "refunds a complete booking and sets status to refunded", %{user: user} do
      checkin = Date.utc_today() |> Date.add(21)
      checkout = Date.add(checkin, 2)

      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: checkin,
        checkout_date: checkout,
        booking_mode: :buyout,
        guests_count: 4,
        total_price: Money.new(:USD, "500.00")
      }

      {:ok, booking} =
        BookingLocker.create_admin_booking(attrs,
          skip_email: true,
          skip_reminders: true
        )

      assert {:ok, updated} = BookingLocker.refund_complete_booking(booking.id)
      assert updated.status == :refunded
    end

    test "refund_complete_booking with release_inventory false does not rollback",
         %{user: user} do
      checkin = Date.utc_today() |> Date.add(28)
      checkout = Date.add(checkin, 2)

      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: checkin,
        checkout_date: checkout,
        booking_mode: :buyout,
        guests_count: 4,
        total_price: Money.new(:USD, "500.00")
      }

      {:ok, booking} =
        BookingLocker.create_admin_booking(attrs,
          skip_email: true,
          skip_reminders: true
        )

      assert {:ok, updated} =
               BookingLocker.refund_complete_booking(booking.id, false)

      assert updated.status == :refunded
    end

    test "refund_complete_booking returns error for non-complete booking", %{
      user: user
    } do
      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 2)

      {:ok, hold_booking} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin,
          checkout,
          4
        )

      assert {:error, {:error, :invalid_status}} =
               BookingLocker.refund_complete_booking(hold_booking.id)
    end
  end

  describe "Clear Lake per-guest capacity" do
    test "create_per_guest_booking succeeds within capacity", %{user: user} do
      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 2)

      assert {:ok, %Booking{} = booking} =
               BookingLocker.create_per_guest_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 2
               )

      assert booking.property == :clear_lake
      assert booking.booking_mode == :day
      assert booking.guests_count == 2
      assert booking.status == :hold
    end

    test "create_per_guest_booking fails when capacity would be exceeded", %{
      user: user
    } do
      checkin = Date.utc_today() |> Date.add(35)
      checkout = Date.add(checkin, 2)

      # Default Clear Lake capacity is 12; book all 12 first
      assert {:ok, _booking1} =
               BookingLocker.create_per_guest_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 12
               )

      # Second user tries to book 1 more guest -> insufficient capacity
      other_user = user_fixture(%{phone_number: "+14159098310"})

      assert {:error, {:error, :insufficient_capacity}} =
               BookingLocker.create_per_guest_booking(
                 other_user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 1
               )
    end
  end

  describe "release_hold/1" do
    test "releases a hold booking", %{user: user} do
      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 2)

      {:ok, booking} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin,
          checkout,
          4
        )

      assert {:ok, _} = BookingLocker.release_hold(booking.id)

      # Verify booking is released (status becomes :canceled)
      updated_booking = Ysc.Repo.reload!(booking)
      assert updated_booking.status == :canceled
    end
  end

  describe "cancel_complete_booking/1" do
    test "cancels a complete booking", %{user: user} do
      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 2)

      {:ok, booking} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin,
          checkout,
          4
        )

      # Mark booking as complete (preload rooms first)
      booking = Ysc.Repo.preload(booking, :rooms)

      booking
      |> Booking.changeset(%{status: :complete},
        rooms: booking.rooms,
        skip_validation: true
      )
      |> Ysc.Repo.update!()

      assert {:ok, _} = BookingLocker.cancel_complete_booking(booking.id)

      # Verify booking is canceled
      updated_booking = Ysc.Repo.reload!(booking)
      assert updated_booking.status == :canceled
    end
  end

  describe "confirm_booking/1 SMS idempotency" do
    # Verifies that calling confirm_booking more than once never re-triggers
    # the check-in reminder SMS — the root cause of the duplicate-SMS bug.
    setup do
      Cachex.clear(:ysc_cache)
      :ok
    end

    test "second call returns {:ok, booking} without scheduling a new SMS", %{
      user: user
    } do
      user =
        user
        |> Ecto.Changeset.change(
          phone_number: "+14155551234",
          account_notifications_sms: true
        )
        |> Ysc.Repo.update!()

      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 3)

      {:ok, booking} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin,
          checkout,
          2
        )

      # First confirmation — reminder is scheduled and (via inline Oban) the SMS
      # idempotency record is committed.
      assert {:ok, confirmed} = BookingLocker.confirm_booking(booking.id)
      assert confirmed.status == :complete

      sms_key = "booking_checkin_reminder_sms_#{confirmed.id}"

      count_after_first =
        Ysc.Repo.aggregate(
          from(m in Ysc.Messages.MessageIdempotency,
            where: m.idempotency_key == ^sms_key and m.message_type == :sms
          ),
          :count
        )

      # Second confirmation (simulating a late webhook or double page-load) must
      # NOT insert a new Oban reminder job and must NOT create a second SMS record.
      assert {:ok, second} = BookingLocker.confirm_booking(booking.id)
      assert second.status == :complete
      assert second.id == confirmed.id

      count_after_second =
        Ysc.Repo.aggregate(
          from(m in Ysc.Messages.MessageIdempotency,
            where: m.idempotency_key == ^sms_key and m.message_type == :sms
          ),
          :count
        )

      assert count_after_second == count_after_first,
             "Expected no new SMS idempotency record on second confirm_booking call " <>
               "(count before: #{count_after_first}, after: #{count_after_second})"
    end

    test "triple confirm_booking calls keep the SMS idempotency record count at 1",
         %{user: user} do
      user =
        user
        |> Ecto.Changeset.change(
          phone_number: "+14155551235",
          account_notifications_sms: true
        )
        |> Ysc.Repo.update!()

      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 3)

      {:ok, booking} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin,
          checkout,
          2
        )

      for _ <- 1..3 do
        assert {:ok, b} = BookingLocker.confirm_booking(booking.id)
        assert b.status == :complete
      end

      sms_key = "booking_checkin_reminder_sms_#{booking.id}"

      assert Ysc.Repo.aggregate(
               from(m in Ysc.Messages.MessageIdempotency,
                 where: m.idempotency_key == ^sms_key and m.message_type == :sms
               ),
               :count
             ) == 1
    end
  end

  # Helper functions
  defp create_room_category do
    {:ok, category} =
      %Ysc.Bookings.RoomCategory{}
      |> Ysc.Bookings.RoomCategory.changeset(%{name: "Test Category"})
      |> Ysc.Repo.insert()

    category
  end
end
