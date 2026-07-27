defmodule Ysc.BookingsTest do
  @moduledoc """
  Tests for Ysc.Bookings context module.
  """
  # Serial: pricing rules and shared fixtures are sensitive to parallel DB races
  # (e.g. room price fallback to property buyout rules from other tests).
  use Ysc.DataCase, async: false

  alias Ysc.Bookings

  alias Ysc.Bookings.{
    Booking,
    BookingRoom,
    PendingRefund,
    Season,
    Room,
    RoomCategory
  }

  alias Ysc.Ledgers

  import Ecto.Query
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Ysc.TestDataFactory

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    # Clear season cache to avoid cross-test pollution in async tests
    Ysc.Bookings.SeasonCache.invalidate()

    # Ensure stripe_client is the test client (defensive reset in case async tests leaked state)
    Application.put_env(:ysc, :stripe_client, Ysc.TestStripeClient)
    :ok
  end

  describe "seasons" do
    test "list_seasons/0 returns all seasons" do
      season1 = create_season_fixture(%{name: "Summer", property: :tahoe})
      season2 = create_season_fixture(%{name: "Winter", property: :clear_lake})

      seasons = Bookings.list_seasons()
      assert length(seasons) >= 2
      assert Enum.any?(seasons, &(&1.id == season1.id))
      assert Enum.any?(seasons, &(&1.id == season2.id))
    end

    test "list_seasons/1 filters by property" do
      season1 = create_season_fixture(%{name: "Summer", property: :tahoe})
      _season2 = create_season_fixture(%{name: "Winter", property: :clear_lake})

      seasons = Bookings.list_seasons(:tahoe)
      assert Enum.any?(seasons, &(&1.id == season1.id))
      refute Enum.any?(seasons, &(&1.property == :clear_lake))
    end

    test "list_seasons/1 uses SeasonCache when season_cache_enabled is true" do
      previous = Application.get_env(:ysc, :season_cache_enabled)
      Application.put_env(:ysc, :season_cache_enabled, true)

      on_exit(fn ->
        Application.put_env(:ysc, :season_cache_enabled, previous)
      end)

      Ysc.Bookings.SeasonCache.invalidate()

      season =
        create_season_fixture(%{
          name: "CacheSeason#{System.unique_integer([:positive])}",
          property: :tahoe
        })

      Ysc.Bookings.SeasonCache.invalidate()

      seasons = Bookings.list_seasons(:tahoe)
      assert Enum.any?(seasons, &(&1.id == season.id))
    end

    test "get_season!/1 returns the season with given id" do
      season = create_season_fixture()
      assert Bookings.get_season!(season.id).id == season.id
    end

    test "create_season/1 with valid data creates a season" do
      valid_attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2025-06-01],
        end_date: ~D[2025-08-31]
      }

      assert {:ok, %Season{} = season} = Bookings.create_season(valid_attrs)
      assert season.name == "Summer"
      assert season.property == :tahoe
    end

    test "create_season/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Bookings.create_season(%{})
    end

    test "update_season/2 with valid data updates the season" do
      season = create_season_fixture()
      update_attrs = %{name: "Updated Summer"}

      assert {:ok, %Season{} = season} =
               Bookings.update_season(season, update_attrs)

      assert season.name == "Updated Summer"
    end

    test "update_season/2 with invalid data returns error changeset" do
      season = create_season_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Bookings.update_season(season, %{name: nil})

      assert season == Bookings.get_season!(season.id)
    end

    test "delete_season/1 deletes the season" do
      season = create_season_fixture()
      assert {:ok, %Season{}} = Bookings.delete_season(season)

      assert_raise Ecto.NoResultsError, fn ->
        Bookings.get_season!(season.id)
      end
    end
  end

  describe "bookings" do
    test "list_bookings/0 returns all bookings" do
      booking1 = booking_fixture()
      booking2 = booking_fixture()

      bookings = Bookings.list_bookings()
      assert length(bookings) >= 2
      assert Enum.any?(bookings, &(&1.id == booking1.id))
      assert Enum.any?(bookings, &(&1.id == booking2.id))
    end

    test "list_bookings/1 filters by property" do
      booking1 = booking_fixture(%{property: :tahoe})
      _booking2 = booking_fixture(%{property: :clear_lake})

      bookings = Bookings.list_bookings(:tahoe)
      assert Enum.any?(bookings, &(&1.id == booking1.id))
      refute Enum.any?(bookings, &(&1.property == :clear_lake))
    end

    test "list_bookings/3 filters by date range" do
      # Ensure dates don't include Saturday without Sunday (Tahoe rule)
      # Start from a Monday to avoid weekend issues
      base_date = Date.utc_today() |> Date.add(7)
      # Find next Monday if not already Monday
      checkin =
        if Date.day_of_week(base_date) == 1,
          do: base_date,
          else: Date.add(base_date, 8 - Date.day_of_week(base_date))

      checkout = Date.add(checkin, 2)

      booking1 =
        booking_fixture(%{checkin_date: checkin, checkout_date: checkout})

      _booking2 =
        booking_fixture(%{
          checkin_date: Date.add(checkin, 30),
          checkout_date: Date.add(checkin, 32)
        })

      start_date = Date.add(checkin, -1)
      end_date = Date.add(checkout, 1)

      bookings = Bookings.list_bookings(nil, start_date, end_date)
      assert Enum.any?(bookings, &(&1.id == booking1.id))
    end

    test "admin_property_dashboard_stats/0 aggregates per-property buckets in one query" do
      today =
        "America/Los_Angeles"
        |> DateTime.now!()
        |> DateTime.to_date()

      two_day_checkout =
        ensure_sunday_when_saturday_included(today, Date.add(today, 2))

      staying =
        active_check_in_booking_fixture(%{
          property: :tahoe,
          status: :complete,
          guests_count: 3
        })

      checkin_today =
        booking_fixture(%{
          property: :clear_lake,
          checkin_date: today,
          checkout_date: two_day_checkout,
          status: :complete,
          guests_count: 2
        })

      checkout_today =
        booking_fixture(%{
          property: :tahoe,
          checkin_date:
            tahoe_checkin_for_fixed_checkout(today, Date.add(today, -2)),
          checkout_date: today,
          status: :complete,
          guests_count: 4
        })

      upcoming =
        booking_fixture(%{
          property: :clear_lake,
          checkin_date: Date.add(today, 5),
          checkout_date: Date.add(today, 7),
          status: :complete,
          guests_count: 5
        })

      _canceled =
        booking_fixture(%{
          property: :tahoe,
          checkin_date: today,
          checkout_date:
            ensure_sunday_when_saturday_included(today, Date.add(today, 1)),
          status: :canceled
        })

      stats = Bookings.admin_property_dashboard_stats()

      assert stats.tahoe.staying >= 1
      assert checkout_today.checkout_date == today
      assert stats.tahoe.checkouts_today >= 1
      assert stats.clear_lake.checkins_today >= 1
      assert stats.clear_lake.upcoming_bookings >= 1
      assert stats.clear_lake.upcoming_guests >= upcoming.guests_count

      assert staying.id
      assert checkin_today.id
      assert checkout_today.id
    end

    test "admin_property_dashboard_stats counts checkout-today guests as staying only before 11 AM PST" do
      today = DateTime.now!("America/Los_Angeles") |> DateTime.to_date()
      before = Bookings.admin_property_dashboard_stats()

      booking_fixture(%{
        property: :tahoe,
        checkin_date:
          tahoe_checkin_for_fixed_checkout(today, Date.add(today, -1)),
        checkout_date: today,
        status: :complete,
        guests_count: 1
      })

      after_stats = Bookings.admin_property_dashboard_stats()
      staying_delta = after_stats.tahoe.staying - before.tahoe.staying

      now_pst = DateTime.now!("America/Los_Angeles")

      checkout_cutoff =
        DateTime.new!(today, ~T[11:00:00], "America/Los_Angeles")

      before_cutoff = DateTime.compare(now_pst, checkout_cutoff) == :lt

      assert staying_delta == if(before_cutoff, do: 1, else: 0)

      assert after_stats.tahoe.checkouts_today >=
               before.tahoe.checkouts_today + 1
    end

    test "list_upcoming_active_bookings_for_user/2 excludes canceled and past checkouts" do
      user = user_fixture()
      today = DateTime.now!("America/Los_Angeles") |> DateTime.to_date()

      active =
        insert_complete_booking(user, Date.add(today, 3), Date.add(today, 5))

      _checkout_today =
        insert_complete_booking(user, Date.add(today, -2), today)

      _canceled =
        insert_complete_booking(user, Date.add(today, 10), Date.add(today, 12))
        |> Ecto.Changeset.change(status: :canceled)
        |> Ysc.Repo.update!()

      now_pst = DateTime.now!("America/Los_Angeles")

      checkout_cutoff =
        DateTime.new!(today, ~T[11:00:00], "America/Los_Angeles")

      before_cutoff = DateTime.compare(now_pst, checkout_cutoff) == :lt

      bookings = Bookings.list_upcoming_active_bookings_for_user(user.id)

      assert Enum.any?(bookings, &(&1.id == active.id))
      refute Enum.any?(bookings, &(&1.status == :canceled))

      checkout_today_included? =
        Enum.any?(bookings, &(&1.checkout_date == today))

      assert checkout_today_included? == before_cutoff
    end

    test "list_upcoming_active_bookings_for_user/2 applies checkout cutoff before limit" do
      user = user_fixture()
      today = DateTime.now!("America/Los_Angeles") |> DateTime.to_date()

      _stale_checkout_today =
        insert_complete_booking(user, Date.add(today, -1), today)

      future =
        insert_complete_booking(user, Date.add(today, 7), Date.add(today, 9))

      now_pst = DateTime.now!("America/Los_Angeles")

      checkout_cutoff =
        DateTime.new!(today, ~T[11:00:00], "America/Los_Angeles")

      if DateTime.compare(now_pst, checkout_cutoff) == :gt do
        bookings =
          Bookings.list_upcoming_active_bookings_for_user(user.id, limit: 1)

        assert length(bookings) == 1
        assert hd(bookings).id == future.id
      else
        bookings =
          Bookings.list_upcoming_active_bookings_for_user(user.id, limit: 2)

        assert length(bookings) == 2
        assert future.id in Enum.map(bookings, & &1.id)
      end
    end

    test "list_active_tahoe_bookings_for_family/2 applies checkout cutoff before limit" do
      user = user_fixture()
      today = DateTime.now!("America/Los_Angeles") |> DateTime.to_date()

      _stale_checkout_today =
        insert_complete_tahoe_booking(user, Date.add(today, -1), today)

      future =
        insert_complete_tahoe_booking(
          user,
          Date.add(today, 7),
          Date.add(today, 9)
        )

      now_pst = DateTime.now!("America/Los_Angeles")

      checkout_cutoff =
        DateTime.new!(today, ~T[11:00:00], "America/Los_Angeles")

      family_user_ids = [user.id]

      if DateTime.compare(now_pst, checkout_cutoff) == :gt do
        bookings =
          Bookings.list_active_tahoe_bookings_for_family(family_user_ids,
            limit: 1
          )

        assert length(bookings) == 1
        assert hd(bookings).id == future.id
      else
        bookings =
          Bookings.list_active_tahoe_bookings_for_family(family_user_ids,
            limit: 2
          )

        assert length(bookings) == 2
        assert future.id in Enum.map(bookings, & &1.id)
      end
    end

    test "list_active_clear_lake_bookings_for_user/2 applies checkout cutoff before limit" do
      user = user_fixture()
      today = DateTime.now!("America/Los_Angeles") |> DateTime.to_date()

      _stale_checkout_today =
        insert_complete_booking(user, Date.add(today, -1), today)

      future =
        insert_complete_booking(user, Date.add(today, 7), Date.add(today, 9))

      now_pst = DateTime.now!("America/Los_Angeles")

      checkout_cutoff =
        DateTime.new!(today, ~T[11:00:00], "America/Los_Angeles")

      if DateTime.compare(now_pst, checkout_cutoff) == :gt do
        bookings =
          Bookings.list_active_clear_lake_bookings_for_user(user.id, limit: 1)

        assert length(bookings) == 1
        assert hd(bookings).id == future.id
      else
        bookings =
          Bookings.list_active_clear_lake_bookings_for_user(user.id, limit: 2)

        assert length(bookings) == 2
        assert future.id in Enum.map(bookings, & &1.id)
      end
    end

    test "list_bookings/4 filters by statuses and exclude_statuses" do
      active =
        booking_fixture()
        |> Ecto.Changeset.change(status: :complete)
        |> Ysc.Repo.update!()

      canceled =
        booking_fixture()
        |> Ecto.Changeset.change(status: :canceled)
        |> Ysc.Repo.update!()

      refunded =
        booking_fixture()
        |> Ecto.Changeset.change(status: :refunded)
        |> Ysc.Repo.update!()

      complete_only =
        Bookings.list_bookings(nil, nil, nil, statuses: [:complete])

      assert Enum.any?(complete_only, &(&1.id == active.id))
      refute Enum.any?(complete_only, &(&1.id == canceled.id))
      refute Enum.any?(complete_only, &(&1.id == refunded.id))

      without_canceled_refunded =
        Bookings.list_bookings(nil, nil, nil,
          exclude_statuses: [:canceled, :refunded]
        )

      assert Enum.any?(without_canceled_refunded, &(&1.id == active.id))
      refute Enum.any?(without_canceled_refunded, &(&1.id == canceled.id))
      refute Enum.any?(without_canceled_refunded, &(&1.id == refunded.id))
    end

    test "get_booking!/1 returns the booking with given id" do
      booking = booking_fixture()
      found = Bookings.get_booking!(booking.id)
      assert found.id == booking.id
      assert Ecto.assoc_loaded?(found.user)
    end

    test "get_booking_by_reference_id/1 returns the booking" do
      booking = booking_fixture()
      found = Bookings.get_booking_by_reference_id(booking.reference_id)
      assert found.id == booking.id
    end

    test "get_booking_by_reference_id/1 returns nil for unknown reference" do
      assert Bookings.get_booking_by_reference_id(
               "ref_no_such_#{System.unique_integer([:positive])}"
             ) ==
               nil
    end

    test "list_bookings/3 with nil date bounds does not apply date filter" do
      booking_fixture()

      all_bookings = Bookings.list_bookings()
      no_date_filter = Bookings.list_bookings(nil, nil, nil)

      assert length(no_date_filter) == length(all_bookings)
    end

    test "list_bookings/4 passes opts preload to the query" do
      booking_fixture()
      bookings = Bookings.list_bookings(nil, nil, nil, preload: [:user, :rooms])
      assert bookings != []
      assert %Booking{user: %Ysc.Accounts.User{}} = hd(bookings)
    end

    test "list_bookings/4 respects custom preload option" do
      booking = booking_fixture()

      found =
        Bookings.list_bookings(nil, nil, nil, preload: [:user])
        |> Enum.find(&(&1.id == booking.id))

      assert found
      assert Ecto.assoc_loaded?(found.user)
      refute Ecto.assoc_loaded?(found.rooms)
    end

    test "create_booking/1 with valid data creates a booking" do
      user = user_fixture()
      {checkin, checkout} = tahoe_booking_dates(7)

      valid_attrs = %{
        user_id: user.id,
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: 2,
        property: :tahoe,
        booking_mode: :buyout,
        status: :draft,
        total_price: Money.new(200, :USD)
      }

      assert {:ok, %Booking{} = booking} = Bookings.create_booking(valid_attrs)
      assert booking.user_id == user.id
      assert booking.property == :tahoe
      assert booking.booking_mode == :buyout
    end

    test "create_booking/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Bookings.create_booking(%{})
    end

    test "update_booking/2 with valid data updates the booking" do
      booking = booking_fixture() |> Ysc.Repo.preload(:rooms)
      update_attrs = %{guests_count: 4}

      assert {:ok, %Booking{} = booking} =
               Bookings.update_booking(booking, update_attrs)

      assert booking.guests_count == 4
    end

    test "update_booking/3 with opts passes changeset options" do
      alias Ysc.Bookings.AvailabilityCache

      booking =
        booking_fixture(%{property: :clear_lake}) |> Ysc.Repo.preload(:rooms)

      start_date = booking.checkin_date
      end_date = booking.checkout_date

      AvailabilityCache.get_clear_lake_daily_availability(start_date, end_date)

      assert {:ok, %Booking{} = updated} =
               Bookings.update_booking(
                 booking,
                 %{guests_count: booking.guests_count + 1},
                 skip_validation: true
               )

      assert updated.guests_count == booking.guests_count + 1

      {_cached, queries_after} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            AvailabilityCache.get_clear_lake_daily_availability(
              start_date,
              end_date
            )
          end,
          pattern: ~r/FROM "bookings"/i
        )

      assert queries_after >= 1
    end

    test "update_booking/2 with invalid data returns error changeset" do
      booking = booking_fixture() |> Ysc.Repo.preload(:rooms)

      assert {:error, %Ecto.Changeset{}} =
               Bookings.update_booking(booking, %{user_id: nil})

      # Compare by ID only since associations may differ
      reloaded = Bookings.get_booking!(booking.id)
      assert reloaded.id == booking.id
    end

    test "delete_booking/1 deletes the booking" do
      booking = booking_fixture()
      assert {:ok, %Booking{}} = Bookings.delete_booking(booking)

      assert_raise Ecto.NoResultsError, fn ->
        Bookings.get_booking!(booking.id)
      end
    end
  end

  describe "calculate_booking_price/4" do
    test "calculates price for buyout booking" do
      property = :tahoe
      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 3)
      booking_mode = :buyout

      # Set up pricing rule for buyout
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(500, :USD),
          booking_mode: :buyout,
          price_unit: :buyout_fixed,
          property: :tahoe,
          season_id: nil
        })

      result =
        Bookings.calculate_booking_price(
          property,
          checkin,
          checkout,
          booking_mode
        )

      assert {:ok, total_price, breakdown} = result
      assert is_struct(total_price, Money)
      assert is_map(breakdown)
    end

    test "calculates price for room booking" do
      property = :tahoe
      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 3)
      booking_mode = :room

      room = create_room_fixture(%{property: property})

      # Set up pricing rule for room booking - must match the room_id or room_category_id
      # Since the room has a category, we can match by room_id (most specific) or room_category_id
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          room_id: room.id,
          season_id: nil
        })

      result =
        Bookings.calculate_booking_price(
          property,
          checkin,
          checkout,
          booking_mode,
          room_id: room.id,
          guests_count: 2
        )

      assert {:ok, total_price, breakdown} = result
      assert is_struct(total_price, Money)
      assert is_map(breakdown)
    end

    test "room mode uses property-wide per_person_per_night rule when no room-specific rule exists" do
      property = :tahoe
      checkin = Date.utc_today() |> Date.add(31)
      checkout = Date.add(checkin, 2)
      room = create_room_fixture(%{property: property})

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: nil
        })

      assert {:ok, total_price, breakdown} =
               Bookings.calculate_booking_price(
                 property,
                 checkin,
                 checkout,
                 :room,
                 room_id: room.id,
                 guests_count: 2
               )

      assert is_struct(total_price, Money)
      assert is_map(breakdown)
    end

    test "returns error for invalid booking dates" do
      property = :tahoe
      checkin = Date.utc_today() |> Date.add(30)
      # Invalid: checkout before checkin
      checkout = Date.add(checkin, -1)
      booking_mode = :buyout

      assert {:error, :invalid_date_range} =
               Bookings.calculate_booking_price(
                 property,
                 checkin,
                 checkout,
                 booking_mode
               )
    end

    test "returns error when room booking mode omits room_id" do
      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 2)

      assert {:error, :room_id_required} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 checkin,
                 checkout,
                 :room,
                 guests_count: 2
               )
    end

    test "returns error for invalid checkin_date type" do
      checkout = Date.utc_today() |> Date.add(32)

      assert {:error, :invalid_checkin_date} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 "not-a-date",
                 checkout,
                 :buyout
               )
    end

    test "returns error for invalid checkout_date type" do
      checkin = Date.utc_today() |> Date.add(30)

      assert {:error, :invalid_checkout_date} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 checkin,
                 "not-a-date",
                 :buyout
               )
    end

    test "returns error for invalid_guests_count in room mode" do
      room = create_room_fixture(%{property: :tahoe})
      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 2)

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          room_id: room.id,
          season_id: nil
        })

      assert {:error, :invalid_guests_count} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 checkin,
                 checkout,
                 :room,
                 room_id: room.id,
                 guests_count: 0
               )
    end

    test "returns error for invalid_children_count in room mode" do
      room = create_room_fixture(%{property: :tahoe})
      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 2)

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          room_id: room.id,
          season_id: nil
        })

      assert {:error, :invalid_children_count} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 checkin,
                 checkout,
                 :room,
                 room_id: room.id,
                 guests_count: 2,
                 children_count: -1
               )
    end

    test "returns error for invalid_property in room mode" do
      room = create_room_fixture(%{property: :tahoe})
      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 2)

      assert {:error, :invalid_property} =
               Bookings.calculate_booking_price(
                 "tahoe",
                 checkin,
                 checkout,
                 :room,
                 room_id: room.id,
                 guests_count: 2
               )
    end

    test "returns error for unsupported booking_mode atom" do
      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 2)

      assert {:error, :invalid_booking_mode} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 checkin,
                 checkout,
                 :not_a_booking_mode
               )
    end

    test "calculates price for day booking when a per-guest-per-day rule exists" do
      checkin = Date.utc_today() |> Date.add(45)
      checkout = Date.add(checkin, 1)

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(50, :USD),
          booking_mode: :day,
          price_unit: :per_guest_per_day,
          property: :clear_lake,
          season_id: nil
        })

      assert {:ok, total, breakdown} =
               Bookings.calculate_booking_price(
                 :clear_lake,
                 checkin,
                 checkout,
                 :day,
                 guests_count: 3
               )

      assert Money.positive?(total)
      assert breakdown.guests_count == 3
    end

    test "includes Tahoe children pricing when children_count > 0 and children_amount is set" do
      room = create_room_fixture(%{property: :tahoe})
      checkin = Date.utc_today() |> Date.add(60) |> first_monday_on_or_after()
      checkout = Date.add(checkin, 2)

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          children_amount: Money.new(20, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          room_id: room.id,
          season_id: nil
        })

      assert {:ok, total, breakdown} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 checkin,
                 checkout,
                 :room,
                 room_id: room.id,
                 guests_count: 2,
                 children_count: 2
               )

      assert Money.positive?(total)
      assert breakdown.children_count == 2
      assert Money.positive?(breakdown.children)
    end
  end

  describe "pricing rules" do
    test "list_pricing_rules/0 returns all pricing rules" do
      rule1 = create_pricing_rule_fixture(%{property: :tahoe})
      rule2 = create_pricing_rule_fixture(%{property: :clear_lake})

      rules = Bookings.list_pricing_rules()
      assert length(rules) >= 2
      assert Enum.any?(rules, &(&1.id == rule1.id))
      assert Enum.any?(rules, &(&1.id == rule2.id))
    end

    test "list_pricing_rules/1 returns only rules for the given property" do
      tahoe_rule = create_pricing_rule_fixture(%{property: :tahoe})
      clear_lake_rule = create_pricing_rule_fixture(%{property: :clear_lake})

      tahoe_rules = Bookings.list_pricing_rules(:tahoe)
      clear_lake_rules = Bookings.list_pricing_rules(:clear_lake)

      assert Enum.any?(tahoe_rules, &(&1.id == tahoe_rule.id))
      refute Enum.any?(tahoe_rules, &(&1.id == clear_lake_rule.id))
      assert Enum.all?(tahoe_rules, &(&1.property == :tahoe))

      assert Enum.any?(clear_lake_rules, &(&1.id == clear_lake_rule.id))
      refute Enum.any?(clear_lake_rules, &(&1.id == tahoe_rule.id))
      assert Enum.all?(clear_lake_rules, &(&1.property == :clear_lake))
    end

    test "get_pricing_rule!/1 returns the pricing rule with given id" do
      rule = create_pricing_rule_fixture()
      found = Bookings.get_pricing_rule!(rule.id)
      assert found.id == rule.id
    end

    test "create_pricing_rule/1 with valid data creates a pricing rule" do
      valid_attrs = %{
        amount: Money.new(100, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      assert {:ok, rule} = Bookings.create_pricing_rule(valid_attrs)
      assert rule.property == :tahoe
      assert rule.booking_mode == :room
    end

    test "create_pricing_rule/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Bookings.create_pricing_rule(%{})
    end

    test "update_pricing_rule/2 with valid data updates the pricing rule" do
      rule = create_pricing_rule_fixture()
      update_attrs = %{amount: Money.new(150, :USD)}

      assert {:ok, updated} = Bookings.update_pricing_rule(rule, update_attrs)
      assert Money.equal?(updated.amount, Money.new(150, :USD))
    end

    test "delete_pricing_rule/1 deletes the pricing rule" do
      rule = create_pricing_rule_fixture()
      assert {:ok, %{}} = Bookings.delete_pricing_rule(rule)

      assert_raise Ecto.NoResultsError, fn ->
        Bookings.get_pricing_rule!(rule.id)
      end
    end

    test "update_pricing_rule/2 with invalid data returns error changeset" do
      rule = create_pricing_rule_fixture()

      assert {:error, %Ecto.Changeset{} = cs} =
               Bookings.update_pricing_rule(rule, %{amount: nil})

      assert cs.errors[:amount]
    end
  end

  describe "rooms" do
    test "list_rooms/0 returns all rooms" do
      room1 = create_room_fixture(%{name: "Room 1", property: :tahoe})
      room2 = create_room_fixture(%{name: "Room 2", property: :clear_lake})

      rooms = Bookings.list_rooms()
      assert length(rooms) >= 2
      assert Enum.any?(rooms, &(&1.id == room1.id))
      assert Enum.any?(rooms, &(&1.id == room2.id))
    end

    test "list_rooms/1 filters by property" do
      room1 = create_room_fixture(%{property: :tahoe})
      _room2 = create_room_fixture(%{property: :clear_lake})

      rooms = Bookings.list_rooms(:tahoe)
      assert Enum.any?(rooms, &(&1.id == room1.id))
      refute Enum.any?(rooms, &(&1.property == :clear_lake))
    end

    test "get_room!/1 returns the room with given id" do
      room = create_room_fixture()
      assert Bookings.get_room!(room.id).id == room.id
    end

    test "create_room/1 with valid data creates a room" do
      category = create_room_category_fixture()

      valid_attrs = %{
        name: "Test Room",
        property: :tahoe,
        room_category_id: category.id,
        capacity_max: 4
      }

      assert {:ok, %Room{} = room} = Bookings.create_room(valid_attrs)
      assert room.name == "Test Room"
      assert room.property == :tahoe
    end

    test "create_room/1 returns error changeset when required fields are missing" do
      assert {:error, %Ecto.Changeset{} = cs} = Bookings.create_room(%{})
      assert cs.errors[:name]
      assert cs.errors[:property]
      assert cs.errors[:capacity_max]
    end

    test "update_room/2 returns error changeset when capacity_max is invalid" do
      room = create_room_fixture()

      assert {:error, %Ecto.Changeset{} = cs} =
               Bookings.update_room(room, %{capacity_max: 0})

      assert cs.errors[:capacity_max]
    end

    test "update_room/2 with valid data updates the room" do
      room = create_room_fixture()
      update_attrs = %{name: "Updated Room"}

      assert {:ok, %Room{} = room} = Bookings.update_room(room, update_attrs)
      assert room.name == "Updated Room"
    end

    test "delete_room/1 deletes the room" do
      room = create_room_fixture()
      assert {:ok, %Room{}} = Bookings.delete_room(room)
      assert_raise Ecto.NoResultsError, fn -> Bookings.get_room!(room.id) end
    end

    test "list_rooms_by_ids/1 returns rooms matching the given ids" do
      room1 = create_room_fixture(%{property: :tahoe})
      room2 = create_room_fixture(%{property: :tahoe})

      results = Bookings.list_rooms_by_ids([room1.id, room2.id])

      assert length(results) == 2

      assert MapSet.new(Enum.map(results, & &1.id)) ==
               MapSet.new([room1.id, room2.id])
    end

    test "list_rooms_by_ids/1 returns empty list for empty input" do
      assert Bookings.list_rooms_by_ids([]) == []
    end

    test "list_rooms_by_ids/1 filters nil ids and deduplicates" do
      room = create_room_fixture()

      assert [%Room{id: id}] =
               Bookings.list_rooms_by_ids([room.id, nil, room.id])

      assert id == room.id
    end

    test "list_rooms_by_ids/1 ignores unknown ids" do
      room = create_room_fixture()
      missing = Ecto.ULID.generate()

      assert [%Room{id: id}] = Bookings.list_rooms_by_ids([room.id, missing])
      assert id == room.id
    end
  end

  describe "room categories" do
    test "list_room_categories/0 returns all room categories" do
      category1 = create_room_category_fixture()
      category2 = create_room_category_fixture()

      categories = Bookings.list_room_categories()
      assert length(categories) >= 2
      assert Enum.any?(categories, &(&1.id == category1.id))
      assert Enum.any?(categories, &(&1.id == category2.id))
    end
  end

  describe "booking guests" do
    test "list_booking_guests/1 returns empty list when booking has no guests" do
      booking = booking_fixture()
      assert Bookings.list_booking_guests(booking.id) == []
    end

    test "list_booking_guests/1 returns guests after create_booking_guests/2" do
      booking = booking_fixture()

      assert {:ok, _} =
               Bookings.create_booking_guests(booking.id, [
                 {0, %{first_name: "A", last_name: "B"}}
               ])

      guests = Bookings.list_booking_guests(booking.id)
      assert length(guests) == 1
      assert hd(guests).first_name == "A"
    end

    test "create_booking_guests/2 creates guests for booking" do
      booking = booking_fixture()

      guests_attrs = [
        {0, %{first_name: "John", last_name: "Doe"}},
        {1, %{first_name: "Jane", last_name: "Doe"}}
      ]

      assert {:ok, guests} =
               Bookings.create_booking_guests(booking.id, guests_attrs)

      assert length(guests) == 2
    end

    test "create_booking_guests/2 returns error when guest attributes are invalid" do
      booking = booking_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Bookings.create_booking_guests(booking.id, [
                 {0, %{first_name: "MissingLastName"}}
               ])
    end

    test "delete_booking_guests/1 deletes all guests for booking" do
      booking = booking_fixture()
      # create_booking_guests expects a list of tuples {index, guest_attrs}
      guests_attrs = [{0, %{first_name: "John", last_name: "Doe"}}]
      {:ok, _guests} = Bookings.create_booking_guests(booking.id, guests_attrs)

      # delete_booking_guests returns {count, nil} from Repo.delete_all
      {count, _} = Bookings.delete_booking_guests(booking.id)
      assert count == 1
      guests = Bookings.list_booking_guests(booking.id)
      assert guests == []
    end
  end

  describe "paginated bookings" do
    test "list_paginated_bookings/1 returns paginated results" do
      _booking1 = booking_fixture()
      _booking2 = booking_fixture()

      params = %{page: 1, page_size: 10}
      assert {:ok, {bookings, meta}} = Bookings.list_paginated_bookings(params)

      assert is_list(bookings)
      assert length(bookings) >= 2
      assert meta.total_count >= 2
      assert meta.page_size == 10
      assert meta.current_page == 1
    end

    test "list_paginated_bookings/2 with search term filters results" do
      user = user_fixture()
      _booking = booking_fixture(%{user_id: user.id})

      params = %{page: 1, page_size: 10}
      # Function returns {:ok, {bookings, meta}} tuple
      assert {:ok, {bookings, _meta}} =
               Bookings.list_paginated_bookings(params, user.email)

      assert is_list(bookings)
    end

    test "list_user_bookings_paginated/2 returns user's bookings" do
      user = user_fixture()
      _booking1 = booking_fixture(%{user_id: user.id})
      _booking2 = booking_fixture(%{user_id: user.id})

      params = %{page: 1, page_size: 10}
      # Function returns {:ok, {bookings, meta}} tuple
      assert {:ok, {bookings, meta}} =
               Bookings.list_user_bookings_paginated(user.id, params)

      assert is_list(bookings)
      assert meta.current_page == 1
    end

    test "list_user_bookings_paginated/2 returns error for invalid Flop params" do
      user = user_fixture()

      assert {:error, %Flop.Meta{errors: errors}} =
               Bookings.list_user_bookings_paginated(user.id, %{
                 "limit" => "not_a_number"
               })

      assert Keyword.has_key?(errors, :limit)
    end

    test "list_paginated_bookings/1 returns error for invalid Flop params" do
      _booking = booking_fixture()

      assert {:error, %Flop.Meta{errors: errors}} =
               Bookings.list_paginated_bookings(%{"limit" => "not_a_number"})

      assert Keyword.has_key?(errors, :limit)
    end

    test "list_paginated_bookings/2 with nil search_term delegates to list_paginated_bookings/1" do
      _booking1 = booking_fixture()
      _booking2 = booking_fixture()
      params = %{page: 1, page_size: 10}

      assert {:ok, {bookings_a, meta_a}} =
               Bookings.list_paginated_bookings(params)

      assert {:ok, {bookings_b, meta_b}} =
               Bookings.list_paginated_bookings(params, nil)

      assert length(bookings_a) == length(bookings_b)
      assert meta_a.total_count == meta_b.total_count
    end
  end

  describe "validate_bookings_for_check_in/1" do
    defp today_pst,
      do: DateTime.now!("America/Los_Angeles") |> DateTime.to_date()

    defp check_in_booking(overrides \\ %{}) do
      today = today_pst()
      {default_checkin, default_checkout} = active_stay_dates(today)

      defaults = %{
        status: :complete,
        checked_in: false,
        checkin_date: default_checkin,
        checkout_date: default_checkout,
        reference_id: "BKG-TEST-#{System.unique_integer([:positive])}"
      }

      struct!(Booking, Map.merge(defaults, Map.new(overrides)))
    end

    test "returns :ok for eligible confirmed bookings in an active stay window" do
      assert :ok = Bookings.validate_bookings_for_check_in([check_in_booking()])
    end

    test "returns :ok for multiple eligible bookings" do
      assert :ok =
               Bookings.validate_bookings_for_check_in([
                 check_in_booking(),
                 check_in_booking()
               ])
    end

    test "returns :ok on check-in date (first day of stay)" do
      today = today_pst()

      booking =
        check_in_booking(%{
          checkin_date: today,
          checkout_date: Date.add(today, 2)
        })

      assert :ok = Bookings.validate_bookings_for_check_in([booking])
    end

    test "returns :ok when checkout date is tomorrow (last night of stay)" do
      today = today_pst()

      booking =
        check_in_booking(%{
          checkin_date: Date.add(today, -2),
          checkout_date: Date.add(today, 1)
        })

      assert :ok = Bookings.validate_bookings_for_check_in([booking])
    end

    test "rejects bookings that are not confirmed" do
      booking = check_in_booking(%{status: :hold})

      assert {:error, message} =
               Bookings.validate_bookings_for_check_in([booking])

      assert message =~ "not confirmed"
      assert message =~ "hold"
    end

    test "rejects canceled bookings" do
      booking = check_in_booking(%{status: :canceled})

      assert {:error, message} =
               Bookings.validate_bookings_for_check_in([booking])

      assert message =~ "not confirmed"
    end

    test "rejects future bookings" do
      today = today_pst()

      booking =
        check_in_booking(%{
          checkin_date: Date.add(today, 3),
          checkout_date: Date.add(today, 5)
        })

      assert {:error, message} =
               Bookings.validate_bookings_for_check_in([booking])

      assert message =~ "not yet active"
    end

    test "rejects ended bookings" do
      today = today_pst()

      booking =
        check_in_booking(%{
          checkin_date: Date.add(today, -5),
          checkout_date: Date.add(today, -1)
        })

      assert {:error, message} =
               Bookings.validate_bookings_for_check_in([booking])

      assert message =~ "already ended"
    end

    test "rejects bookings on checkout day (stay has ended)" do
      today = today_pst()

      booking =
        check_in_booking(%{
          checkin_date: Date.add(today, -3),
          checkout_date: today
        })

      assert {:error, message} =
               Bookings.validate_bookings_for_check_in([booking])

      assert message =~ "already ended"
    end

    test "rejects already checked-in bookings" do
      booking = check_in_booking(%{checked_in: true})

      assert {:error, message} =
               Bookings.validate_bookings_for_check_in([booking])

      assert message =~ "already checked in"
    end

    test "halts on first ineligible booking when validating multiple" do
      valid = check_in_booking()
      invalid = check_in_booking(%{status: :canceled})

      assert {:error, message} =
               Bookings.validate_bookings_for_check_in([valid, invalid])

      assert message =~ "not confirmed"
    end

    test "uses reference_id in error messages when available" do
      ref = "BK-TEST-#{System.unique_integer([:positive])}"
      booking = check_in_booking(%{status: :canceled, reference_id: ref})

      assert {:error, message} =
               Bookings.validate_bookings_for_check_in([booking])

      assert message =~ ref
    end
  end

  describe "ensure_user_may_book/1" do
    test "returns :ok for active users with lifetime membership" do
      user = user_with_membership(:lifetime, %{state: :active})

      assert :ok = Bookings.ensure_user_may_book(user)
    end

    test "rejects users without active membership" do
      user = user_with_membership(:none, %{state: :active})

      assert {:error, :membership_required} =
               Bookings.ensure_user_may_book(user)
    end

    test "rejects non-active users before checking membership" do
      user = user_with_membership(:lifetime, %{state: :suspended})

      assert {:error, :application_pending_approval} =
               Bookings.ensure_user_may_book(user)
    end

    test "rejects pending approval users" do
      user = user_fixture(%{state: :pending_approval})

      assert {:error, :application_pending_approval} =
               Bookings.ensure_user_may_book(user)
    end
  end

  describe "check-ins" do
    test "create_check_in/1 creates a check-in" do
      booking = booking_fixture()

      attrs = %{
        bookings: [booking],
        rules_agreed: true,
        checked_in_at: DateTime.utc_now()
      }

      assert {:ok, check_in} = Bookings.create_check_in(attrs)
      assert check_in.id != nil
      # Check that the booking is associated
      check_in = Ysc.Repo.preload(check_in, :bookings)
      assert length(check_in.bookings) == 1
      assert Enum.at(check_in.bookings, 0).id == booking.id
      assert Ysc.Repo.get!(Ysc.Bookings.Booking, booking.id).checked_in == true
    end

    test "create_check_in/1 persists vehicles when provided" do
      booking = booking_fixture()

      assert {:ok, check_in} =
               Bookings.create_check_in(%{
                 bookings: [booking],
                 rules_agreed: true,
                 vehicles: [
                   %{
                     "type" => "car",
                     "color" => "silver",
                     "make" => "Honda"
                   }
                 ]
               })

      loaded = Bookings.get_check_in!(check_in.id)
      assert length(loaded.check_in_vehicles) == 1
      v = hd(loaded.check_in_vehicles)
      assert v.type == "car"
      assert v.color == "silver"
      assert v.make == "Honda"
    end

    test "get_check_in!/1 returns check-in by id" do
      booking = booking_fixture()

      {:ok, check_in} =
        Bookings.create_check_in(%{
          booking_id: booking.id,
          checked_in_at: DateTime.utc_now()
        })

      found = Bookings.get_check_in!(check_in.id)
      assert found.id == check_in.id
    end

    test "list_check_ins_by_booking/1 returns check-ins for booking" do
      booking = booking_fixture()

      {:ok, _check_in} =
        Bookings.create_check_in(%{
          bookings: [booking],
          rules_agreed: true,
          checked_in_at: DateTime.utc_now()
        })

      check_ins = Bookings.list_check_ins_by_booking(booking.id)
      assert is_list(check_ins)
      assert check_ins != []
    end

    test "list_check_ins_by_booking/1 returns empty list when booking has no check-ins" do
      booking = booking_fixture()
      assert Bookings.list_check_ins_by_booking(booking.id) == []
    end

    test "get_booking_by_reference_id/1 returns nil when reference does not exist" do
      assert Bookings.get_booking_by_reference_id("BK-NONEXISTENT-REF") == nil
    end

    test "get_booking_by_reference_id/1 returns booking when reference matches" do
      booking = booking_fixture()

      assert %Booking{} =
               found =
               Bookings.get_booking_by_reference_id(booking.reference_id)

      assert found.id == booking.id
    end

    test "list_user_bookings_paginated/2 returns empty list when user has no bookings" do
      user = user_fixture()
      params = %{page: 1, page_size: 10}

      assert {:ok, {bookings, meta}} =
               Bookings.list_user_bookings_paginated(user.id, params)

      assert bookings == []
      assert meta.total_count == 0
    end

    test "get_booking!/1 preloads booking_guests and rooms" do
      booking = booking_fixture()
      loaded = Bookings.get_booking!(booking.id)
      assert Ecto.assoc_loaded?(loaded.rooms)
      assert Ecto.assoc_loaded?(loaded.booking_guests)
    end

    test "mark_booking_checked_in/1 marks booking as checked in" do
      booking = booking_fixture()
      refute booking.checked_in

      # mark_booking_checked_in now preloads rooms internally
      assert {:ok, updated} = Bookings.mark_booking_checked_in(booking.id)
      assert updated.checked_in == true

      reloaded = Ysc.Repo.get!(Ysc.Bookings.Booking, booking.id)
      assert reloaded.checked_in == true
    end
  end

  describe "blackouts" do
    test "list_blackouts/0 returns all blackouts" do
      blackout1 = create_blackout_fixture(%{property: :tahoe})
      blackout2 = create_blackout_fixture(%{property: :clear_lake})

      blackouts = Bookings.list_blackouts()
      assert length(blackouts) >= 2
      assert Enum.any?(blackouts, &(&1.id == blackout1.id))
      assert Enum.any?(blackouts, &(&1.id == blackout2.id))
    end

    test "list_blackouts/3 filters by property and date range" do
      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 2)

      blackout =
        create_blackout_fixture(%{
          property: :tahoe,
          start_date: checkin,
          end_date: checkout
        })

      blackouts = Bookings.list_blackouts(:tahoe, checkin, checkout)
      assert Enum.any?(blackouts, &(&1.id == blackout.id))
    end

    test "get_blackout!/1 returns blackout by id" do
      blackout = create_blackout_fixture()
      found = Bookings.get_blackout!(blackout.id)
      assert found.id == blackout.id
    end

    test "create_blackout/1 creates a blackout" do
      attrs = %{
        property: :tahoe,
        start_date: Date.utc_today() |> Date.add(30),
        end_date: Date.utc_today() |> Date.add(32),
        reason: "Maintenance"
      }

      assert {:ok, blackout} = Bookings.create_blackout(attrs)
      assert blackout.property == :tahoe
    end

    test "update_blackout/2 updates a blackout" do
      blackout = create_blackout_fixture()
      update_attrs = %{reason: "Updated reason"}

      assert {:ok, updated} = Bookings.update_blackout(blackout, update_attrs)
      assert updated.reason == "Updated reason"
    end

    test "delete_blackout/1 deletes a blackout" do
      blackout = create_blackout_fixture()
      assert {:ok, %{}} = Bookings.delete_blackout(blackout)

      assert_raise Ecto.NoResultsError, fn ->
        Bookings.get_blackout!(blackout.id)
      end
    end

    test "has_blackout?/3 checks if property has blackout for dates" do
      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 2)

      _blackout =
        create_blackout_fixture(%{
          property: :tahoe,
          start_date: checkin,
          end_date: checkout
        })

      assert Bookings.has_blackout?(:tahoe, checkin, checkout) == true

      assert Bookings.has_blackout?(
               :tahoe,
               Date.add(checkin, 10),
               Date.add(checkin, 12)
             ) == false
    end

    test "has_blackout?/3 treats single-day blackout as blocking that night" do
      night = Date.utc_today() |> Date.add(35)

      _blackout =
        create_blackout_fixture(%{
          property: :tahoe,
          start_date: night,
          end_date: night
        })

      # Overnight on the blackout night conflicts
      assert Bookings.has_blackout?(:tahoe, night, Date.add(night, 1)) == true

      # Checkout on the blackout day is allowed (leave by 11am)
      assert Bookings.has_blackout?(:tahoe, Date.add(night, -1), night) == false

      # Check-in on the day after a single-day blackout is allowed
      assert Bookings.has_blackout?(
               :tahoe,
               Date.add(night, 1),
               Date.add(night, 2)
             ) == false
    end

    test "has_blackout?/3 allows check-in on multi-day blackout end date" do
      start_date = Date.utc_today() |> Date.add(40)
      end_date = Date.add(start_date, 3)

      _blackout =
        create_blackout_fixture(%{
          property: :tahoe,
          start_date: start_date,
          end_date: end_date
        })

      assert Bookings.has_blackout?(:tahoe, end_date, Date.add(end_date, 1)) ==
               false

      assert Bookings.has_blackout?(
               :tahoe,
               Date.add(end_date, -1),
               Date.add(end_date, 1)
             ) == true
    end

    test "blackout_occupied_nights/1 and stay_occupied_nights/2 match turnaround model" do
      assert Bookings.stay_occupied_nights(~D[2026-07-24], ~D[2026-07-26]) == [
               ~D[2026-07-24],
               ~D[2026-07-25]
             ]

      assert Bookings.blackout_occupied_nights(%{
               start_date: ~D[2026-07-26],
               end_date: ~D[2026-07-29]
             }) == [
               ~D[2026-07-26],
               ~D[2026-07-27],
               ~D[2026-07-28]
             ]

      assert Bookings.blackout_occupied_nights(%{
               start_date: ~D[2026-07-26],
               end_date: ~D[2026-07-26]
             }) == [~D[2026-07-26]]
    end

    test "get_overlapping_blackouts/3 returns overlapping blackouts" do
      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 2)

      blackout =
        create_blackout_fixture(%{
          property: :tahoe,
          start_date: checkin,
          end_date: checkout
        })

      overlapping =
        Bookings.get_overlapping_blackouts(:tahoe, checkin, checkout)

      assert Enum.any?(overlapping, &(&1.id == blackout.id))
    end
  end

  describe "utility functions" do
    test "bookings_overlap?/4 detects overlapping bookings" do
      checkin1 = ~D[2025-06-01]
      checkout1 = ~D[2025-06-05]
      checkin2 = ~D[2025-06-03]
      checkout2 = ~D[2025-06-07]

      assert Bookings.bookings_overlap?(
               checkin1,
               checkout1,
               checkin2,
               checkout2
             ) == true

      assert Bookings.bookings_overlap?(
               checkin1,
               checkout1,
               ~D[2025-06-10],
               ~D[2025-06-12]
             ) ==
               false
    end

    test "checkin_time/0 returns check-in time" do
      assert Bookings.checkin_time() == ~T[15:00:00]
    end

    test "checkout_time/0 returns check-out time" do
      assert Bookings.checkout_time() == ~T[11:00:00]
    end

    test "room_available?/3 checks room availability" do
      room = create_room_fixture()
      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 2)

      # Room should be available when no bookings exist
      assert Bookings.room_available?(room.id, checkin, checkout) == true
    end

    test "get_available_rooms/3 returns available rooms" do
      _room = create_room_fixture(%{property: :tahoe})
      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 2)

      rooms = Bookings.get_available_rooms(:tahoe, checkin, checkout)
      assert is_list(rooms)
    end

    test "batch_check_room_availability/4 checks multiple rooms" do
      room1 = create_room_fixture(%{property: :tahoe})
      room2 = create_room_fixture(%{property: :tahoe})
      checkin = Date.utc_today() |> Date.add(90) |> first_monday_on_or_after()
      checkout = Date.add(checkin, 2)

      results =
        Bookings.batch_check_room_availability(
          [room1.id, room2.id],
          :tahoe,
          checkin,
          checkout
        )

      assert %MapSet{} = results
      # Verify both rooms are in the results (they should be available)
      assert MapSet.member?(results, room1.id)
      assert MapSet.member?(results, room2.id)
    end
  end

  describe "door codes" do
    test "get_active_door_code/1 returns active door code for property" do
      code = create_door_code_fixture(%{property: :tahoe, is_active: true})
      active = Bookings.get_active_door_code(:tahoe)
      assert active.id == code.id
    end

    test "list_door_codes/1 returns door codes for property" do
      code1 = create_door_code_fixture(%{property: :tahoe})
      _code2 = create_door_code_fixture(%{property: :clear_lake})

      codes = Bookings.list_door_codes(:tahoe)
      assert Enum.any?(codes, &(&1.id == code1.id))
    end

    test "get_recent_door_codes/2 returns recent door codes" do
      code1 = create_door_code_fixture(%{property: :tahoe})
      _code2 = create_door_code_fixture(%{property: :tahoe})

      codes = Bookings.get_recent_door_codes(:tahoe, code1.code)
      assert is_list(codes)
    end

    test "get_recent_door_codes/2 excludes the given code from results" do
      excluded = create_door_code_fixture(%{property: :tahoe})
      _other = create_door_code_fixture(%{property: :tahoe})

      recent = Bookings.get_recent_door_codes(:tahoe, excluded.code)
      refute Enum.any?(recent, &(&1.code == excluded.code))
    end

    test "create_door_code/1 creates a door code" do
      attrs = %{
        property: :tahoe,
        code: "1234",
        is_active: true
      }

      assert {:ok, door_code} = Bookings.create_door_code(attrs)
      assert door_code.property == :tahoe
      assert door_code.code == "1234"
    end

    test "get_door_code!/1 returns door code by id" do
      code = create_door_code_fixture()
      found = Bookings.get_door_code!(code.id)
      assert found.id == code.id
    end
  end

  describe "refund policies" do
    test "list_refund_policies/0 returns all refund policies" do
      policy1 = create_refund_policy_fixture(%{property: :tahoe})
      policy2 = create_refund_policy_fixture(%{property: :clear_lake})

      policies = Bookings.list_refund_policies()
      assert length(policies) >= 2
      assert Enum.any?(policies, &(&1.id == policy1.id))
      assert Enum.any?(policies, &(&1.id == policy2.id))
    end

    test "list_refund_policies/2 filters by property and booking mode" do
      policy =
        create_refund_policy_fixture(%{property: :tahoe, booking_mode: :buyout})

      _other =
        create_refund_policy_fixture(%{
          property: :clear_lake,
          booking_mode: :room
        })

      policies = Bookings.list_refund_policies(:tahoe, :buyout)
      assert Enum.any?(policies, &(&1.id == policy.id))
    end

    test "get_refund_policy!/1 returns refund policy by id" do
      policy = create_refund_policy_fixture()
      found = Bookings.get_refund_policy!(policy.id)
      assert found.id == policy.id
    end

    test "get_active_refund_policy/2 returns active policy" do
      _inactive =
        create_refund_policy_fixture(%{property: :tahoe, is_active: false})

      active =
        create_refund_policy_fixture(%{
          property: :tahoe,
          is_active: true,
          booking_mode: :buyout
        })

      found = Bookings.get_active_refund_policy(:tahoe, :buyout)
      assert found.id == active.id
    end

    test "create_refund_policy/1 creates a refund policy" do
      attrs = %{
        property: :tahoe,
        booking_mode: :buyout,
        is_active: true,
        name: "Test Policy"
      }

      assert {:ok, policy} = Bookings.create_refund_policy(attrs)
      assert policy.property == :tahoe
    end

    test "update_refund_policy/2 updates a refund policy" do
      policy = create_refund_policy_fixture()
      update_attrs = %{name: "Updated Policy"}

      assert {:ok, updated} =
               Bookings.update_refund_policy(policy, update_attrs)

      assert updated.name == "Updated Policy"
    end

    test "delete_refund_policy/1 deletes a refund policy" do
      policy = create_refund_policy_fixture()
      assert {:ok, %{}} = Bookings.delete_refund_policy(policy)

      assert_raise Ecto.NoResultsError, fn ->
        Bookings.get_refund_policy!(policy.id)
      end
    end
  end

  describe "refund policy rules" do
    test "list_refund_policy_rules/1 returns rules for policy" do
      policy = create_refund_policy_fixture()
      rule = create_refund_policy_rule_fixture(%{refund_policy_id: policy.id})

      rules = Bookings.list_refund_policy_rules(policy.id)
      assert Enum.any?(rules, &(&1.id == rule.id))
    end

    test "get_refund_policy_rule!/1 returns rule by id" do
      rule = create_refund_policy_rule_fixture()
      found = Bookings.get_refund_policy_rule!(rule.id)
      assert found.id == rule.id
    end

    test "create_refund_policy_rule/1 creates a rule" do
      policy = create_refund_policy_fixture()

      attrs = %{
        refund_policy_id: policy.id,
        days_before_checkin: 7,
        refund_percentage: 50
      }

      assert {:ok, rule} = Bookings.create_refund_policy_rule(attrs)
      assert rule.refund_policy_id == policy.id
    end

    test "update_refund_policy_rule/2 updates a rule" do
      rule = create_refund_policy_rule_fixture()
      update_attrs = %{refund_percentage: 75}

      assert {:ok, updated} =
               Bookings.update_refund_policy_rule(rule, update_attrs)

      # refund_percentage is stored as Decimal, so compare with Decimal
      assert Decimal.equal?(updated.refund_percentage, Decimal.new(75))
    end

    test "delete_refund_policy_rule/1 deletes a rule" do
      rule = create_refund_policy_rule_fixture()
      assert {:ok, %{}} = Bookings.delete_refund_policy_rule(rule)

      assert_raise Ecto.NoResultsError, fn ->
        Bookings.get_refund_policy_rule!(rule.id)
      end
    end
  end

  describe "refund calculations" do
    test "calculate_refund/2 calculates refund amount" do
      # Deactivate any active policy left over from earlier tests in this shared-sandbox
      # module so calculate_refund always follows the deterministic "no policy" path.
      from(p in Ysc.Bookings.RefundPolicy,
        where: p.property == ^:tahoe,
        where: p.booking_mode == ^:buyout,
        where: p.is_active == true
      )
      |> Ysc.Repo.update_all(set: [is_active: false])

      # Raw update_all bypasses Bookings context — must invalidate cache or
      # get_active_refund_policy/2 still serves a stale policy.
      Ysc.Bookings.RefundPolicyCache.invalidate()

      booking = booking_fixture(%{total_price: Money.new(10_000, :USD)})
      cancellation_date = Date.utc_today()

      assert {:ok, nil, nil} =
               Bookings.calculate_refund(booking, cancellation_date)
    end

    test "get_booking_payment_amount/1 returns payment amount for booking" do
      booking = booking_fixture()
      # Function returns {:ok, amount} or {:error, :payment_not_found}
      # Since booking_fixture doesn't create a payment, we expect an error
      result = Bookings.get_booking_payment_amount(booking)
      assert {:error, :payment_not_found} = result
    end
  end

  describe "search functions" do
    test "search_bookings_by_last_name/2 searches bookings by last name" do
      user = user_fixture(%{last_name: "Smith"})
      _booking = booking_fixture(%{user_id: user.id})

      results = Bookings.search_bookings_by_last_name("Smith", :tahoe)
      assert is_list(results)
    end

    test "search_bookings_by_last_name/2 returns empty list for blank query" do
      assert Bookings.search_bookings_by_last_name("   ", :tahoe) == []
      assert Bookings.search_bookings_by_last_name("", :clear_lake) == []
    end

    test "search_bookings_by_last_name/2 finds active clear_lake booking by owner last name" do
      suffix = "#{System.unique_integer([:positive])}"
      last_name = "LakeSearch#{suffix}"
      user = user_fixture(%{last_name: last_name})

      {:ok, booking} =
        Bookings.create_booking(%{
          user_id: user.id,
          property: :clear_lake,
          booking_mode: :day,
          checkin_date: Date.add(Date.utc_today(), -2),
          checkout_date: Date.add(Date.utc_today(), 3),
          guests_count: 2,
          status: :complete,
          total_price: Money.new(100, :USD)
        })

      results = Bookings.search_bookings_by_last_name(last_name, :clear_lake)
      assert Enum.any?(results, &(&1.id == booking.id))
    end

    test "search_bookings_by_last_name/2 batch preloads guests and check-ins without N+1" do
      suffix = System.unique_integer([:positive])
      last_name = "BatchSearch#{suffix}"
      today = DateTime.now!("America/Los_Angeles") |> DateTime.to_date()

      {checkin, checkout} = active_stay_dates(today)

      for _ <- 1..3 do
        user = user_fixture(%{last_name: last_name})

        booking_fixture(%{
          user_id: user.id,
          property: :tahoe,
          checkin_date: checkin,
          checkout_date: checkout
        })
      end

      {results, query_count} =
        Ysc.QueryCounter.with_query_counter(fn ->
          Bookings.search_bookings_by_last_name(last_name, :tahoe)
        end)

      assert length(results) == 3

      for booking <- results do
        assert Ecto.assoc_loaded?(booking.booking_guests)
        assert Ecto.assoc_loaded?(booking.check_ins)
      end

      # One main query plus batched association preloads — not one preload per booking.
      assert query_count <= 6
    end
  end

  describe "get_booking_payment/1" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    test "returns payment for booking", %{user: user} do
      booking = booking_fixture(%{user_id: user.id})

      # Create a payment for the booking
      {:ok, {payment, _, _}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id: "pi_booking_payment",
          stripe_fee: Money.new(320, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, found} = Bookings.get_booking_payment(booking)
      assert found.id == payment.id
    end

    test "returns nil when booking has no payment" do
      booking = booking_fixture()

      assert {:error, :payment_not_found} =
               Bookings.get_booking_payment(booking)
    end
  end

  describe "daily availability" do
    test "get_tahoe_daily_availability/2 returns availability data" do
      start_date = Date.utc_today() |> Date.add(30)
      end_date = Date.add(start_date, 7)

      availability = Bookings.get_tahoe_daily_availability(start_date, end_date)
      assert is_map(availability)
      # Verify it has the expected structure for each date
      Enum.each(Date.range(start_date, end_date), fn date ->
        assert Map.has_key?(availability, date)
        date_data = availability[date]
        assert Map.has_key?(date_data, :has_room_booking)
        assert Map.has_key?(date_data, :has_buyout)
      end)
    end

    test "get_clear_lake_daily_availability/2 returns availability data" do
      start_date = Date.utc_today() |> Date.add(30)
      end_date = Date.add(start_date, 7)

      availability =
        Bookings.get_clear_lake_daily_availability(start_date, end_date)

      assert is_map(availability)
      # Verify it has the expected structure for each date
      Enum.each(Date.range(start_date, end_date), fn date ->
        assert Map.has_key?(availability, date)
        date_data = availability[date]
        assert is_map(date_data)
      end)
    end

    test "can_book_day is true even when more than 12 guests are already booked" do
      user = user_fixture()
      start_date = Date.utc_today() |> Date.add(60)
      end_date = Date.add(start_date, 3)

      # Create two a la carte bookings that together exceed 12 guests
      {:ok, _b1} =
        Bookings.create_booking(%{
          user_id: user.id,
          property: :clear_lake,
          booking_mode: :day,
          checkin_date: start_date,
          checkout_date: end_date,
          guests_count: 8,
          status: :complete,
          total_price: Money.new(100, :USD)
        })

      {:ok, _b2} =
        Bookings.create_booking(%{
          user_id: user.id,
          property: :clear_lake,
          booking_mode: :day,
          checkin_date: start_date,
          checkout_date: end_date,
          guests_count: 6,
          status: :complete,
          total_price: Money.new(100, :USD)
        })

      availability =
        Bookings.get_clear_lake_daily_availability(start_date, end_date)

      night = start_date
      day_data = availability[night]

      assert day_data.day_bookings_count == 14
      # No hard cap — day bookings should still be permitted
      assert day_data.can_book_day == true
    end

    test "can_book_day is false when a buyout is on the same date" do
      user = user_fixture()
      start_date = Date.utc_today() |> Date.add(60)
      end_date = Date.add(start_date, 2)

      {:ok, _buyout} =
        Bookings.create_booking(%{
          user_id: user.id,
          property: :clear_lake,
          booking_mode: :buyout,
          checkin_date: start_date,
          checkout_date: end_date,
          guests_count: 10,
          status: :complete,
          total_price: Money.new(500, :USD)
        })

      availability =
        Bookings.get_clear_lake_daily_availability(start_date, end_date)

      night = start_date
      day_data = availability[night]

      assert day_data.has_buyout == true
      assert day_data.can_book_day == false
    end

    test "day_bookings_count accumulates across multiple bookings" do
      user = user_fixture()
      start_date = Date.utc_today() |> Date.add(45)
      end_date = Date.add(start_date, 2)

      {:ok, _b1} =
        Bookings.create_booking(%{
          user_id: user.id,
          property: :clear_lake,
          booking_mode: :day,
          checkin_date: start_date,
          checkout_date: end_date,
          guests_count: 3,
          status: :complete,
          total_price: Money.new(100, :USD)
        })

      {:ok, _b2} =
        Bookings.create_booking(%{
          user_id: user.id,
          property: :clear_lake,
          booking_mode: :day,
          checkin_date: start_date,
          checkout_date: end_date,
          guests_count: 4,
          status: :complete,
          total_price: Money.new(100, :USD)
        })

      availability =
        Bookings.get_clear_lake_daily_availability(start_date, end_date)

      day_data = availability[start_date]
      assert day_data.day_bookings_count == 7
    end
  end

  describe "pending refunds" do
    test "list_pending_refunds/0 returns pending refunds" do
      refunds = Bookings.list_pending_refunds()
      assert is_list(refunds)
    end

    test "get_pending_refund!/1 returns pending refund by id" do
      # This test may need a pending refund fixture
      # For now, we'll test that it raises when not found
      assert_raise Ecto.NoResultsError, fn ->
        Bookings.get_pending_refund!(Ecto.ULID.generate())
      end
    end

    test "get_pending_refund!/1 returns pending refund when one exists" do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id})

      {:ok, booking} =
        booking
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update()

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_pending_refund_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(100, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, pr} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: Money.new(1000, :USD),
          status: :pending
        })
        |> Ysc.Repo.insert()

      found = Bookings.get_pending_refund!(pr.id)
      assert found.id == pr.id
      assert Ecto.assoc_loaded?(found.booking)
      assert Ecto.assoc_loaded?(found.payment)
    end

    test "reject_pending_refund/3 marks refund as rejected" do
      user = user_fixture()
      admin = user_fixture(%{role: :admin})
      booking = booking_fixture(%{user_id: user.id})

      {:ok, booking} =
        booking
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update()

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_reject_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(100, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, pr} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: Money.new(1000, :USD),
          status: :pending
        })
        |> Ysc.Repo.insert()

      assert {:ok, updated} =
               Bookings.reject_pending_refund(pr, "No funds", admin)

      assert updated.status == :rejected
      assert updated.admin_notes == "No funds"
      assert updated.reviewed_by_id == admin.id
    end

    test "approve_pending_refund/4 completes when payment has Stripe intent" do
      previous_stripe = Application.get_env(:ysc, :stripe_client)

      Application.put_env(
        :ysc,
        :stripe_client,
        Ysc.StripeRefundApproveTestClient
      )

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, previous_stripe)
      end)

      user = user_fixture()
      admin = user_fixture(%{role: :admin})
      booking = booking_fixture(%{user_id: user.id})

      {:ok, booking} =
        booking
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update()

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_approve_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(100, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, pr} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: Money.new(5000, :USD),
          status: :pending
        })
        |> Ysc.Repo.insert()

      assert {:ok, updated, _stripe_refund_id} =
               Bookings.approve_pending_refund(pr, nil, "Approved", admin)

      assert updated.status == :approved
      assert updated.reviewed_by_id == admin.id
    end

    test "approve_pending_refund/4 approves $0 policy refund without Stripe or ledger refund" do
      previous_stripe = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, Ysc.StripeRetrieveBlockedClient)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, previous_stripe)
      end)

      user = user_fixture()
      admin = user_fixture(%{role: :admin})
      booking = booking_fixture(%{user_id: user.id})

      {:ok, booking} =
        booking
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update()

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_approve_zero_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(100, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      zero_policy = Money.new!(:USD, "0")

      {:ok, pr} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: zero_policy,
          status: :pending
        })
        |> Ysc.Repo.insert()

      assert {:ok, updated, nil} =
               Bookings.approve_pending_refund(pr, nil, nil, admin)

      assert updated.status == :approved
      assert updated.reviewed_by_id == admin.id
      assert Money.equal?(updated.admin_refund_amount, zero_policy)

      ref_count =
        Ysc.Repo.aggregate(
          from(r in Ysc.Ledgers.Refund, where: r.payment_id == ^payment.id),
          :count
        )

      assert ref_count == 0
    end

    test "approve_pending_refund/4 returns invalid_refund_amount for negative admin amount" do
      previous_stripe = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, Ysc.StripeRetrieveBlockedClient)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, previous_stripe)
      end)

      user = user_fixture()
      admin = user_fixture(%{role: :admin})
      booking = booking_fixture(%{user_id: user.id})

      {:ok, booking} =
        booking
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update()

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_approve_negative_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(100, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, pr} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: Money.new(5000, :USD),
          status: :pending
        })
        |> Ysc.Repo.insert()

      bad = Money.new!(:USD, "-10.00")

      assert {:error, :invalid_refund_amount} =
               Bookings.approve_pending_refund(pr, bad, "notes", admin)

      reloaded = Ysc.Repo.get!(PendingRefund, pr.id)
      assert reloaded.status == :pending
    end

    test "approve_pending_refund/4 uses custom admin_refund_amount and nil admin_notes" do
      previous_stripe = Application.get_env(:ysc, :stripe_client)

      Application.put_env(
        :ysc,
        :stripe_client,
        Ysc.StripeRefundApproveTestClient
      )

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, previous_stripe)
      end)

      user = user_fixture()
      admin = user_fixture(%{role: :admin})
      booking = booking_fixture(%{user_id: user.id})

      {:ok, booking} =
        booking
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update()

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_approve_custom_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(100, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, pr} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: Money.new(5000, :USD),
          status: :pending
        })
        |> Ysc.Repo.insert()

      custom = Money.new(1200, :USD)

      assert {:ok, updated, _stripe_refund_id} =
               Bookings.approve_pending_refund(pr, custom, nil, admin)

      assert updated.status == :approved
      assert updated.reviewed_by_id == admin.id
      assert Money.equal?(updated.admin_refund_amount, custom)
      assert updated.admin_notes == nil
    end

    test "approve_pending_refund/4 returns refund_failed when Stripe payment intent retrieve fails" do
      previous = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, Ysc.StripeRetrieveFailClient)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, previous)
      end)

      user = user_fixture()
      admin = user_fixture(%{role: :admin})
      booking = booking_fixture(%{user_id: user.id})

      {:ok, booking} =
        booking
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update()

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_approve_retrieve_fail_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(100, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, pr} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: Money.new(500, :USD),
          status: :pending
        })
        |> Ysc.Repo.insert()

      assert {:error, {:refund_failed, "Failed to retrieve payment intent"}} =
               Bookings.approve_pending_refund(pr, nil, "notes", admin)
    end

    test "reject_pending_refund/3 allows nil admin_notes" do
      user = user_fixture()
      admin = user_fixture(%{role: :admin})
      booking = booking_fixture(%{user_id: user.id})

      {:ok, booking} =
        booking
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update()

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_reject_nil_notes_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(100, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, pr} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment.id,
          policy_refund_amount: Money.new(1000, :USD),
          status: :pending
        })
        |> Ysc.Repo.insert()

      assert {:ok, updated} = Bookings.reject_pending_refund(pr, nil, admin)

      assert updated.status == :rejected
      assert updated.admin_notes == nil
      assert updated.reviewed_by_id == admin.id
    end
  end

  describe "cancel_booking/3" do
    test "returns invalid status when booking is not hold or complete" do
      booking = booking_fixture()

      assert {:error, {:cancellation_failed, :invalid_status}} =
               Bookings.cancel_booking(booking)
    end

    test "returns cancellation_failed when complete booking cannot update inventory" do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id})

      {:ok, booking} =
        booking
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update()

      assert {:error,
              {:cancellation_failed, {:error, :inventory_update_failed}}} =
               Bookings.cancel_booking(booking)
    end
  end

  describe "calculate_refund/3 original_amount option" do
    setup do
      previously_active_ids =
        from(p in Ysc.Bookings.RefundPolicy,
          where:
            p.property == :tahoe and p.booking_mode == :buyout and
              p.is_active == true,
          select: p.id
        )
        |> Repo.all()

      from(p in Ysc.Bookings.RefundPolicy,
        where:
          p.property == :tahoe and p.booking_mode == :buyout and
            p.is_active == true
      )
      |> Repo.update_all(set: [is_active: false])

      {:ok, refund_policy} =
        Bookings.create_refund_policy(%{
          property: :tahoe,
          booking_mode: :buyout,
          is_active: true,
          name: "original_amount opt #{System.unique_integer([:positive])}"
        })

      {:ok, _} =
        Bookings.create_refund_policy_rule(%{
          refund_policy_id: refund_policy.id,
          days_before_checkin: 9999,
          refund_percentage: 50,
          priority: 1
        })

      Ysc.Bookings.RefundPolicyCache.invalidate()

      on_exit(fn ->
        {:ok, _} = Bookings.delete_refund_policy(refund_policy)

        from(p in Ysc.Bookings.RefundPolicy,
          where: p.id in ^previously_active_ids
        )
        |> Repo.update_all(set: [is_active: true])

        Ysc.Bookings.RefundPolicyCache.invalidate()
      end)

      :ok
    end

    test "uses original_amount from opts without ledger payment lookup" do
      user = user_fixture()
      {checkin, checkout} = tahoe_booking_dates(30)

      booking =
        booking_fixture(%{
          user_id: user.id,
          property: :tahoe,
          booking_mode: :buyout,
          status: :complete,
          checkin_date: checkin,
          checkout_date: checkout
        })

      payment_amount = Money.new(10_000, :USD)

      assert {:ok, refund, rule} =
               Bookings.calculate_refund(
                 booking,
                 Date.utc_today(),
                 original_amount: payment_amount
               )

      assert %Ysc.Bookings.RefundPolicyRule{} = rule
      assert Money.equal?(refund, Money.new(5_000, :USD))
    end

    test "falls back to ledger lookup when original_amount is omitted" do
      user = user_fixture()
      {checkin, checkout} = tahoe_booking_dates(30)

      booking =
        booking_fixture(%{
          user_id: user.id,
          property: :tahoe,
          booking_mode: :buyout,
          status: :complete,
          checkin_date: checkin,
          checkout_date: checkout
        })

      assert {:error, :payment_not_found} =
               Bookings.calculate_refund(booking, Date.utc_today())
    end
  end

  describe "calculate_refund/2" do
    test "returns zero refund when cancellation is after check-in" do
      user = user_fixture()

      {:ok, booking} =
        Bookings.create_booking(%{
          user_id: user.id,
          checkin_date: ~D[2020-07-06],
          checkout_date: ~D[2020-07-09],
          guests_count: 2,
          property: :tahoe,
          booking_mode: :buyout,
          status: :complete,
          total_price: Money.new(200, :USD)
        })

      assert {:ok, refund, nil} =
               Bookings.calculate_refund(booking, ~D[2020-07-10])

      assert Money.equal?(refund, Money.new(0, :USD))
    end
  end

  describe "get_booking_payment_amount/1" do
    test "returns amount from ledger stripe debit entry when present" do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id})

      {:ok, booking} =
        booking
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update()

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_payment_amount_test_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(100, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      assert {:ok, amount} = Bookings.get_booking_payment_amount(booking)
      assert Money.equal?(amount, payment.amount)
    end
  end

  describe "list_paginated_bookings/1 filter extraction" do
    test "filters by property and booking date range" do
      user = user_fixture()
      base = Date.utc_today() |> Date.add(14)
      checkin = first_monday_on_or_after(base)
      checkout = Date.add(checkin, 2)

      booking =
        booking_fixture(%{
          user_id: user.id,
          property: :tahoe,
          checkin_date: checkin,
          checkout_date: checkout
        })

      params = %{
        "page" => 1,
        "page_size" => 20,
        "filter" => %{
          "property" => "tahoe",
          "filter_start_date" => Date.to_iso8601(Date.add(checkin, -1)),
          "filter_end_date" => Date.to_iso8601(Date.add(checkout, 1))
        }
      }

      assert {:ok, {bookings, _meta}} = Bookings.list_paginated_bookings(params)
      assert Enum.any?(bookings, &(&1.id == booking.id))
    end

    test "invalid filter date strings skip date range filter without error" do
      _booking = booking_fixture()

      params = %{
        "page" => 1,
        "page_size" => 20,
        "filter" => %{
          "filter_start_date" => "not-a-date",
          "filter_end_date" => "also-bad"
        }
      }

      assert {:ok, {_bookings, _meta}} =
               Bookings.list_paginated_bookings(params)
    end

    test "list_paginated_bookings/2 applies search with property filter" do
      email = unique_user_email()
      user = user_fixture(%{email: email})
      _booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      params = %{
        "page" => 1,
        "page_size" => 20,
        "filter" => %{"property" => "tahoe"}
      }

      assert {:ok, {bookings, meta}} =
               Bookings.list_paginated_bookings(params, user.email)

      assert Enum.any?(bookings, fn b -> b.user && b.user.id == user.id end)
      assert meta.total_count >= 1
    end

    test "list_paginated_bookings/1 applies property filter for clear_lake via string atom" do
      user = user_fixture()
      _booking = booking_fixture(%{user_id: user.id, property: :clear_lake})

      params = %{
        "page" => 1,
        "page_size" => 20,
        "filter" => %{"property" => "clear_lake"}
      }

      assert {:ok, {bookings, _meta}} = Bookings.list_paginated_bookings(params)
      assert Enum.any?(bookings, &(&1.property == :clear_lake))
    end
  end

  describe "calculate_booking_price/4 room mode errors" do
    test "returns no_pricing_rules_found when no rules match the room" do
      # Strip all Tahoe (and property-agnostic) room per-night rules for this
      # transaction so no hierarchy tier can match — seeds and other tests may
      # insert category-level or property-wide rules that would otherwise price
      # any room.
      from(pr in Ysc.Bookings.PricingRule,
        where: pr.booking_mode == :room,
        where: pr.price_unit == :per_person_per_night,
        where: is_nil(pr.property) or pr.property == :tahoe
      )
      |> Repo.delete_all()

      Ysc.Bookings.PricingRuleCache.invalidate()

      category = create_room_category_fixture()

      {:ok, room} =
        Bookings.create_room(%{
          name: "Unpriced room #{System.unique_integer([:positive])}",
          property: :tahoe,
          room_category_id: category.id,
          capacity_max: 4
        })

      checkin = Date.utc_today() |> Date.add(60) |> first_monday_on_or_after()
      checkout = Date.add(checkin, 2)

      assert {:error, :no_pricing_rules_found} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 checkin,
                 checkout,
                 :room,
                 room_id: room.id,
                 guests_count: 2
               )
    end
  end

  describe "get_active_refund_policy_db/2" do
    test "returns policy with rules ordered by days_before_checkin" do
      policy =
        create_refund_policy_fixture(%{property: :tahoe, booking_mode: :buyout})

      assert {:ok, _} =
               Bookings.create_refund_policy_rule(%{
                 refund_policy_id: policy.id,
                 days_before_checkin: 30,
                 refund_percentage: 100,
                 priority: 1
               })

      assert {:ok, _} =
               Bookings.create_refund_policy_rule(%{
                 refund_policy_id: policy.id,
                 days_before_checkin: 7,
                 refund_percentage: 50,
                 priority: 2
               })

      result = Bookings.get_active_refund_policy_db(:tahoe, :buyout)
      assert result != nil
      assert result.id == policy.id
      assert length(result.rules) == 2
    end
  end

  describe "refund policy bang helpers" do
    test "create_refund_policy!/1 inserts and returns policy" do
      attrs = %{
        property: :clear_lake,
        booking_mode: :day,
        is_active: true,
        name: "Bang policy #{System.unique_integer([:positive])}"
      }

      policy = Bookings.create_refund_policy!(attrs)
      assert policy.id != nil
      assert policy.property == :clear_lake
    end

    test "create_refund_policy_rule!/1 inserts rule" do
      policy =
        create_refund_policy_fixture(%{property: :tahoe, booking_mode: :room})

      rule =
        Bookings.create_refund_policy_rule!(%{
          refund_policy_id: policy.id,
          days_before_checkin: 14,
          refund_percentage: 80,
          priority: 1
        })

      assert rule.refund_policy_id == policy.id
    end
  end

  describe "list_paginated_bookings/1" do
    test "returns error for invalid Flop params" do
      _booking1 = booking_fixture()

      assert {:error, %Flop.Meta{errors: errors}} =
               Bookings.list_paginated_bookings(%{"limit" => "not_a_number"})

      assert Keyword.has_key?(errors, :limit)
    end

    test "list_paginated_bookings/2 with empty search term delegates to list_paginated_bookings/1" do
      _booking = booking_fixture()
      params = %{"page" => 1, "page_size" => 20}

      assert {:ok, {bookings_a, meta_a}} =
               Bookings.list_paginated_bookings(params)

      assert {:ok, {bookings_b, meta_b}} =
               Bookings.list_paginated_bookings(params, "")

      assert length(bookings_a) == length(bookings_b)
      assert meta_a.total_count == meta_b.total_count
    end
  end

  describe "create_stripe_refund_for_admin/3" do
    test "creates a refund in test stub mode" do
      assert {:ok, %Stripe.Refund{id: id}} =
               Bookings.create_stripe_refund_for_admin(
                 "pi_test_admin",
                 5000,
                 "Admin reason"
               )

      assert String.starts_with?(id, "re_test")
    end
  end

  describe "maybe_refund_unfulfilled_checkout_payment/3" do
    test "refunds captured hold payments when entitlement pricing is stale" do
      booking = booking_fixture(%{status: :hold})

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_unfulfilled_#{System.unique_integer([:positive])}",
        status: "succeeded",
        amount: 12_345,
        latest_charge: "ch_test_unfulfilled"
      }

      assert {:ok, %Stripe.Refund{id: refund_id}} =
               Bookings.maybe_refund_unfulfilled_checkout_payment(
                 booking,
                 payment_intent,
                 :entitlement_no_longer_valid
               )

      assert String.starts_with?(refund_id, "re_test")
    end

    test "skips refund for non-refundable verification failures" do
      booking = booking_fixture(%{status: :hold})

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_skip_refund_#{System.unique_integer([:positive])}",
        status: "succeeded",
        amount: 5000,
        latest_charge: "ch_test_skip"
      }

      assert :skipped =
               Bookings.maybe_refund_unfulfilled_checkout_payment(
                 booking,
                 payment_intent,
                 :payment_metadata_mismatch
               )
    end

    test "skips refund when booking is already complete" do
      booking = booking_fixture(%{status: :complete})

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_complete_#{System.unique_integer([:positive])}",
        status: "succeeded",
        amount: 5000,
        latest_charge: "ch_test_complete"
      }

      assert :skipped =
               Bookings.maybe_refund_unfulfilled_checkout_payment(
                 booking,
                 payment_intent,
                 :entitlement_no_longer_valid
               )
    end

    test "refunds hold payments for payment_amount_mismatch" do
      booking = booking_fixture(%{status: :hold})

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_amount_mismatch_#{System.unique_integer([:positive])}",
        status: "succeeded",
        amount: 9999,
        latest_charge: "ch_test_amount_mismatch"
      }

      assert {:ok, %Stripe.Refund{id: refund_id}} =
               Bookings.maybe_refund_unfulfilled_checkout_payment(
                 booking,
                 payment_intent,
                 :payment_amount_mismatch
               )

      assert String.starts_with?(refund_id, "re_test")
    end

    test "refunds canceled holds for booking_confirmation_failed" do
      booking = booking_fixture(%{status: :canceled})

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_confirm_failed_#{System.unique_integer([:positive])}",
        status: "succeeded",
        amount: 5000,
        latest_charge: "ch_test_confirm_failed"
      }

      assert {:ok, %Stripe.Refund{id: refund_id}} =
               Bookings.maybe_refund_unfulfilled_checkout_payment(
                 booking,
                 payment_intent,
                 :booking_confirmation_failed
               )

      assert String.starts_with?(refund_id, "re_test")
    end

    test "skips refund when payment intent is not succeeded" do
      booking = booking_fixture(%{status: :hold})

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_processing_#{System.unique_integer([:positive])}",
        status: "processing",
        amount: 5000,
        latest_charge: "ch_test_processing"
      }

      assert :skipped =
               Bookings.maybe_refund_unfulfilled_checkout_payment(
                 booking,
                 payment_intent,
                 :entitlement_no_longer_valid
               )
    end

    test "normalizes {:error, reason} tuples before refunding" do
      booking = booking_fixture(%{status: :hold})

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_tuple_reason_#{System.unique_integer([:positive])}",
        status: "succeeded",
        amount: 5000,
        latest_charge: "ch_test_tuple_reason"
      }

      assert {:ok, %Stripe.Refund{}} =
               Bookings.maybe_refund_unfulfilled_checkout_payment(
                 booking,
                 payment_intent,
                 {:error, :inventory_update_failed}
               )
    end
  end

  describe "maybe_refund_unfulfilled_modification_payment/3" do
    test "refunds captured modification payments when fulfillment fails" do
      user = Ysc.AccountsFixtures.user_fixture()

      booking =
        booking_fixture(%{user_id: user.id})
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update!()

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_unfulfilled_mod_#{System.unique_integer([:positive])}",
        status: "succeeded",
        amount: 5000,
        metadata: %{
          "modification" => "true",
          "booking_id" => to_string(booking.id),
          "user_id" => to_string(user.id)
        },
        latest_charge: "ch_test_unfulfilled_mod"
      }

      assert {:ok, %Stripe.Refund{id: refund_id}} =
               Bookings.maybe_refund_unfulfilled_modification_payment(
                 booking,
                 payment_intent,
                 :blackout_conflict
               )

      assert String.starts_with?(refund_id, "re_test")
    end

    test "skips refund when booking is not complete" do
      user = Ysc.AccountsFixtures.user_fixture()
      booking = booking_fixture(%{status: :hold, user_id: user.id})

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_hold_mod_#{System.unique_integer([:positive])}",
        status: "succeeded",
        amount: 5000,
        metadata: %{
          "modification" => "true",
          "booking_id" => to_string(booking.id),
          "user_id" => to_string(user.id)
        },
        latest_charge: "ch_test_hold_mod"
      }

      assert :skipped =
               Bookings.maybe_refund_unfulfilled_modification_payment(
                 booking,
                 payment_intent,
                 :blackout_conflict
               )
    end

    test "skips refund when payment intent is not a modification" do
      user = Ysc.AccountsFixtures.user_fixture()

      booking =
        booking_fixture(%{user_id: user.id})
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update!()

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_not_mod_#{System.unique_integer([:positive])}",
        status: "succeeded",
        amount: 5000,
        metadata: %{
          "booking_id" => to_string(booking.id),
          "user_id" => to_string(user.id)
        },
        latest_charge: "ch_test_not_mod"
      }

      assert :skipped =
               Bookings.maybe_refund_unfulfilled_modification_payment(
                 booking,
                 payment_intent,
                 :blackout_conflict
               )
    end

    test "skips refund for non-refundable verification failures" do
      user = Ysc.AccountsFixtures.user_fixture()

      booking =
        booking_fixture(%{user_id: user.id})
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update!()

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_skip_mod_#{System.unique_integer([:positive])}",
        status: "succeeded",
        amount: 5000,
        metadata: %{
          "modification" => "true",
          "booking_id" => to_string(booking.id),
          "user_id" => to_string(user.id)
        },
        latest_charge: "ch_test_skip_mod"
      }

      assert :skipped =
               Bookings.maybe_refund_unfulfilled_modification_payment(
                 booking,
                 payment_intent,
                 :payment_metadata_mismatch
               )
    end

    test "refunds via payment intent id string" do
      user = Ysc.AccountsFixtures.user_fixture()

      booking =
        booking_fixture(%{user_id: user.id})
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update!()

      payment_intent_id =
        "pi_unfulfilled_mod_str_#{System.unique_integer([:positive])}"

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "succeeded",
           amount: 5000,
           metadata: %{
             "modification" => "true",
             "booking_id" => to_string(booking.id),
             "user_id" => to_string(user.id)
           },
           latest_charge: "ch_test_unfulfilled_mod_str"
         }}
      end)

      previous_client = Application.get_env(:ysc, :stripe_client)

      try do
        Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

        assert {:ok, %Stripe.Refund{id: refund_id}} =
                 Bookings.maybe_refund_unfulfilled_modification_payment(
                   booking,
                   payment_intent_id,
                   {:error, :blackout_conflict}
                 )

        assert String.starts_with?(refund_id, "re_test")
      after
        Application.put_env(:ysc, :stripe_client, previous_client)
      end
    end

    test "returns error when payment intent retrieval fails" do
      user = Ysc.AccountsFixtures.user_fixture()

      booking =
        booking_fixture(%{user_id: user.id})
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update!()

      payment_intent_id =
        "pi_unfulfilled_mod_err_#{System.unique_integer([:positive])}"

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error,
         %Stripe.Error{
           message: "not found",
           code: "resource_missing",
           source: :stripe
         }}
      end)

      previous_client = Application.get_env(:ysc, :stripe_client)

      try do
        Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

        assert {:error,
                %Stripe.Error{
                  message: "not found",
                  code: "resource_missing",
                  source: :stripe
                }} =
                 Bookings.maybe_refund_unfulfilled_modification_payment(
                   booking,
                   payment_intent_id,
                   :blackout_conflict
                 )
      after
        Application.put_env(:ysc, :stripe_client, previous_client)
      end
    end

    test "skips refund when metadata does not match booking" do
      user = Ysc.AccountsFixtures.user_fixture()

      booking =
        booking_fixture(%{user_id: user.id})
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update!()

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_metadata_mismatch_#{System.unique_integer([:positive])}",
        status: "succeeded",
        amount: 5000,
        metadata: %{
          modification: true,
          booking_id: "other_booking_id",
          user_id: to_string(user.id)
        },
        latest_charge: "ch_test_metadata_mismatch"
      }

      assert :skipped =
               Bookings.maybe_refund_unfulfilled_modification_payment(
                 booking,
                 payment_intent,
                 :blackout_conflict
               )
    end

    test "skips refund when payment intent is not captured" do
      user = Ysc.AccountsFixtures.user_fixture()

      booking =
        booking_fixture(%{user_id: user.id})
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update!()

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_not_captured_#{System.unique_integer([:positive])}",
        status: "requires_capture",
        amount: 5000,
        metadata: %{
          "modification" => "true",
          "booking_id" => to_string(booking.id),
          "user_id" => to_string(user.id)
        },
        latest_charge: "ch_test_not_captured"
      }

      assert :skipped =
               Bookings.maybe_refund_unfulfilled_modification_payment(
                 booking,
                 payment_intent,
                 :blackout_conflict
               )
    end
  end

  describe "Bookings coverage: listing, blackouts, availability, check-in, refunds" do
    test "list_bookings/4 skips date filter when only one of start/end is set" do
      booking = booking_fixture()
      all_ids = Bookings.list_bookings() |> Enum.map(& &1.id) |> MapSet.new()

      with_start_only =
        Bookings.list_bookings(nil, Date.utc_today(), nil)
        |> Enum.map(& &1.id)
        |> MapSet.new()

      with_end_only =
        Bookings.list_bookings(nil, nil, Date.utc_today())
        |> Enum.map(& &1.id)
        |> MapSet.new()

      assert MapSet.equal?(all_ids, with_start_only)
      assert MapSet.equal?(all_ids, with_end_only)
      assert MapSet.member?(with_start_only, booking.id)
    end

    test "list_bookings/4 can preload rooms and user together" do
      booking = booking_fixture()

      found =
        Bookings.list_bookings(nil, nil, nil, preload: [:user, :rooms])
        |> Enum.find(&(&1.id == booking.id))

      assert found
      assert Ecto.assoc_loaded?(found.user)
      assert Ecto.assoc_loaded?(found.rooms)
    end

    test "list_blackouts/3 with nil property returns blackouts for all properties in range" do
      start_d = Date.utc_today() |> Date.add(120)
      end_d = Date.add(start_d, 5)

      {:ok, b1} =
        Bookings.create_blackout(%{
          property: :tahoe,
          start_date: start_d,
          end_date: end_d,
          reason: "cov tahoe #{System.unique_integer([:positive])}"
        })

      {:ok, b2} =
        Bookings.create_blackout(%{
          property: :clear_lake,
          start_date: start_d,
          end_date: end_d,
          reason: "cov cl #{System.unique_integer([:positive])}"
        })

      rows =
        Bookings.list_blackouts(nil, Date.add(start_d, -1), Date.add(end_d, 1))

      ids = Enum.map(rows, & &1.id)
      assert b1.id in ids
      assert b2.id in ids
    end

    test "batch_check_room_availability/4 returns empty MapSet for empty room id list" do
      checkin = Date.utc_today() |> Date.add(40)
      checkout = Date.add(checkin, 2)

      assert Bookings.batch_check_room_availability(
               [],
               :tahoe,
               checkin,
               checkout
             ) == MapSet.new()
    end

    test "room_available?/4 returns false when room is inactive" do
      room = create_room_fixture(%{property: :tahoe, is_active: false})
      checkin = Date.utc_today() |> Date.add(35)
      checkout = Date.add(checkin, 2)

      refute Bookings.room_available?(room.id, checkin, checkout)
    end

    test "room_available?/4 with exclude_booking_id ignores the excluded booking overlap" do
      user = user_fixture()
      room = create_room_fixture(%{property: :tahoe})

      {checkin, checkout} = tahoe_room_booking_dates(14, 3)

      {:ok, booking} =
        Bookings.create_booking(%{
          user_id: user.id,
          checkin_date: checkin,
          checkout_date: checkout,
          guests_count: 2,
          property: :tahoe,
          booking_mode: :room,
          status: :complete,
          total_price: Money.new(200, :USD)
        })

      %BookingRoom{}
      |> Ecto.Changeset.change(%{booking_id: booking.id, room_id: room.id})
      |> Ysc.Repo.insert!()

      refute Bookings.room_available?(room.id, checkin, checkout)
      assert Bookings.room_available?(room.id, checkin, checkout, booking.id)
    end

    test "create_check_in/1 returns error when vehicle data is invalid" do
      booking = booking_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Bookings.create_check_in(%{
                 bookings: [booking],
                 rules_agreed: true,
                 vehicles: [%{"type" => "car", "color" => "red"}]
               })
    end

    test "calculate_booking_price/5 use_actual_guests uses raw guests_count for room mode" do
      room = create_room_fixture(%{property: :tahoe, capacity_max: 2})
      checkin = Date.utc_today() |> Date.add(55) |> first_monday_on_or_after()
      checkout = Date.add(checkin, 2)

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          room_id: room.id,
          season_id: nil
        })

      assert {:ok, total, breakdown} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 checkin,
                 checkout,
                 :room,
                 room_id: room.id,
                 guests_count: 5,
                 use_actual_guests: true
               )

      assert Money.positive?(total)
      assert breakdown.billable_people == 5
    end

    test "list_refund_policies/2 filters by property only when booking_mode is nil" do
      p_buyout =
        create_refund_policy_fixture(%{property: :tahoe, booking_mode: :buyout})

      p_room =
        create_refund_policy_fixture(%{property: :tahoe, booking_mode: :room})

      policies = Bookings.list_refund_policies(:tahoe, nil)
      ids = Enum.map(policies, & &1.id)

      assert p_buyout.id in ids
      assert p_room.id in ids
    end

    test "approve_pending_refund/4 returns error when payment has no Stripe payment intent" do
      previous_stripe = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, Ysc.StripeRetrieveBlockedClient)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, previous_stripe)
      end)

      user = user_fixture()
      admin = user_fixture(%{role: :admin})
      booking = booking_fixture(%{user_id: user.id})

      {:ok, booking} =
        booking
        |> Ecto.Changeset.change(%{status: :complete})
        |> Ysc.Repo.update()

      {:ok, {payment, _, _}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: booking.total_price,
          entity_type: :booking,
          entity_id: booking.id,
          external_payment_id:
            "pi_stripe_then_cleared_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(100, :USD),
          description: "Booking payment",
          property: booking.property,
          payment_method_id: nil
        })

      {:ok, payment_no_intent} =
        payment
        |> Ecto.Changeset.change(%{external_payment_id: nil})
        |> Ysc.Repo.update()

      {:ok, pr} =
        %PendingRefund{}
        |> PendingRefund.changeset(%{
          booking_id: booking.id,
          payment_id: payment_no_intent.id,
          policy_refund_amount: Money.new(50, :USD),
          status: :pending
        })
        |> Ysc.Repo.insert()

      assert {:error,
              {:refund_failed,
               "Payment does not have a valid Stripe payment intent ID"}} =
               Bookings.approve_pending_refund(pr, nil, "notes", admin)
    end

    test "list_paginated_bookings/2 returns Flop error for invalid params with search" do
      _booking = booking_fixture()

      assert {:error, %Flop.Meta{errors: errors}} =
               Bookings.list_paginated_bookings(
                 %{"limit" => "not_a_number"},
                 "anyone@example.com"
               )

      assert Keyword.has_key?(errors, :limit)
    end
  end

  describe "Bookings: additional context coverage" do
    test "list_bookings/4 filters by property and overlapping date range" do
      user = user_fixture()
      base = Date.utc_today() |> Date.add(20)
      checkin = first_monday_on_or_after(base)
      checkout = Date.add(checkin, 2)

      booking =
        booking_fixture(%{
          user_id: user.id,
          property: :tahoe,
          checkin_date: checkin,
          checkout_date: checkout
        })

      rows =
        Bookings.list_bookings(
          :tahoe,
          Date.add(checkin, -1),
          Date.add(checkout, 1)
        )

      assert Enum.any?(rows, &(&1.id == booking.id))
    end

    test "list_paginated_bookings/1 applies property filter without date filters" do
      user = user_fixture()
      _booking = booking_fixture(%{user_id: user.id, property: :tahoe})

      params = %{
        "page" => 1,
        "page_size" => 20,
        "filter" => %{"property" => "tahoe"}
      }

      assert {:ok, {bookings, _meta}} = Bookings.list_paginated_bookings(params)
      assert Enum.any?(bookings, &(&1.property == :tahoe))
    end

    test "list_paginated_bookings/2 applies search with property and date range filters" do
      email = unique_user_email()
      user = user_fixture(%{email: email})
      base = Date.utc_today() |> Date.add(25)
      checkin = first_monday_on_or_after(base)
      checkout = Date.add(checkin, 2)

      _booking =
        booking_fixture(%{
          user_id: user.id,
          property: :tahoe,
          checkin_date: checkin,
          checkout_date: checkout
        })

      params = %{
        "page" => 1,
        "page_size" => 20,
        "filter" => %{
          "property" => "tahoe",
          "filter_start_date" => Date.to_iso8601(Date.add(checkin, -1)),
          "filter_end_date" => Date.to_iso8601(Date.add(checkout, 1))
        }
      }

      assert {:ok, {bookings, _meta}} =
               Bookings.list_paginated_bookings(params, user.email)

      assert Enum.any?(bookings, fn b -> b.user && b.user.id == user.id end)
    end

    test "create_booking_guests/2 accepts guest maps with string keys" do
      booking = booking_fixture()

      assert {:ok, guests} =
               Bookings.create_booking_guests(booking.id, [
                 {0, %{"first_name" => "Sam", "last_name" => "Gamgee"}}
               ])

      assert length(guests) == 1
      assert hd(guests).first_name == "Sam"
    end

    test "create_check_in/1 succeeds with no bookings and no vehicles" do
      assert {:ok, check_in} =
               Bookings.create_check_in(%{rules_agreed: true})

      assert check_in.rules_agreed == true
      check_in = Ysc.Repo.preload(check_in, [:bookings, :check_in_vehicles])
      assert check_in.bookings == []
      assert check_in.check_in_vehicles == []
    end

    test "get_recent_door_codes/2 with nil exclude lists recent codes" do
      _c1 = create_door_code_fixture(%{property: :tahoe})
      _c2 = create_door_code_fixture(%{property: :tahoe})

      codes = Bookings.get_recent_door_codes(:tahoe, nil)
      assert is_list(codes)
      assert length(codes) <= 3
    end

    test "create_door_code/1 returns invalid_attributes when property is missing" do
      assert Bookings.create_door_code(%{
               code: "onlycode#{System.unique_integer([:positive])}"
             }) == {:error, :invalid_attributes}
    end

    test "create_door_code/1 returns invalid_attributes when code is missing" do
      assert Bookings.create_door_code(%{property: :tahoe}) ==
               {:error, :invalid_attributes}
    end

    test "bookings_overlap?/4 returns false for same-day turnaround (checkout1 == checkin2)" do
      refute Bookings.bookings_overlap?(
               ~D[2025-11-01],
               ~D[2025-11-03],
               ~D[2025-11-03],
               ~D[2025-11-05]
             )
    end

    test "bookings_overlap?/4 returns false for same-day turnaround (checkout2 == checkin1)" do
      refute Bookings.bookings_overlap?(
               ~D[2025-11-03],
               ~D[2025-11-05],
               ~D[2025-11-01],
               ~D[2025-11-03]
             )
    end

    test "mark_booking_checked_in/1 raises when booking does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Bookings.mark_booking_checked_in(Ecto.ULID.generate())
      end
    end

    test "has_blackout?/3 returns false when no blackout covers the range" do
      checkin = Date.utc_today() |> Date.add(400)
      checkout = Date.add(checkin, 3)

      refute Bookings.has_blackout?(:tahoe, checkin, checkout)
    end

    test "get_clear_lake_daily_availability/2 marks changeover when check-in and check-out same day" do
      start_d = Date.utc_today() |> Date.add(200) |> first_monday_on_or_after()
      end_d = Date.add(start_d, 2)

      user = user_fixture()

      {:ok, out_booking} =
        Bookings.create_booking(%{
          user_id: user.id,
          checkin_date: Date.add(start_d, -2),
          checkout_date: start_d,
          guests_count: 2,
          property: :clear_lake,
          booking_mode: :day,
          status: :complete,
          total_price: Money.new(100, :USD)
        })

      {:ok, in_booking} =
        Bookings.create_booking(%{
          user_id: user.id,
          checkin_date: start_d,
          checkout_date: Date.add(start_d, 2),
          guests_count: 2,
          property: :clear_lake,
          booking_mode: :day,
          status: :complete,
          total_price: Money.new(100, :USD)
        })

      _ = out_booking
      _ = in_booking

      map = Bookings.get_clear_lake_daily_availability(start_d, end_d)
      info = Map.fetch!(map, start_d)
      assert info.has_checkout == true
      assert info.has_checkin == true
      assert info.is_changeover_day == true
    end

    test "batch_check_room_availability/4 returns empty when buyout blocks the property" do
      room = create_room_fixture(%{property: :tahoe})
      checkin = Date.utc_today() |> Date.add(70) |> first_monday_on_or_after()
      checkout = Date.add(checkin, 2)

      for day <- Date.range(checkin, Date.add(checkout, -1)) do
        {:ok, _} =
          %Ysc.Bookings.PropertyInventory{}
          |> Ysc.Bookings.PropertyInventory.changeset(%{
            property: :tahoe,
            day: day,
            capacity_total: 0,
            capacity_held: 0,
            capacity_booked: 0,
            buyout_booked: true
          })
          |> Ysc.Repo.insert()
      end

      assert Bookings.batch_check_room_availability(
               [room.id],
               :tahoe,
               checkin,
               checkout
             ) == MapSet.new()
    end

    test "search_bookings_by_last_name/2 matches case-insensitively on owner last name" do
      last = "McCoverage#{System.unique_integer([:positive])}"
      email = unique_user_email()

      user =
        user_fixture(%{
          email: email,
          first_name: "Test",
          last_name: String.upcase(last)
        })

      today = DateTime.now!("America/Los_Angeles") |> DateTime.to_date()
      {checkin, checkout} = active_stay_dates(today)

      booking =
        booking_fixture(%{
          user_id: user.id,
          property: :tahoe,
          checkin_date: checkin,
          checkout_date: checkout
        })

      results =
        Bookings.search_bookings_by_last_name(String.downcase(last), :tahoe)

      assert Enum.any?(results, &(&1.id == booking.id))
    end
  end

  # Helper functions for creating test data
  defp create_season_fixture(attrs \\ %{}) do
    default_attrs = %{
      name: "Test Season #{System.unique_integer()}",
      property: :tahoe,
      start_date: ~D[2025-01-01],
      end_date: ~D[2025-12-31]
    }

    {:ok, season} =
      default_attrs
      |> Map.merge(attrs)
      |> Bookings.create_season()

    season
  end

  defp create_room_fixture(attrs \\ %{}) do
    category = create_room_category_fixture()

    default_attrs = %{
      name: "Test Room #{System.unique_integer()}",
      property: :tahoe,
      room_category_id: category.id,
      capacity_max: 4
    }

    {:ok, room} =
      default_attrs
      |> Map.merge(attrs)
      |> Bookings.create_room()

    room
  end

  defp create_room_category_fixture(attrs \\ %{}) do
    default_attrs = %{
      name: "Test Category #{System.unique_integer()}"
    }

    {:ok, category} =
      %RoomCategory{}
      |> RoomCategory.changeset(Map.merge(default_attrs, attrs))
      |> Ysc.Repo.insert()

    category
  end

  defp create_pricing_rule_fixture(attrs \\ %{}) do
    default_attrs = %{
      amount: Money.new(100, :USD),
      booking_mode: :room,
      price_unit: :per_person_per_night,
      property: :tahoe
    }

    {:ok, rule} =
      default_attrs
      |> Map.merge(attrs)
      |> Bookings.create_pricing_rule()

    rule
  end

  defp ensure_buyout_base_pricing! do
    for prop <- [:tahoe, :clear_lake] do
      case Bookings.create_pricing_rule(%{
             amount: Money.new(430, :USD),
             booking_mode: :buyout,
             price_unit: :buyout_fixed,
             property: prop,
             season_id: nil,
             room_id: nil,
             room_category_id: nil
           }) do
        {:ok, _} ->
          :ok

        {:error, %Ecto.Changeset{} = cs} ->
          if duplicate_buyout_base_pricing_rule?(cs) do
            :ok
          else
            flunk(
              "unexpected Bookings.create_pricing_rule failure in ensure_buyout_base_pricing!: #{inspect(cs.errors)}"
            )
          end

        {:error, other} ->
          flunk(
            "unexpected Bookings.create_pricing_rule result in ensure_buyout_base_pricing!: #{inspect(other)}"
          )
      end
    end

    :ok
  end

  defp duplicate_buyout_base_pricing_rule?(%Ecto.Changeset{} = cs) do
    Enum.any?(cs.errors, fn {_field, {_msg, meta}} ->
      meta[:constraint] == :unique
    end)
  end

  defp create_blackout_fixture(attrs \\ %{}) do
    default_attrs = %{
      property: :tahoe,
      start_date: Date.utc_today() |> Date.add(30),
      end_date: Date.utc_today() |> Date.add(32),
      reason: "Test blackout"
    }

    {:ok, blackout} =
      default_attrs
      |> Map.merge(attrs)
      |> Bookings.create_blackout()

    blackout
  end

  defp create_door_code_fixture(attrs \\ %{}) do
    # Generate a 4-5 character alphanumeric code
    unique_suffix =
      System.unique_integer([:positive])
      |> Integer.to_string()
      |> String.slice(-1, 1)

    code = "123#{unique_suffix}"

    default_attrs = %{
      property: :tahoe,
      code: code,
      is_active: false
    }

    {:ok, door_code} =
      default_attrs
      |> Map.merge(attrs)
      |> Bookings.create_door_code()

    door_code
  end

  defp create_refund_policy_fixture(attrs \\ %{}) do
    default_attrs = %{
      property: :tahoe,
      booking_mode: :buyout,
      is_active: true,
      name: "Test Policy #{System.unique_integer()}"
    }

    merged_attrs = Map.merge(default_attrs, attrs)

    # If creating an active policy, deactivate any existing active policies for the same property/mode
    # to avoid unique constraint violations
    if Map.get(merged_attrs, :is_active, true) do
      from(p in Ysc.Bookings.RefundPolicy,
        where: p.property == ^merged_attrs[:property],
        where: p.booking_mode == ^merged_attrs[:booking_mode],
        where: p.is_active == true
      )
      |> Ysc.Repo.update_all(set: [is_active: false])
    end

    {:ok, policy} = Bookings.create_refund_policy(merged_attrs)

    policy
  end

  defp create_refund_policy_rule_fixture(attrs \\ %{}) do
    policy = create_refund_policy_fixture()

    default_attrs = %{
      refund_policy_id: policy.id,
      days_before_checkin: 7,
      refund_percentage: 50,
      priority: 1
    }

    {:ok, rule} =
      default_attrs
      |> Map.merge(attrs)
      |> Bookings.create_refund_policy_rule()

    rule
  end

  defp first_monday_on_or_after(%Date{} = date) do
    case Date.day_of_week(date, :monday) do
      1 -> date
      n -> Date.add(date, 8 - n)
    end
  end

  describe "bookings_overlap?/4" do
    test "returns true when ranges overlap with checkin1 before checkout2 and checkout1 after checkin2" do
      # From module doc: first booking includes Nov 3–4, second includes Nov 3–4 — overlap.
      assert Bookings.bookings_overlap?(
               ~D[2025-11-01],
               ~D[2025-11-04],
               ~D[2025-11-03],
               ~D[2025-11-05]
             )
    end

    test "returns false for separated ranges (neither overlap nor same-day turnaround)" do
      refute Bookings.bookings_overlap?(
               ~D[2025-06-01],
               ~D[2025-06-03],
               ~D[2025-06-10],
               ~D[2025-06-12]
             )
    end
  end

  describe "has_conflicting_bookings?/3" do
    test "returns true when a complete booking overlaps the requested range" do
      user = user_fixture()

      # Monday–Thursday stay (avoid Saturday check-in weekend rule)
      booking =
        booking_fixture(%{
          user_id: user.id,
          property: :tahoe,
          status: :complete,
          checkin_date: ~D[2026-08-03],
          checkout_date: ~D[2026-08-06]
        })

      assert Bookings.has_conflicting_bookings?(
               :tahoe,
               ~D[2026-08-04],
               ~D[2026-08-08]
             )

      refute Bookings.has_conflicting_bookings?(
               :tahoe,
               booking.checkout_date,
               Date.add(booking.checkout_date, 3)
             )
    end

    test "ignores cancelled bookings" do
      user = user_fixture()

      booking =
        booking_fixture(%{
          user_id: user.id,
          property: :tahoe,
          checkin_date: ~D[2026-09-07],
          checkout_date: ~D[2026-09-10]
        })

      {:ok, _cancelled} =
        booking
        |> Ecto.Changeset.change(%{status: :canceled})
        |> Ysc.Repo.update()

      refute Bookings.has_conflicting_bookings?(
               :tahoe,
               ~D[2026-09-08],
               ~D[2026-09-09]
             )
    end
  end

  describe "calculate_booking_price/5 non-Date date arguments" do
    test "returns invalid_checkin_date when checkin is not a Date" do
      assert {:error, :invalid_checkin_date} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 "not-a-date",
                 ~D[2026-07-10],
                 :buyout
               )
    end

    test "returns invalid_checkout_date when checkout is not a Date" do
      assert {:error, :invalid_checkout_date} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 ~D[2026-07-01],
                 "not-a-date",
                 :buyout
               )
    end
  end

  describe "get_tahoe_daily_availability/2 buyout bookings" do
    test "marks has_buyout on nights covered by a complete buyout booking" do
      user = user_fixture()

      booking =
        booking_fixture(%{
          user_id: user.id,
          booking_mode: :buyout,
          property: :tahoe
        })

      assert {:ok, booking} =
               booking
               |> Ecto.Changeset.change(%{status: :complete})
               |> Ysc.Repo.update()

      availability =
        Bookings.get_tahoe_daily_availability(
          booking.checkin_date,
          booking.checkout_date
        )

      occupied_nights =
        Date.range(booking.checkin_date, Date.add(booking.checkout_date, -1))

      for date <- occupied_nights do
        assert availability[date].has_buyout == true
      end
    end

    test "disallows buyout on Winter season nights (including Aug–Sep when Winter starts Aug 1)" do
      previous = Application.get_env(:ysc, :season_cache_enabled)
      Application.put_env(:ysc, :season_cache_enabled, false)

      on_exit(fn ->
        Application.put_env(:ysc, :season_cache_enabled, previous)
      end)

      Repo.delete_all(from(s in Season, where: s.property == :tahoe))

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
          is_default: false,
          advance_booking_days: 45,
          max_nights: 4
        })
        |> Repo.insert()

      availability =
        Bookings.get_tahoe_daily_availability(~D[2026-07-28], ~D[2026-09-05])

      assert availability[~D[2026-07-28]].can_book_buyout == true
      assert availability[~D[2026-07-31]].can_book_buyout == true
      assert availability[~D[2026-08-01]].can_book_buyout == false
      assert availability[~D[2026-08-15]].can_book_buyout == false
      assert availability[~D[2026-09-01]].can_book_buyout == false
    end
  end

  describe "calculate_refund/2 empty matching rules" do
    test "returns full-refund tuple when cancellation is too late for all policy thresholds" do
      user = user_fixture()

      policy =
        create_refund_policy_fixture(%{property: :tahoe, booking_mode: :buyout})

      for {days, pct, pr} <- [{30, 100, 1}, {14, 50, 2}, {7, 25, 3}] do
        assert {:ok, _} =
                 Bookings.create_refund_policy_rule(%{
                   refund_policy_id: policy.id,
                   days_before_checkin: days,
                   refund_percentage: pct,
                   priority: pr
                 })
      end

      {checkin, checkout} = locker_buyout_dates(10)
      # Far enough before check-in that no policy threshold matches
      cancellation = Date.add(checkin, -50)

      {:ok, booking} =
        Bookings.create_booking(%{
          user_id: user.id,
          property: :tahoe,
          booking_mode: :buyout,
          checkin_date: checkin,
          checkout_date: checkout,
          guests_count: 4,
          status: :complete,
          total_price: Money.new(500, :USD)
        })

      assert {:ok, nil, nil} = Bookings.calculate_refund(booking, cancellation)
    end
  end

  describe "cancel_booking/3 hold booking and release_hold" do
    test "returns cancellation_failed when buyout hold cannot clear inventory" do
      user = user_fixture()

      {checkin_date, _} = locker_buyout_dates(14)
      checkout_date = Date.add(checkin_date, 2)

      assert {:ok, booking} =
               Ysc.Bookings.BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin_date,
                 checkout_date,
                 4
               )

      from(pi in Ysc.Bookings.PropertyInventory,
        where:
          pi.property == :tahoe and pi.day >= ^checkin_date and
            pi.day < ^checkout_date
      )
      |> Ysc.Repo.delete_all()

      assert {:error,
              {:cancellation_failed, {:error, :inventory_update_failed}}} =
               Bookings.cancel_booking(booking)
    end
  end

  describe "create_booking/1 validation errors" do
    test "returns error changeset when required fields are missing" do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Bookings.create_booking(%{})
    end
  end

  describe "coverage: bookings.ex error branches and availability" do
    test "create_door_code/1 returns changeset error when code fails validation" do
      assert {:error, %Ecto.Changeset{}} =
               Bookings.create_door_code(%{property: :tahoe, code: "12"})
    end

    test "get_tahoe_daily_availability/2 marks dates covered by blackouts" do
      start_date =
        Date.utc_today() |> Date.add(80) |> first_monday_on_or_after()

      end_date = Date.add(start_date, 5)

      _blackout =
        create_blackout_fixture(%{
          property: :tahoe,
          start_date: Date.add(start_date, 1),
          end_date: Date.add(start_date, 3)
        })

      availability = Bookings.get_tahoe_daily_availability(start_date, end_date)

      for d <- Date.range(Date.add(start_date, 1), Date.add(start_date, 3)) do
        assert availability[d].is_blacked_out == true
      end
    end

    test "get_tahoe_daily_availability/2 reflects held room bookings across stay nights" do
      user = user_fixture()
      room = create_room_fixture(%{property: :tahoe})
      {checkin, checkout} = tahoe_room_booking_dates(21, 2)

      {:ok, booking} =
        Bookings.create_booking(%{
          user_id: user.id,
          checkin_date: checkin,
          checkout_date: checkout,
          guests_count: 2,
          property: :tahoe,
          booking_mode: :room,
          status: :hold,
          total_price: Money.new(200, :USD)
        })

      %BookingRoom{}
      |> Ecto.Changeset.change(%{booking_id: booking.id, room_id: room.id})
      |> Ysc.Repo.insert!()

      availability =
        Bookings.get_tahoe_daily_availability(checkin, Date.add(checkout, -1))

      for d <- Date.range(checkin, Date.add(checkout, -1)) do
        assert availability[d].has_room_booking == true
      end
    end

    test "refund policy create/update/delete error branches" do
      assert {:error, %Ecto.Changeset{}} = Bookings.create_refund_policy(%{})

      policy = create_refund_policy_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Bookings.update_refund_policy(policy, %{name: nil})

      assert {:ok, _} = Bookings.delete_refund_policy(policy)
    end

    test "refund policy rule create/update/delete error branches" do
      policy = create_refund_policy_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Bookings.create_refund_policy_rule(%{})

      assert {:ok, rule} =
               Bookings.create_refund_policy_rule(%{
                 refund_policy_id: policy.id,
                 days_before_checkin: 10,
                 refund_percentage: 50,
                 priority: 1
               })

      assert {:error, %Ecto.Changeset{}} =
               Bookings.update_refund_policy_rule(rule, %{
                 refund_percentage: nil
               })

      assert {:ok, _} = Bookings.delete_refund_policy_rule(rule)
    end
  end

  describe "cancel_booking/3 cancellation notification emails" do
    defp deactivate_tahoe_buyout_refund_policies do
      from(p in Ysc.Bookings.RefundPolicy,
        where: p.property == :tahoe,
        where: p.booking_mode == :buyout
      )
      |> Ysc.Repo.update_all(set: [is_active: false])

      Ysc.Bookings.RefundPolicyCache.invalidate()
    end

    defp assign_board!(user, position) do
      {:ok, _} = Ysc.Accounts.assign_board_position(user, position)
      Ysc.Repo.get!(Ysc.Accounts.User, user.id)
    end

    # booking_fixture/1 only inserts a row; cancel_complete_booking/1 needs property_inventory
    # rows. Admin buyout creation marks inventory like a real complete booking.
    defp complete_buyout_booking_with_stripe_payment!(guest, checkin, checkout) do
      assert {:ok, %Booking{} = booking} =
               Ysc.Bookings.BookingLocker.create_admin_booking(
                 %{
                   user_id: guest.id,
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

      assert {:ok, {_payment, _, _}} =
               Ledgers.process_payment(%{
                 user_id: guest.id,
                 amount: booking.total_price,
                 entity_type: :booking,
                 entity_id: booking.id,
                 external_payment_id:
                   "pi_cancel_notif_#{System.unique_integer([:positive])}",
                 stripe_fee: Money.new(100, :USD),
                 description: "Booking payment",
                 property: booking.property,
                 payment_method_id: nil
               })

      booking
    end

    test "full Stripe refund enqueues user confirmation, cabin master, and treasurer emails" do
      deactivate_tahoe_buyout_refund_policies()

      guest = user_fixture()
      _cabin_master = assign_board!(user_fixture(), :tahoe_cabin_master)
      _treasurer = assign_board!(user_fixture(), :treasurer)

      checkin = Date.utc_today() |> Date.add(100) |> first_monday_on_or_after()
      checkout = Date.add(checkin, 3)

      booking =
        complete_buyout_booking_with_stripe_payment!(guest, checkin, checkout)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _booking, _amount, _stripe_id} =
                 Bookings.cancel_booking(
                   booking,
                   Date.utc_today(),
                   "test reason"
                 )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{"template" => "booking_cancellation_confirmation"}
        )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "booking_cancellation_cabin_master_notification"
          }
        )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{"template" => "booking_cancellation_treasurer_notification"}
        )
      end)
    end

    test "policy-based cancellation enqueues refund pending and board cancellation emails" do
      policy =
        create_refund_policy_fixture(%{property: :tahoe, booking_mode: :buyout})

      assert {:ok, _} =
               Bookings.create_refund_policy_rule(%{
                 refund_policy_id: policy.id,
                 days_before_checkin: 30,
                 refund_percentage: 50,
                 priority: 1
               })

      guest = user_fixture()
      _cabin_master = assign_board!(user_fixture(), :tahoe_cabin_master)
      _treasurer = assign_board!(user_fixture(), :treasurer)

      # Within 30 days so the 30-day rule matches → pending refund (not immediate Stripe).
      checkin = Date.utc_today() |> Date.add(18) |> first_monday_on_or_after()
      checkout = Date.add(checkin, 3)

      booking =
        complete_buyout_booking_with_stripe_payment!(guest, checkin, checkout)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _booking, _amount, %PendingRefund{}} =
                 Bookings.cancel_booking(
                   booking,
                   Date.utc_today(),
                   "policy cancel"
                 )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{"template" => "booking_refund_pending"}
        )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "booking_cancellation_cabin_master_notification"
          }
        )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{"template" => "booking_cancellation_treasurer_notification"}
        )
      end)
    end

    test "still enqueues treasurer email when no tahoe cabin master user exists" do
      deactivate_tahoe_buyout_refund_policies()

      guest = user_fixture()
      _treasurer = assign_board!(user_fixture(), :treasurer)

      checkin = Date.utc_today() |> Date.add(100) |> first_monday_on_or_after()
      checkout = Date.add(checkin, 3)

      booking =
        complete_buyout_booking_with_stripe_payment!(guest, checkin, checkout)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _booking, _amount, _stripe_id} =
                 Bookings.cancel_booking(
                   booking,
                   Date.utc_today(),
                   "no cabin master"
                 )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{"template" => "booking_cancellation_treasurer_notification"}
        )

        refute_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "booking_cancellation_cabin_master_notification"
          }
        )
      end)
    end
  end

  describe "sync_hold_checkout_pricing/2" do
    test "updates pricing fields on an active hold" do
      booking =
        booking_fixture(status: :hold, total_price: Money.new(720, :USD))

      recalculated_total = Money.new(360, :USD)

      assert {:ok, updated} =
               Bookings.sync_hold_checkout_pricing(booking, %{
                 total_price: recalculated_total,
                 subtotal_price: Money.new(400, :USD),
                 discount_total: Money.new(40, :USD)
               })

      assert updated.total_price == recalculated_total
      assert updated.subtotal_price == Money.new(400, :USD)
      assert updated.discount_total == Money.new(40, :USD)
    end

    test "rejects non-hold bookings" do
      booking = booking_fixture(status: :complete)

      assert {:error, :invalid_status} =
               Bookings.sync_hold_checkout_pricing(booking, %{
                 total_price: Money.new(100, :USD)
               })
    end

    test "updates total_price when optional breakdown fields are omitted" do
      booking =
        booking_fixture(status: :hold, total_price: Money.new(720, :USD))

      recalculated_total = Money.new(360, :USD)

      assert {:ok, updated} =
               Bookings.sync_hold_checkout_pricing(booking, %{
                 total_price: recalculated_total,
                 subtotal_price: nil,
                 discount_total: nil
               })

      assert updated.total_price == recalculated_total
    end
  end

  describe "sync_hold_pricing_from_calculation/1" do
    test "recalculates and persists hold pricing from booking details" do
      ensure_buyout_base_pricing!()

      user = user_fixture()
      {checkin, checkout} = tahoe_booking_dates(7)

      assert {:ok, booking} =
               Ysc.Bookings.BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 2
               )

      {:ok, priced} = Bookings.calculate_modification_pricing(booking)
      assert Money.positive?(priced.total)

      stale_total = Money.mult!(priced.total, 2)

      booking =
        booking
        |> Ecto.Changeset.change(total_price: stale_total)
        |> Repo.update!()

      assert {:ok, updated} =
               Bookings.sync_hold_pricing_from_calculation(booking)

      assert Money.equal?(updated.total_price, priced.total)
      refute Money.equal?(updated.total_price, stale_total)
    end

    test "rejects non-hold bookings" do
      booking = booking_fixture(status: :complete)

      assert {:error, :invalid_status} =
               Bookings.sync_hold_pricing_from_calculation(booking)
    end

    test "preserves minimum billable occupancy for room holds" do
      room =
        create_room_fixture(%{
          property: :tahoe,
          min_billable_occupancy: 2,
          capacity_max: 4
        })

      {checkin, checkout} = tahoe_booking_dates(40)

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          room_id: room.id,
          season_id: nil
        })

      user = user_fixture()

      assert {:ok, booking} =
               Ysc.Bookings.BookingLocker.create_room_booking(
                 user.id,
                 room.id,
                 checkin,
                 checkout,
                 1,
                 children_count: 0
               )

      min_occupancy_total = Money.new(600, :USD)
      assert Money.equal?(booking.total_price, min_occupancy_total)

      {:ok, priced} = Bookings.calculate_modification_pricing(booking)
      assert Money.equal?(priced.total, min_occupancy_total)

      booking =
        booking
        |> Ecto.Changeset.change(total_price: Money.new(200, :USD))
        |> Ysc.Repo.update!()

      assert {:ok, updated} =
               Bookings.sync_hold_pricing_from_calculation(booking)

      assert Money.equal?(updated.total_price, min_occupancy_total)
    end
  end

  describe "verify_booking_payment_intent/2" do
    test "accepts a payment intent that matches booking metadata and amount" do
      user = user_fixture()
      booking = booking_fixture(user_id: user.id, status: :hold)

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_valid",
        status: "succeeded",
        amount: Ysc.MoneyHelper.money_to_cents(booking.total_price),
        metadata: %{
          "booking_id" => booking.id,
          "user_id" => user.id
        }
      }

      assert :ok =
               Bookings.verify_booking_payment_intent(payment_intent, booking)
    end

    test "rejects payment intents bound to another booking" do
      user = user_fixture()
      booking_a = booking_fixture(user_id: user.id, status: :hold)
      booking_b = booking_fixture(user_id: user.id, status: :hold)

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_foreign",
        status: "succeeded",
        amount: Ysc.MoneyHelper.money_to_cents(booking_a.total_price),
        metadata: %{
          "booking_id" => booking_a.id,
          "user_id" => user.id
        }
      }

      assert {:error, :payment_metadata_mismatch} =
               Bookings.verify_booking_payment_intent(payment_intent, booking_b)
    end

    test "rejects underpaid payment intents for the same booking" do
      user = user_fixture()
      booking = booking_fixture(user_id: user.id, status: :hold)

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_underpaid",
        status: "succeeded",
        amount: Ysc.MoneyHelper.money_to_cents(Money.new(1, :USD)),
        metadata: %{
          "booking_id" => booking.id,
          "user_id" => user.id
        }
      }

      assert {:error, :payment_amount_mismatch} =
               Bookings.verify_booking_payment_intent(payment_intent, booking)
    end

    test "rejects modification payment intents during initial checkout" do
      user = user_fixture()
      booking = booking_fixture(user_id: user.id, status: :hold)

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_modification",
        status: "succeeded",
        amount: Ysc.MoneyHelper.money_to_cents(booking.total_price),
        metadata: %{
          "booking_id" => booking.id,
          "user_id" => user.id,
          "modification" => "true"
        }
      }

      assert {:error, :payment_metadata_mismatch} =
               Bookings.verify_booking_payment_intent(payment_intent, booking)
    end

    test "rejects payment intents that have not succeeded" do
      user = user_fixture()
      booking = booking_fixture(user_id: user.id, status: :hold)

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_pending",
        status: "requires_payment_method",
        amount: Ysc.MoneyHelper.money_to_cents(booking.total_price),
        metadata: %{
          "booking_id" => booking.id,
          "user_id" => user.id
        }
      }

      assert {:error, :payment_not_succeeded} =
               Bookings.verify_booking_payment_intent(payment_intent, booking)
    end

    test "rejects payment intents bound to another user" do
      owner = user_fixture()
      other_user = user_fixture()
      booking = booking_fixture(user_id: owner.id, status: :hold)

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_wrong_user",
        status: "succeeded",
        amount: Ysc.MoneyHelper.money_to_cents(booking.total_price),
        metadata: %{
          "booking_id" => booking.id,
          "user_id" => other_user.id
        }
      }

      assert {:error, :payment_metadata_mismatch} =
               Bookings.verify_booking_payment_intent(payment_intent, booking)
    end

    test "rejects payment intents already recorded for another booking" do
      user = user_fixture()
      booking_a = booking_fixture(user_id: user.id, status: :hold)
      booking_b = booking_fixture(user_id: user.id, status: :hold)
      payment_intent_id = "pi_reused_#{System.unique_integer([:positive])}"

      assert {:ok, {_payment, _, _}} =
               Ledgers.process_payment(%{
                 user_id: user.id,
                 amount: booking_a.total_price,
                 entity_type: :booking,
                 entity_id: booking_a.id,
                 external_payment_id: payment_intent_id,
                 stripe_fee: Money.new(100, :USD),
                 description: "Booking payment",
                 property: booking_a.property,
                 payment_method_id: nil
               })

      payment_intent = %Stripe.PaymentIntent{
        id: payment_intent_id,
        status: "succeeded",
        amount: Ysc.MoneyHelper.money_to_cents(booking_b.total_price),
        metadata: %{
          "booking_id" => booking_b.id,
          "user_id" => user.id
        }
      }

      assert {:error, :payment_already_used} =
               Bookings.verify_booking_payment_intent(payment_intent, booking_b)
    end
  end

  describe "verify_modification_redirect_payment_intent/2" do
    test "accepts a modification intent for a complete booking with matching metadata" do
      user = user_fixture()
      booking = booking_fixture(user_id: user.id, status: :complete)

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_mod_redirect_valid",
        status: "succeeded",
        amount: 5_000,
        metadata: %{
          "booking_id" => booking.id,
          "user_id" => user.id,
          "modification" => "true"
        }
      }

      assert :ok =
               Bookings.verify_modification_redirect_payment_intent(
                 payment_intent,
                 booking
               )
    end

    test "rejects modification intents on hold bookings" do
      user = user_fixture()
      booking = booking_fixture(user_id: user.id, status: :hold)

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_mod_redirect_hold",
        status: "succeeded",
        amount: 5_000,
        metadata: %{
          "booking_id" => booking.id,
          "user_id" => user.id,
          "modification" => "true"
        }
      }

      assert {:error, :payment_metadata_mismatch} =
               Bookings.verify_modification_redirect_payment_intent(
                 payment_intent,
                 booking
               )
    end

    test "rejects modification intents bound to another booking" do
      user_a = user_fixture()
      user_b = user_fixture()
      booking_a = booking_fixture(user_id: user_a.id, status: :complete)
      booking_b = booking_fixture(user_id: user_b.id, status: :complete)

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_mod_redirect_foreign",
        status: "succeeded",
        amount: 5_000,
        metadata: %{
          "booking_id" => booking_a.id,
          "user_id" => user_a.id,
          "modification" => "true"
        }
      }

      assert {:error, :payment_metadata_mismatch} =
               Bookings.verify_modification_redirect_payment_intent(
                 payment_intent,
                 booking_b
               )
    end
  end

  defp insert_complete_booking(user, checkin_date, checkout_date) do
    %Booking{
      user_id: user.id,
      property: :clear_lake,
      booking_mode: :day,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      guests_count: 2,
      status: :complete,
      total_price: Money.new(100, :USD),
      reference_id: "BKG-TEST-#{System.unique_integer([:positive])}"
    }
    |> Ysc.Repo.insert!()
    |> Ysc.Repo.preload(:rooms)
  end

  defp insert_complete_tahoe_booking(user, checkin_date, checkout_date) do
    %Booking{
      user_id: user.id,
      property: :tahoe,
      booking_mode: :room,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      guests_count: 2,
      status: :complete,
      total_price: Money.new(100, :USD),
      reference_id: "BKG-TEST-#{System.unique_integer([:positive])}"
    }
    |> Ysc.Repo.insert!()
    |> Ysc.Repo.preload(:rooms)
  end
end
