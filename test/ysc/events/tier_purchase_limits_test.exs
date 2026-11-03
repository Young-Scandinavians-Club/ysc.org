defmodule Ysc.Events.TierPurchaseLimitsTest do
  use ExUnit.Case, async: true

  alias Ysc.Events.TierPurchaseLimits, as: Limits

  defp tier(id, opts \\ []) do
    %{
      id: id,
      type: Keyword.get(opts, :type, "paid"),
      max_per_buyer: Keyword.get(opts, :max_per_buyer)
    }
  end

  describe "limit/1" do
    test "returns the positive limit" do
      assert Limits.limit(tier("a", max_per_buyer: 2)) == 2
    end

    test "nil, zero and negative values mean no limit" do
      assert Limits.limit(tier("a")) == nil
      assert Limits.limit(tier("a", max_per_buyer: 0)) == nil
      assert Limits.limit(tier("a", max_per_buyer: -1)) == nil
    end

    test "donation tiers are never limited" do
      assert Limits.limit(tier("a", type: "donation", max_per_buyer: 1)) == nil
    end

    test "supports string keys and nil" do
      assert Limits.limit(%{"id" => "a", "max_per_buyer" => 3}) == 3
      assert Limits.limit(nil) == nil
    end
  end

  describe "can_add?/3 and remaining/3" do
    test "unlimited tiers can always add" do
      assert Limits.can_add?(tier("a"), %{"a" => 99})
      assert Limits.remaining(tier("a"), %{}) == :unlimited
    end

    test "counts the current selection" do
      t = tier("a", max_per_buyer: 2)

      assert Limits.can_add?(t, %{})
      assert Limits.can_add?(t, %{"a" => 1})
      refute Limits.can_add?(t, %{"a" => 2})
      assert Limits.remaining(t, %{"a" => 1}) == 1
    end

    test "counts tickets already owned" do
      t = tier("a", max_per_buyer: 1)

      refute Limits.can_add?(t, %{}, 1)
      assert Limits.remaining(t, %{}, 1) == 0
    end

    test "never goes negative" do
      assert Limits.remaining(tier("a", max_per_buyer: 1), %{"a" => 5}, 2) == 0
    end

    test "ignores selections of other tiers" do
      assert Limits.can_add?(tier("a", max_per_buyer: 1), %{"b" => 4})
    end
  end

  describe "validate_selection/3" do
    setup do
      %{tiers: [tier("guest", max_per_buyer: 1), tier("member")]}
    end

    test "ok within the limit", %{tiers: tiers} do
      assert :ok =
               Limits.validate_selection(%{"guest" => 1, "member" => 4}, tiers)
    end

    test "errors when the selection exceeds the limit", %{tiers: tiers} do
      assert {:error, :tier_purchase_limit_exceeded} =
               Limits.validate_selection(%{"guest" => 2}, tiers)
    end

    test "errors when owned plus selected exceeds the limit", %{tiers: tiers} do
      assert {:error, :tier_purchase_limit_exceeded} =
               Limits.validate_selection(%{"guest" => 1}, tiers, %{"guest" => 1})
    end

    test "accepts string quantities", %{tiers: tiers} do
      assert {:error, :tier_purchase_limit_exceeded} =
               Limits.validate_selection(%{"guest" => "2"}, tiers)
    end

    test "unselected limited tiers are fine even if already at the limit", %{
      tiers: tiers
    } do
      assert :ok =
               Limits.validate_selection(%{"member" => 1}, tiers, %{
                 "guest" => 1
               })
    end
  end

  describe "limited_tier_ids/1 and any_limited?/1" do
    test "picks out only limited tiers" do
      tiers = [tier("a", max_per_buyer: 1), tier("b")]

      assert Limits.limited_tier_ids(tiers) == ["a"]
      assert Limits.any_limited?(tiers)
      refute Limits.any_limited?([tier("b")])
    end
  end
end
