defmodule Ysc.Bookings.PricingRuleCache do
  @moduledoc """
  In-memory cache for pricing rules to improve performance.

  Caches pricing rules keyed by:
  {room_id | nil, room_category_id | nil, property, season_id, booking_mode, price_unit}

  Cache is invalidated via PubSub when pricing rules are created/updated/deleted.
  """

  require Logger
  alias Ysc.Bookings.PricingRule

  @cache_name :ysc_cache
  @cache_prefix "pricing_rule:"
  @cache_version_key "pricing_rule:version"

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
    cache_key =
      build_cache_key(
        property,
        season_id,
        room_id,
        room_category_id,
        booking_mode,
        price_unit
      )

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        # Cache miss - fetch from database
        rule =
          PricingRule.find_most_specific_db(
            property,
            season_id,
            room_id,
            room_category_id,
            booking_mode,
            price_unit
          )

        # Cache the result (even if nil) with version check
        cache_with_version(cache_key, rule)
        rule

      {:ok, {:version, version, rule}} ->
        # Check if cache version is still valid
        case Cachex.get(@cache_name, @cache_version_key) do
          {:ok, current_version} when current_version == version ->
            rule

          _ ->
            # Version mismatch - invalidate and refetch
            Cachex.del(@cache_name, cache_key)

            rule =
              PricingRule.find_most_specific_db(
                property,
                season_id,
                room_id,
                room_category_id,
                booking_mode,
                price_unit
              )

            cache_with_version(cache_key, rule)
            rule
        end

      {:ok, rule} ->
        # Legacy format (no version) - upgrade to versioned
        cache_with_version(cache_key, rule)
        rule

      {:error, _reason} ->
        # Cache error - fallback to database
        PricingRule.find_most_specific_db(
          property,
          season_id,
          room_id,
          room_category_id,
          booking_mode,
          price_unit
        )
    end
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
    cache_key =
      build_cache_key(
        property,
        season_id,
        room_id,
        room_category_id,
        booking_mode,
        price_unit,
        "children"
      )

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        # Cache miss - fetch from database
        rule =
          PricingRule.find_children_pricing_rule_db(
            property,
            season_id,
            room_id,
            room_category_id,
            booking_mode,
            price_unit
          )

        # Cache the result (even if nil) with version check
        cache_with_version(cache_key, rule)
        rule

      {:ok, {:version, version, rule}} ->
        # Check if cache version is still valid
        case Cachex.get(@cache_name, @cache_version_key) do
          {:ok, current_version} when current_version == version ->
            rule

          _ ->
            # Version mismatch - invalidate and refetch
            Cachex.del(@cache_name, cache_key)

            rule =
              PricingRule.find_children_pricing_rule_db(
                property,
                season_id,
                room_id,
                room_category_id,
                booking_mode,
                price_unit
              )

            cache_with_version(cache_key, rule)
            rule
        end

      {:ok, rule} ->
        # Legacy format (no version) - upgrade to versioned
        cache_with_version(cache_key, rule)
        rule

      {:error, _reason} ->
        # Cache error - fallback to database
        PricingRule.find_children_pricing_rule_db(
          property,
          season_id,
          room_id,
          room_category_id,
          booking_mode,
          price_unit
        )
    end
  end

  @doc """
  Invalidates the pricing rule cache by bumping the version.

  This should be called when pricing rules are created, updated, or deleted.
  """
  def invalidate do
    # Bump version to invalidate all cached rules
    new_version = System.system_time(:second)
    Cachex.put(@cache_name, @cache_version_key, new_version)

    # Broadcast invalidation event via PubSub
    Phoenix.PubSub.broadcast(
      Ysc.PubSub,
      "pricing_rule_cache:invalidate",
      {:pricing_rule_cache_invalidated, new_version}
    )

    Logger.debug("Pricing rule cache invalidated", version: new_version)
    :ok
  end

  # Private functions

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

  defp cache_with_version(key, value) do
    case Cachex.get(@cache_name, @cache_version_key) do
      {:ok, version} when is_integer(version) ->
        Cachex.put(@cache_name, key, {:version, version, value})

      _ ->
        # No version set yet - initialize it
        version = System.system_time(:second)
        Cachex.put(@cache_name, @cache_version_key, version)
        Cachex.put(@cache_name, key, {:version, version, value})
    end
  end
end
