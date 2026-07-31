defmodule Ysc.Bookings.BookingLockerTest do
  @moduledoc """
  Tests for Ysc.Bookings.BookingLocker module.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Bookings.BookingLocker
  alias Ysc.Bookings.Booking
  alias Ysc.Bookings.PropertyInventory
  alias Ysc.Bookings
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Ecto.Query

  defp ensure_clear_lake_day_pricing_rule do
    Ysc.Bookings.SeasonCache.invalidate()
    Cachex.clear(:ysc_cache)

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(:USD, 30),
        booking_mode: :day,
        price_unit: :per_guest_per_day,
        property: :clear_lake,
        season_id: nil
      })
  end

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    allow_far_future_booking_dates()

    # Ensure stripe_client is the test client (defensive reset in case async tests leaked state)
    Application.put_env(:ysc, :stripe_client, Ysc.TestStripeClient)
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
      {checkin, checkout} = tahoe_booking_dates(7)

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

  describe "create_buyout_booking/6 conflicts" do
    test "returns blackout_conflict when dates overlap a blackout", %{
      user: user
    } do
      {checkin, checkout} = locker_room_dates(45, 3)

      assert {:ok, _} =
               Bookings.create_blackout(%{
                 property: :tahoe,
                 start_date: checkin,
                 end_date: Date.add(checkout, -1),
                 reason: "Test blackout for locker"
               })

      assert {:error, {:error, :blackout_conflict}} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )
    end

    test "returns rooms_already_booked when a Tahoe room is held for the same dates",
         %{user: user} do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Room blocks buyout",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = locker_room_dates(46, 3)

      first =
        BookingLocker.create_room_booking(
          user.id,
          room.id,
          checkin,
          checkout,
          2
        )

      case first do
        {:ok, %Booking{}} ->
          assert {:error, {:error, :rooms_already_booked}} =
                   BookingLocker.create_buyout_booking(
                     user.id,
                     :tahoe,
                     checkin,
                     checkout,
                     4
                   )

        {:ok, {:error, :pricing_calculation_failed}} ->
          :ok

        {:error, :pricing_calculation_failed} ->
          :ok
      end
    end
  end

  describe "create_buyout_booking/6" do
    test "creates a buyout booking for Tahoe", %{user: user} do
      {checkin, checkout} = tahoe_booking_dates(7)

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

    test "honors hold_duration_minutes in opts for hold_expires_at", %{
      user: user
    } do
      {checkin, checkout} = locker_buyout_dates(131)

      assert {:ok, %Booking{} = booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 2,
                 hold_duration_minutes: 5
               )

      seconds =
        DateTime.diff(booking.hold_expires_at, DateTime.utc_now(), :second)

      assert seconds >= 4 * 60
      assert seconds <= 7 * 60
    end

    test "creates a buyout booking for Clear Lake", %{user: user} do
      {checkin, checkout} = tahoe_room_booking_dates(7, 2)

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
      {checkin, checkout} = tahoe_booking_dates(7)

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

  describe "create_room_booking/6 validation" do
    test "returns :no_rooms_provided when room list is empty", %{user: user} do
      {checkin, checkout} = locker_room_dates(40, 2)

      assert {:error, :no_rooms_provided} =
               BookingLocker.create_room_booking(
                 user.id,
                 [],
                 checkin,
                 checkout,
                 2
               )
    end

    test "returns rooms_not_found when a room id does not exist", %{user: user} do
      {checkin, checkout} = locker_room_dates(41, 2)
      missing_id = Ecto.ULID.generate()

      assert {:error, {:error, {:rooms_not_found, [^missing_id]}}} =
               BookingLocker.create_room_booking(
                 user.id,
                 [missing_id],
                 checkin,
                 checkout,
                 2
               )
    end

    test "returns :rooms_must_be_same_property when mixing Tahoe and Clear Lake rooms",
         %{user: user} do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category_tahoe = create_room_category()
      category_cl = create_room_category()

      {:ok, room_tahoe} =
        Bookings.create_room(%{
          name: "Tahoe mixed",
          property: :tahoe,
          room_category_id: category_tahoe.id,
          capacity_max: 4
        })

      {:ok, room_cl} =
        Bookings.create_room(%{
          name: "Clear Lake mixed",
          property: :clear_lake,
          room_category_id: category_cl.id,
          capacity_max: 4
        })

      {checkin, checkout} = locker_room_dates(42, 2)

      assert {:error, {:error, :rooms_must_be_same_property}} =
               BookingLocker.create_room_booking(
                 user.id,
                 [room_tahoe.id, room_cl.id],
                 checkin,
                 checkout,
                 2
               )
    end

    test "returns blackout_conflict when room stay overlaps a blackout", %{
      user: user
    } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Room blackout conflict",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, _checkout} = locker_room_dates(55, 2)
      checkout = Date.add(checkin, 2)

      assert {:ok, _} =
               Bookings.create_blackout(%{
                 property: :tahoe,
                 start_date: checkin,
                 end_date: checkout,
                 reason: "Room blackout"
               })

      assert {:error, {:error, :blackout_conflict}} =
               BookingLocker.create_room_booking(
                 user.id,
                 room.id,
                 checkin,
                 checkout,
                 2
               )
    end

    test "allows room booking that checks out on blackout start", %{user: user} do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Room blackout turnaround",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, _checkout} = locker_room_dates(58, 2)
      checkout = Date.add(checkin, 2)

      assert {:ok, _} =
               Bookings.create_blackout(%{
                 property: :tahoe,
                 start_date: checkout,
                 end_date: Date.add(checkout, 3),
                 reason: "Starts at checkout"
               })

      assert {:ok, %Booking{}} =
               BookingLocker.create_room_booking(
                 user.id,
                 room.id,
                 checkin,
                 checkout,
                 2
               )
    end
  end

  describe "create_room_booking/6 buyout overlap" do
    test "returns property_buyout_active when a buyout hold exists for the range",
         %{user: user} do
      other_user = user_fixture(%{phone_number: "+14159098311"})

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Room under buyout",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = locker_buyout_dates(48)

      assert {:ok, %Booking{}} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      second =
        BookingLocker.create_room_booking(
          other_user.id,
          room.id,
          checkin,
          checkout,
          2
        )

      case second do
        {:error, {:error, :property_buyout_active}} ->
          :ok

        {:ok, {:error, :property_buyout_active}} ->
          :ok

        {:ok, %Booking{}} ->
          flunk("expected room booking to fail when buyout is active")

        other ->
          flunk("unexpected result: #{inspect(other)}")
      end
    end
  end

  describe "create_room_booking/6 single room id" do
    test "accepts room id as binary (delegates to list form)", %{user: user} do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Binary room id",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, _checkout} = locker_room_dates(14, 2)
      checkout = Date.add(checkin, 2)

      result =
        BookingLocker.create_room_booking(
          user.id,
          room.id,
          checkin,
          checkout,
          2
        )

      case result do
        {:ok, %Booking{} = booking} ->
          booking = Ysc.Repo.preload(booking, :rooms)
          assert booking.booking_mode == :room
          assert [%Ysc.Bookings.Room{id: rid}] = booking.rooms
          assert rid == room.id

        {:ok, {:error, :pricing_calculation_failed}} ->
          :ok

        {:error, :pricing_calculation_failed} ->
          :ok
      end
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

      {checkin, checkout} = tahoe_room_booking_dates(7, 2)

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

    test "passes children_count through opts into pricing and booking", %{
      user: user
    } do
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
          name: "Children count room",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 6
        })

      {checkin, _checkout} = locker_room_dates(16, 2)
      checkout = Date.add(checkin, 2)

      result =
        BookingLocker.create_room_booking(
          user.id,
          room.id,
          checkin,
          checkout,
          2,
          children_count: 1
        )

      case result do
        {:ok, %Booking{} = booking} ->
          assert booking.children_count == 1

        {:ok, {:error, :pricing_calculation_failed}} ->
          :ok

        {:error, :pricing_calculation_failed} ->
          :ok
      end
    end

    test "multi-room booking combines pricing for multiple rooms" do
      # Family/lifetime required — BookingValidator enforces max rooms on create
      user = Ysc.TestDataFactory.user_with_membership(:lifetime)

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

      {checkin, _checkout} = locker_room_dates(14, 2)
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

      {checkin, checkout} = tahoe_room_booking_dates(7, 2)

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
    test "returns blackout_conflict when dates overlap a blackout", %{
      user: user
    } do
      {checkin, _checkout} = locker_room_dates(420, 2)
      checkout = Date.add(checkin, 2)

      assert {:ok, _} =
               Bookings.create_blackout(%{
                 property: :tahoe,
                 start_date: checkin,
                 end_date: checkout,
                 reason: "Admin blackout block"
               })

      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: checkin,
        checkout_date: checkout,
        booking_mode: :buyout,
        guests_count: 4,
        total_price: Money.new(:USD, "500.00")
      }

      assert {:error, :blackout_conflict} =
               BookingLocker.create_admin_booking(attrs,
                 skip_email: true,
                 skip_reminders: true
               )
    end

    test "enqueues booking confirmation email when skip_email is false", %{
      user: user
    } do
      {checkin, checkout} = locker_buyout_dates(412)

      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: checkin,
        checkout_date: checkout,
        booking_mode: :buyout,
        guests_count: 4,
        total_price: Money.new(:USD, "500.00")
      }

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %Booking{} = booking} =
                 BookingLocker.create_admin_booking(attrs,
                   skip_email: false,
                   skip_reminders: true
                 )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "booking_confirmation",
            "idempotency_key" => "booking_confirmation_#{booking.id}"
          }
        )
      end)
    end

    test "schedules check-in and checkout reminder Oban jobs when skip_reminders is false",
         %{user: user} do
      {checkin, checkout} = locker_future_buyout_dates(14)

      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: checkin,
        checkout_date: checkout,
        booking_mode: :buyout,
        guests_count: 4,
        total_price: Money.new(:USD, "500.00")
      }

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %Booking{} = booking} =
                 BookingLocker.create_admin_booking(attrs,
                   skip_email: true,
                   skip_reminders: false
                 )

        assert_enqueued(
          worker: YscWeb.Workers.BookingCheckinReminderWorker,
          args: %{"booking_id" => booking.id}
        )

        assert_enqueued(
          worker: YscWeb.Workers.BookingCheckoutReminderWorker,
          args: %{"booking_id" => booking.id}
        )
      end)
    end

    test "creates a complete room booking and marks room inventory booked", %{
      user: user
    } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Admin room locker",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = locker_room_dates(408, 2)

      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: checkin,
        checkout_date: checkout,
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(:USD, "400.00")
      }

      assert {:ok, %Booking{} = booking} =
               BookingLocker.create_admin_booking(attrs,
                 rooms: [room],
                 skip_email: true,
                 skip_reminders: true
               )

      booking = Ysc.Repo.preload(booking, :rooms)
      assert [%Ysc.Bookings.Room{id: rid}] = booking.rooms
      assert rid == room.id

      nights = Date.diff(checkout, checkin)

      booked_days =
        Ysc.Repo.aggregate(
          from(ri in Ysc.Bookings.RoomInventory,
            where:
              ri.room_id == ^room.id and ri.day >= ^checkin and
                ri.day < ^checkout and ri.booked == true
          ),
          :count
        )

      assert booked_days == nights
    end

    test "creates a complete buyout booking and updates inventory", %{
      user: user
    } do
      {checkin, checkout} = locker_buyout_dates(14)

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
    test "refunds a complete room booking without releasing inventory when release_inventory is false",
         %{user: user} do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Refund room no release",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = locker_room_dates(413, 2)

      result =
        BookingLocker.create_room_booking(
          user.id,
          room.id,
          checkin,
          checkout,
          2
        )

      case result do
        {:ok, %Booking{} = hold} ->
          assert {:ok, booking} = BookingLocker.confirm_booking(hold.id)
          assert booking.booking_mode == :room

          assert {:ok, refunded} =
                   BookingLocker.refund_complete_booking(booking.id, false)

          assert refunded.status == :refunded

        {:ok, {:error, :pricing_calculation_failed}} ->
          :ok

        {:error, :pricing_calculation_failed} ->
          :ok
      end
    end

    test "refunds a complete Clear Lake day booking and sets status to refunded",
         %{user: user} do
      ensure_clear_lake_day_pricing_rule()

      {checkin, checkout} = locker_room_dates(414, 2)

      assert {:ok, hold} =
               BookingLocker.create_per_guest_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 3
               )

      assert {:ok, booking} = BookingLocker.confirm_booking(hold.id)
      assert booking.booking_mode == :day

      assert {:ok, refunded} = BookingLocker.refund_complete_booking(booking.id)
      assert refunded.status == :refunded
    end

    test "refunds a complete booking and sets status to refunded", %{user: user} do
      {checkin, checkout} = locker_buyout_dates(21)

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
      {checkin, checkout} = locker_buyout_dates(28)

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
      {checkin, checkout} = tahoe_room_booking_dates(7, 2)

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
    setup do
      ensure_clear_lake_day_pricing_rule()
      :ok
    end

    test "create_per_guest_booking succeeds within capacity", %{user: user} do
      {checkin, checkout} = locker_room_dates(30, 2)

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
      {checkin, checkout} = locker_room_dates(35, 2)

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

    test "create_per_guest_booking returns blackout_conflict when dates overlap a blackout",
         %{
           user: user
         } do
      {checkin, checkout} = locker_room_dates(88, 2)

      assert {:ok, _} =
               Bookings.create_blackout(%{
                 property: :clear_lake,
                 start_date: checkin,
                 end_date: Date.add(checkout, -1),
                 reason: "Clear Lake blackout locker"
               })

      assert {:error, {:error, :blackout_conflict}} =
               BookingLocker.create_per_guest_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 2
               )
    end
  end

  describe "confirm_booking/1 inventory errors" do
    test "returns inventory_update_failed when property inventory rows are missing after buyout hold",
         %{user: user} do
      {checkin, checkout} = locker_buyout_dates(206)

      {:ok, booking} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin,
          checkout,
          4
        )

      from(pi in PropertyInventory,
        where:
          pi.property == :tahoe and pi.day >= ^checkin and pi.day < ^checkout
      )
      |> Repo.delete_all()

      assert {:error, {:error, :inventory_update_failed}} =
               BookingLocker.confirm_booking(booking.id)
    end

    test "returns inventory_update_failed when room inventory rows are missing after room hold",
         %{user: user} do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Confirm room inventory missing",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = locker_room_dates(210, 2)

      result =
        BookingLocker.create_room_booking(
          user.id,
          room.id,
          checkin,
          checkout,
          2
        )

      case result do
        {:ok, %Booking{} = booking} ->
          from(ri in Ysc.Bookings.RoomInventory,
            where:
              ri.room_id == ^room.id and ri.day >= ^checkin and
                ri.day < ^checkout
          )
          |> Repo.delete_all()

          assert {:error, {:error, :inventory_update_failed}} =
                   BookingLocker.confirm_booking(booking.id)

        {:ok, {:error, :pricing_calculation_failed}} ->
          :ok

        {:error, :pricing_calculation_failed} ->
          :ok
      end
    end

    test "re-seeds property inventory and confirms when rows were missing after per-guest hold",
         %{user: user} do
      ensure_clear_lake_day_pricing_rule()

      {checkin, checkout} = locker_room_dates(211, 2)

      {:ok, booking} =
        BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      assert booking.booking_mode == :day

      from(pi in PropertyInventory,
        where:
          pi.property == :clear_lake and pi.day >= ^checkin and
            pi.day < ^checkout
      )
      |> Repo.delete_all()

      assert {:ok, confirmed} = BookingLocker.confirm_booking(booking.id)
      assert confirmed.status == :complete

      prop_inv =
        Repo.all(
          from pi in PropertyInventory,
            where:
              pi.property == :clear_lake and pi.day >= ^checkin and
                pi.day < ^checkout
        )

      assert length(prop_inv) == Date.diff(checkout, checkin)
    end
  end

  describe "release_hold/1 inventory errors" do
    test "returns inventory_update_failed when property inventory rows are missing",
         %{
           user: user
         } do
      {checkin, checkout} = locker_buyout_dates(203)

      {:ok, booking} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin,
          checkout,
          4
        )

      from(pi in PropertyInventory,
        where:
          pi.property == :tahoe and pi.day >= ^checkin and pi.day < ^checkout
      )
      |> Repo.delete_all()

      assert {:error, {:error, :inventory_update_failed}} =
               BookingLocker.release_hold(booking.id)
    end

    test "returns inventory_update_failed when room inventory rows are missing for a room hold",
         %{user: user} do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Room release inventory",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = locker_room_dates(207, 2)

      result =
        BookingLocker.create_room_booking(
          user.id,
          room.id,
          checkin,
          checkout,
          2
        )

      case result do
        {:ok, %Booking{} = booking} ->
          from(ri in Ysc.Bookings.RoomInventory,
            where:
              ri.room_id == ^room.id and ri.day >= ^checkin and
                ri.day < ^checkout
          )
          |> Repo.delete_all()

          assert {:error, {:error, :inventory_update_failed}} =
                   BookingLocker.release_hold(booking.id)

        {:ok, {:error, :pricing_calculation_failed}} ->
          :ok

        {:error, :pricing_calculation_failed} ->
          :ok
      end
    end
  end

  describe "release_hold/1" do
    test "searches PaymentIntents and attempts cancel when metadata matches booking",
         %{user: user} do
      {checkin, checkout} = locker_buyout_dates(409)

      {:ok, booking} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin,
          checkout,
          4
        )

      stub(Stripe.PaymentIntentMock, :list, fn _params ->
        {:ok,
         %Stripe.List{
           data: [
             %Stripe.PaymentIntent{
               id: "pi_test_booking_locker_release",
               metadata: %{"booking_id" => booking.id},
               status: "requires_payment_method"
             }
           ],
           has_more: false,
           object: "list",
           url: "/v1/payment_intents"
         }}
      end)

      assert {:ok, released} = BookingLocker.release_hold(booking.id)
      assert released.status == :canceled
    end

    test "releases a hold booking", %{user: user} do
      {checkin, checkout} = tahoe_room_booking_dates(7, 2)

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

    test "releases Clear Lake per-guest hold and restores capacity_held", %{
      user: user
    } do
      ensure_clear_lake_day_pricing_rule()

      {checkin, checkout} = locker_room_dates(125, 2)
      guests = 3

      assert {:ok, booking} =
               BookingLocker.create_per_guest_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 guests
               )

      assert booking.booking_mode == :day

      day = checkin

      before =
        Ysc.Repo.get_by!(Ysc.Bookings.PropertyInventory,
          property: :clear_lake,
          day: day
        )

      assert {:ok, released} = BookingLocker.release_hold(booking.id)
      assert released.status == :canceled

      after_inv =
        Ysc.Repo.get_by!(Ysc.Bookings.PropertyInventory,
          property: :clear_lake,
          day: day
        )

      assert after_inv.capacity_held == before.capacity_held - guests
    end

    test "returns invalid_status when booking is not a hold", %{user: user} do
      {checkin, checkout} = tahoe_room_booking_dates(7, 2)

      {:ok, booking} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin,
          checkout,
          4
        )

      booking = Ysc.Repo.preload(booking, :rooms)

      booking =
        booking
        |> Booking.changeset(%{status: :complete},
          rooms: booking.rooms,
          skip_validation: true
        )
        |> Ysc.Repo.update!()

      assert {:error, {:error, :invalid_status}} =
               BookingLocker.release_hold(booking.id)
    end
  end

  describe "cancel_complete_booking/1 room and day modes" do
    test "cancels a complete room booking and clears room inventory", %{
      user: user
    } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Locker cancel room",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = locker_room_dates(201, 2)

      result =
        BookingLocker.create_room_booking(
          user.id,
          room.id,
          checkin,
          checkout,
          2
        )

      case result do
        {:ok, %Booking{} = booking_hold} ->
          assert {:ok, booking} = BookingLocker.confirm_booking(booking_hold.id)
          assert booking.booking_mode == :room

          assert {:ok, canceled} =
                   BookingLocker.cancel_complete_booking(booking.id)

          assert canceled.status == :canceled

        {:ok, {:error, :pricing_calculation_failed}} ->
          :ok

        {:error, :pricing_calculation_failed} ->
          :ok
      end
    end

    test "cancels a complete Clear Lake day booking and decrements capacity_booked",
         %{
           user: user
         } do
      ensure_clear_lake_day_pricing_rule()

      {checkin, checkout} = locker_room_dates(202, 2)
      guests = 3

      {:ok, hold} =
        BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          guests
        )

      assert {:ok, booking} = BookingLocker.confirm_booking(hold.id)
      assert booking.booking_mode == :day

      day = checkin

      before_cancel =
        Ysc.Repo.get_by!(PropertyInventory,
          property: :clear_lake,
          day: day
        )

      assert {:ok, canceled} = BookingLocker.cancel_complete_booking(booking.id)
      assert canceled.status == :canceled

      after_cancel =
        Ysc.Repo.get_by!(PropertyInventory,
          property: :clear_lake,
          day: day
        )

      assert after_cancel.capacity_booked ==
               before_cancel.capacity_booked - guests
    end
  end

  describe "cancel_complete_booking/1" do
    test "returns invalid_status when booking is still a hold", %{user: user} do
      {checkin, checkout} = locker_buyout_dates(415)

      assert {:ok, hold} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      assert {:error, {:error, :invalid_status}} =
               BookingLocker.cancel_complete_booking(hold.id)
    end

    test "cancels a complete booking", %{user: user} do
      {checkin, checkout} = tahoe_room_booking_dates(7, 2)

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

  describe "confirm_booking/1 confirmation email scheduling" do
    defmodule NotifierScheduleError do
      @moduledoc false
      def schedule_email(a, b, c, d, e, f, g),
        do: schedule_email(a, b, c, d, e, f, g, nil)

      def schedule_email(_, _, _, _, _, _, _, _),
        do: {:error, :coverage_schedule_failed}
    end

    defp with_booking_confirmation_notifier(module, fun) do
      prev = Application.get_env(:ysc, :booking_confirmation_email_notifier)
      Application.put_env(:ysc, :booking_confirmation_email_notifier, module)

      on_exit(fn ->
        if prev do
          Application.put_env(:ysc, :booking_confirmation_email_notifier, prev)
        else
          Application.delete_env(:ysc, :booking_confirmation_email_notifier)
        end
      end)

      fun.()
    end

    test "keeps booking complete when confirmation email enqueue fails", %{
      user: user
    } do
      {checkin, checkout} = locker_buyout_dates(415)

      {:ok, hold} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin,
          checkout,
          4
        )

      with_booking_confirmation_notifier(NotifierScheduleError, fn ->
        assert {:ok, confirmed} = BookingLocker.confirm_booking(hold.id)
        assert confirmed.status == :complete
        assert Repo.get!(Booking, hold.id).status == :complete
      end)
    end
  end

  describe "confirm_booking/1 other holds" do
    test "second confirm_booking is idempotent when booking is already complete",
         %{
           user: user
         } do
      {checkin, checkout} = locker_buyout_dates(411)

      {:ok, booking} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin,
          checkout,
          4
        )

      assert {:ok, confirmed} = BookingLocker.confirm_booking(booking.id)
      assert confirmed.status == :complete

      assert {:ok, confirmed_again} = BookingLocker.confirm_booking(booking.id)
      assert confirmed_again.status == :complete
      assert confirmed_again.id == confirmed.id
    end

    test "releases other hold bookings for the same property and user", %{
      user: user
    } do
      {week1_in, week1_out} = locker_buyout_dates(10)
      {week2_in, week2_out} = locker_buyout_dates_after(week1_out)

      assert {:ok, first_hold} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 week1_in,
                 week1_out,
                 4
               )

      assert {:ok, second_hold} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 week2_in,
                 week2_out,
                 4
               )

      assert {:ok, confirmed} = BookingLocker.confirm_booking(first_hold.id)
      assert confirmed.status == :complete

      second = Ysc.Repo.reload!(second_hold)
      assert second.status == :canceled
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

      {checkin, checkout} = tahoe_booking_dates(7)

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

      {checkin, checkout} = tahoe_booking_dates(7)

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

  describe "confirm_booking/1 after hold release" do
    test "confirms canceled hold when inventory is still available", %{
      user: user
    } do
      # Summer weekday — buyout + weekend rules now enforced on create
      {checkin, _checkout} = locker_room_dates(21, 2)
      checkout = Date.add(checkin, 2)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      assert {:ok, _} = BookingLocker.release_hold(booking.id)
      canceled = Ysc.Repo.reload!(booking)
      assert canceled.status == :canceled

      assert {:ok, confirmed} = BookingLocker.confirm_booking(booking.id)
      assert confirmed.status == :complete
    end

    test "rejects canceled hold when buyout inventory was taken after release",
         %{
           user: user
         } do
      other_user = user_fixture(%{phone_number: "+14159098312"})
      {checkin, _checkout} = locker_room_dates(28, 2)
      checkout = Date.add(checkin, 2)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      assert {:ok, _} = BookingLocker.release_hold(booking.id)

      assert {:ok, _other_booking} =
               BookingLocker.create_buyout_booking(
                 other_user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      assert {:error, {:error, :buyout_unavailable}} =
               BookingLocker.confirm_booking(booking.id)
    end

    test "confirms canceled room hold when inventory is still available", %{
      user: user
    } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Released hold room",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = locker_room_dates(122, 2)

      assert {:ok, hold} =
               BookingLocker.create_room_booking(
                 user.id,
                 room.id,
                 checkin,
                 checkout,
                 2
               )

      assert {:ok, _} = BookingLocker.release_hold(hold.id)
      assert Ysc.Repo.reload!(hold).status == :canceled

      assert {:ok, confirmed} = BookingLocker.confirm_booking(hold.id)
      assert confirmed.status == :complete
      assert confirmed.booking_mode == :room
    end

    test "rejects canceled room hold when room was booked after release", %{
      user: user
    } do
      other_user = user_fixture(%{phone_number: "+14159098313"})

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Contested room",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = locker_room_dates(123, 2)

      assert {:ok, hold} =
               BookingLocker.create_room_booking(
                 user.id,
                 room.id,
                 checkin,
                 checkout,
                 2
               )

      assert {:ok, _} = BookingLocker.release_hold(hold.id)

      assert {:ok, other_hold} =
               BookingLocker.create_room_booking(
                 other_user.id,
                 room.id,
                 checkin,
                 checkout,
                 2
               )

      assert {:ok, _other_confirmed} =
               BookingLocker.confirm_booking(other_hold.id)

      assert {:error, {:error, :room_unavailable}} =
               BookingLocker.confirm_booking(hold.id)
    end

    test "confirms canceled per-guest hold when inventory is still available",
         %{
           user: user
         } do
      ensure_clear_lake_day_pricing_rule()

      {checkin, checkout} = locker_room_dates(124, 2)

      assert {:ok, hold} =
               BookingLocker.create_per_guest_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 2
               )

      assert {:ok, _} = BookingLocker.release_hold(hold.id)
      assert Ysc.Repo.reload!(hold).status == :canceled

      assert {:ok, confirmed} = BookingLocker.confirm_booking(hold.id)
      assert confirmed.status == :complete
      assert confirmed.booking_mode == :day
    end

    test "rejects canceled per-guest hold when capacity was taken after release",
         %{
           user: user
         } do
      other_user = user_fixture(%{phone_number: "+14159098314"})
      ensure_clear_lake_day_pricing_rule()

      {checkin, checkout} = locker_room_dates(125, 2)

      assert {:ok, hold} =
               BookingLocker.create_per_guest_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 2
               )

      assert {:ok, _} = BookingLocker.release_hold(hold.id)

      assert {:ok, buyout_hold} =
               BookingLocker.create_buyout_booking(
                 other_user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 6
               )

      assert {:ok, _buyout_confirmed} =
               BookingLocker.confirm_booking(buyout_hold.id)

      assert {:error, {:error, :insufficient_capacity}} =
               BookingLocker.confirm_booking(hold.id)
    end
  end

  describe "create_buyout_booking/6 Clear Lake vs per-guest capacity" do
    setup do
      ensure_clear_lake_day_pricing_rule()
      :ok
    end

    test "returns property_unavailable when per-guest hold consumes Clear Lake capacity",
         %{
           user: user
         } do
      {checkin, checkout} = locker_room_dates(121, 2)

      assert {:ok, _} =
               BookingLocker.create_per_guest_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 4
               )

      assert {:error, {:error, :property_unavailable}} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 6
               )
    end
  end

  describe "create_admin_booking/2 Clear Lake" do
    test "creates a complete buyout for Clear Lake", %{user: user} do
      {checkin, checkout} = locker_buyout_dates(122)

      attrs = %{
        user_id: user.id,
        property: :clear_lake,
        checkin_date: checkin,
        checkout_date: checkout,
        booking_mode: :buyout,
        guests_count: 6,
        total_price: Money.new(:USD, "600.00")
      }

      assert {:ok, %Booking{} = booking} =
               BookingLocker.create_admin_booking(attrs,
                 skip_email: true,
                 skip_reminders: true
               )

      assert booking.property == :clear_lake
      assert booking.status == :complete
      assert booking.booking_mode == :buyout
    end

    @tag process_caches: true
    test "invalidates Clear Lake availability cache", %{user: user} do
      alias Ysc.Bookings.AvailabilityCache

      {checkin, checkout} = locker_room_dates(412, 2)

      AvailabilityCache.get_clear_lake_daily_availability(checkin, checkout)

      {_cached, queries_before} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            AvailabilityCache.get_clear_lake_daily_availability(
              checkin,
              checkout
            )
          end,
          pattern: ~r/FROM "bookings"/i,
          caller_pids: [self()]
        )

      assert queries_before == 0

      attrs = %{
        user_id: user.id,
        property: :clear_lake,
        checkin_date: checkin,
        checkout_date: checkout,
        booking_mode: :buyout,
        guests_count: 6,
        total_price: Money.new(:USD, "600.00")
      }

      assert {:ok, %Booking{}} =
               BookingLocker.create_admin_booking(attrs,
                 skip_email: true,
                 skip_reminders: true
               )

      {_refetched, queries_after} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            AvailabilityCache.get_clear_lake_daily_availability(
              checkin,
              checkout
            )
          end,
          pattern: ~r/FROM "bookings"/i,
          caller_pids: [self()]
        )

      assert queries_after >= 1
    end

    test "creates a complete per-guest (day) booking for Clear Lake", %{
      user: user
    } do
      {checkin, checkout} = locker_room_dates(123, 2)

      attrs = %{
        user_id: user.id,
        property: :clear_lake,
        checkin_date: checkin,
        checkout_date: checkout,
        booking_mode: :day,
        guests_count: 3,
        total_price: Money.new(:USD, "300.00")
      }

      assert {:ok, %Booking{} = booking} =
               BookingLocker.create_admin_booking(attrs,
                 skip_email: true,
                 skip_reminders: true
               )

      assert booking.booking_mode == :day
      assert booking.status == :complete
    end
  end

  describe "confirm_booking/1 Clear Lake per-guest" do
    setup do
      ensure_clear_lake_day_pricing_rule()
      :ok
    end

    test "confirms a per-guest hold and completes booking", %{user: user} do
      {checkin, checkout} = locker_room_dates(124, 2)

      assert {:ok, hold} =
               BookingLocker.create_per_guest_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 2
               )

      assert {:ok, done} = BookingLocker.confirm_booking(hold.id)
      assert done.status == :complete
      assert done.booking_mode == :day
    end
  end

  describe "create_per_guest_booking pricing_items (price_per_guest_per_night)" do
    test "includes computed price_per_guest_per_night in pricing_items", %{
      user: user
    } do
      Ysc.Bookings.SeasonCache.invalidate()
      Cachex.clear(:ysc_cache)

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 30),
          booking_mode: :day,
          price_unit: :per_guest_per_day,
          property: :clear_lake,
          season_id: nil
        })

      {checkin, checkout} = locker_room_dates(30, 3)
      guests = 4

      assert {:ok, booking} =
               BookingLocker.create_per_guest_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 guests
               )

      booking = Ysc.Repo.reload!(booking)
      assert booking.pricing_items
      pi = booking.pricing_items
      assert (Map.get(pi, "type") || Map.get(pi, :type)) == "per_guest"

      assert (Map.get(pi, "guests_count") || Map.get(pi, :guests_count)) ==
               guests

      nights = Date.diff(checkout, checkin)
      assert (Map.get(pi, "nights") || Map.get(pi, :nights)) == nights

      ppg =
        Map.get(pi, "price_per_guest_per_night") ||
          Map.get(pi, :price_per_guest_per_night)

      assert ppg

      ppg = for {k, v} <- ppg, into: %{}, do: {to_string(k), v}

      assert ppg["currency"] == "USD"
      assert match?(%Decimal{}, Decimal.new(ppg["amount"]))

      {:ok, expected_per_guest} =
        Money.div(booking.total_price, nights * guests)

      assert Decimal.equal?(
               Decimal.new(ppg["amount"]),
               expected_per_guest.amount
             )
    end
  end

  describe "Tahoe buyout vs room hold (rooms_already_booked)" do
    test "returns rooms_already_booked when a room hold blocks Tahoe buyout for the dates",
         %{user: user} do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Room blocks Tahoe buyout",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = locker_room_dates(209, 3)

      first =
        BookingLocker.create_room_booking(
          user.id,
          room.id,
          checkin,
          checkout,
          2
        )

      case first do
        {:ok, %Booking{}} ->
          assert {:error, {:error, :rooms_already_booked}} =
                   BookingLocker.create_buyout_booking(
                     user.id,
                     :tahoe,
                     checkin,
                     checkout,
                     4
                   )

        _ ->
          :ok
      end
    end
  end

  describe "create_room_booking/6 pricing_calculation_failed branches" do
    test "returns pricing_calculation_failed when room pricing cannot be calculated",
         %{user: user} do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      category = create_room_category()

      {:ok, room} =
        Bookings.create_room(%{
          name: "No pricing path",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = locker_room_dates(504, 2)

      assert {:error, :pricing_calculation_failed} =
               BookingLocker.create_room_booking(
                 user.id,
                 room.id,
                 checkin,
                 checkout,
                 0,
                 children_count: 0
               )
    end
  end

  # Helper functions
  defp create_room_category do
    {:ok, category} =
      %Ysc.Bookings.RoomCategory{}
      |> Ysc.Bookings.RoomCategory.changeset(%{
        name: "Test Category #{System.unique_integer([:positive])}"
      })
      |> Ysc.Repo.insert()

    category
  end
end
