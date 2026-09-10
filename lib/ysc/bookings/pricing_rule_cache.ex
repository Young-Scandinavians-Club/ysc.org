defmodule Ysc.Bookings.PricingRuleCache do
  @moduledoc """
  In-memory cache for pricing rules to improve performance.

  Caches pricing rules keyed by:
  {room_id | nil, room_category_id | nil, property, season_id, booking_mode, price_unit}

  Cache is invalidated via PubSub when pricing rules are created/updated/deleted.
  """

  require Ysc.Logging
  alias Ysc.Bookings.{ConfigCacheTelemetry, PricingRule}
  alias Ysc.VersionedCache

  @cache_name :ysc_cache
  @cache_prefix "pricing_rule:"
  @cache_version_key "pricing_rule:version"
  @pubsub_topic "pricing_rule_cache:invalidate"

  @doc """
  Subscribes the current process to pricing-rule cache invalidation events.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Ysc.PubSub, @pubsub_topic)
  end

  @doc """
  Gets a pricing rule from cache or fetches from database and caches it.

  Returns the pricing rule or nil if not found.
  """
  def get(
        property,
        season_id,
        room_id,
        room_category_id,
        booking_mode,
        price_unit
      ) do
    VersionedCache.fetch(
      @cache_version_key,
      build_cache_key(
        property,
        season_id,
        room_id,
        room_category_id,
        booking_mode,
        price_unit
      ),
      fn ->
        PricingRule.find_most_specific_db(
          property,
          season_id,
          room_id,
          room_category_id,
          booking_mode,
          price_unit
        )
      end,
      cache_name: @cache_name
    )
  end

  @doc """
  Gets a children pricing rule from cache or fetches from database and caches it.

  Returns the pricing rule or nil if not found.
  """
  def get_children(
        property,
        season_id,
        room_id,
        room_category_id,
        booking_mode,
        price_unit
      ) do
    VersionedCache.fetch(
      @cache_version_key,
      build_cache_key(
        property,
        season_id,
        room_id,
        room_category_id,
        booking_mode,
        price_unit,
        "children"
      ),
      fn ->
        PricingRule.find_children_pricing_rule_db(
          property,
          season_id,
          room_id,
          room_category_id,
          booking_mode,
          price_unit
        )
      end,
      cache_name: @cache_name
    )
  end

  @doc """
  Invalidates the pricing rule cache by bumping the version.

  This should be called when pricing rules are created, updated, or deleted.
  """
  def invalidate do
    # Monotonic version so two invalidations in the same wall-clock second still
    # bump the global version (unix seconds alone matched embedded entry versions
    # and served stale rules after DB deletes — see pricing_calculation_test setup).
    new_version = System.unique_integer([:monotonic, :positive])
    Ysc.DistributedCache.put(@cache_name, @cache_version_key, new_version)

    # Broadcast invalidation event via PubSub
    if Process.whereis(Ysc.PubSub) do
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        @pubsub_topic,
        {:pricing_rule_cache_invalidated, new_version}
      )
    end

    Ysc.Logging.debug("Pricing rule cache invalidated", version: new_version)
    ConfigCacheTelemetry.invalidated(:pricing_rule)
    :ok
  end

  defp build_cache_key(
         property,
         season_id,
         room_id,
         room_category_id,
         booking_mode,
         price_unit,
         suffix \\ nil
       ) do
    key_parts = [
      @cache_prefix,
      "room_id:",
      to_string(room_id || "nil"),
      ":room_category_id:",
      to_string(room_category_id || "nil"),
      ":property:",
      to_string(property),
      ":season_id:",
      to_string(season_id || "nil"),
      ":booking_mode:",
      to_string(booking_mode),
      ":price_unit:",
      to_string(price_unit)
    ]

    key_parts = if suffix, do: key_parts ++ [":", suffix], else: key_parts
    Enum.join(key_parts)
  end

  @doc false
  def ci_query_explain_query do
    PricingRule.ci_query_explain_query()
  end
end
