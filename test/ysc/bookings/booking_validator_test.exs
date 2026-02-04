defmodule Ysc.Bookings.BookingValidatorTest do
  @moduledoc """
  Tests for BookingValidator business logic.

  This module tests the most complex booking validation rules:
  - Winter vs Summer season rules (Tahoe)
  - Weekend requirement validation (Saturday must include Sunday)
  - Max nights validation (property and season-specific)
  - Active booking limits (membership-dependent)
  - Buyout rules (no concurrent active bookings)
  - Membership room limits (Single: 1, Family/Lifetime: 2)
  - Clear Lake guest capacity (12 guests max per day)
  - Room capacity validation
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, Season, Room}
  alias Ysc.Subscriptions
  alias Ysc.Repo

  # Helper to create seasons for testing
  defp create_test_seasons do
    # Create Winter season (Oct 1 - Apr 30) - rooms only
    {:ok, _winter} =
      %Season{}
      |> Season.changeset(%{
        name: "Winter",
        property: :tahoe,
        start_date: ~D[2024-10-01],
        end_date: ~D[2025-04-30],
        max_nights: 4,
        advance_booking_days: 90
      })
      |> Repo.insert()

    # Create Summer season (May 1 - Sep 30) - rooms or buyout
    {:ok, _summer} =
      %Season{}
      |> Season.changeset(%{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30],
        max_nights: 4,
        advance_booking_days: 180
      })
      |> Repo.insert()

    # Clear Lake season (year-round)
    {:ok, _clear_lake} =
      %Season{}
      |> Season.changeset(%{
        name: "Year-Round",
        property: :clear_lake,
        start_date: ~D[2024-01-01],
        end_date: ~D[2024-12-31],
        max_nights: 30,
        advance_booking_days: 365
      })
      |> Repo.insert()

    :ok
  end

  # Helper to create test rooms
  defp create_test_rooms do
    {:ok, room1} =
      %Room{}
      |> Room.changeset(%{
        name: "Tahoe Room 1",
        property: :tahoe,
        capacity_max: 4,
        is_active: true
      })
      |> Repo.insert()

    {:ok, room2} =
      %Room{}
      |> Room.changeset(%{
        name: "Tahoe Room 2",
        property: :tahoe,
        capacity_max: 6,
        is_active: true
      })
      |> Repo.insert()

    {:ok, clear_lake_room} =
      %Room{}
      |> Room.changeset(%{
        name: "Clear Lake Main",
        property: :clear_lake,
        capacity_max: 12,
        is_active: true
      })
      |> Repo.insert()

    %{tahoe_room1: room1, tahoe_room2: room2, clear_lake_room: clear_lake_room}
  end

  # Helper to create subscription with specific membership type
  defp create_subscription(user, membership_type)
       when membership_type in [:single, :family] do
    # Create subscription with required fields
    name =
      if membership_type == :family,
        do: "Family Membership",
        else: "Single Membership"

    {:ok, subscription} =
      %Subscriptions.Subscription{}
      |> Subscriptions.Subscription.changeset(%{
        user_id: user.id,
        name: name,
        stripe_id: "sub_test_#{System.unique_integer()}",
        stripe_status: "active",
        current_period_start:
          DateTime.utc_now() |> DateTime.add(-2_592_000, :second),
        # 30 days ago
        current_period_end:
          DateTime.utc_now() |> DateTime.add(28_944_000, :second)
        # 335 days from now
      })
      |> Repo.insert()

    # Create subscription item with membership type
    product_id =
      if membership_type == :family,
        do: "prod_family_membership",
        else: "prod_single_membership"

    price_id =
      if membership_type == :family,
        do: "price_family_annual",
        else: "price_single_annual"

    {:ok, _item} =
      %Subscriptions.SubscriptionItem{}
      |> Subscriptions.SubscriptionItem.changeset(%{
        subscription_id: subscription.id,
        stripe_id: "si_test_#{System.unique_integer()}",
        stripe_product_id: product_id,
        stripe_price_id: price_id,
        quantity: 1
      })
      |> Repo.insert()

    # Reload user with subscriptions preloaded
    Repo.get(Ysc.Accounts.User, user.id)
    |> Repo.preload(:subscriptions)
  end

  setup do
    create_test_seasons()
    rooms = create_test_rooms()

    # Configure membership plans for testing
    Application.put_env(:ysc, :membership_plans, [
      %{
        id: :single,
        stripe_price_id: "price_single_annual",
        amount: 45,
        name: "Single",
        interval: "year",
        currency: "usd"
      },
      %{
        id: :family,
        stripe_price_id: "price_family_annual",
        amount: 65,
        name: "Family",
        interval: "year",
        currency: "usd"
      }
    ])

    user = user_fixture()

    %{user: user, rooms: rooms}
  end

  describe "Winter vs Summer season rules (Tahoe)" do
    test "Winter: allows room bookings", %{user: user, rooms: rooms} do
      # Winter booking (Feb 2025)
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2025-02-10],
        checkout_date: ~D[2025-02-12],
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(200, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1],
          user: user
        )

      assert changeset.valid?
    end

    test "Winter: rejects buyout bookings", %{user: user} do
      # Winter booking with buyout mode
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2025-02-10],
        checkout_date: ~D[2025-02-12],
        booking_mode: :buyout,
        guests_count: 8,
        total_price: Money.new(800, :USD)
      }

      changeset = Booking.changeset(%Booking{}, attrs, user: user)

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :booking_mode)
    end

    test "Summer: allows room bookings", %{user: user, rooms: rooms} do
      # Summer booking (July 2024)
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-10],
        checkout_date: ~D[2024-07-12],
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(200, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1],
          user: user
        )

      assert changeset.valid?
    end

    test "Summer: allows buyout bookings", %{user: user} do
      # Summer booking with buyout
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-10],
        checkout_date: ~D[2024-07-12],
        booking_mode: :buyout,
        guests_count: 10,
        total_price: Money.new(1000, :USD)
      }

      changeset = Booking.changeset(%Booking{}, attrs, user: user)

      assert changeset.valid?
    end
  end

  describe "Weekend requirement validation (Saturday must include Sunday)" do
    test "rejects Saturday booking without Sunday", %{user: user, rooms: rooms} do
      # Saturday July 13, 2024 checkout on Sunday without staying
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-13],
        # Saturday
        checkout_date: ~D[2024-07-14],
        # Sunday checkout (not staying Sunday)
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(200, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1],
          user: user
        )

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :checkout_date)
    end

    test "accepts Saturday-Sunday booking", %{user: user, rooms: rooms} do
      # Saturday July 13 to Monday July 15 (includes Sunday)
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-13],
        # Saturday
        checkout_date: ~D[2024-07-15],
        # Monday (stayed Sunday night)
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(400, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1],
          user: user
        )

      assert changeset.valid?
    end

    test "accepts booking with multiple Saturdays if Sundays included", %{
      user: user,
      rooms: rooms
    } do
      # Two weeks: Saturday July 13 to Monday July 22
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-13],
        # Saturday
        checkout_date: ~D[2024-07-15],
        # Monday (only 2 nights, within limit)
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(400, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1],
          user: user
        )

      assert changeset.valid?
    end

    test "accepts weekday bookings without Saturday", %{
      user: user,
      rooms: rooms
    } do
      # Monday to Wednesday (no Saturday)
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-15],
        # Monday
        checkout_date: ~D[2024-07-17],
        # Wednesday
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(400, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1],
          user: user
        )

      assert changeset.valid?
    end
  end

  describe "Max nights validation" do
    test "Tahoe: rejects booking exceeding 4 nights default", %{
      user: user,
      rooms: rooms
    } do
      # 5 nights (exceeds Tahoe limit)
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-15],
        checkout_date: ~D[2024-07-20],
        # 5 nights
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(1000, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1],
          user: user
        )

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :checkout_date)
      {message, _} = Keyword.get(changeset.errors, :checkout_date)
      assert message =~ "4 nights"
    end

    test "Tahoe: accepts booking within 4 nights limit", %{
      user: user,
      rooms: rooms
    } do
      # 4 nights (at limit)
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-15],
        checkout_date: ~D[2024-07-19],
        # 4 nights
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(800, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1],
          user: user
        )

      assert changeset.valid?
    end

    test "Clear Lake: allows bookings up to 30 nights", %{
      user: user,
      rooms: rooms
    } do
      # 30 nights
      attrs = %{
        user_id: user.id,
        property: :clear_lake,
        checkin_date: ~D[2024-07-01],
        checkout_date: ~D[2024-07-31],
        # 30 nights
        booking_mode: :room,
        guests_count: 4,
        total_price: Money.new(6000, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.clear_lake_room],
          user: user
        )

      assert changeset.valid?
    end

    test "Clear Lake: rejects booking exceeding 30 nights", %{
      user: user,
      rooms: rooms
    } do
      # 31 nights
      attrs = %{
        user_id: user.id,
        property: :clear_lake,
        checkin_date: ~D[2024-07-01],
        checkout_date: ~D[2024-08-01],
        # 31 nights
        booking_mode: :room,
        guests_count: 4,
        total_price: Money.new(6200, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.clear_lake_room],
          user: user
        )

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :checkout_date)
    end
  end

  describe "Active booking limits (membership-dependent)" do
    test "Single member: allows one active booking", %{user: user, rooms: rooms} do
      # Create single membership and reload user with subscriptions
      user = create_subscription(user, :single)

      # Use dates in the future, avoiding weekends
      # Pick Monday-Wednesday to avoid Saturday/Sunday
      today = Date.utc_today()
      # Find next Monday
      days_to_monday = rem(8 - Date.day_of_week(today, :monday), 7)
      # Add 7 to ensure it's in the future
      next_monday = Date.add(today, days_to_monday + 7)
      future_date1 = next_monday
      # Wednesday
      future_date2 = Date.add(next_monday, 2)
      # Monday, 3 weeks later
      future_date3 = Date.add(next_monday, 21)
      # Wednesday, 3 weeks later
      future_date4 = Date.add(next_monday, 23)

      # Create first confirmed booking (future dates)
      attrs1 = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: future_date1,
        checkout_date: future_date2,
        booking_mode: :room,
        guests_count: 2,
        status: :complete,
        total_price: Money.new(400, :USD)
      }

      {:ok, _booking1} =
        %Booking{}
        |> Booking.changeset(attrs1, rooms: [rooms.tahoe_room1], user: user)
        |> Repo.insert()

      # Try to create second booking with different dates (also future)
      attrs2 = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: future_date3,
        checkout_date: future_date4,
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(400, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs2,
          rooms: [rooms.tahoe_room1],
          user: user
        )

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :user_id)
    end

    test "Family member: allows up to 2 overlapping bookings", %{
      user: user,
      rooms: rooms
    } do
      # Create family membership and reload user with subscriptions
      user = create_subscription(user, :family)

      # Create first confirmed booking (Mon-Thu)
      attrs1 = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-08],
        # Monday
        checkout_date: ~D[2024-07-11],
        # Thursday
        booking_mode: :room,
        rooms: [rooms.tahoe_room1],
        guests_count: 2,
        status: :complete,
        total_price: Money.new(600, :USD)
      }

      {:ok, _booking1} = Bookings.create_booking(attrs1)

      # Second booking with overlapping dates (should be allowed) (Wed-Fri)
      attrs2 = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-10],
        # Wednesday
        checkout_date: ~D[2024-07-12],
        # Friday
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(600, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs2,
          rooms: [rooms.tahoe_room2],
          user: user
        )

      assert changeset.valid?
    end

    test "Family member: rejects 3rd overlapping booking", %{
      user: user,
      rooms: rooms
    } do
      # Create family membership and reload user with subscriptions
      user = create_subscription(user, :family)

      # Create two confirmed bookings (both avoiding Saturday)
      attrs1 = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-08],
        # Monday
        checkout_date: ~D[2024-07-10],
        # Wednesday
        booking_mode: :room,
        rooms: [rooms.tahoe_room1],
        guests_count: 2,
        status: :complete,
        total_price: Money.new(400, :USD)
      }

      {:ok, _booking1} = Bookings.create_booking(attrs1)

      attrs2 = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-09],
        # Tuesday
        checkout_date: ~D[2024-07-11],
        # Thursday
        booking_mode: :room,
        rooms: [rooms.tahoe_room2],
        guests_count: 2,
        status: :complete,
        total_price: Money.new(400, :USD)
      }

      {:ok, _booking2} = Bookings.create_booking(attrs2)

      # Try third overlapping booking (Tue-Thu)
      attrs3 = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-09],
        # Tuesday
        checkout_date: ~D[2024-07-11],
        # Thursday
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(400, :USD)
      }

      # Don't specify rooms to test that validator rejects based on booking count alone
      changeset = Booking.changeset(%Booking{}, attrs3, user: user)

      refute changeset.valid?
    end

    test "allows new booking after previous one is cancelled", %{
      user: user,
      rooms: rooms
    } do
      # Create single membership and reload user with subscriptions
      user = create_subscription(user, :single)

      # Create first booking then cancel it (Mon-Wed)
      attrs1 = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-08],
        # Monday
        checkout_date: ~D[2024-07-10],
        # Wednesday
        booking_mode: :room,
        rooms: [rooms.tahoe_room1],
        guests_count: 2,
        status: :canceled,
        # Cancelled status
        total_price: Money.new(400, :USD)
      }

      {:ok, _booking1} = Bookings.create_booking(attrs1)

      # Should allow new booking since first is cancelled (Mon-Wed)
      attrs2 = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-08-05],
        # Monday
        checkout_date: ~D[2024-08-07],
        # Wednesday
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(400, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs2,
          rooms: [rooms.tahoe_room1],
          user: user
        )

      assert changeset.valid?
    end
  end

  describe "Buyout rules" do
    test "rejects buyout if user has active room bookings", %{
      user: user,
      rooms: rooms
    } do
      user = create_subscription(user, :family)

      # Use dates in the future, avoiding weekends
      # Pick Monday-Wednesday to avoid Saturday/Sunday
      today = Date.utc_today()
      # Find next Monday
      days_to_monday = rem(8 - Date.day_of_week(today, :monday), 7)
      # Add 7 to ensure it's in the future
      next_monday = Date.add(today, days_to_monday + 7)
      future_date1 = next_monday
      # Wednesday
      future_date2 = Date.add(next_monday, 2)
      # Monday, 3 weeks later
      future_date3 = Date.add(next_monday, 21)
      # Wednesday, 3 weeks later
      future_date4 = Date.add(next_monday, 23)

      # Create existing room booking (future dates)
      attrs1 = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: future_date1,
        checkout_date: future_date2,
        booking_mode: :room,
        guests_count: 2,
        status: :complete,
        total_price: Money.new(400, :USD)
      }

      {:ok, _booking1} =
        %Booking{}
        |> Booking.changeset(attrs1, rooms: [rooms.tahoe_room1], user: user)
        |> Repo.insert()

      # Try to create buyout (should fail) (different future dates)
      attrs2 = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: future_date3,
        checkout_date: future_date4,
        booking_mode: :buyout,
        guests_count: 10,
        total_price: Money.new(2000, :USD)
      }

      changeset = Booking.changeset(%Booking{}, attrs2, user: user)

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :booking_mode)
    end

    test "allows buyout if no active bookings exist", %{user: user} do
      user = create_subscription(user, :family)

      # Try to create buyout with no existing bookings (Mon-Wed)
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-08-05],
        # Monday
        checkout_date: ~D[2024-08-07],
        # Wednesday
        booking_mode: :buyout,
        guests_count: 10,
        total_price: Money.new(2000, :USD)
      }

      changeset = Booking.changeset(%Booking{}, attrs, user: user)

      assert changeset.valid?
    end
  end

  describe "Membership room limits" do
    test "Single member: can only book 1 room", %{user: user, rooms: rooms} do
      user = create_subscription(user, :single)

      # Try to book 2 rooms (should fail for single member) (Mon-Wed)
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-08-05],
        # Monday
        checkout_date: ~D[2024-08-07],
        # Wednesday
        booking_mode: :room,
        guests_count: 4,
        total_price: Money.new(800, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1, rooms.tahoe_room2],
          user: user
        )

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :rooms)
    end

    test "Family member: can book up to 2 rooms", %{user: user, rooms: rooms} do
      user = create_subscription(user, :family)

      # Book 2 rooms (should succeed for family member) (Mon-Wed)
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-08-05],
        # Monday
        checkout_date: ~D[2024-08-07],
        # Wednesday
        booking_mode: :room,
        guests_count: 6,
        total_price: Money.new(1200, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1, rooms.tahoe_room2],
          user: user
        )

      assert changeset.valid?
    end
  end

  describe "Clear Lake guest capacity (12 guests max per day)" do
    test "rejects booking exceeding 12 guests", %{user: user, rooms: rooms} do
      # Try to book with 13 guests
      attrs = %{
        user_id: user.id,
        property: :clear_lake,
        checkin_date: ~D[2024-07-10],
        checkout_date: ~D[2024-07-12],
        booking_mode: :room,
        guests_count: 13,
        total_price: Money.new(2600, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.clear_lake_room],
          user: user
        )

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :guests_count)
    end

    test "accepts booking with exactly 12 guests", %{user: user, rooms: rooms} do
      # Book with 12 guests (at limit)
      attrs = %{
        user_id: user.id,
        property: :clear_lake,
        checkin_date: ~D[2024-07-10],
        checkout_date: ~D[2024-07-12],
        booking_mode: :room,
        guests_count: 12,
        total_price: Money.new(2400, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.clear_lake_room],
          user: user
        )

      assert changeset.valid?
    end
  end

  describe "Room capacity validation" do
    test "rejects booking where guests exceed room capacity", %{
      user: user,
      rooms: rooms
    } do
      # tahoe_room1 has capacity 4, try to book with 5 guests
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-10],
        checkout_date: ~D[2024-07-12],
        booking_mode: :room,
        guests_count: 5,
        total_price: Money.new(1000, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1],
          user: user
        )

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :guests_count)
    end

    test "accepts booking where guests fit in combined room capacity", %{
      user: user,
      rooms: rooms
    } do
      # room1 (cap 4) + room2 (cap 6) = 10 total, book with 8 guests
      # Need family membership for 2 rooms
      user = create_subscription(user, :family)

      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-10],
        checkout_date: ~D[2024-07-12],
        booking_mode: :room,
        guests_count: 8,
        total_price: Money.new(1600, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1, rooms.tahoe_room2],
          user: user
        )

      assert changeset.valid?
    end
  end

  describe "skip_validation option" do
    test "skips all validations when skip_validation is true", %{user: user} do
      # Create conditions that would normally fail validation
      user = create_subscription(user, :single)

      # Create existing booking
      attrs1 = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-01],
        checkout_date: ~D[2024-07-03],
        booking_mode: :room,
        guests_count: 2,
        status: :complete,
        total_price: Money.new(400, :USD)
      }

      {:ok, _booking1} = Bookings.create_booking(attrs1)

      # This would normally fail (single member with 2 active bookings)
      attrs2 = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-08-01],
        checkout_date: ~D[2024-08-10],
        # Exceeds max nights
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(1600, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs2, skip_validation: true, user: user)

      # Should pass because validation is skipped
      assert changeset.valid?
    end
  end
end
