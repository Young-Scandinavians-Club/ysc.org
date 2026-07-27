defmodule Ysc.Bookings.BookingValidatorTest do
  @moduledoc """
  Tests for BookingValidator business logic.

  This module tests the most complex booking validation rules:
  - Winter vs Summer season rules (Tahoe)
  - Weekend requirement validation (Saturday must include Sunday)
  - Max nights validation (property and season-specific)
  - Active booking limits (membership-dependent)
  - Buyout rules (mutually exclusive with other active bookings)
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
    Repo.delete_all(Season)
    Ysc.Bookings.SeasonCache.invalidate()

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
    original_plans = Application.get_env(:ysc, :membership_plans)

    Application.put_env(:ysc, :membership_plans, [
      %{
        id: :single,
        stripe_price_id: "price_single_annual",
        amount: 45,
        name: "Single",
        description: "Membership just for yourself",
        interval: "year",
        currency: "usd"
      },
      %{
        id: :family,
        stripe_price_id: "price_family_annual",
        amount: 65,
        name: "Family",
        description: "For you, your Spouse and your children under 18",
        interval: "year",
        currency: "usd"
      }
    ])

    on_exit(fn ->
      Application.put_env(:ysc, :membership_plans, original_plans)
    end)

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

      assert elem(Keyword.get(changeset.errors, :booking_mode), 0) ==
               "Entire-cabin rentals are not available for winter nights in this stay"
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

    test "rejects buyout when any stay night falls in Winter", %{user: user} do
      # create_test_seasons: Winter starts Oct 1. Fri→Sun includes winter nights.
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-10-31],
        checkout_date: ~D[2024-11-02],
        booking_mode: :buyout,
        guests_count: 10,
        total_price: Money.new(1000, :USD)
      }

      changeset = Booking.changeset(%Booking{}, attrs, user: user)

      refute changeset.valid?

      assert elem(Keyword.get(changeset.errors, :booking_mode), 0) ==
               "Entire-cabin rentals are not available for winter nights in this stay"
    end

    test "rejects buyout spanning Summer into Winter when Summer ends Jul 31",
         %{
           user: user
         } do
      Repo.delete_all(Season)

      {:ok, _} =
        %Season{}
        |> Season.changeset(%{
          name: "Summer",
          property: :tahoe,
          start_date: ~D[2024-05-01],
          end_date: ~D[2024-07-31],
          is_default: true
        })
        |> Repo.insert()

      {:ok, _} =
        %Season{}
        |> Season.changeset(%{
          name: "Winter",
          property: :tahoe,
          start_date: ~D[2024-08-01],
          end_date: ~D[2025-04-30],
          advance_booking_days: 45,
          max_nights: 4
        })
        |> Repo.insert()

      Ysc.Bookings.SeasonCache.invalidate()

      # Thu Jul 30 → Sat Aug 1: includes Jul 31 (summer) and Aug nights (winter)
      # Use Mon→Thu entirely in July first to confirm buyout ok, then span.
      ok_attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2026-07-27],
        checkout_date: ~D[2026-07-30],
        booking_mode: :buyout,
        guests_count: 10,
        total_price: Money.new(1000, :USD)
      }

      assert Booking.changeset(%Booking{}, ok_attrs, user: user).valid?

      span_attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2026-07-30],
        checkout_date: ~D[2026-08-02],
        booking_mode: :buyout,
        guests_count: 10,
        total_price: Money.new(1000, :USD)
      }

      changeset = Booking.changeset(%Booking{}, span_attrs, user: user)
      refute changeset.valid?

      assert elem(Keyword.get(changeset.errors, :booking_mode), 0) ==
               "Entire-cabin rentals are not available for winter nights in this stay"
    end
  end

  describe "Weekend requirement validation (Saturday must include Sunday)" do
    test "rejects checkout on Saturday without Sunday in reservation", %{
      user: user,
      rooms: rooms
    } do
      # Friday check-in, Saturday checkout (Saturday in range but not Sunday)
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-12],
        checkout_date: ~D[2024-07-13],
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

    test "accepts Saturday check-in with Sunday checkout", %{
      user: user,
      rooms: rooms
    } do
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-13],
        checkout_date: ~D[2024-07-14],
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

    test "rejects Saturday check-in with Monday checkout (must be one night to Sunday)",
         %{
           user: user,
           rooms: rooms
         } do
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-13],
        # Saturday
        checkout_date: ~D[2024-07-15],
        # Monday — not allowed for Saturday arrivals
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(400, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1],
          user: user
        )

      refute changeset.valid?

      assert {msg, _} = Keyword.get(changeset.errors, :checkout_date)

      assert msg =~
               "Check-ins on Saturday must check out on Sunday"
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

      {message, _} = Keyword.fetch!(changeset.errors, :user_id)
      assert message =~ "one active booking at a time"
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

      {message, _} = Keyword.fetch!(changeset.errors, :checkin_date)
      assert message =~ "2 cabin bookings at the same time"
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

  describe "checkout cutoff (11 AM PST)" do
    defp pst_today do
      DateTime.now!("America/Los_Angeles") |> DateTime.to_date()
    end

    defp before_checkout_cutoff? do
      today = pst_today()
      now_pst = DateTime.now!("America/Los_Angeles")

      checkout_cutoff =
        DateTime.new!(today, ~T[11:00:00], "America/Los_Angeles")

      DateTime.compare(now_pst, checkout_cutoff) == :lt
    end

    defp future_monday_wednesday do
      today = Date.utc_today()
      days_to_monday = rem(8 - Date.day_of_week(today, :monday), 7)
      next_monday = Date.add(today, days_to_monday + 7)
      {next_monday, Date.add(next_monday, 2)}
    end

    defp insert_checkout_today_booking!(user, rooms, booking_mode \\ :room) do
      today = pst_today()
      checkin = Date.add(today, -2)

      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: checkin,
        checkout_date: today,
        booking_mode: booking_mode,
        guests_count: if(booking_mode == :buyout, do: 10, else: 2),
        status: :complete,
        total_price: Money.new(400, :USD)
      }

      opts =
        if booking_mode == :room do
          [rooms: [rooms.tahoe_room1], user: user, skip_validation: true]
        else
          [skip_validation: true, user: user]
        end

      {:ok, booking} =
        %Booking{}
        |> Booking.changeset(attrs, opts)
        |> Repo.insert()

      booking
    end

    test "single member: checkout-today booking blocks second active booking only before cutoff",
         %{user: user, rooms: rooms} do
      user = create_subscription(user, :single)
      _existing = insert_checkout_today_booking!(user, rooms)

      {checkin, checkout} = future_monday_wednesday()

      changeset =
        Booking.changeset(
          %Booking{},
          %{
            user_id: user.id,
            property: :tahoe,
            checkin_date: checkin,
            checkout_date: checkout,
            booking_mode: :room,
            guests_count: 2,
            total_price: Money.new(400, :USD)
          },
          rooms: [rooms.tahoe_room1],
          user: user
        )

      if before_checkout_cutoff?() do
        refute changeset.valid?

        {message, _} = Keyword.fetch!(changeset.errors, :user_id)
        assert message =~ "one active booking at a time"
      else
        assert changeset.valid?
      end
    end

    test "buyout exclusivity: checkout-today buyout blocks room booking only before cutoff",
         %{user: user, rooms: rooms} do
      user = create_subscription(user, :family)
      _existing = insert_checkout_today_booking!(user, rooms, :buyout)

      {checkin, checkout} = future_monday_wednesday()

      changeset =
        Booking.changeset(
          %Booking{},
          %{
            user_id: user.id,
            property: :tahoe,
            checkin_date: checkin,
            checkout_date: checkout,
            booking_mode: :room,
            guests_count: 2,
            total_price: Money.new(400, :USD)
          },
          rooms: [rooms.tahoe_room1],
          user: user
        )

      if before_checkout_cutoff?() do
        refute changeset.valid?

        {message, _} = Keyword.fetch!(changeset.errors, :booking_mode)
        assert message =~ "active or future full buyout"
      else
        assert changeset.valid?
      end
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

    test "rejects room booking if user has active buyout", %{
      user: user,
      rooms: rooms
    } do
      user = create_subscription(user, :family)

      today = Date.utc_today()
      days_to_monday = rem(8 - Date.day_of_week(today, :monday), 7)
      next_monday = Date.add(today, days_to_monday + 7)
      buyout_checkin = next_monday
      buyout_checkout = Date.add(next_monday, 2)
      room_checkin = Date.add(next_monday, 21)
      room_checkout = Date.add(next_monday, 23)

      {:ok, _buyout} =
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: user.id,
            property: :tahoe,
            checkin_date: buyout_checkin,
            checkout_date: buyout_checkout,
            booking_mode: :buyout,
            guests_count: 10,
            status: :complete,
            total_price: Money.new(2000, :USD)
          },
          user: user
        )
        |> Repo.insert()

      changeset =
        Booking.changeset(
          %Booking{},
          %{
            user_id: user.id,
            property: :tahoe,
            checkin_date: room_checkin,
            checkout_date: room_checkout,
            booking_mode: :room,
            guests_count: 2,
            total_price: Money.new(400, :USD)
          },
          rooms: [rooms.tahoe_room1],
          user: user
        )

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :booking_mode)

      assert {"You cannot book rooms while you have an active or future full buyout reservation. Please complete or cancel your buyout first.",
              _} = Keyword.get(changeset.errors, :booking_mode)
    end

    test "allows room booking if buyout checkout is in the past", %{
      user: user,
      rooms: rooms
    } do
      user = create_subscription(user, :family)

      {:ok, _past_buyout} =
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: user.id,
            property: :tahoe,
            checkin_date: ~D[2024-08-05],
            checkout_date: ~D[2024-08-07],
            booking_mode: :buyout,
            guests_count: 10,
            status: :complete,
            total_price: Money.new(2000, :USD)
          },
          skip_validation: true,
          user: user
        )
        |> Repo.insert()

      changeset =
        Booking.changeset(
          %Booking{},
          %{
            user_id: user.id,
            property: :tahoe,
            checkin_date: ~D[2024-08-12],
            checkout_date: ~D[2024-08-14],
            booking_mode: :room,
            guests_count: 2,
            total_price: Money.new(400, :USD)
          },
          rooms: [rooms.tahoe_room1],
          user: user
        )

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

    test "rejects booking where adults plus children exceed room capacity", %{
      user: user,
      rooms: rooms
    } do
      # tahoe_room1 has capacity 4, 2 adults + 3 children = 5 total
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-10],
        checkout_date: ~D[2024-07-12],
        booking_mode: :room,
        guests_count: 2,
        children_count: 3,
        total_price: Money.new(1000, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1],
          user: user
        )

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :children_count)
    end

    test "accepts booking where adults plus children fit in room capacity", %{
      user: user,
      rooms: rooms
    } do
      # tahoe_room1 has capacity 4, 2 adults + 2 children = 4 total
      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2024-07-10],
        checkout_date: ~D[2024-07-12],
        booking_mode: :room,
        guests_count: 2,
        children_count: 2,
        total_price: Money.new(1000, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1],
          user: user
        )

      assert changeset.valid?
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

  describe "lifetime membership (Tahoe)" do
    test "lifetime member: rejects third overlapping booking like family", %{
      user: user,
      rooms: rooms
    } do
      user =
        user
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        )
        |> Repo.update!()
        |> Repo.preload(:subscriptions)

      attrs1 = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2025-07-08],
        checkout_date: ~D[2025-07-10],
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
        checkin_date: ~D[2025-07-09],
        checkout_date: ~D[2025-07-11],
        booking_mode: :room,
        rooms: [rooms.tahoe_room2],
        guests_count: 2,
        status: :complete,
        total_price: Money.new(400, :USD)
      }

      {:ok, _booking2} = Bookings.create_booking(attrs2)

      attrs3 = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: ~D[2025-07-09],
        checkout_date: ~D[2025-07-11],
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(400, :USD)
      }

      changeset = Booking.changeset(%Booking{}, attrs3, user: user)

      refute changeset.valid?
    end
  end

  describe "advance booking limit (Tahoe)" do
    test "adds error when check-in is beyond season advance_booking_days", %{
      user: user,
      rooms: rooms
    } do
      summer =
        Repo.get_by!(Season,
          name: "Summer",
          property: :tahoe
        )

      old_advance = summer.advance_booking_days

      on_exit(fn ->
        Repo.update!(
          Ecto.Changeset.change(summer, advance_booking_days: old_advance)
        )

        Ysc.Bookings.SeasonCache.invalidate_property(:tahoe)
      end)

      Repo.update!(Ecto.Changeset.change(summer, advance_booking_days: 7))
      Ysc.Bookings.SeasonCache.invalidate_property(:tahoe)

      today = Date.utc_today()
      advance_days = 7

      # Pick a Monday far enough out to exceed the advance booking window.
      checkin =
        today
        |> Date.add(advance_days + 7)
        |> then(fn base ->
          days_to_monday = rem(8 - Date.day_of_week(base, :monday), 7)
          Date.add(base, days_to_monday)
        end)

      checkout = Date.add(checkin, 2)

      attrs = %{
        user_id: user.id,
        property: :tahoe,
        checkin_date: checkin,
        checkout_date: checkout,
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(400, :USD)
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [rooms.tahoe_room1],
          user: user
        )

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :checkin_date)
      {msg, _} = Keyword.fetch!(changeset.errors, :checkin_date)
      assert msg =~ "advance" or msg =~ "days"
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
