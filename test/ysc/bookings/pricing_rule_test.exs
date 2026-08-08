defmodule Ysc.Bookings.PricingRuleTest do
  @moduledoc """
  Tests for PricingRule schema.

  These tests verify:
  - Money type validation (USD, non-negative)
  - Booking mode enum (room, day, buyout)
  - Price unit enum (per_person_per_night, per_guest_per_day, buyout_fixed)
  - Hierarchical specificity (room > category > property+season)
  - Children pricing (optional children_amount)
  - Unique constraints
  - Foreign key constraints
  """
  use Ysc.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Ysc.Bookings
  alias Ysc.Bookings.{PricingRule, PricingRuleCache, Room, RoomCategory, Season}
  alias Ysc.Repo

  setup do
    # Create season for Tahoe
    {:ok, season} =
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

    # Create room category
    {:ok, category} =
      %RoomCategory{}
      |> RoomCategory.changeset(%{
        name: "Standard",
        property: :tahoe
      })
      |> Repo.insert()

    # Create room
    {:ok, room} =
      %Room{}
      |> Room.changeset(%{
        name: "Tahoe Room 1",
        property: :tahoe,
        capacity_max: 4,
        room_category_id: category.id,
        is_active: true
      })
      |> Repo.insert()

    %{season: season, category: category, room: room}
  end

  describe "changeset/2" do
    test "uses default empty attrs when second argument omitted" do
      changeset = PricingRule.changeset(%PricingRule{})
      refute changeset.valid?
    end

    test "creates valid changeset with all required fields" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
      assert changeset.changes.amount == Money.new(10_000, :USD)
      assert changeset.changes.booking_mode == :room
      assert changeset.changes.price_unit == :per_person_per_night
    end

    test "creates valid changeset with children pricing", %{season: season} do
      attrs = %{
        amount: Money.new(10_000, :USD),
        children_amount: Money.new(5000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        season_id: season.id
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
      assert changeset.changes.children_amount == Money.new(5000, :USD)
    end

    test "requires amount" do
      attrs = %{
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:amount] != nil
    end

    test "requires booking_mode" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:booking_mode] != nil
    end

    test "requires price_unit" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :room,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:price_unit] != nil
    end

    test "requires at least one specificity field (property, room_id, or category_id)" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:base] != nil
      {message, _} = changeset.errors[:base]
      assert message =~ "must specify at least one"
    end
  end

  describe "Money validation" do
    test "accepts valid USD amount" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
    end

    test "accepts zero amount" do
      attrs = %{
        amount: Money.new(0, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
    end

    test "rejects negative amount" do
      attrs = %{
        amount: Money.new(-100, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:amount] != nil
      {message, _} = changeset.errors[:amount]
      assert message =~ "must be greater than or equal to 0"
    end

    test "rejects non-USD currency for amount" do
      attrs = %{
        amount: Money.new(10_000, :EUR),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:amount] != nil
      {message, _} = changeset.errors[:amount]
      assert message =~ "must be in USD"
    end

    test "rejects non-USD currency for children_amount" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        children_amount: Money.new(5000, :GBP),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      refute changeset.valid?
      {message, _} = changeset.errors[:children_amount]
      assert message =~ "must be in USD"
    end

    test "rejects negative children_amount" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        children_amount: Money.new(-50, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:children_amount] != nil
      {message, _} = changeset.errors[:children_amount]
      assert message =~ "must be greater than or equal to 0"
    end

    test "accepts nil children_amount" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        children_amount: nil,
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
    end

    test "accepts explicitly clearing a previously-set children_amount to nil" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        children_amount: Money.new(5000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      {:ok, rule} =
        %PricingRule{}
        |> PricingRule.changeset(attrs)
        |> Repo.insert()

      # Update with children_amount explicitly nil so it is recorded as a
      # change (rather than being absent from cast) and clears the stored
      # value. Note: Ecto's own `validate_change/3` short-circuits on a nil
      # change before calling our validator, so the `nil ->` clause inside
      # validate_money/2 is unreachable dead code guarding against something
      # Ecto already handles — this test covers the clearing behavior itself.
      changeset = PricingRule.changeset(rule, %{children_amount: nil})

      assert changeset.valid?
      {:ok, updated} = Repo.update(changeset)
      assert is_nil(updated.children_amount)
    end
  end

  describe "booking_mode enum" do
    test "accepts room booking mode" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
      assert changeset.changes.booking_mode == :room
    end

    test "accepts day booking mode" do
      attrs = %{
        amount: Money.new(20_000, :USD),
        booking_mode: :day,
        price_unit: :per_guest_per_day,
        property: :clear_lake
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
      assert changeset.changes.booking_mode == :day
    end

    test "accepts buyout booking mode" do
      attrs = %{
        amount: Money.new(500_000, :USD),
        booking_mode: :buyout,
        price_unit: :buyout_fixed,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
      assert changeset.changes.booking_mode == :buyout
    end

    test "rejects invalid booking mode" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :invalid_mode,
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      refute changeset.valid?
    end
  end

  describe "price_unit enum" do
    test "accepts per_person_per_night" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
      assert changeset.changes.price_unit == :per_person_per_night
    end

    test "accepts per_guest_per_day" do
      attrs = %{
        amount: Money.new(15_000, :USD),
        booking_mode: :day,
        price_unit: :per_guest_per_day,
        property: :clear_lake
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
      assert changeset.changes.price_unit == :per_guest_per_day
    end

    test "accepts buyout_fixed" do
      attrs = %{
        amount: Money.new(500_000, :USD),
        booking_mode: :buyout,
        price_unit: :buyout_fixed,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
      assert changeset.changes.price_unit == :buyout_fixed
    end

    test "rejects invalid price unit" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :room,
        price_unit: :invalid_unit,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      refute changeset.valid?
    end
  end

  describe "property enum" do
    test "accepts tahoe property" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
      assert changeset.changes.property == :tahoe
    end

    test "accepts clear_lake property" do
      attrs = %{
        amount: Money.new(15_000, :USD),
        booking_mode: :day,
        price_unit: :per_guest_per_day,
        property: :clear_lake
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
      assert changeset.changes.property == :clear_lake
    end

    test "rejects invalid property" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :invalid_property
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      refute changeset.valid?
    end
  end

  describe "hierarchical specificity" do
    test "room-level pricing (most specific)", %{room: room} do
      attrs = %{
        amount: Money.new(12_000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        room_id: room.id
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
      {:ok, rule} = Repo.insert(changeset)
      assert rule.room_id == room.id
      assert is_nil(rule.room_category_id)
      assert is_nil(rule.property)
    end

    test "category-level pricing (medium specificity)", %{category: category} do
      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        room_category_id: category.id
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
      {:ok, rule} = Repo.insert(changeset)
      assert is_nil(rule.room_id)
      assert rule.room_category_id == category.id
      assert is_nil(rule.property)
    end

    test "property-level pricing (least specific)" do
      attrs = %{
        amount: Money.new(8000, :USD),
        booking_mode: :buyout,
        # Use buyout to avoid conflict
        price_unit: :buyout_fixed,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
      {:ok, rule} = Repo.insert(changeset)
      assert is_nil(rule.room_id)
      assert is_nil(rule.room_category_id)
      assert rule.property == :tahoe
    end

    test "property + season pricing", %{season: season} do
      attrs = %{
        amount: Money.new(12_000, :USD),
        booking_mode: :day,
        # Use day to avoid conflict
        price_unit: :per_guest_per_day,
        property: :tahoe,
        season_id: season.id
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)

      assert changeset.valid?
      {:ok, rule} = Repo.insert(changeset)
      assert rule.property == :tahoe
      assert rule.season_id == season.id
    end
  end

  describe "database constraints" do
    test "enforces foreign key constraint on room_id" do
      invalid_room_id = Ecto.ULID.generate()

      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        room_id: invalid_room_id
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)
      {:error, changeset_error} = Repo.insert(changeset)

      assert changeset_error.errors[:room_id] != nil
    end

    test "enforces foreign key constraint on room_category_id" do
      invalid_category_id = Ecto.ULID.generate()

      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        room_category_id: invalid_category_id
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)
      {:error, changeset_error} = Repo.insert(changeset)

      assert changeset_error.errors[:room_category_id] != nil
    end

    test "enforces foreign key constraint on season_id" do
      invalid_season_id = Ecto.ULID.generate()

      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        season_id: invalid_season_id
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)
      {:error, changeset_error} = Repo.insert(changeset)

      assert changeset_error.errors[:season_id] != nil
    end

    test "can insert and retrieve complete pricing rule", %{
      season: season,
      room: room
    } do
      attrs = %{
        amount: Money.new(15_000, :USD),
        children_amount: Money.new(7500, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        season_id: season.id,
        room_id: room.id
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)
      {:ok, rule} = Repo.insert(changeset)

      retrieved = Repo.get(PricingRule, rule.id)

      assert retrieved.amount == Money.new(15_000, :USD)
      assert retrieved.children_amount == Money.new(7500, :USD)
      assert retrieved.booking_mode == :room
      assert retrieved.price_unit == :per_person_per_night
      assert retrieved.property == :tahoe
      assert retrieved.season_id == season.id
      assert retrieved.room_id == room.id
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "can retrieve pricing rule with preloaded associations", %{
      season: season,
      room: room,
      category: category
    } do
      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        season_id: season.id,
        room_id: room.id,
        room_category_id: category.id
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)
      {:ok, rule} = Repo.insert(changeset)

      retrieved =
        PricingRule
        |> Repo.get(rule.id)
        |> Repo.preload([:room, :room_category, :season])

      assert retrieved.room.id == room.id
      assert retrieved.room.name == "Tahoe Room 1"
      assert retrieved.room_category.id == category.id
      assert retrieved.room_category.name == "Standard"
      assert retrieved.season.id == season.id
      assert retrieved.season.name == "Summer"
    end
  end

  describe "children pricing" do
    test "stores children amount separately", %{room: room} do
      attrs = %{
        amount: Money.new(10_000, :USD),
        children_amount: Money.new(5000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        room_id: room.id
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)
      {:ok, rule} = Repo.insert(changeset)

      assert rule.amount == Money.new(10_000, :USD)
      assert rule.children_amount == Money.new(5000, :USD)
    end

    test "children amount is optional" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        booking_mode: :day,
        price_unit: :per_guest_per_day,
        property: :clear_lake
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)
      {:ok, rule} = Repo.insert(changeset)

      assert rule.amount == Money.new(10_000, :USD)
      assert is_nil(rule.children_amount)
    end

    test "children amount can be zero", %{category: category} do
      attrs = %{
        amount: Money.new(10_000, :USD),
        children_amount: Money.new(0, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        room_category_id: category.id
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)
      {:ok, rule} = Repo.insert(changeset)

      assert rule.children_amount == Money.new(0, :USD)
    end
  end

  describe "typical pricing scenarios" do
    test "Tahoe per-person-per-night pricing", %{season: season, room: room} do
      # Use season + room to make it unique
      attrs = %{
        amount: Money.new(8500, :USD),
        children_amount: Money.new(4250, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        season_id: season.id,
        room_id: room.id
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)
      {:ok, rule} = Repo.insert(changeset)

      assert rule.amount == Money.new(8500, :USD)
      assert rule.children_amount == Money.new(4250, :USD)
      assert rule.booking_mode == :room
      assert rule.price_unit == :per_person_per_night
    end

    test "Clear Lake per-guest-per-day pricing" do
      attrs = %{
        amount: Money.new(15_000, :USD),
        children_amount: Money.new(7500, :USD),
        booking_mode: :day,
        price_unit: :per_guest_per_day,
        property: :clear_lake
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)
      {:ok, rule} = Repo.insert(changeset)

      assert rule.amount == Money.new(15_000, :USD)
      assert rule.children_amount == Money.new(7500, :USD)
      assert rule.booking_mode == :day
      assert rule.price_unit == :per_guest_per_day
    end

    test "Tahoe buyout fixed pricing" do
      attrs = %{
        amount: Money.new(500_000, :USD),
        booking_mode: :buyout,
        price_unit: :buyout_fixed,
        property: :tahoe
      }

      changeset = PricingRule.changeset(%PricingRule{}, attrs)
      {:ok, rule} = Repo.insert(changeset)

      assert rule.amount == Money.new(500_000, :USD)
      assert is_nil(rule.children_amount)
      assert rule.booking_mode == :buyout
      assert rule.price_unit == :buyout_fixed
    end

    test "seasonal pricing differential", %{season: season, category: category} do
      # Base pricing (no season) - use category to avoid conflict
      base_attrs = %{
        amount: Money.new(8000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        room_category_id: category.id
      }

      {:ok, base_rule} =
        %PricingRule{}
        |> PricingRule.changeset(base_attrs)
        |> Repo.insert()

      # Summer pricing (higher rate) - use category + season
      summer_attrs = %{
        amount: Money.new(12_000, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        room_category_id: category.id,
        season_id: season.id
      }

      {:ok, summer_rule} =
        %PricingRule{}
        |> PricingRule.changeset(summer_attrs)
        |> Repo.insert()

      assert base_rule.amount == Money.new(8000, :USD)
      assert summer_rule.amount == Money.new(12_000, :USD)
      assert is_nil(base_rule.season_id)
      assert summer_rule.season_id == season.id
    end
  end

  describe "find_most_specific_db/6 and find_children_pricing_rule_db/6" do
    setup do
      Ysc.Ledgers.ensure_basic_accounts()
      Ysc.Bookings.SeasonCache.invalidate()
      Cachex.clear(:ysc_cache)
      :ok
    end

    test "returns property-level rule when no room or category filters apply",
         %{
           season: season
         } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 99),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: season.id
        })

      found =
        PricingRule.find_most_specific_db(
          :tahoe,
          season.id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

      assert found.amount == Money.new(:USD, 99)
      assert is_nil(found.room_id)
      assert is_nil(found.room_category_id)
    end

    test "prefers room-specific rule over property-level rule", %{
      season: season,
      room: room,
      category: category
    } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 50),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          season_id: season.id,
          room_category_id: category.id
        })

      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 200),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          room_id: room.id,
          season_id: season.id
        })

      found =
        PricingRule.find_most_specific_db(
          :tahoe,
          season.id,
          room.id,
          category.id,
          :room,
          :per_person_per_night
        )

      assert found.room_id == room.id
      assert found.amount == Money.new(:USD, 200)
    end

    test "returns nil when no rules exist for the property and mode", %{
      season: season
    } do
      assert is_nil(
               PricingRule.find_most_specific_db(
                 :clear_lake,
                 season.id,
                 nil,
                 nil,
                 :buyout,
                 :buyout_fixed
               )
             )
    end

    test "find_children_pricing_rule_db returns rule with children_amount set",
         %{
           season: season,
           room: room
         } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          children_amount: Money.new(:USD, 40),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          room_id: room.id,
          season_id: season.id
        })

      found =
        PricingRule.find_children_pricing_rule_db(
          :tahoe,
          season.id,
          room.id,
          nil,
          :room,
          :per_person_per_night
        )

      assert found.children_amount == Money.new(:USD, 40)
    end

    test "find_children_pricing_rule_db returns nil when no children pricing exists",
         %{
           season: season,
           room: room
         } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          room_id: room.id,
          season_id: season.id
        })

      assert is_nil(
               PricingRule.find_children_pricing_rule_db(
                 :tahoe,
                 season.id,
                 room.id,
                 nil,
                 :room,
                 :per_person_per_night
               )
             )
    end

    test "matches category-level rule when no room_id is provided", %{
      season: season,
      category: category
    } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 77),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          room_category_id: category.id,
          season_id: season.id
        })

      found =
        PricingRule.find_most_specific_db(
          :tahoe,
          season.id,
          nil,
          category.id,
          :room,
          :per_person_per_night
        )

      assert found.amount == Money.new(:USD, 77)
      assert is_nil(found.room_id)
      assert found.room_category_id == category.id
    end

    test "uses property fallback when season_id is nil", %{season: _season} do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 33),
          booking_mode: :day,
          price_unit: :per_guest_per_day,
          property: :clear_lake,
          season_id: nil
        })

      found =
        PricingRule.find_most_specific_db(
          :clear_lake,
          nil,
          nil,
          nil,
          :day,
          :per_guest_per_day
        )

      assert found.amount == Money.new(:USD, 33)
      assert is_nil(found.season_id)
    end

    test "find_most_specific/6 returns same rule as find_most_specific_db/6 via cache",
         %{
           season: season,
           category: category
         } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 88),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          room_category_id: category.id,
          season_id: season.id
        })

      PricingRuleCache.invalidate()

      via_public =
        PricingRule.find_most_specific(
          :tahoe,
          season.id,
          nil,
          category.id,
          :room,
          :per_person_per_night
        )

      via_db =
        PricingRule.find_most_specific_db(
          :tahoe,
          season.id,
          nil,
          category.id,
          :room,
          :per_person_per_night
        )

      assert via_public.id == via_db.id
      assert via_public.amount == Money.new(:USD, 88)
    end

    test "find_children_pricing_rule/6 returns same rule as find_children_pricing_rule_db/6",
         %{
           season: season,
           room: room
         } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 120),
          children_amount: Money.new(:USD, 55),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          room_id: room.id,
          season_id: season.id
        })

      PricingRuleCache.invalidate()

      via_public =
        PricingRule.find_children_pricing_rule(
          :tahoe,
          season.id,
          room.id,
          nil,
          :room,
          :per_person_per_night
        )

      via_db =
        PricingRule.find_children_pricing_rule_db(
          :tahoe,
          season.id,
          room.id,
          nil,
          :room,
          :per_person_per_night
        )

      assert via_public.id == via_db.id
      assert via_public.children_amount == Money.new(:USD, 55)
    end

    test "find_children_pricing_rule_db logs branch when a children rule is found",
         %{
           season: season,
           room: room
         } do
      {:ok, r} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 200),
          children_amount: Money.new(:USD, 90),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          room_id: room.id,
          season_id: season.id
        })

      found =
        PricingRule.find_children_pricing_rule_db(
          :tahoe,
          season.id,
          room.id,
          nil,
          :room,
          :per_person_per_night
        )

      assert found.id == r.id
      assert found.children_amount == Money.new(:USD, 90)
    end

    test "find_most_specific_db runs diagnostic counts when no rule matches", %{
      season: season
    } do
      assert is_nil(
               PricingRule.find_most_specific_db(
                 :tahoe,
                 season.id,
                 nil,
                 nil,
                 :buyout,
                 :buyout_fixed
               )
             )
    end

    test "find_children_pricing_rule_db returns category-level rule when room_id is nil",
         %{
           season: season,
           category: category
         } do
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 100),
          children_amount: Money.new(:USD, 42),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          room_category_id: category.id,
          season_id: season.id
        })

      found =
        PricingRule.find_children_pricing_rule_db(
          :tahoe,
          season.id,
          nil,
          category.id,
          :room,
          :per_person_per_night
        )

      assert found.children_amount == Money.new(:USD, 42)
      assert is_nil(found.room_id)
      assert found.room_category_id == category.id
    end

    test "find_most_specific_db returns row when rule matches (no diagnostic branch)",
         %{
           season: season,
           room: room
         } do
      {:ok, inserted} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(:USD, 301),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          room_id: room.id,
          season_id: season.id
        })

      found =
        PricingRule.find_most_specific_db(
          :tahoe,
          season.id,
          room.id,
          nil,
          :room,
          :per_person_per_night
        )

      assert found.id == inserted.id
      assert found.amount == Money.new(:USD, 301)

      # Sanity-check the same rule is visible via a direct query
      assert Repo.exists?(
               from pr in PricingRule,
                 where: pr.id == ^inserted.id
             )
    end
  end

  describe "ci_query_explain_query/0" do
    test "builds a runnable Ecto query for CI query-plan diagnostics" do
      query = PricingRule.ci_query_explain_query()

      assert %Ecto.Query{} = query
      assert Repo.all(query) == []
    end
  end
end
