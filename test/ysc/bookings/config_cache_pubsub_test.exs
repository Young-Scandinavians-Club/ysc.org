defmodule Ysc.Bookings.ConfigCachePubSubTest do
  @moduledoc """
  Ensures booking config caches always notify LiveViews on invalidate.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Bookings.{
    AvailabilityCache,
    BlackoutListCache,
    PricingRuleCache,
    RefundPolicyCache,
    RoomsListCache,
    SeasonCache
  }

  test "rooms list invalidate broadcasts even when process caches are disabled" do
    previous = Application.get_env(:ysc, :process_caches_enabled)
    Application.put_env(:ysc, :process_caches_enabled, false)

    on_exit(fn ->
      Application.put_env(:ysc, :process_caches_enabled, previous)
    end)

    RoomsListCache.subscribe()
    RoomsListCache.invalidate()

    assert_receive {:rooms_list_cache_invalidated, _version}, 1000
  end

  test "blackout invalidate broadcasts blackout and availability events" do
    BlackoutListCache.subscribe()
    AvailabilityCache.subscribe()
    BlackoutListCache.invalidate()

    assert_receive {:blackout_list_cache_invalidated, _version}, 1000
    assert_receive :availability_cache_invalidated, 1000
  end

  test "season, pricing, and refund caches expose subscribe/0" do
    SeasonCache.subscribe()
    PricingRuleCache.subscribe()
    RefundPolicyCache.subscribe()

    SeasonCache.invalidate()
    PricingRuleCache.invalidate()
    RefundPolicyCache.invalidate()

    assert_receive {:season_cache_invalidated, _version}, 1000
    assert_receive {:pricing_rule_cache_invalidated, _version}, 1000
    assert_receive {:refund_policy_cache_invalidated, _version}, 1000
  end
end
