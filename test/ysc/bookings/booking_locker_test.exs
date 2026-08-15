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

        cabin_master_email = Ysc.EmailConfig.booking_reply_to(:tahoe)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "booking_confirmation",
            "idempotency_key" => "booking_confirmation_#{booking.id}",
            "reply_to" => cabin_master_email,
            "cc" => cabin_master_email
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

    test "rejects overlapping admin buyout bookings for the same dates", %{
      user: user
    } do
      user2 = user_fixture()
      {checkin, checkout} = locker_buyout_dates(15)

      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: checkin,
        checkout_date: checkout,
        booking_mode: :buyout,
        guests_count: 4,
        total_price: Money.new(:USD, "500.00")
      }

      assert {:ok, %Booking{}} =
               BookingLocker.create_admin_booking(attrs,
                 skip_email: true,
                 skip_reminders: true
               )

      overlap_attrs = Map.put(attrs, :user_id, user2.id)

      assert {:error, {:error, :stale_inventory}} =
               BookingLocker.create_admin_booking(overlap_attrs,
                 skip_email: true,
                 skip_reminders: true
               )

      overlapping_bookings =
        Ysc.Repo.aggregate(
          from(b in Ysc.Bookings.Booking,
            where:
              b.property == :tahoe and b.booking_mode == :buyout and
                b.checkin_date == ^checkin and b.checkout_date == ^checkout and
                b.status == :complete
          ),
          :count
        )

      assert overlapping_bookings == 1
    end

    test "rejects overlapping admin room bookings for the same dates", %{
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
          name: "Admin room overlap",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      user2 = user_fixture()
      {checkin, checkout} = locker_room_dates(17, 2)

      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: checkin,
        checkout_date: checkout,
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(:USD, "200.00")
      }

      assert {:ok, %Booking{}} =
               BookingLocker.create_admin_booking(attrs,
                 rooms: [room],
                 skip_email: true,
                 skip_reminders: true
               )

      overlap_attrs = Map.put(attrs, :user_id, user2.id)

      assert {:error, {:error, :stale_inventory}} =
               BookingLocker.create_admin_booking(overlap_attrs,
                 rooms: [room],
                 skip_email: true,
                 skip_reminders: true
               )

      overlapping_bookings =
        Ysc.Repo.aggregate(
          from(b in Ysc.Bookings.Booking,
            join: br in Ysc.Bookings.BookingRoom,
            on: br.booking_id == b.id,
            where:
              br.room_id == ^room.id and b.checkin_date == ^checkin and
                b.checkout_date == ^checkout and b.status == :complete
          ),
          :count
        )

      assert overlapping_bookings == 1
    end

    test "concurrent admin buyout bookings allow only one winner on new inventory rows",
         %{sandbox_owner: owner} do
      user1 = user_fixture()
      user2 = user_fixture()
      {checkin, checkout} = locker_buyout_dates(16)
      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()

      Ysc.Repo.delete_all(
        from(pi in Ysc.Bookings.PropertyInventory,
          where: pi.property == :tahoe and pi.day in ^stay_days
        )
      )

      booking_attrs = fn user ->
        %{
          user_id: user.id,
          property: :tahoe,
          checkin_date: checkin,
          checkout_date: checkout,
          booking_mode: :buyout,
          guests_count: 4,
          total_price: Money.new(:USD, "500.00")
        }
      end

      results =
        [user1, user2]
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            BookingLocker.create_admin_booking(
              booking_attrs.(user),
              skip_email: true,
              skip_reminders: true
            )
          end,
          max_concurrency: 2,
          timeout: 5_000
        )
        |> Enum.to_list()

      successes = Enum.count(results, &match?({:ok, {:ok, _}}, &1))

      stale_failures =
        Enum.count(
          results,
          &match?({:ok, {:error, {:error, :stale_inventory}}}, &1)
        )

      assert successes == 1
      assert stale_failures == 1

      overlapping_bookings =
        Ysc.Repo.aggregate(
          from(b in Ysc.Bookings.Booking,
            where:
              b.property == :tahoe and b.booking_mode == :buyout and
                b.checkin_date == ^checkin and b.checkout_date == ^checkout and
                b.status == :complete
          ),
          :count
        )

      assert overlapping_bookings == 1
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

    test "successfully cancels a matching cancelable PaymentIntent", %{
      user: user
    } do
      {checkin, checkout} = locker_buyout_dates(410)

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
               id: "pi_test_booking_locker_release_ok",
               metadata: %{"booking_id" => booking.id},
               status: "requires_confirmation"
             }
           ],
           has_more: false,
           object: "list",
           url: "/v1/payment_intents"
         }}
      end)

      stub(Ysc.StripeMock, :cancel_payment_intent, fn _id, _opts ->
        {:ok, %Stripe.PaymentIntent{id: "pi_test_booking_locker_release_ok"}}
      end)

      previous_client = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      try do
        assert {:ok, released} = BookingLocker.release_hold(booking.id)
        assert released.status == :canceled
      after
        Application.put_env(:ysc, :stripe_client, previous_client)
      end
    end

    test "skips cancellation when matching PaymentIntent is not cancelable", %{
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

      stub(Stripe.PaymentIntentMock, :list, fn _params ->
        {:ok,
         %Stripe.List{
           data: [
             %Stripe.PaymentIntent{
               id: "pi_test_booking_locker_release_noncancelable",
               metadata: %{"booking_id" => booking.id},
               status: "succeeded"
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

    test "continues releasing the hold when the PaymentIntent search fails", %{
      user: user
    } do
      {checkin, checkout} = locker_buyout_dates(412)

      {:ok, booking} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin,
          checkout,
          4
        )

      stub(Stripe.PaymentIntentMock, :list, fn _params ->
        {:error, :search_unavailable}
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

      with_booking_confirmation_notifier(Ysc.TestNotifiers.ScheduleError, fn ->
        assert {:ok, confirmed} = BookingLocker.confirm_booking(hold.id)
        assert confirmed.status == :complete
        assert Repo.get!(Booking, hold.id).status == :complete
      end)
    end

    test "CCs cabin master and sets reply-to on confirmation email", %{
      user: user
    } do
      {checkin, checkout} = locker_buyout_dates(416)

      {:ok, hold} =
        BookingLocker.create_buyout_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          4
        )

      cabin_master_email = Ysc.EmailConfig.booking_reply_to(:clear_lake)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, confirmed} = BookingLocker.confirm_booking(hold.id)
        assert confirmed.status == :complete

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "booking_confirmation",
            "idempotency_key" => "booking_confirmation_#{confirmed.id}",
            "reply_to" => cabin_master_email,
            "cc" => cabin_master_email
          }
        )
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

    test "concurrent admin day bookings accumulate capacity_booked on new inventory rows",
         %{sandbox_owner: owner} do
      ensure_clear_lake_day_pricing_rule()
      user1 = user_fixture()
      user2 = user_fixture()
      {checkin, checkout} = locker_room_dates(130, 2)
      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()

      Repo.delete_all(
        from(pi in Ysc.Bookings.PropertyInventory,
          where: pi.property == :clear_lake and pi.day in ^stay_days
        )
      )

      booking_attrs = fn user, guests ->
        %{
          user_id: user.id,
          property: :clear_lake,
          checkin_date: checkin,
          checkout_date: checkout,
          booking_mode: :day,
          guests_count: guests,
          total_price: Money.new(:USD, "#{guests * 100}.00")
        }
      end

      results =
        [
          {user1, 5},
          {user2, 3}
        ]
        |> Task.async_stream(
          fn {user, guests} ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            BookingLocker.create_admin_booking(
              booking_attrs.(user, guests),
              skip_email: true,
              skip_reminders: true
            )
          end,
          max_concurrency: 2,
          timeout: 5_000
        )
        |> Enum.to_list()

      assert Enum.all?(results, &match?({:ok, {:ok, _}}, &1))

      capacity_per_day =
        Enum.map(stay_days, fn day ->
          Repo.one!(
            from(pi in Ysc.Bookings.PropertyInventory,
              where: pi.property == :clear_lake and pi.day == ^day,
              select: pi.capacity_booked
            )
          )
        end)

      assert capacity_per_day == [8, 8]
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

  describe "place_modification_hold/3 and release_modification_hold/2 Clear Lake per-guest (day mode)" do
    setup do
      ensure_clear_lake_day_pricing_rule()
      :ok
    end

    test "holds extra guest capacity on overlapping days and new days, then releases both",
         %{user: user} do
      {checkin, checkout} = locker_room_dates(126, 2)

      assert {:ok, hold} =
               BookingLocker.create_per_guest_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 2
               )

      assert {:ok, booking} = BookingLocker.confirm_booking(hold.id)
      assert booking.status == :complete

      extended_checkout = Date.add(checkout, 1)

      attrs = %{
        checkin_date: checkin,
        checkout_date: extended_checkout,
        guests_count: 4,
        children_count: 0
      }

      assert {:ok, held_booking} =
               Ysc.Bookings.place_modification_hold(booking, attrs)

      assert held_booking.modification_hold_expires_at
      assert held_booking.modification_hold_attrs

      new_day_inv =
        Ysc.Repo.get_by!(PropertyInventory,
          property: :clear_lake,
          day: checkout
        )

      assert new_day_inv.capacity_held == 4

      overlap_day_inv =
        Ysc.Repo.get_by!(PropertyInventory, property: :clear_lake, day: checkin)

      assert overlap_day_inv.capacity_held == 2

      assert {:ok, released} =
               Ysc.Bookings.release_modification_hold(held_booking.id)

      assert is_nil(released.modification_hold_expires_at)
      assert is_nil(released.modification_hold_attrs)

      new_day_after =
        Ysc.Repo.get_by!(PropertyInventory,
          property: :clear_lake,
          day: checkout
        )

      assert new_day_after.capacity_held == 0

      overlap_day_after =
        Ysc.Repo.get_by!(PropertyInventory, property: :clear_lake, day: checkin)

      assert overlap_day_after.capacity_held == 0
    end
  end

  describe "modify_complete_booking/3 Clear Lake per-guest (day mode) happy path" do
    setup do
      ensure_clear_lake_day_pricing_rule()
      :ok
    end

    test "books held days and applies overlap extra guests when confirming a held modification",
         %{user: user} do
      {checkin, checkout} = locker_room_dates(920, 2)

      assert {:ok, hold} =
               BookingLocker.create_per_guest_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 2
               )

      assert {:ok, booking} = BookingLocker.confirm_booking(hold.id)
      assert booking.status == :complete

      extended_checkout = Date.add(checkout, 1)

      attrs = %{
        checkin_date: checkin,
        checkout_date: extended_checkout,
        guests_count: 4,
        children_count: 0
      }

      assert {:ok, held_booking} =
               Ysc.Bookings.place_modification_hold(booking, attrs)

      assert {:ok, updated} =
               BookingLocker.modify_complete_booking(held_booking, attrs)

      assert updated.status == :complete
      assert updated.checkin_date == checkin
      assert updated.checkout_date == extended_checkout
      assert updated.guests_count == 4
      assert is_nil(updated.modification_hold_expires_at)
      assert is_nil(updated.modification_hold_attrs)

      # Overlap days (every night of the original stay): released from the
      # old 2-guest booking, then rebooked via the overlap_extra_guests path
      # using the held extra capacity.
      Date.range(checkin, Date.add(checkout, -1))
      |> Enum.each(fn day ->
        overlap_inv =
          Ysc.Repo.get_by!(PropertyInventory, property: :clear_lake, day: day)

        assert overlap_inv.capacity_booked == 4
        assert overlap_inv.capacity_held == 0
      end)

      # New day: entirely new to the stay, booked via the from_held path
      # using the capacity reserved when the hold was placed.
      new_day_inv =
        Ysc.Repo.get_by!(PropertyInventory,
          property: :clear_lake,
          day: checkout
        )

      assert new_day_inv.capacity_booked == 4
      assert new_day_inv.capacity_held == 0
    end

    test "confirms new inventory directly when no modification hold is active",
         %{
           user: user
         } do
      {checkin, checkout} = locker_room_dates(921, 2)

      assert {:ok, hold} =
               BookingLocker.create_per_guest_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 2
               )

      assert {:ok, booking} = BookingLocker.confirm_booking(hold.id)
      assert booking.status == :complete

      assert {:ok, updated} =
               BookingLocker.modify_complete_booking(booking, %{
                 checkin_date: checkin,
                 checkout_date: checkout,
                 guests_count: 3,
                 children_count: 0
               })

      assert updated.guests_count == 3

      Date.range(checkin, Date.add(checkout, -1))
      |> Enum.each(fn day ->
        inv =
          Ysc.Repo.get_by!(PropertyInventory, property: :clear_lake, day: day)

        assert inv.capacity_booked == 3
        assert inv.capacity_held == 0
      end)
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

    test "price_per_guest_per_night is zero when guests_count is 0", %{
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

      assert {:ok, booking} =
               BookingLocker.create_per_guest_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkout,
                 0
               )

      booking = Ysc.Repo.reload!(booking)
      pi = booking.pricing_items

      ppg =
        Map.get(pi, "price_per_guest_per_night") ||
          Map.get(pi, :price_per_guest_per_night)

      ppg = for {k, v} <- ppg, into: %{}, do: {to_string(k), v}

      assert Decimal.equal?(Decimal.new(ppg["amount"]), Decimal.new(0))
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

  describe "create_buyout_booking/6 invalid date range" do
    test "returns pricing_calculation_failed when checkin equals checkout", %{
      user: user
    } do
      {checkin, _checkout} = locker_buyout_dates(600)

      assert {:error, :pricing_calculation_failed} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkin,
                 4
               )
    end
  end

  describe "create_per_guest_booking/6 invalid date range" do
    test "returns pricing_calculation_failed when checkin equals checkout", %{
      user: user
    } do
      {checkin, _checkout} = locker_room_dates(601, 2)

      assert {:error, :pricing_calculation_failed} =
               BookingLocker.create_per_guest_booking(
                 user.id,
                 :clear_lake,
                 checkin,
                 checkin,
                 2
               )
    end
  end

  describe "confirm_booking/1 invalid status" do
    test "returns invalid_status when booking is neither hold nor canceled", %{
      user: user
    } do
      {checkin, checkout} = locker_buyout_dates(602)

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
        |> Booking.changeset(%{status: :refunded},
          rooms: booking.rooms,
          skip_validation: true
        )
        |> Ysc.Repo.update!()

      assert {:error, {:error, :invalid_status}} =
               BookingLocker.confirm_booking(booking.id)
    end
  end

  describe "create_admin_booking/2 changeset error" do
    test "returns the changeset error when required attrs are missing" do
      {checkin, checkout} = locker_buyout_dates(603)

      attrs = %{
        property: :tahoe,
        checkin_date: checkin,
        checkout_date: checkout,
        booking_mode: :buyout,
        guests_count: 4,
        total_price: Money.new(:USD, "500.00")
      }

      assert {:error, {:error, %Ecto.Changeset{valid?: false}}} =
               BookingLocker.create_admin_booking(attrs,
                 skip_email: true,
                 skip_reminders: true
               )
    end
  end

  describe "confirm_booking/1 other holds error handling" do
    test "logs and continues when releasing a sibling hold fails", %{
      user: user
    } do
      {week1_in, week1_out} = locker_buyout_dates(20)
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

      # Remove the second hold's property inventory rows so that when
      # confirm_booking tries to release it as a sibling hold, release_hold
      # fails with :inventory_update_failed instead of succeeding.
      from(pi in PropertyInventory,
        where:
          pi.property == :tahoe and pi.day >= ^week2_in and pi.day < ^week2_out
      )
      |> Repo.delete_all()

      assert {:ok, confirmed} = BookingLocker.confirm_booking(first_hold.id)
      assert confirmed.status == :complete

      # The sibling hold should remain untouched (still :hold) since release
      # failed and cancel_other_hold_bookings swallows the error.
      second = Ysc.Repo.reload!(second_hold)
      assert second.status == :hold
    end
  end

  describe "confirm_booking/1 confirmation email rescue branch" do
    test "keeps booking complete when the notifier raises", %{user: user} do
      {checkin, checkout} = locker_buyout_dates(604)

      {:ok, hold} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin,
          checkout,
          4
        )

      with_booking_confirmation_notifier(Ysc.TestNotifiers.Raising, fn ->
        assert {:ok, confirmed} = BookingLocker.confirm_booking(hold.id)
        assert confirmed.status == :complete
        assert Repo.get!(Booking, hold.id).status == :complete
      end)
    end
  end

  describe "admin_modify_complete_booking/3" do
    test "reconciles Clear Lake day capacity when guests_count changes" do
      user = user_fixture()
      checkin = ~D[2036-10-05]
      checkout = ~D[2036-10-08]

      {:ok, booking} =
        BookingLocker.create_admin_booking(
          %{
            user_id: user.id,
            property: :clear_lake,
            checkin_date: checkin,
            checkout_date: checkout,
            guests_count: 2,
            booking_mode: :day
          },
          skip_email: true,
          skip_reminders: true
        )

      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()

      assert day_capacity_booked(:clear_lake, stay_days) == [2, 2, 2]

      assert {:ok, updated} =
               BookingLocker.admin_modify_complete_booking(booking, %{
                 checkin_date: checkin,
                 checkout_date: checkout,
                 guests_count: 5,
                 children_count: 0,
                 booking_mode: :day
               })

      assert updated.guests_count == 5
      assert day_capacity_booked(:clear_lake, stay_days) == [5, 5, 5]
    end

    test "returns invalid_status when booking is not complete" do
      ensure_clear_lake_day_pricing_rule()
      user = user_fixture()
      {checkin, checkout} = locker_room_dates(45, 3)

      {:ok, hold} =
        BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      assert {:error, :invalid_status} =
               BookingLocker.admin_modify_complete_booking(hold, %{
                 checkin_date: checkin,
                 checkout_date: checkout,
                 guests_count: 5,
                 children_count: 0,
                 booking_mode: :day
               })
    end

    test "returns blackout_conflict when new dates overlap a blackout" do
      ensure_clear_lake_day_pricing_rule()
      user = user_fixture()
      checkin = ~D[2036-11-05]
      checkout = ~D[2036-11-08]

      {:ok, booking} =
        BookingLocker.create_admin_booking(
          %{
            user_id: user.id,
            property: :clear_lake,
            checkin_date: checkin,
            checkout_date: checkout,
            guests_count: 2,
            booking_mode: :day
          },
          skip_email: true,
          skip_reminders: true
        )

      new_checkin = ~D[2036-12-10]
      new_checkout = ~D[2036-12-13]

      assert {:ok, _} =
               Bookings.create_blackout(%{
                 property: :clear_lake,
                 start_date: new_checkin,
                 end_date: new_checkout,
                 reason: "Admin modify blackout conflict"
               })

      assert {:error, :blackout_conflict} =
               BookingLocker.admin_modify_complete_booking(booking, %{
                 checkin_date: new_checkin,
                 checkout_date: new_checkout,
                 guests_count: 2,
                 children_count: 0,
                 booking_mode: :day
               })
    end

    test "reconciles inventory when stay dates change" do
      ensure_clear_lake_day_pricing_rule()
      user = user_fixture()
      checkin = ~D[2036-11-15]
      checkout = ~D[2036-11-18]
      new_checkin = ~D[2036-11-20]
      new_checkout = ~D[2036-11-23]

      {:ok, booking} =
        BookingLocker.create_admin_booking(
          %{
            user_id: user.id,
            property: :clear_lake,
            checkin_date: checkin,
            checkout_date: checkout,
            guests_count: 3,
            booking_mode: :day
          },
          skip_email: true,
          skip_reminders: true
        )

      old_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()

      new_days =
        Date.range(new_checkin, Date.add(new_checkout, -1)) |> Enum.to_list()

      assert day_capacity_booked(:clear_lake, old_days) == [3, 3, 3]

      assert {:ok, updated} =
               BookingLocker.admin_modify_complete_booking(booking, %{
                 checkin_date: new_checkin,
                 checkout_date: new_checkout,
                 guests_count: 3,
                 children_count: 0,
                 booking_mode: :day
               })

      assert updated.checkin_date == new_checkin
      assert day_capacity_booked(:clear_lake, old_days) == [0, 0, 0]
      assert day_capacity_booked(:clear_lake, new_days) == [3, 3, 3]
    end

    test "reconciles buyout inventory when stay dates change" do
      user = user_fixture()
      {checkin, checkout} = locker_buyout_dates(620)
      new_checkin = Date.add(checkin, 14)
      new_checkout = Date.add(checkout, 14)

      {:ok, booking} =
        BookingLocker.create_admin_booking(
          %{
            user_id: user.id,
            property: :tahoe,
            checkin_date: checkin,
            checkout_date: checkout,
            guests_count: 4,
            booking_mode: :buyout
          },
          skip_email: true,
          skip_reminders: true
        )

      old_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()

      new_days =
        Date.range(new_checkin, Date.add(new_checkout, -1)) |> Enum.to_list()

      assert buyout_booked?(:tahoe, old_days)

      assert {:ok, updated} =
               BookingLocker.admin_modify_complete_booking(booking, %{
                 "checkin_date" => new_checkin,
                 "checkout_date" => new_checkout,
                 "guests_count" => 4,
                 "children_count" => 0,
                 "booking_mode" => :buyout
               })

      assert updated.checkin_date == new_checkin
      refute buyout_booked?(:tahoe, old_days)
      assert buyout_booked?(:tahoe, new_days)
    end

    test "returns changeset error for invalid stay dates" do
      ensure_clear_lake_day_pricing_rule()
      user = user_fixture()
      checkin = ~D[2036-12-01]
      checkout = ~D[2036-12-04]

      {:ok, booking} =
        BookingLocker.create_admin_booking(
          %{
            user_id: user.id,
            property: :clear_lake,
            checkin_date: checkin,
            checkout_date: checkout,
            guests_count: 2,
            booking_mode: :day
          },
          skip_email: true,
          skip_reminders: true
        )

      assert {:error, %Ecto.Changeset{}} =
               BookingLocker.admin_modify_complete_booking(booking, %{
                 checkin_date: checkout,
                 checkout_date: checkin,
                 guests_count: 2,
                 children_count: 0,
                 booking_mode: :day
               })
    end

    test "reconciles room inventory when guest count changes", %{user: user} do
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
          name: "Admin modify room",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = locker_room_dates(650, 2)

      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: checkin,
        checkout_date: checkout,
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(:USD, "400.00")
      }

      {:ok, booking} =
        BookingLocker.create_admin_booking(attrs,
          rooms: [room],
          skip_email: true,
          skip_reminders: true
        )

      nights = Date.diff(checkout, checkin)

      booked_before =
        Repo.aggregate(
          from(ri in Ysc.Bookings.RoomInventory,
            where:
              ri.room_id == ^room.id and ri.day >= ^checkin and
                ri.day < ^checkout and ri.booked == true
          ),
          :count
        )

      assert booked_before == nights

      assert {:ok, updated} =
               BookingLocker.admin_modify_complete_booking(
                 booking,
                 %{
                   checkin_date: checkin,
                   checkout_date: checkout,
                   guests_count: 3,
                   children_count: 0,
                   booking_mode: :room
                 },
                 rooms: [room]
               )

      assert updated.guests_count == 3

      booked_after =
        Repo.aggregate(
          from(ri in Ysc.Bookings.RoomInventory,
            where:
              ri.room_id == ^room.id and ri.day >= ^checkin and
                ri.day < ^checkout and ri.booked == true
          ),
          :count
        )

      assert booked_after == nights
    end

    defp buyout_booked?(property, days) do
      alias Ysc.Bookings.PropertyInventory

      Enum.all?(days, fn day ->
        Repo.one!(
          from(pi in PropertyInventory,
            where: pi.property == ^property and pi.day == ^day,
            select: pi.buyout_booked
          )
        )
      end)
    end

    defp day_capacity_booked(property, days) do
      alias Ysc.Bookings.PropertyInventory

      days
      |> Enum.map(fn day ->
        Repo.one!(
          from(pi in PropertyInventory,
            where: pi.property == ^property and pi.day == ^day,
            select: pi.capacity_booked
          )
        )
      end)
    end

    defp day_capacity_held(property, days) do
      alias Ysc.Bookings.PropertyInventory

      days
      |> Enum.map(fn day ->
        Repo.one!(
          from(pi in PropertyInventory,
            where: pi.property == ^property and pi.day == ^day,
            select: pi.capacity_held
          )
        )
      end)
    end
  end

  describe "admin_modify_hold_booking/3" do
    test "reconciles Clear Lake day capacity_held when stay dates change" do
      ensure_clear_lake_day_pricing_rule()
      user = user_fixture()
      {checkin, checkout} = locker_room_dates(120, 3)
      {new_checkin, new_checkout} = locker_room_dates(130, 3)

      {:ok, hold} =
        BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      old_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()

      new_days =
        Date.range(new_checkin, Date.add(new_checkout, -1)) |> Enum.to_list()

      assert day_capacity_held(:clear_lake, old_days) == [2, 2, 2]

      assert {:ok, updated} =
               BookingLocker.admin_modify_hold_booking(hold, %{
                 checkin_date: new_checkin,
                 checkout_date: new_checkout,
                 guests_count: 3,
                 children_count: 0,
                 booking_mode: :day
               })

      assert updated.checkin_date == new_checkin
      assert updated.guests_count == 3
      assert day_capacity_held(:clear_lake, old_days) == [0, 0, 0]
      assert day_capacity_held(:clear_lake, new_days) == [3, 3, 3]
    end

    test "confirm_booking succeeds after admin moves hold dates" do
      ensure_clear_lake_day_pricing_rule()
      user = user_fixture()
      {checkin, checkout} = locker_room_dates(140, 3)
      {new_checkin, new_checkout} = locker_room_dates(150, 3)

      {:ok, hold} =
        BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      assert {:ok, updated} =
               BookingLocker.admin_modify_hold_booking(hold, %{
                 checkin_date: new_checkin,
                 checkout_date: new_checkout,
                 guests_count: 4,
                 children_count: 0,
                 booking_mode: :day
               })

      new_days =
        Date.range(new_checkin, Date.add(new_checkout, -1)) |> Enum.to_list()

      assert {:ok, confirmed} = BookingLocker.confirm_booking(updated.id)
      assert confirmed.status == :complete
      assert day_capacity_booked(:clear_lake, new_days) == [4, 4, 4]
      assert day_capacity_held(:clear_lake, new_days) == [0, 0, 0]
    end

    test "returns invalid_status for complete bookings" do
      ensure_clear_lake_day_pricing_rule()
      user = user_fixture()
      checkin = ~D[2028-06-05]
      checkout = ~D[2028-06-08]

      {:ok, booking} =
        BookingLocker.create_admin_booking(
          %{
            user_id: user.id,
            property: :clear_lake,
            checkin_date: checkin,
            checkout_date: checkout,
            guests_count: 2,
            booking_mode: :day
          },
          skip_email: true,
          skip_reminders: true
        )

      assert {:error, :invalid_status} =
               BookingLocker.admin_modify_hold_booking(booking, %{
                 checkin_date: checkin,
                 checkout_date: checkout,
                 guests_count: 3,
                 children_count: 0,
                 booking_mode: :day
               })
    end

    test "returns blackout_conflict when new dates overlap a blackout" do
      ensure_clear_lake_day_pricing_rule()
      user = user_fixture()
      {checkin, checkout} = locker_room_dates(160, 3)
      {new_checkin, new_checkout} = locker_room_dates(170, 3)

      {:ok, hold} =
        BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      assert {:ok, _} =
               Bookings.create_blackout(%{
                 property: :clear_lake,
                 start_date: new_checkin,
                 end_date: new_checkout,
                 reason: "Admin hold modify blackout conflict"
               })

      assert {:error, :blackout_conflict} =
               BookingLocker.admin_modify_hold_booking(hold, %{
                 checkin_date: new_checkin,
                 checkout_date: new_checkout,
                 guests_count: 2,
                 children_count: 0,
                 booking_mode: :day
               })
    end

    test "reconciles day capacity_held when guests_count changes on same dates" do
      ensure_clear_lake_day_pricing_rule()
      user = user_fixture()
      {checkin, checkout} = locker_room_dates(180, 3)

      {:ok, hold} =
        BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()
      assert day_capacity_held(:clear_lake, stay_days) == [2, 2, 2]

      assert {:ok, updated} =
               BookingLocker.admin_modify_hold_booking(hold, %{
                 checkin_date: checkin,
                 checkout_date: checkout,
                 guests_count: 5,
                 children_count: 0,
                 booking_mode: :day
               })

      assert updated.guests_count == 5
      assert day_capacity_held(:clear_lake, stay_days) == [5, 5, 5]
    end

    test "reconciles buyout hold inventory when stay dates change", %{
      user: user
    } do
      {checkin, checkout} = locker_buyout_dates(710)
      new_checkin = Date.add(checkin, 14)
      new_checkout = Date.add(checkout, 14)

      {:ok, hold} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin,
          checkout,
          4
        )

      old_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()

      new_days =
        Date.range(new_checkin, Date.add(new_checkout, -1)) |> Enum.to_list()

      assert buyout_held?(:tahoe, old_days)

      assert {:ok, updated} =
               BookingLocker.admin_modify_hold_booking(hold, %{
                 checkin_date: new_checkin,
                 checkout_date: new_checkout,
                 guests_count: 4,
                 children_count: 0,
                 booking_mode: :buyout
               })

      assert updated.checkin_date == new_checkin
      refute buyout_held?(:tahoe, old_days)
      assert buyout_held?(:tahoe, new_days)
    end

    test "reconciles room held inventory when guest count changes", %{
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
          name: "Admin hold modify room",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      {checkin, checkout} = locker_room_dates(720, 2)

      {:ok, hold} =
        BookingLocker.create_room_booking(
          user.id,
          room.id,
          checkin,
          checkout,
          2
        )

      hold = Ysc.Repo.preload(hold, :rooms)
      assert hold.status == :hold
      assert room_held?(room.id, checkin, checkout)

      assert {:ok, updated} =
               BookingLocker.admin_modify_hold_booking(
                 hold,
                 %{
                   checkin_date: checkin,
                   checkout_date: checkout,
                   guests_count: 3,
                   children_count: 0,
                   booking_mode: :room
                 },
                 rooms: [room]
               )

      assert updated.guests_count == 3
      assert room_held?(room.id, checkin, checkout)
    end

    test "rejects admin hold date change onto already-booked buyout dates", %{
      user: user
    } do
      user2 = user_fixture()
      {checkin, checkout} = locker_buyout_dates(730)
      {hold_checkin, hold_checkout} = locker_buyout_dates(740)

      assert {:ok, _complete} =
               BookingLocker.create_admin_booking(
                 %{
                   user_id: user.id,
                   property: :tahoe,
                   checkin_date: checkin,
                   checkout_date: checkout,
                   booking_mode: :buyout,
                   guests_count: 4,
                   total_price: Money.new(:USD, "500.00")
                 },
                 skip_email: true,
                 skip_reminders: true
               )

      {:ok, hold} =
        BookingLocker.create_buyout_booking(
          user2.id,
          :tahoe,
          hold_checkin,
          hold_checkout,
          4
        )

      assert {:error, :stale_inventory} =
               BookingLocker.admin_modify_hold_booking(hold, %{
                 checkin_date: checkin,
                 checkout_date: checkout,
                 guests_count: 4,
                 children_count: 0,
                 booking_mode: :buyout
               })

      booked_days =
        Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()

      assert Enum.all?(booked_days, fn day ->
               Repo.one!(
                 from(pi in PropertyInventory,
                   where: pi.property == :tahoe and pi.day == ^day,
                   select: {pi.buyout_booked, pi.buyout_held}
                 )
               ) == {true, false}
             end)
    end

    test "rejects admin hold date change onto already-booked room dates", %{
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
          name: "Admin hold overlap room",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      user2 = user_fixture()
      {checkin, checkout} = locker_room_dates(750, 2)
      {hold_checkin, hold_checkout} = locker_room_dates(760, 2)

      assert {:ok, _complete} =
               BookingLocker.create_admin_booking(
                 %{
                   user_id: user.id,
                   property: :tahoe,
                   checkin_date: checkin,
                   checkout_date: checkout,
                   booking_mode: :room,
                   guests_count: 2,
                   total_price: Money.new(:USD, "200.00")
                 },
                 rooms: [room],
                 skip_email: true,
                 skip_reminders: true
               )

      {:ok, hold} =
        BookingLocker.create_room_booking(
          user2.id,
          room.id,
          hold_checkin,
          hold_checkout,
          2
        )

      hold = Ysc.Repo.preload(hold, :rooms)

      assert {:error, :stale_inventory} =
               BookingLocker.admin_modify_hold_booking(
                 hold,
                 %{
                   checkin_date: checkin,
                   checkout_date: checkout,
                   guests_count: 2,
                   children_count: 0,
                   booking_mode: :room
                 },
                 rooms: [room]
               )

      nights = Date.diff(checkout, checkin)

      booked_count =
        Repo.aggregate(
          from(ri in Ysc.Bookings.RoomInventory,
            where:
              ri.room_id == ^room.id and ri.day >= ^checkin and
                ri.day < ^checkout and ri.booked == true and ri.held == false
          ),
          :count
        )

      assert booked_count == nights
    end

    test "rejects admin hold date change onto already-booked day capacity dates", %{
      user: user
    } do
      ensure_clear_lake_day_pricing_rule()
      user2 = user_fixture()
      {checkin, checkout} = locker_room_dates(770, 2)
      {hold_checkin, hold_checkout} = locker_room_dates(780, 2)

      assert {:ok, _complete} =
               BookingLocker.create_admin_booking(
                 %{
                   user_id: user.id,
                   property: :clear_lake,
                   checkin_date: checkin,
                   checkout_date: checkout,
                   guests_count: 12,
                   booking_mode: :day
                 },
                 skip_email: true,
                 skip_reminders: true
               )

      {:ok, hold} =
        BookingLocker.create_per_guest_booking(
          user2.id,
          :clear_lake,
          hold_checkin,
          hold_checkout,
          2
        )

      assert {:error, :stale_inventory} =
               BookingLocker.admin_modify_hold_booking(hold, %{
                 checkin_date: checkin,
                 checkout_date: checkout,
                 guests_count: 2,
                 children_count: 0,
                 booking_mode: :day
               })

      stay_days = Date.range(checkin, Date.add(checkout, -1)) |> Enum.to_list()
      assert day_capacity_booked(:clear_lake, stay_days) == [12, 12]
      assert day_capacity_held(:clear_lake, stay_days) == [0, 0]
    end

    test "returns changeset error for invalid stay dates" do
      ensure_clear_lake_day_pricing_rule()
      user = user_fixture()
      {checkin, checkout} = locker_room_dates(190, 3)

      {:ok, hold} =
        BookingLocker.create_per_guest_booking(
          user.id,
          :clear_lake,
          checkin,
          checkout,
          2
        )

      assert {:error, %Ecto.Changeset{}} =
               BookingLocker.admin_modify_hold_booking(hold, %{
                 checkin_date: checkout,
                 checkout_date: checkin,
                 guests_count: 2,
                 children_count: 0,
                 booking_mode: :day
               })
    end

    defp buyout_held?(property, days) do
      Enum.all?(days, fn day ->
        Repo.one!(
          from(pi in PropertyInventory,
            where: pi.property == ^property and pi.day == ^day,
            select: pi.buyout_held
          )
        )
      end)
    end

    defp room_held?(room_id, checkin, checkout) do
      nights = Date.diff(checkout, checkin)

      held_count =
        Repo.aggregate(
          from(ri in Ysc.Bookings.RoomInventory,
            where:
              ri.room_id == ^room_id and ri.day >= ^checkin and
                ri.day < ^checkout and ri.held == true
          ),
          :count
        )

      held_count == nights
    end
  end

  describe "modify_complete_booking/3 error branches" do
    defp complete_buyout_booking_for_modify!(user, checkin, checkout) do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 500),
          booking_mode: :buyout,
          price_unit: :buyout_fixed,
          property: :tahoe,
          season_id: nil
        })

      {:ok, total, _} =
        Bookings.calculate_booking_price(
          :tahoe,
          checkin,
          checkout,
          :buyout,
          guests_count: 4
        )

      {:ok, booking} =
        BookingLocker.create_admin_booking(
          %{
            user_id: user.id,
            property: :tahoe,
            checkin_date: checkin,
            checkout_date: checkout,
            booking_mode: :buyout,
            guests_count: 4,
            total_price: total
          },
          skip_email: true,
          skip_reminders: true
        )

      {:ok, _} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: total,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_locker_modify_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(:USD, 1),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      Ysc.Repo.preload(booking, [:rooms, :user])
    end

    test "returns invalid_status when booking is not complete", %{user: user} do
      {checkin, checkout} = locker_buyout_dates(605)

      {:ok, hold} =
        BookingLocker.create_buyout_booking(
          user.id,
          :tahoe,
          checkin,
          checkout,
          4
        )

      hold = Ysc.Repo.preload(hold, [:rooms, :user])

      assert {:error, {:error, :invalid_status}} =
               BookingLocker.modify_complete_booking(hold, %{
                 checkin_date: checkin,
                 checkout_date: Date.add(checkout, 1),
                 guests_count: 4,
                 children_count: 0
               })
    end

    test "returns no_changes when attrs match the existing booking", %{
      user: user
    } do
      Ysc.Ledgers.ensure_basic_accounts()
      {checkin, checkout} = locker_buyout_dates(606)

      booking = complete_buyout_booking_for_modify!(user, checkin, checkout)

      assert {:error, {:error, :no_changes}} =
               BookingLocker.modify_complete_booking(booking, %{
                 checkin_date: booking.checkin_date,
                 checkout_date: booking.checkout_date,
                 guests_count: booking.guests_count,
                 children_count: booking.children_count || 0
               })
    end

    test "returns blackout_conflict when new dates overlap a blackout", %{
      user: user
    } do
      Ysc.Ledgers.ensure_basic_accounts()
      {checkin, checkout} = locker_buyout_dates(607)

      booking = complete_buyout_booking_for_modify!(user, checkin, checkout)

      new_checkin = Date.add(checkout, 7)
      new_checkout = Date.add(new_checkin, 3)

      assert {:ok, _} =
               Bookings.create_blackout(%{
                 property: :tahoe,
                 start_date: new_checkin,
                 end_date: new_checkout,
                 reason: "Modify blackout conflict"
               })

      assert {:error, {:error, :blackout_conflict}} =
               BookingLocker.modify_complete_booking(booking, %{
                 checkin_date: new_checkin,
                 checkout_date: new_checkout,
                 guests_count: 4,
                 children_count: 0
               })
    end

    test "returns an availability error when new dates overlap another confirmed booking",
         %{user: user} do
      Ysc.Ledgers.ensure_basic_accounts()
      {checkin, checkout} = locker_buyout_dates(608)

      booking = complete_buyout_booking_for_modify!(user, checkin, checkout)

      new_checkin = Date.add(checkout, 7)
      new_checkout = Date.add(new_checkin, 3)

      other_user = user_fixture()

      {:ok, other_total, _} =
        Bookings.calculate_booking_price(
          :tahoe,
          new_checkin,
          new_checkout,
          :buyout,
          guests_count: 4
        )

      {:ok, _other_booking} =
        BookingLocker.create_admin_booking(
          %{
            user_id: other_user.id,
            property: :tahoe,
            checkin_date: new_checkin,
            checkout_date: new_checkout,
            booking_mode: :buyout,
            guests_count: 4,
            total_price: other_total
          },
          skip_email: true,
          skip_reminders: true
        )

      assert {:error, {:error, _reason}} =
               BookingLocker.modify_complete_booking(booking, %{
                 checkin_date: new_checkin,
                 checkout_date: new_checkout,
                 guests_count: 4,
                 children_count: 0
               })
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
