defmodule Ysc.Bookings.SeasonCache do
  @moduledoc """
  In-memory cache for season resolution to improve performance.

  Caches season lookups per property/day with a short TTL (5-15 minutes).

  Cache is invalidated via PubSub when seasons are created/updated/deleted.
  """

  require Ysc.Logging
  alias Ysc.Bookings.{ConfigCacheTelemetry, Season}
  alias Ysc.VersionedCache

  @cache_name :ysc_cache
  @cache_prefix "season:"
  @cache_version_key "season:version"
  @pubsub_topic "season_cache:invalidate"
  # 10 minutes in milliseconds
  @default_ttl 10 * 60 * 1000

  @doc """
  Subscribes the current process to season cache invalidation events.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Ysc.PubSub, @pubsub_topic)
  end

  @doc """
  Gets a season for a property/date from cache or fetches from database and caches it.

  Returns the season or nil if not found.
  """
  def get(property, date) when is_atom(property) do
    VersionedCache.fetch(
      @cache_version_key,
      build_cache_key(property, date),
      fn -> Season.for_date_db(property, date) end,
      cache_name: @cache_name,
      ttl: ttl_ms()
    )
  end

  @doc """
  Invalidates the season cache by bumping the version.

  This should be called when seasons are created, updated, or deleted.
  """
  def invalidate do
    # Use unique_integer so the version always increases, even when invalidate/0
    # is called multiple times within the same second (e.g. in tests). Second-
    # resolution versions were a no-op and leaked rolled-back Season structs.
    new_version = System.unique_integer([:monotonic, :positive])
    Ysc.DistributedCache.put(@cache_name, @cache_version_key, new_version)

    # Broadcast invalidation event via PubSub
    if Process.whereis(Ysc.PubSub) do
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        @pubsub_topic,
        {:season_cache_invalidated, new_version}
      )
    end

    Ysc.Logging.debug("Season cache invalidated", version: new_version)
    ConfigCacheTelemetry.invalidated(:season)
    :ok
  end

  @doc """
  Invalidates cached seasons for a specific property.

  Useful when you know only one property's seasons changed.
  """
  def invalidate_property(_property) do
    # Get all cache keys for this property
    # Note: Cachex doesn't support pattern matching, so we'll use version bump
    # which will cause all cached entries to be revalidated on next access
    invalidate()
  end

  @doc """
  Gets all seasons for a property from cache or fetches from database and caches it.

  This is useful when you need all seasons for a property (e.g., for UI display).
  """
  def get_all_for_property(property) when is_atom(property) do
    VersionedCache.fetch(
      @cache_version_key,
      "#{@cache_prefix}all:#{property}",
      fn -> Season.list_all_for_property_db(property) end,
      cache_name: @cache_name,
      ttl: ttl_ms()
    )
  end

  defp build_cache_key(property, date) do
    date_str = Date.to_iso8601(date)
    "#{@cache_prefix}#{property}:#{date_str}"
  end

  defp ttl_ms do
    Application.get_env(:ysc, :season_cache_ttl_ms, @default_ttl)
  end
end
