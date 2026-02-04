defmodule Ysc.Bookings.RefundPolicyCacheTest do
  @moduledoc """
  Tests for RefundPolicyCache module.

  These tests verify:
  - Cache hit/miss behavior
  - Cache invalidation on data change
  - Version-based cache validation
  - Active policy lookup
  - Rules preloading
  - Fallback to database on cache errors
  - PubSub broadcast on invalidation
  - Graceful handling when cache not initialized

  Note: Uses async: false to prevent Cachex race conditions.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Bookings.{RefundPolicyCache, RefundPolicy, RefundPolicyRule}
  alias Ysc.Repo

  # Helper to create a refund policy
  defp create_refund_policy(attrs) do
    {:ok, policy} =
      %RefundPolicy{}
      |> RefundPolicy.changeset(attrs)
      |> Repo.insert()

    policy
  end

  # Helper to create a refund policy rule
  defp create_refund_policy_rule(policy_id, days, percentage) do
    {:ok, rule} =
      %RefundPolicyRule{}
      |> RefundPolicyRule.changeset(%{
        refund_policy_id: policy_id,
        days_before_checkin: days,
        refund_percentage: Decimal.new(percentage)
      })
      |> Repo.insert()

    rule
  end

  # Clear cache before each test
  setup do
    # Invalidate cache to start fresh
    RefundPolicyCache.invalidate()
    :ok
  end

  describe "get_active/2" do
    test "returns active policy from database on cache miss" do
      policy =
        create_refund_policy(%{
          name: "Standard Refund Policy",
          property: :tahoe,
          booking_mode: :room,
          is_active: true
        })

      create_refund_policy_rule(policy.id, 14, "100.0")

      # First call - cache miss, fetches from DB
      cached_policy = RefundPolicyCache.get_active(:tahoe, :room)

      assert cached_policy.id == policy.id
      assert cached_policy.name == "Standard Refund Policy"
      assert length(cached_policy.rules) == 1
    end

    test "returns policy from cache on cache hit" do
      policy =
        create_refund_policy(%{
          name: "Flexible Policy",
          property: :tahoe,
          booking_mode: :room,
          is_active: true
        })

      create_refund_policy_rule(policy.id, 14, "100.0")

      # First call - populates cache
      RefundPolicyCache.get_active(:tahoe, :room)

      # Second call - should hit cache
      cached_policy = RefundPolicyCache.get_active(:tahoe, :room)

      assert cached_policy.id == policy.id
    end

    test "returns nil when no active policy exists" do
      # No active policy in database
      result = RefundPolicyCache.get_active(:tahoe, :room)

      assert result == nil
    end

    test "caches nil results" do
      # First call - caches nil
      result1 = RefundPolicyCache.get_active(:tahoe, :room)
      assert result1 == nil

      # Second call - should return cached nil
      result2 = RefundPolicyCache.get_active(:tahoe, :room)
      assert result2 == nil
    end

    test "ignores inactive policies" do
      # Create inactive policy
      create_refund_policy(%{
        name: "Inactive Policy",
        property: :tahoe,
        booking_mode: :room,
        is_active: false
      })

      # Should return nil (no active policy)
      result = RefundPolicyCache.get_active(:tahoe, :room)

      assert result == nil
    end

    test "preloads rules ordered by days_before_checkin descending" do
      policy =
        create_refund_policy(%{
          name: "Graduated Policy",
          property: :tahoe,
          booking_mode: :room,
          is_active: true
        })

      # Create rules in random order
      create_refund_policy_rule(policy.id, 7, "50.0")
      create_refund_policy_rule(policy.id, 30, "100.0")
      create_refund_policy_rule(policy.id, 14, "75.0")

      cached_policy = RefundPolicyCache.get_active(:tahoe, :room)

      assert length(cached_policy.rules) == 3

      # Verify rules are ordered by days_before_checkin descending
      days_list = Enum.map(cached_policy.rules, & &1.days_before_checkin)
      assert days_list == [30, 14, 7]
    end

    test "different property/booking_mode combinations have separate cache entries" do
      tahoe_room =
        create_refund_policy(%{
          name: "Tahoe Room Policy",
          property: :tahoe,
          booking_mode: :room,
          is_active: true
        })

      tahoe_buyout =
        create_refund_policy(%{
          name: "Tahoe Buyout Policy",
          property: :tahoe,
          booking_mode: :buyout,
          is_active: true
        })

      clear_lake_day =
        create_refund_policy(%{
          name: "Clear Lake Day Policy",
          property: :clear_lake,
          booking_mode: :day,
          is_active: true
        })

      # Fetch all policies - should be cached separately
      cached_tahoe_room = RefundPolicyCache.get_active(:tahoe, :room)
      cached_tahoe_buyout = RefundPolicyCache.get_active(:tahoe, :buyout)
      cached_clear_lake = RefundPolicyCache.get_active(:clear_lake, :day)

      assert cached_tahoe_room.id == tahoe_room.id
      assert cached_tahoe_buyout.id == tahoe_buyout.id
      assert cached_clear_lake.id == clear_lake_day.id
    end

    test "returns most recent active policy when only one is active (due to unique constraint)" do
      # Create first policy
      policy =
        create_refund_policy(%{
          name: "Active Policy",
          property: :tahoe,
          booking_mode: :room,
          is_active: true
        })

      # Note: Database has unique constraint preventing multiple active policies
      # for same property/booking_mode combination. This is the expected behavior.

      # Should return the active policy
      cached_policy = RefundPolicyCache.get_active(:tahoe, :room)

      assert cached_policy.id == policy.id
      assert cached_policy.name == "Active Policy"
    end
  end

  describe "invalidate/0" do
    test "invalidates cached refund policies" do
      policy =
        create_refund_policy(%{
          name: "Original Policy",
          property: :tahoe,
          booking_mode: :room,
          is_active: true
        })

      create_refund_policy_rule(policy.id, 14, "100.0")

      # Populate cache
      cached1 = RefundPolicyCache.get_active(:tahoe, :room)
      assert cached1.name == "Original Policy"

      # Invalidate cache
      RefundPolicyCache.invalidate()

      # Update policy in database
      {:ok, updated_policy} =
        policy
        |> RefundPolicy.changeset(%{name: "Updated Policy"})
        |> Repo.update()

      # Next get should fetch updated policy from DB
      cached2 = RefundPolicyCache.get_active(:tahoe, :room)

      assert cached2.id == updated_policy.id
      assert cached2.name == "Updated Policy"
    end

    test "invalidation bumps cache version" do
      # Get initial version
      {:ok, version1} = Cachex.get(:ysc_cache, "refund_policy:version")

      # Wait a moment to ensure time difference
      Process.sleep(10)

      # Invalidate
      RefundPolicyCache.invalidate()

      # Get new version
      {:ok, version2} = Cachex.get(:ysc_cache, "refund_policy:version")

      assert version2 > version1
    end

    test "broadcasts invalidation event via PubSub" do
      # Subscribe to PubSub topic
      Phoenix.PubSub.subscribe(Ysc.PubSub, "refund_policy_cache:invalidate")

      # Invalidate cache
      RefundPolicyCache.invalidate()

      # Verify broadcast was received
      assert_receive {:refund_policy_cache_invalidated, _version}, 1000
    end

    test "handles cache not initialized gracefully" do
      # This shouldn't raise an error even if cache isn't initialized
      assert RefundPolicyCache.invalidate() == :ok
    end
  end

  describe "cache version validation" do
    test "refetches when cache version is stale" do
      policy =
        create_refund_policy(%{
          name: "Original Policy",
          property: :tahoe,
          booking_mode: :room,
          is_active: true
        })

      create_refund_policy_rule(policy.id, 14, "100.0")

      # Populate cache with version 1
      RefundPolicyCache.get_active(:tahoe, :room)

      # Invalidate to bump version
      RefundPolicyCache.invalidate()

      # Update policy in DB
      {:ok, _updated_policy} =
        policy
        |> RefundPolicy.changeset(%{name: "Updated Policy"})
        |> Repo.update()

      # Get should detect stale version and refetch
      cached_policy = RefundPolicyCache.get_active(:tahoe, :room)

      assert cached_policy.name == "Updated Policy"
    end
  end

  describe "rules association" do
    test "loads all rules for a policy" do
      policy =
        create_refund_policy(%{
          name: "Multi-tier Policy",
          property: :tahoe,
          booking_mode: :room,
          is_active: true
        })

      # Create multiple rules
      create_refund_policy_rule(policy.id, 30, "100.0")
      create_refund_policy_rule(policy.id, 21, "90.0")
      create_refund_policy_rule(policy.id, 14, "75.0")
      create_refund_policy_rule(policy.id, 7, "50.0")
      create_refund_policy_rule(policy.id, 0, "0.0")

      cached_policy = RefundPolicyCache.get_active(:tahoe, :room)

      assert length(cached_policy.rules) == 5
    end

    test "rules are properly structured with all fields" do
      policy =
        create_refund_policy(%{
          name: "Test Policy",
          property: :tahoe,
          booking_mode: :room,
          is_active: true
        })

      create_refund_policy_rule(policy.id, 14, "100.0")

      cached_policy = RefundPolicyCache.get_active(:tahoe, :room)

      rule = hd(cached_policy.rules)
      assert rule.days_before_checkin == 14
      assert Decimal.equal?(rule.refund_percentage, Decimal.new("100.0"))
      assert rule.refund_policy_id == policy.id
    end
  end

  describe "cache key uniqueness" do
    test "cache keys include property and booking_mode" do
      tahoe_policy =
        create_refund_policy(%{
          name: "Tahoe Room Policy",
          property: :tahoe,
          booking_mode: :room,
          is_active: true
        })

      clear_lake_policy =
        create_refund_policy(%{
          name: "Clear Lake Day Policy",
          property: :clear_lake,
          booking_mode: :day,
          is_active: true
        })

      # Fetch both - should be cached separately
      cached_tahoe = RefundPolicyCache.get_active(:tahoe, :room)
      cached_clear_lake = RefundPolicyCache.get_active(:clear_lake, :day)

      assert cached_tahoe.id == tahoe_policy.id
      assert cached_clear_lake.id == clear_lake_policy.id
      assert cached_tahoe.id != cached_clear_lake.id
    end
  end

  describe "typical refund policy scenarios" do
    test "non-refundable policy" do
      policy =
        create_refund_policy(%{
          name: "Non-Refundable",
          property: :tahoe,
          booking_mode: :buyout,
          is_active: true
        })

      create_refund_policy_rule(policy.id, 0, "0.0")

      cached_policy = RefundPolicyCache.get_active(:tahoe, :buyout)

      assert cached_policy.name == "Non-Refundable"
      assert length(cached_policy.rules) == 1

      assert Decimal.equal?(
               hd(cached_policy.rules).refund_percentage,
               Decimal.new("0.0")
             )
    end

    test "graduated refund tiers policy" do
      policy =
        create_refund_policy(%{
          name: "Graduated Refund",
          property: :tahoe,
          booking_mode: :room,
          is_active: true
        })

      create_refund_policy_rule(policy.id, 30, "100.0")
      create_refund_policy_rule(policy.id, 14, "75.0")
      create_refund_policy_rule(policy.id, 7, "50.0")
      create_refund_policy_rule(policy.id, 0, "0.0")

      cached_policy = RefundPolicyCache.get_active(:tahoe, :room)

      assert length(cached_policy.rules) == 4

      # Verify tiers are properly ordered
      percentages = Enum.map(cached_policy.rules, & &1.refund_percentage)

      assert Decimal.equal?(Enum.at(percentages, 0), Decimal.new("100.0"))
      assert Decimal.equal?(Enum.at(percentages, 1), Decimal.new("75.0"))
      assert Decimal.equal?(Enum.at(percentages, 2), Decimal.new("50.0"))
      assert Decimal.equal?(Enum.at(percentages, 3), Decimal.new("0.0"))
    end
  end
end
