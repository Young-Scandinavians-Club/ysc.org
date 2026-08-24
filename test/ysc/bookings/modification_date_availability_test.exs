defmodule Ysc.Bookings.ModificationDateAvailabilityTest do
  use Ysc.DataCase, async: false

  import Ecto.Query
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Ysc.Bookings

  alias Ysc.Bookings.{
    Booking,
    BookingLocker,
    BookingValidator,
    ModificationDateAvailability,
    RoomCategory,
    Season
  }

  alias Ysc.Ledgers
  alias Ysc.Repo

  setup do
    Ledgers.ensure_basic_accounts()
    seed_permissive_tahoe_seasons!()

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

  # Wide advance windows so these tests are not coupled to admin-tuned seasons
  # lingering in the shared test database.
  defp seed_permissive_tahoe_seasons! do
    Repo.delete_all(from(s in Season, where: s.property == :tahoe))

    {:ok, _} =
      %Season{}
      |> Season.changeset(%{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-10-31],
        is_default: true,
        advance_booking_days: 365,
        max_nights: 4
      })
      |> Repo.insert()

    {:ok, _} =
      %Season{}
      |> Season.changeset(%{
        name: "Winter",
        property: :tahoe,
        start_date: ~D[2024-11-01],
        end_date: ~D[2025-04-30],
        advance_booking_days: 365,
        max_nights: 4
      })
      |> Repo.insert()

    Ysc.Bookings.SeasonCache.invalidate()
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

  test "validate_modification_dates rejects extending stay on a deactivated room",
       %{
         user: user
       } do
    room = create_room!()
    checkin = Date.utc_today() |> Date.add(150) |> first_monday_on_or_after()
    checkout = Date.add(checkin, 2)
    booking = complete_room_booking!(user, room, checkin, checkout)

    room
    |> Ecto.Changeset.change(is_active: false)
    |> Repo.update!()

    booking = Repo.preload(booking, [:rooms, :user], force: true)

    extended_checkout = Date.add(checkout, 1)

    parsed = %{
      checkin_date: checkin,
      checkout_date: extended_checkout,
      guests_count: 2,
      children_count: 0
    }

    assert {:error, :room_unavailable} =
             Bookings.validate_modification_availability(booking, parsed)

    snapshot =
      ModificationDateAvailability.build_snapshot_for_modification(
        booking,
        parsed.checkin_date,
        parsed.checkout_date
      )

    assert {:error, :room_unavailable} =
             ModificationDateAvailability.validate_modification_dates(
               snapshot,
               parsed.checkin_date,
               parsed.checkout_date
             )
  end

  test "validate_modification_dates rejects extending a room stay into another buyout hold",
       %{
         user: user
       } do
    other_user =
      user_fixture()
      |> Ecto.Changeset.change(state: :active)
      |> Repo.update!()

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(500, :USD),
        booking_mode: :buyout,
        price_unit: :buyout_fixed,
        property: :tahoe,
        season_id: nil
      })

    room = create_room!()
    checkin = Date.utc_today() |> Date.add(150) |> first_monday_on_or_after()
    checkout = Date.add(checkin, 2)
    booking = complete_room_booking!(user, room, checkin, checkout)

    # Start at room checkout (same-day turnaround); end on Sunday so Sat⇒Sun holds.
    overlapping_checkin = checkout
    overlapping_checkout = Date.add(checkout, 4)

    assert {:ok, _} =
             BookingLocker.create_admin_booking(
               %{
                 user_id: other_user.id,
                 property: :tahoe,
                 checkin_date: overlapping_checkin,
                 checkout_date: overlapping_checkout,
                 booking_mode: :buyout,
                 guests_count: 4,
                 total_price: Money.new(500, :USD)
               },
               skip_email: true,
               skip_reminders: true
             )

    parsed = %{
      checkin_date: checkin,
      checkout_date: overlapping_checkout,
      guests_count: 2,
      children_count: 0
    }

    assert {:error, :property_buyout_active} =
             Bookings.validate_modification_availability(booking, parsed)

    calendar = ModificationDateAvailability.calendar_context(booking)

    cached_snapshot =
      ModificationDateAvailability.build_availability_snapshot(
        booking,
        calendar.min_date,
        calendar.max_date,
        calendar.today,
        calendar.seasons
      )

    assert {:error, :property_buyout_active} =
             Bookings.validate_modification_availability(
               booking,
               parsed,
               availability_snapshot: cached_snapshot
             )
  end

  test "validate_modification_dates matches Bookings.validate_modification_availability",
       %{
         user: user
       } do
    room = create_room!()
    checkin = Date.utc_today() |> Date.add(150) |> first_monday_on_or_after()
    checkout = Date.add(checkin, 2)
    booking = complete_room_booking!(user, room, checkin, checkout)

    parsed = %{
      checkin_date: Date.add(checkin, 7),
      checkout_date: Date.add(checkout, 7),
      guests_count: 2,
      children_count: 0
    }

    assert :ok = Bookings.validate_modification_availability(booking, parsed)

    snapshot =
      ModificationDateAvailability.build_snapshot_for_modification(
        booking,
        parsed.checkin_date,
        parsed.checkout_date
      )

    assert :ok =
             ModificationDateAvailability.validate_modification_dates(
               snapshot,
               parsed.checkin_date,
               parsed.checkout_date
             )
  end

  test "prepare_modification reuses calendar availability snapshot without inventory queries",
       %{
         user: user
       } do
    room = create_room!()
    checkin = Date.utc_today() |> Date.add(150) |> first_monday_on_or_after()
    checkout = Date.add(checkin, 2)
    booking = complete_room_booking!(user, room, checkin, checkout)

    calendar = ModificationDateAvailability.calendar_context(booking)

    snapshot =
      ModificationDateAvailability.build_availability_snapshot(
        booking,
        calendar.min_date,
        calendar.max_date,
        calendar.today,
        calendar.seasons
      )

    new_checkin = Date.add(checkin, 7)
    new_checkout = Date.add(checkout, 7)

    attrs = %{
      "checkin_date" => Date.to_iso8601(new_checkin),
      "checkout_date" => Date.to_iso8601(new_checkout),
      "guests_count" => "2",
      "children_count" => "0"
    }

    inventory_pattern = ~r/FROM "(property_inventory|room_inventory)"/i

    {_preview, with_snapshot} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          assert {:ok, _} =
                   Bookings.prepare_modification(booking, attrs,
                     availability_snapshot: snapshot
                   )
        end,
        pattern: inventory_pattern,
        caller_pids: [self()]
      )

    {_preview, without_snapshot} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          assert {:ok, _} = Bookings.prepare_modification(booking, attrs)
        end,
        pattern: inventory_pattern,
        caller_pids: [self()]
      )

    assert with_snapshot == 0
    assert without_snapshot > 0
  end

  test "prepare_modification reuses amount_paid option without ledger queries",
       %{
         user: user
       } do
    room = create_room!()
    checkin = Date.utc_today() |> Date.add(150) |> first_monday_on_or_after()
    checkout = Date.add(checkin, 2)
    booking = complete_room_booking!(user, room, checkin, checkout)

    calendar = ModificationDateAvailability.calendar_context(booking)

    snapshot =
      ModificationDateAvailability.build_availability_snapshot(
        booking,
        calendar.min_date,
        calendar.max_date,
        calendar.today,
        calendar.seasons
      )

    new_checkin = Date.add(checkin, 7)
    new_checkout = Date.add(checkout, 7)

    attrs = %{
      "checkin_date" => Date.to_iso8601(new_checkin),
      "checkout_date" => Date.to_iso8601(new_checkout),
      "guests_count" => "2",
      "children_count" => "0"
    }

    amount_paid = Money.new(:USD, 500)
    ledger_pattern = ~r/FROM "ledger_entries"/i

    {_preview, ledger_queries} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          assert {:ok, preview} =
                   Bookings.prepare_modification(booking, attrs,
                     availability_snapshot: snapshot,
                     amount_paid: amount_paid
                   )

          assert Money.equal?(preview.amount_paid, amount_paid)
        end,
        pattern: ledger_pattern,
        caller_pids: [self()]
      )

    assert ledger_queries == 0
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
      booking_fixture(%{
        user_id: other_user.id,
        property: :tahoe,
        booking_mode: :room,
        checkin_date: Date.add(checkin, 1),
        checkout_date: Date.add(checkout, 2),
        status: :complete,
        rooms: [room]
      })

    calendar = ModificationDateAvailability.calendar_context(booking)

    snapshot =
      ModificationDateAvailability.build_availability_snapshot(
        booking,
        calendar.min_date,
        calendar.max_date,
        calendar.today,
        calendar.seasons
      )

    tooltips =
      ModificationDateAvailability.checkout_date_tooltips(
        booking,
        checkin,
        calendar.max_date,
        calendar.today,
        calendar.seasons,
        snapshot
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

    snapshot =
      ModificationDateAvailability.build_availability_snapshot(
        booking,
        calendar.min_date,
        calendar.max_date,
        calendar.today,
        calendar.seasons
      )

    tooltips =
      ModificationDateAvailability.checkin_date_tooltips(
        booking,
        calendar.min_date,
        calendar.max_date,
        calendar.today,
        calendar.seasons,
        snapshot
      )

    refute Map.has_key?(tooltips, Date.to_iso8601(checkin))
  end

  test "checkin and checkout tooltips with snapshot match without snapshot", %{
    user: user
  } do
    room = create_room!()
    base = Date.utc_today() |> Date.add(140) |> first_monday_on_or_after()
    checkin = base
    checkout = Date.add(checkin, 2)

    booking = complete_room_booking!(user, room, checkin, checkout)
    calendar = ModificationDateAvailability.calendar_context(booking)

    snapshot =
      ModificationDateAvailability.build_availability_snapshot(
        booking,
        calendar.min_date,
        calendar.max_date,
        calendar.today,
        calendar.seasons
      )

    checkin_with =
      ModificationDateAvailability.checkin_date_tooltips(
        booking,
        calendar.min_date,
        calendar.max_date,
        calendar.today,
        calendar.seasons,
        snapshot
      )

    checkin_without =
      ModificationDateAvailability.checkin_date_tooltips(
        booking,
        calendar.min_date,
        calendar.max_date,
        calendar.today,
        calendar.seasons
      )

    checkout_with =
      ModificationDateAvailability.checkout_date_tooltips(
        booking,
        checkin,
        calendar.max_date,
        calendar.today,
        calendar.seasons,
        snapshot
      )

    checkout_without =
      ModificationDateAvailability.checkout_date_tooltips(
        booking,
        checkin,
        calendar.max_date,
        calendar.today,
        calendar.seasons
      )

    assert checkin_with == checkin_without
    assert checkout_with == checkout_without
  end

  test "calendar_placeholder returns bounds without loading seasons from the database" do
    booking = %Booking{
      property: :tahoe,
      checkin_date: ~D[2026-06-01],
      checkout_date: ~D[2026-06-05],
      booking_mode: :buyout
    }

    calendar = ModificationDateAvailability.calendar_placeholder(booking)

    assert calendar.seasons == []
    assert calendar.min_date == calendar.today
    assert Date.compare(calendar.max_date, calendar.today) == :gt
    assert calendar.max_nights == 365
  end

  describe "Clear Lake day mode" do
    setup do
      ensure_clear_lake_day_pricing_rule()
      :ok
    end

    test "checkin_date_tooltips allows nights without property_inventory rows",
         %{
           user: user
         } do
      # Keep within Clear Lake summer; calendar max clamps to season end when
      # advance_booking_days is nil.
      checkin = Date.utc_today() |> Date.add(21)
      checkout = Date.add(checkin, 2)
      booking = complete_clear_lake_day_booking!(user, checkin, checkout, 3)

      open_checkin = Date.add(checkin, 14)
      open_checkout = Date.add(open_checkin, 1)

      calendar = ModificationDateAvailability.calendar_context(booking)

      snapshot =
        ModificationDateAvailability.build_availability_snapshot(
          booking,
          calendar.min_date,
          calendar.max_date,
          calendar.today,
          calendar.seasons
        )

      refute Map.has_key?(snapshot.property_by_day, open_checkin)

      tooltips =
        ModificationDateAvailability.checkin_date_tooltips(
          booking,
          calendar.min_date,
          calendar.max_date,
          calendar.today,
          calendar.seasons,
          snapshot
        )

      refute Map.get(tooltips, Date.to_iso8601(open_checkin)) ==
               "The cabin is not available starting on this date"

      assert :ok =
               ModificationDateAvailability.validate_modification_dates(
                 snapshot,
                 open_checkin,
                 open_checkout
               )
    end

    test "checkin_date_tooltips blocks nights at full capacity", %{user: user} do
      other_user =
        user_fixture()
        |> Ecto.Changeset.change(state: :active)
        |> Repo.update!()

      checkin = Date.utc_today() |> Date.add(21)
      checkout = Date.add(checkin, 2)
      booking = complete_clear_lake_day_booking!(user, checkin, checkout, 3)

      full_checkin = Date.add(checkin, 10)
      full_checkout = Date.add(full_checkin, 1)

      _full =
        complete_clear_lake_day_booking!(
          other_user,
          full_checkin,
          full_checkout,
          12
        )

      calendar = ModificationDateAvailability.calendar_context(booking)

      snapshot =
        ModificationDateAvailability.build_availability_snapshot(
          booking,
          calendar.min_date,
          calendar.max_date,
          calendar.today,
          calendar.seasons
        )

      tooltips =
        ModificationDateAvailability.checkin_date_tooltips(
          booking,
          calendar.min_date,
          calendar.max_date,
          calendar.today,
          calendar.seasons,
          snapshot
        )

      assert Map.get(tooltips, Date.to_iso8601(full_checkin)) ==
               "The cabin is not available starting on this date"

      assert {:error, :property_unavailable} =
               ModificationDateAvailability.validate_modification_dates(
                 snapshot,
                 full_checkin,
                 full_checkout
               )
    end
  end

  defp ensure_clear_lake_day_pricing_rule do
    Ysc.Bookings.SeasonCache.invalidate()
    Ysc.Bookings.PricingRuleCache.invalidate()

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(:USD, 30),
        booking_mode: :day,
        price_unit: :per_guest_per_day,
        property: :clear_lake,
        season_id: nil
      })
  end

  defp complete_clear_lake_day_booking!(user, checkin, checkout, guests) do
    assert {:ok, hold} =
             BookingLocker.create_per_guest_booking(
               user.id,
               :clear_lake,
               checkin,
               checkout,
               guests
             )

    assert {:ok, %Booking{} = booking} = BookingLocker.confirm_booking(hold.id)
    Repo.preload(booking, [:rooms, :user])
  end

  defp first_monday_on_or_after(date) do
    days_until_monday = rem(8 - Date.day_of_week(date, :monday), 7)
    Date.add(date, days_until_monday)
  end

  # Nearest Monday, from today, that falls within the seeded Summer season
  # (May-Oct, matched by month/day only) and within the booking advance window.
  defp next_summer_monday do
    Date.utc_today()
    |> Stream.iterate(&Date.add(&1, 1))
    |> Enum.find(fn d ->
      Date.day_of_week(d, :monday) == 1 and d.month in 5..10
    end)
  end

  defp first_saturday_on_or_after(date) do
    days_until_saturday = rem(13 - Date.day_of_week(date, :monday), 7)
    Date.add(date, days_until_saturday)
  end

  defp seed_tahoe_summer_winter_seasons! do
    Repo.delete_all(from(s in Season, where: s.property == :tahoe))

    {:ok, _} =
      %Season{}
      |> Season.changeset(%{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-07-31],
        is_default: true,
        advance_booking_days: 365,
        max_nights: 4
      })
      |> Repo.insert()

    {:ok, _} =
      %Season{}
      |> Season.changeset(%{
        name: "Winter",
        property: :tahoe,
        start_date: ~D[2024-08-01],
        end_date: ~D[2025-04-30],
        advance_booking_days: 365,
        max_nights: 4
      })
      |> Repo.insert()

    Ysc.Bookings.SeasonCache.invalidate()
  end

  defp complete_buyout_booking!(user, checkin, checkout) do
    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(500, :USD),
        booking_mode: :buyout,
        price_unit: :buyout_fixed,
        property: :tahoe,
        season_id: nil
      })

    assert {:ok, %Booking{} = booking} =
             BookingLocker.create_admin_booking(
               %{
                 user_id: user.id,
                 property: :tahoe,
                 checkin_date: checkin,
                 checkout_date: checkout,
                 booking_mode: :buyout,
                 guests_count: 8,
                 total_price: Money.new(1500, :USD)
               },
               skip_email: true,
               skip_reminders: true
             )

    Repo.preload(booking, [:rooms, :user])
  end

  test "checkout tooltips block buyout ranges that enter Winter nights", %{
    user: user
  } do
    seed_tahoe_summer_winter_seasons!()

    # Wed–Fri in Summer; extending to Sun Aug 2 adds Aug 1 winter night
    # while staying within the 4-night Summer max.
    checkin = ~D[2026-07-29]
    checkout = ~D[2026-07-31]
    booking = complete_buyout_booking!(user, checkin, checkout)
    calendar = ModificationDateAvailability.calendar_context(booking)

    snapshot =
      ModificationDateAvailability.build_availability_snapshot(
        booking,
        calendar.min_date,
        calendar.max_date,
        calendar.today,
        calendar.seasons
      )

    tooltips =
      ModificationDateAvailability.checkout_date_tooltips(
        booking,
        checkin,
        calendar.max_date,
        calendar.today,
        calendar.seasons,
        snapshot
      )

    winter_checkout = ~D[2026-08-02]

    assert tooltips[Date.to_iso8601(winter_checkout)] =~
             "winter nights"
  end

  test "validate_modification_dates/3 builds its own snapshot when given a Booking directly",
       %{user: user} do
    room = create_room!()
    checkin = Date.utc_today() |> Date.add(150) |> first_monday_on_or_after()
    checkout = Date.add(checkin, 2)
    booking = complete_room_booking!(user, room, checkin, checkout)

    new_checkin = Date.add(checkin, 7)
    new_checkout = Date.add(checkout, 7)

    assert :ok =
             ModificationDateAvailability.validate_modification_dates(
               booking,
               new_checkin,
               new_checkout
             )
  end

  test "unsupported booking modes are rejected and fall back to the generic tooltip message",
       %{user: user} do
    room = create_room!()
    checkin = Date.utc_today() |> Date.add(150) |> first_monday_on_or_after()
    checkout = Date.add(checkin, 2)
    booking = complete_room_booking!(user, room, checkin, checkout)
    bad_booking = %{booking | booking_mode: :unsupported_mode}

    calendar = ModificationDateAvailability.calendar_context(booking)

    snapshot =
      ModificationDateAvailability.build_availability_snapshot(
        bad_booking,
        calendar.min_date,
        calendar.max_date,
        calendar.today,
        calendar.seasons
      )

    new_checkin = Date.add(checkin, 7)
    new_checkout = Date.add(checkout, 7)

    assert {:error, :invalid_booking_mode} =
             ModificationDateAvailability.validate_modification_dates(
               snapshot,
               new_checkin,
               new_checkout
             )

    tooltips =
      ModificationDateAvailability.checkout_date_tooltips(
        bad_booking,
        new_checkin,
        calendar.max_date,
        calendar.today,
        calendar.seasons,
        snapshot
      )

    assert tooltips[Date.to_iso8601(new_checkout)] ==
             "The selected dates are not available"
  end

  test "checkout tooltips flag a buyout extension into another booked buyout as property_unavailable",
       %{user: user} do
    other_user =
      user_fixture()
      |> Ecto.Changeset.change(state: :active)
      |> Repo.update!()

    # Nearest upcoming midsummer Monday (season matching is month/day-only
    # and recurs every year) so this stays clear of the seeded Winter season
    # while still landing inside the booking advance window.
    checkin = next_summer_monday()
    checkout = Date.add(checkin, 2)
    booking = complete_buyout_booking!(user, checkin, checkout)

    overlapping_checkin = checkout
    overlapping_checkout = Date.add(checkout, 2)

    assert {:ok, _} =
             BookingLocker.create_admin_booking(
               %{
                 user_id: other_user.id,
                 property: :tahoe,
                 checkin_date: overlapping_checkin,
                 checkout_date: overlapping_checkout,
                 booking_mode: :buyout,
                 guests_count: 8,
                 total_price: Money.new(1500, :USD)
               },
               skip_email: true,
               skip_reminders: true
             )

    calendar = ModificationDateAvailability.calendar_context(booking)

    snapshot =
      ModificationDateAvailability.build_availability_snapshot(
        booking,
        calendar.min_date,
        calendar.max_date,
        calendar.today,
        calendar.seasons
      )

    extended_checkout = Date.add(checkout, 1)

    tooltips =
      ModificationDateAvailability.checkout_date_tooltips(
        booking,
        checkin,
        calendar.max_date,
        calendar.today,
        calendar.seasons,
        snapshot
      )

    assert tooltips[Date.to_iso8601(extended_checkout)] ==
             "The selected dates or guest count are not available"

    assert {:error, :property_unavailable} =
             ModificationDateAvailability.validate_modification_dates(
               snapshot,
               checkin,
               extended_checkout
             )
  end

  test "checkout tooltips block Saturday check-in except Sunday one-night", %{
    user: user
  } do
    room = create_room!()
    saturday = Date.utc_today() |> Date.add(21) |> first_saturday_on_or_after()
    sunday = Date.add(saturday, 1)
    booking = complete_room_booking!(user, room, saturday, sunday)
    calendar = ModificationDateAvailability.calendar_context(booking)

    snapshot =
      ModificationDateAvailability.build_availability_snapshot(
        booking,
        calendar.min_date,
        calendar.max_date,
        calendar.today,
        calendar.seasons
      )

    tooltips =
      ModificationDateAvailability.checkout_date_tooltips(
        booking,
        saturday,
        calendar.max_date,
        calendar.today,
        calendar.seasons,
        snapshot
      )

    monday = Date.add(saturday, 2)

    assert tooltips[Date.to_iso8601(monday)] =~
             BookingValidator.saturday_checkin_one_night_message()

    refute Map.has_key?(tooltips, Date.to_iso8601(sunday))
  end
end
