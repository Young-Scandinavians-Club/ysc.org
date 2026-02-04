defmodule Ysc.Bookings.PricingRuleCacheTest do
  @moduledoc """
  Tests for PricingRuleCache module.

  These tests verify:
  - Cache hit/miss behavior
  - Cache invalidation on data change
  - Version-based cache validation
  - Children pricing rule caching
  - Fallback to database on cache errors
  - Cache key building
  - PubSub broadcast on invalidation

  Note: Uses async: false to prevent Cachex race conditions.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Bookings.{PricingRuleCache, PricingRule, Room, Season}
  alias Ysc.Repo

  # Helper to create a season for testing
  defp create_season(attrs \\ %{}) do
    default_attrs = %{
      name: "Test Season #{System.unique_integer()}",
      property: :tahoe,
      start_date: ~D[2024-01-01],
      end_date: ~D[2024-12-31]
    }

    attrs = Map.merge(default_attrs, attrs)

    {:ok, season} =
      %Season{}
      |> Season.changeset(attrs)
      |> Repo.insert()

    season
  end

  # Helper to create a room for testing
  defp create_room(attrs \\ %{}) do
    default_attrs = %{
      name: "Test Room #{System.unique_integer()}",
      property: :tahoe,
      capacity_max: 2
    }

    attrs = Map.merge(default_attrs, attrs)

    {:ok, room} =
      %Room{}
      |> Room.changeset(attrs)
      |> Repo.insert()

    room
  end

  # Helper to create a pricing rule
  defp create_pricing_rule(attrs) do
    {:ok, rule} =
      %PricingRule{}
      |> PricingRule.changeset(attrs)
      |> Repo.insert()

    rule
  end

  # Clear cache before each test
  setup do
    # Clear the entire cache to start fresh
    Cachex.clear(:ysc_cache)
    # Reset version
    PricingRuleCache.invalidate()
    :ok
  end

  describe "get/6" do
    test "returns pricing rule from database on cache miss" do
      season = create_season()

      rule =
        create_pricing_rule(%{
          amount: Money.new(10_000, :USD),
          property: :tahoe,
          season_id: season.id,
          booking_mode: :room,
          price_unit: :per_person_per_night
        })

      # First call - cache miss, fetches from DB
      cached_rule =
        PricingRuleCache.get(
          :tahoe,
          season.id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

      assert cached_rule.id == rule.id
      assert cached_rule.amount == Money.new(10_000, :USD)
    end

    test "returns pricing rule from cache on cache hit" do
      season = create_season()

      rule =
        create_pricing_rule(%{
          amount: Money.new(10_000, :USD),
          property: :tahoe,
          season_id: season.id,
          booking_mode: :room,
          price_unit: :per_person_per_night
        })

      # First call - populates cache
      PricingRuleCache.get(
        :tahoe,
        season.id,
        nil,
        nil,
        :room,
        :per_person_per_night
      )

      # Second call - should hit cache (verify by checking it returns same result)
      cached_rule =
        PricingRuleCache.get(
          :tahoe,
          season.id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

      assert cached_rule.id == rule.id
    end

    test "returns nil when no pricing rule exists" do
      season = create_season()

      # No pricing rule in database
      result =
        PricingRuleCache.get(
          :tahoe,
          season.id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

      assert result == nil
    end

    test "caches nil results" do
      season = create_season()

      # First call - caches nil
      result1 =
        PricingRuleCache.get(
          :tahoe,
          season.id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

      assert result1 == nil

      # Second call - should return cached nil
      result2 =
        PricingRuleCache.get(
          :tahoe,
          season.id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

      assert result2 == nil
    end

    test "finds most specific pricing rule (room-specific)" do
      season = create_season()
      room = create_room()

      # Create property-level rule
      create_pricing_rule(%{
        amount: Money.new(10_000, :USD),
        property: :tahoe,
        season_id: season.id,
        booking_mode: :room,
        price_unit: :per_person_per_night
      })

      # Create room-specific rule (more specific)
      room_rule =
        create_pricing_rule(%{
          amount: Money.new(15_000, :USD),
          property: :tahoe,
          season_id: season.id,
          room_id: room.id,
          booking_mode: :room,
          price_unit: :per_person_per_night
        })

      # Should return room-specific rule
      cached_rule =
        PricingRuleCache.get(
          :tahoe,
          season.id,
          room.id,
          nil,
          :room,
          :per_person_per_night
        )

      assert cached_rule.id == room_rule.id
      assert cached_rule.amount == Money.new(15_000, :USD)
    end

    test "different cache keys for different parameters" do
      season = create_season()

      rule1 =
        create_pricing_rule(%{
          amount: Money.new(10_000, :USD),
          property: :tahoe,
          season_id: season.id,
          booking_mode: :room,
          price_unit: :per_person_per_night
        })

      rule2 =
        create_pricing_rule(%{
          amount: Money.new(20_000, :USD),
          property: :tahoe,
          season_id: season.id,
          booking_mode: :buyout,
          price_unit: :buyout_fixed
        })

      # Get both rules - should be cached separately
      cached1 =
        PricingRuleCache.get(
          :tahoe,
          season.id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

      cached2 =
        PricingRuleCache.get(
          :tahoe,
          season.id,
          nil,
          nil,
          :buyout,
          :buyout_fixed
        )

      assert cached1.id == rule1.id
      assert cached2.id == rule2.id
    end
  end

  describe "get_children/6" do
    test "returns children pricing rule from database on cache miss" do
      season = create_season()

      rule =
        create_pricing_rule(%{
          amount: Money.new(10_000, :USD),
          children_amount: Money.new(5000, :USD),
          property: :tahoe,
          season_id: season.id,
          booking_mode: :room,
          price_unit: :per_person_per_night
        })

      # First call - cache miss, fetches from DB
      cached_rule =
        PricingRuleCache.get_children(
          :tahoe,
          season.id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

      assert cached_rule.id == rule.id
      assert cached_rule.children_amount == Money.new(5000, :USD)
    end

    test "returns children pricing rule from cache on cache hit" do
      season = create_season()

      rule =
        create_pricing_rule(%{
          amount: Money.new(10_000, :USD),
          children_amount: Money.new(5000, :USD),
          property: :tahoe,
          season_id: season.id,
          booking_mode: :room,
          price_unit: :per_person_per_night
        })

      # First call - populates cache
      PricingRuleCache.get_children(
        :tahoe,
        season.id,
        nil,
        nil,
        :room,
        :per_person_per_night
      )

      # Second call - should hit cache
      cached_rule =
        PricingRuleCache.get_children(
          :tahoe,
          season.id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

      assert cached_rule.id == rule.id
    end

    test "children cache uses separate cache key from regular cache" do
      season = create_season()

      # Create rule with both adult and children pricing
      rule =
        create_pricing_rule(%{
          amount: Money.new(10_000, :USD),
          children_amount: Money.new(5000, :USD),
          property: :tahoe,
          season_id: season.id,
          booking_mode: :room,
          price_unit: :per_person_per_night
        })

      # Get regular rule (returns the same rule for adult pricing)
      cached_regular =
        PricingRuleCache.get(
          :tahoe,
          season.id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

      # Get children rule (returns the same rule for children pricing)
      cached_children =
        PricingRuleCache.get_children(
          :tahoe,
          season.id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

      # Both should return the same rule (since it has both prices)
      assert cached_regular.id == rule.id
      assert cached_children.id == rule.id
      assert cached_regular.amount == Money.new(10_000, :USD)
      assert cached_children.children_amount == Money.new(5000, :USD)
    end
  end

  describe "invalidate/0" do
    test "invalidates cached pricing rules" do
      season = create_season()

      rule =
        create_pricing_rule(%{
          amount: Money.new(10_000, :USD),
          property: :tahoe,
          season_id: season.id,
          booking_mode: :room,
          price_unit: :per_person_per_night
        })

      # Populate cache
      cached1 =
        PricingRuleCache.get(
          :tahoe,
          season.id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

      assert cached1.id == rule.id

      # Wait to ensure version timestamp is different (versions use second resolution)
      Process.sleep(1100)

      # Invalidate cache
      PricingRuleCache.invalidate()

      # Update the rule in database
      {:ok, updated_rule} =
        rule
        |> PricingRule.changeset(%{amount: Money.new(15_000, :USD)})
        |> Repo.update()

      # Next get should fetch updated rule from DB
      cached2 =
        PricingRuleCache.get(
          :tahoe,
          season.id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

      assert cached2.id == updated_rule.id
      assert cached2.amount == Money.new(15_000, :USD)
    end

    test "invalidation bumps cache version" do
      # Get initial version
      {:ok, version1} = Cachex.get(:ysc_cache, "pricing_rule:version")

      # Wait one second to ensure time difference (version uses second resolution)
      Process.sleep(1100)

      # Invalidate
      PricingRuleCache.invalidate()

      # Get new version
      {:ok, version2} = Cachex.get(:ysc_cache, "pricing_rule:version")

      assert version2 > version1
    end

    test "broadcasts invalidation event via PubSub" do
      # Subscribe to PubSub topic
      Phoenix.PubSub.subscribe(Ysc.PubSub, "pricing_rule_cache:invalidate")

      # Invalidate cache
      PricingRuleCache.invalidate()

      # Verify broadcast was received
      assert_receive {:pricing_rule_cache_invalidated, _version}, 1000
    end
  end

  describe "cache version validation" do
    test "refetches when cache version is stale" do
      season = create_season()

      rule =
        create_pricing_rule(%{
          amount: Money.new(10_000, :USD),
          property: :tahoe,
          season_id: season.id,
          booking_mode: :room,
          price_unit: :per_person_per_night
        })

      # Populate cache with version 1
      PricingRuleCache.get(
        :tahoe,
        season.id,
        nil,
        nil,
        :room,
        :per_person_per_night
      )

      # Wait to ensure version timestamp is different
      Process.sleep(1100)

      # Invalidate to bump version
      PricingRuleCache.invalidate()

      # Update rule in DB
      {:ok, _updated_rule} =
        rule
        |> PricingRule.changeset(%{amount: Money.new(15_000, :USD)})
        |> Repo.update()

      # Get should detect stale version and refetch
      cached_rule =
        PricingRuleCache.get(
          :tahoe,
          season.id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

      assert cached_rule.amount == Money.new(15_000, :USD)
    end
  end

  describe "cache key uniqueness" do
    test "cache keys are unique for different combinations" do
      season = create_season()
      room = create_room()

      # Create rules with different specificity
      rule1 =
        create_pricing_rule(%{
          amount: Money.new(10_000, :USD),
          property: :tahoe,
          season_id: season.id,
          booking_mode: :room,
          price_unit: :per_person_per_night
        })

      rule2 =
        create_pricing_rule(%{
          amount: Money.new(15_000, :USD),
          property: :tahoe,
          season_id: season.id,
          room_id: room.id,
          booking_mode: :room,
          price_unit: :per_person_per_night
        })

      # Fetch both - they should be cached separately
      cached1 =
        PricingRuleCache.get(
          :tahoe,
          season.id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

      cached2 =
        PricingRuleCache.get(
          :tahoe,
          season.id,
          room.id,
          nil,
          :room,
          :per_person_per_night
        )

      assert cached1.id == rule1.id
      assert cached2.id == rule2.id
      assert cached1.id != cached2.id
    end
  end
end
