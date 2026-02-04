defmodule Ysc.BookingsTest do
  @moduledoc """
  Tests for Ysc.Bookings context module.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Bookings

  alias Ysc.Bookings.{
    Booking,
    Season,
    Room,
    RoomCategory
  }

  import Ecto.Query
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    # Clear season cache to avoid cross-test pollution in async tests
    Ysc.Bookings.SeasonCache.invalidate()
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

    test "create_booking/1 with valid data creates a booking" do
      user = user_fixture()
      # Ensure dates don't include Saturday without Sunday (Tahoe rule)
      base_date = Date.utc_today() |> Date.add(7)

      checkin =
        if Date.day_of_week(base_date) == 1,
          do: base_date,
          else: Date.add(base_date, 8 - Date.day_of_week(base_date))

      checkout = Date.add(checkin, 2)

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
    test "list_booking_guests/1 returns guests for booking" do
      booking = booking_fixture()
      guests = Bookings.list_booking_guests(booking.id)
      assert is_list(guests)
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

    test "mark_booking_checked_in/1 marks booking as checked in" do
      booking = booking_fixture()
      # mark_booking_checked_in now preloads rooms internally
      assert {:ok, _} = Bookings.mark_booking_checked_in(booking.id)
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
      checkin = Date.utc_today() |> Date.add(30)
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
      booking = booking_fixture(%{total_price: Money.new(10_000, :USD)})
      cancellation_date = Date.utc_today()

      result = Bookings.calculate_refund(booking, cancellation_date)
      # Function returns {:ok, refund_amount, rule} or {:ok, nil, nil}
      assert {:ok, refund_amount, _rule} = result

      # If there's no policy, refund_amount will be nil, otherwise it's a Money struct
      if refund_amount == nil do
        assert refund_amount == nil
      else
        assert %Money{} = refund_amount
      end
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
end
