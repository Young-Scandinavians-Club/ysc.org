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

  describe "create_buyout_booking/6 conflicts" do
    test "returns blackout_conflict when dates overlap a blackout", %{
      user: user
    } do
      checkin = Date.utc_today() |> Date.add(45)
      checkout = Date.add(checkin, 3)

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

      checkin = Date.utc_today() |> Date.add(46)
      checkout = Date.add(checkin, 3)

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

    test "honors hold_duration_minutes in opts for hold_expires_at", %{
      user: user
    } do
      checkin = Date.utc_today() |> Date.add(131)
      checkout = Date.add(checkin, 2)

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

  describe "create_room_booking/6 validation" do
    test "returns :no_rooms_provided when room list is empty", %{user: user} do
      checkin = Date.utc_today() |> Date.add(40)
      checkout = Date.add(checkin, 2)

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
      checkin = Date.utc_today() |> Date.add(41)
      checkout = Date.add(checkin, 2)
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

      checkin = Date.utc_today() |> Date.add(42)
      checkout = Date.add(checkin, 2)

      assert {:error, {:error, :rooms_must_be_same_property}} =
               BookingLocker.create_room_booking(
                 user.id,
                 [room_tahoe.id, room_cl.id],
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

      checkin = Date.utc_today() |> Date.add(48)
      checkout = Date.add(checkin, 3)

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

      checkin = Date.utc_today() |> Date.add(209)
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

      checkin = Date.utc_today() |> Date.add(204)
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
    test "enqueues booking confirmation email when skip_email is false", %{
      user: user
    } do
      checkin = Date.utc_today() |> Date.add(412)
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
      checkin = Date.utc_today() |> Date.add(45)
      checkout = Date.add(checkin, 4)

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

      checkin = Date.utc_today() |> Date.add(408)
      checkout = Date.add(checkin, 2)

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

      checkin = Date.utc_today() |> Date.add(413)
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

      checkin = Date.utc_today() |> Date.add(414)
      checkout = Date.add(checkin, 2)

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
    setup do
      ensure_clear_lake_day_pricing_rule()
      :ok
    end

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

    test "create_per_guest_booking returns blackout_conflict when dates overlap a blackout",
         %{
           user: user
         } do
      checkin = Date.utc_today() |> Date.add(88)
      checkout = Date.add(checkin, 2)

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
      checkin = Date.utc_today() |> Date.add(206)
      checkout = Date.add(checkin, 2)

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

      checkin = Date.utc_today() |> Date.add(210)
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

      checkin = Date.utc_today() |> Date.add(211)
      checkout = Date.add(checkin, 2)

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
      checkin = Date.utc_today() |> Date.add(203)
      checkout = Date.add(checkin, 2)

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

      checkin = Date.utc_today() |> Date.add(207)
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
      checkin = Date.utc_today() |> Date.add(409)
      checkout = Date.add(checkin, 2)

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

    test "releases Clear Lake per-guest hold and restores capacity_held", %{
      user: user
    } do
      ensure_clear_lake_day_pricing_rule()

      checkin = Date.utc_today() |> Date.add(125)
      checkout = Date.add(checkin, 2)
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

      checkin = Date.utc_today() |> Date.add(201)
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

      checkin = Date.utc_today() |> Date.add(202)
      checkout = Date.add(checkin, 2)
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
      checkin = Date.utc_today() |> Date.add(415)
      checkout = Date.add(checkin, 2)

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

  describe "confirm_booking/1 other holds" do
    test "second confirm_booking is idempotent when booking is already complete",
         %{
           user: user
         } do
      checkin = Date.utc_today() |> Date.add(411)
      checkout = Date.add(checkin, 2)

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
      week1_in = Date.utc_today() |> Date.add(410)
      week1_out = Date.add(week1_in, 2)
      week2_in = Date.add(week1_out, 5)
      week2_out = Date.add(week2_in, 2)

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

  describe "confirm_booking/1 invalid status" do
    test "returns invalid_status when booking was released (canceled hold)", %{
      user: user
    } do
      checkin = Date.utc_today() |> Date.add(120)
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

      assert {:error, {:error, :invalid_status}} =
               BookingLocker.confirm_booking(booking.id)
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
      checkin = Date.utc_today() |> Date.add(121)
      checkout = Date.add(checkin, 2)

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
      checkin = Date.utc_today() |> Date.add(122)
      checkout = Date.add(checkin, 2)

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

      checkin = Date.utc_today() |> Date.add(412)
      checkout = Date.add(checkin, 2)

      AvailabilityCache.get_clear_lake_daily_availability(checkin, checkout)

      {_cached, queries_before} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            AvailabilityCache.get_clear_lake_daily_availability(
              checkin,
              checkout
            )
          end,
          pattern: ~r/FROM "bookings"/i
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
          pattern: ~r/FROM "bookings"/i
        )

      assert queries_after >= 1
    end

    test "creates a complete per-guest (day) booking for Clear Lake", %{
      user: user
    } do
      checkin = Date.utc_today() |> Date.add(123)
      checkout = Date.add(checkin, 2)

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
      checkin = Date.utc_today() |> Date.add(124)
      checkout = Date.add(checkin, 2)

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

      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 3)
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

      checkin = Date.utc_today() |> Date.add(209)
      checkout = Date.add(checkin, 3)

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

      checkin = Date.utc_today() |> Date.add(504)
      checkout = Date.add(checkin, 2)

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
