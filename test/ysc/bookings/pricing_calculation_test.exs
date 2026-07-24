defmodule Ysc.Bookings.PricingCalculationTest do
  @moduledoc """
  Verifies that pricing calculations produce correct money totals across all
  booking modes and configurations. Includes regression tests for the multi-room
  pricing bug where totals were incorrectly multiplied by the number of rooms.

  Two notes on test setup:
  - Room pricing rules must be created with `room_category_id` so the lookup
    hierarchy in `find_pricing_rule_for_room/4` can find them. Property-wide
    room rules (no room_id, no room_category_id) are unreachable via that
    hierarchy and are therefore never used.
  - `Cachex.clear(:ysc_cache)` is called in setup to prevent stale cached `nil`
    entries (which arise when `System.system_time(:second)` returns the same
    version for multiple tests within the same wall-clock second) from masking
    freshly-created pricing rules.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Bookings
  alias Ysc.Bookings.{BookingLocker, Booking, RoomCategory}

  import Ysc.TestDataFactory

  # Fixed summer dates. No seasons are created in these tests, so the
  # `season_id: nil` rules always apply.
  @checkin ~D[2026-07-01]
  @checkout_2n ~D[2026-07-03]
  @checkout_3n ~D[2026-07-04]

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    Ysc.Bookings.SeasonCache.invalidate()
    # Wipe the Cachex cache to prevent stale `nil` entries from a prior test
    # (within the same wall-clock second) from being served as valid cache hits.
    Cachex.clear(:ysc_cache)

    {:ok, category} =
      %RoomCategory{}
      |> RoomCategory.changeset(%{
        name: "Pricing Test #{System.unique_integer()}"
      })
      |> Ysc.Repo.insert()

    # Lifetime membership is required for multi-room Tahoe bookings under
    # BookingValidator membership room limits.
    user = user_with_membership(:lifetime)
    %{category: category, user: user}
  end

  # ─── Helpers ────────────────────────────────────────────────────────────────

  defp make_room(category, attrs \\ %{}) do
    {:ok, r} =
      Bookings.create_room(
        Map.merge(
          %{
            name: "Room #{System.unique_integer()}",
            property: :tahoe,
            room_category_id: category.id,
            capacity_max: 8,
            min_billable_occupancy: 1
          },
          attrs
        )
      )

    r
  end

  # Creates a room pricing rule that can be found for rooms in `category`.
  # Using room_category_id is required: the lookup hierarchy calls
  # find_most_specific with room_category_id, not with (nil, nil).
  defp make_room_rule(category, amount_usd, opts \\ []) do
    {:ok, rule} =
      Bookings.create_pricing_rule(
        Keyword.merge(
          [
            amount: Money.new(:USD, amount_usd),
            booking_mode: :room,
            price_unit: :per_person_per_night,
            property: :tahoe,
            room_category_id: category.id,
            season_id: nil
          ],
          opts
        )
        |> Enum.into(%{})
      )

    rule
  end

  # ─── Buyout pricing ─────────────────────────────────────────────────────────

  describe "buyout pricing" do
    setup do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 500),
          booking_mode: :buyout,
          price_unit: :buyout_fixed,
          property: :tahoe,
          season_id: nil
        })

      :ok
    end

    test "price_per_night × nights (3 nights → $1500)" do
      assert {:ok, total, breakdown} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 @checkin,
                 @checkout_3n,
                 :buyout
               )

      assert total == Money.new(:USD, 1500)
      assert breakdown.nights == 3
      assert breakdown.price_per_night == Money.new(:USD, 500)
    end

    test "scales linearly: 2 nights → $1000" do
      assert {:ok, total, _} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 @checkin,
                 @checkout_2n,
                 :buyout
               )

      assert total == Money.new(:USD, 1000)
    end
  end

  # ─── Room (per-person-per-night) ────────────────────────────────────────────

  describe "room pricing" do
    test "guests × price_per_person_per_night × nights", %{category: cat} do
      make_room_rule(cat, 45)
      r = make_room(cat)

      # 4 guests × $45/ppn × 2 nights = $360
      # This is the exact scenario from the reported email bug.
      assert {:ok, total, breakdown} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 @checkin,
                 @checkout_2n,
                 :room,
                 room_id: r.id,
                 guests_count: 4
               )

      assert total == Money.new(:USD, 360)
      assert breakdown.billable_people == 4
    end

    test "scales linearly with guest count", %{category: cat} do
      make_room_rule(cat, 45)

      for guests <- [1, 2, 3, 4] do
        r = make_room(cat)

        assert {:ok, total, _} =
                 Bookings.calculate_booking_price(
                   :tahoe,
                   @checkin,
                   @checkout_2n,
                   :room,
                   room_id: r.id,
                   guests_count: guests
                 )

        expected_cents = 45 * guests * 2

        assert total == Money.new(:USD, expected_cents),
               "expected $#{expected_cents} for #{guests} guests"
      end
    end

    test "scales linearly with nights", %{category: cat} do
      make_room_rule(cat, 45)
      r = make_room(cat)

      for nights <- [1, 2, 3] do
        checkout = Date.add(@checkin, nights)

        assert {:ok, total, _} =
                 Bookings.calculate_booking_price(
                   :tahoe,
                   @checkin,
                   checkout,
                   :room,
                   room_id: r.id,
                   guests_count: 2
                 )

        expected_cents = 45 * 2 * nights

        assert total == Money.new(:USD, expected_cents),
               "expected $#{expected_cents} for #{nights} nights"
      end
    end

    test "returns error when no pricing rule covers the room", %{category: cat} do
      # We create a room but deliberately do NOT create a pricing rule for its category
      r = make_room(cat)

      assert {:error, :no_pricing_rules_found} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 @checkin,
                 @checkout_2n,
                 :room,
                 room_id: r.id,
                 guests_count: 2
               )
    end
  end

  # ─── Room: min_billable_occupancy ───────────────────────────────────────────

  describe "room pricing with min_billable_occupancy" do
    test "charges at least the minimum occupancy when fewer guests book", %{
      category: cat
    } do
      make_room_rule(cat, 100)

      # Room requires billing for at least 2 people even if only 1 guest shows up
      r = make_room(cat, %{min_billable_occupancy: 2, capacity_max: 4})

      # 1 guest but min is 2 → billed for 2 × $100 × 2 nights = $400
      assert {:ok, total, breakdown} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 @checkin,
                 @checkout_2n,
                 :room,
                 room_id: r.id,
                 guests_count: 1
               )

      assert total == Money.new(:USD, 400)
      assert breakdown.billable_people == 2
    end

    test "uses actual guest count when it exceeds min_billable_occupancy", %{
      category: cat
    } do
      make_room_rule(cat, 100)
      r = make_room(cat, %{min_billable_occupancy: 2, capacity_max: 6})

      # 4 guests > min 2 → billed for actual 4 × $100 × 2 nights = $800
      assert {:ok, total, _} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 @checkin,
                 @checkout_2n,
                 :room,
                 room_id: r.id,
                 guests_count: 4
               )

      assert total == Money.new(:USD, 800)
    end
  end

  # ─── Day (per-guest-per-day) ─────────────────────────────────────────────────

  describe "day pricing" do
    setup do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 30),
          booking_mode: :day,
          price_unit: :per_guest_per_day,
          property: :clear_lake,
          season_id: nil
        })

      :ok
    end

    test "guests × price_per_guest_per_day × days (4 guests, 2 days → $240)" do
      assert {:ok, total, breakdown} =
               Bookings.calculate_booking_price(
                 :clear_lake,
                 @checkin,
                 @checkout_2n,
                 :day,
                 guests_count: 4
               )

      assert total == Money.new(:USD, 240)
      assert breakdown.guests_count == 4
      assert breakdown.nights == 2
    end

    test "scales linearly with guest count" do
      for guests <- [1, 3, 6] do
        assert {:ok, total, _} =
                 Bookings.calculate_booking_price(
                   :clear_lake,
                   @checkin,
                   @checkout_2n,
                   :day,
                   guests_count: guests
                 )

        expected_cents = 30 * guests * 2

        assert total == Money.new(:USD, expected_cents),
               "expected $#{expected_cents} for #{guests} guests"
      end
    end
  end

  # ─── Error cases ────────────────────────────────────────────────────────────

  describe "calculate_booking_price/5 error cases" do
    test "returns error for checkout before checkin" do
      assert {:error, :invalid_date_range} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 @checkout_2n,
                 @checkin,
                 :buyout
               )
    end

    test "returns error for same-day checkin/checkout" do
      assert {:error, :invalid_date_range} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 @checkin,
                 @checkin,
                 :buyout
               )
    end

    test "returns error for room mode without room_id" do
      assert {:error, :room_id_required} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 @checkin,
                 @checkout_2n,
                 :room,
                 guests_count: 2
               )
    end
  end

  # ─── Season-specific pricing ─────────────────────────────────────────────────

  describe "season-specific room pricing" do
    setup %{category: cat} do
      {:ok, summer} =
        Bookings.create_season(%{
          name: "Test Summer #{System.unique_integer()}",
          property: :tahoe,
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-08-31]
        })

      Ysc.Bookings.SeasonCache.invalidate()

      # Summer rate: $80/ppn
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 80),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          room_category_id: cat.id,
          season_id: summer.id
        })

      # Default (off-season) rate: $50/ppn
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 50),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          room_category_id: cat.id,
          season_id: nil
        })

      r = make_room(cat)
      %{room: r, summer_season: summer}
    end

    test "applies summer rate when checkin is within the season", %{room: r} do
      # 2 guests × $80/ppn × 2 nights = $320
      assert {:ok, total, _} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 ~D[2026-07-01],
                 ~D[2026-07-03],
                 :room,
                 room_id: r.id,
                 guests_count: 2
               )

      assert total == Money.new(:USD, 320)
    end

    test "falls back to off-season rate when checkin is outside the season", %{
      room: r
    } do
      # 2 guests × $50/ppn × 2 nights = $200
      assert {:ok, total, _} =
               Bookings.calculate_booking_price(
                 :tahoe,
                 ~D[2026-10-01],
                 ~D[2026-10-03],
                 :room,
                 room_id: r.id,
                 guests_count: 2
               )

      assert total == Money.new(:USD, 200)
    end
  end

  # ─── Multi-room pricing invariant (regression) ──────────────────────────────

  describe "multi-room booking price invariant" do
    setup %{category: cat, user: user} do
      make_room_rule(cat, 45)
      r1 = make_room(cat, %{name: "Room A #{System.unique_integer()}"})
      r2 = make_room(cat, %{name: "Room B #{System.unique_integer()}"})
      r3 = make_room(cat, %{name: "Room C #{System.unique_integer()}"})
      %{user: user, room1: r1, room2: r2, room3: r3}
    end

    test "1-room booking: total_price = guests × price × nights",
         %{user: user, room1: r1} do
      # 4 guests × $45/ppn × 2 nights = $360
      assert {:ok, %Booking{} = booking} =
               BookingLocker.create_room_booking(
                 user.id,
                 r1.id,
                 @checkin,
                 @checkout_2n,
                 4
               )

      assert booking.total_price == Money.new(:USD, 360)
    end

    test "2-room booking: total_price equals the 1-room price (not doubled)",
         %{user: user, room1: r1, room2: r2} do
      # Regression: before the fix, BookingLocker summed calculate_booking_price
      # once per room (with the full guests_count each time), producing:
      #   2 rooms × 4 guests × $45/ppn × 2 nights = $720 ← was stored
      # Correct: price is per-person, so room count is irrelevant:
      #   4 guests × $45/ppn × 2 nights = $360
      assert {:ok, %Booking{} = booking} =
               BookingLocker.create_room_booking(
                 user.id,
                 [r1.id, r2.id],
                 @checkin,
                 @checkout_2n,
                 4
               )

      assert booking.total_price == Money.new(:USD, 360)
    end

    test "3-room booking: total_price equals the 1-room price (not tripled)",
         %{user: user, room1: r1, room2: r2, room3: r3} do
      assert {:ok, %Booking{} = booking} =
               BookingLocker.create_room_booking(
                 user.id,
                 [r1.id, r2.id, r3.id],
                 @checkin,
                 @checkout_2n,
                 4
               )

      assert booking.total_price == Money.new(:USD, 360)
    end

    test "pricing_items records correct type, nights, and room list",
         %{user: user, room1: r1, room2: r2} do
      assert {:ok, %Booking{} = booking} =
               BookingLocker.create_room_booking(
                 user.id,
                 [r1.id, r2.id],
                 @checkin,
                 @checkout_2n,
                 4
               )

      items = booking.pricing_items
      assert items["type"] == "room"
      assert items["nights"] == 2
      assert items["guests_count"] == 4
      assert length(items["rooms"]) == 2
    end
  end
end
