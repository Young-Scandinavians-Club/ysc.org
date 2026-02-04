defmodule Ysc.Bookings.SeasonCache do
  @moduledoc """
  In-memory cache for season resolution to improve performance.

  Caches season lookups per property/day with a short TTL (5-15 minutes).

  Cache is invalidated via PubSub when seasons are created/updated/deleted.
  """

  require Logger
  alias Ysc.Bookings.Season

  @cache_name :ysc_cache
  @cache_prefix "season:"
  @cache_version_key "season:version"
  # 10 minutes in milliseconds
  @default_ttl 10 * 60 * 1000

  @doc """
  Gets a season for a property/date from cache or fetches from database and caches it.

  Returns the season or nil if not found.
  """
  def get(property, date) when is_atom(property) do
    cache_key = build_cache_key(property, date)

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        # Cache miss - fetch from database
        season = Season.for_date_db(property, date)
        # Cache with TTL and version check
        cache_with_version_and_ttl(cache_key, season)
        season

      {:ok, {:version, version, ttl_expires_at, season}} ->
        # Check if TTL has expired
        now = System.system_time(:millisecond)

        if now < ttl_expires_at do
          validate_cached_season_version(
            cache_key,
            version,
            season,
            property,
            date
          )
        else
          # TTL expired - refetch
          refetch_and_cache_season(cache_key, property, date)
        end

      {:ok, season} ->
        # Legacy format (no version/ttl) - upgrade to versioned
        cache_with_version_and_ttl(cache_key, season)
        season

      {:error, _reason} ->
        # Cache error - fallback to database
        Season.for_date_db(property, date)
    end
  end

  @doc """
  Invalidates the season cache by bumping the version.

  This should be called when seasons are created, updated, or deleted.
  """
  def invalidate do
    # Bump version to invalidate all cached seasons
    new_version = System.system_time(:second)
    Cachex.put(@cache_name, @cache_version_key, new_version)

    # Broadcast invalidation event via PubSub
    Phoenix.PubSub.broadcast(
      Ysc.PubSub,
      "season_cache:invalidate",
      {:season_cache_invalidated, new_version}
    )

    Logger.debug("Season cache invalidated", version: new_version)
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
    cache_key = "#{@cache_prefix}all:#{property}"

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        # Cache miss - fetch from database
        seasons = Season.list_all_for_property_db(property)
        # Cache with TTL and version check
        cache_with_version_and_ttl(cache_key, seasons)
        seasons

      {:ok, {:version, version, ttl_expires_at, seasons}} ->
        # Check if TTL has expired
        now = System.system_time(:millisecond)

        if now < ttl_expires_at do
          validate_cached_seasons_version(cache_key, version, seasons, property)
        else
          # TTL expired - refetch
          refetch_and_cache_seasons(cache_key, property)
        end

      {:ok, seasons} ->
        # Legacy format (no version/ttl) - upgrade to versioned
        cache_with_version_and_ttl(cache_key, seasons)
        seasons

      {:error, _reason} ->
        # Cache error - fallback to database
        Season.list_all_for_property_db(property)
    end
  end

  # Private functions

  defp build_cache_key(property, date) do
    date_str = Date.to_iso8601(date)
    "#{@cache_prefix}#{property}:#{date_str}"
  end

  defp cache_with_version_and_ttl(key, value) do
    ttl_ms = get_ttl()
    now = System.system_time(:millisecond)
    ttl_expires_at = now + ttl_ms

    case Cachex.get(@cache_name, @cache_version_key) do
      {:ok, version} when is_integer(version) ->
        Cachex.put(@cache_name, key, {:version, version, ttl_expires_at, value},
          ttl: ttl_ms
        )

      _ ->
        # No version set yet - initialize it
        version = System.system_time(:second)
        Cachex.put(@cache_name, @cache_version_key, version)

        Cachex.put(@cache_name, key, {:version, version, ttl_expires_at, value},
          ttl: ttl_ms
        )
    end
  end

  defp get_ttl do
    # Use 10 minutes as default, but can be configured
    Application.get_env(:ysc, :season_cache_ttl_ms, @default_ttl)
  end

  defp validate_cached_season_version(
         cache_key,
         version,
         season,
         property,
         date
       ) do
    # Check if cache version is still valid
    case Cachex.get(@cache_name, @cache_version_key) do
      {:ok, current_version} when current_version == version ->
        season

      _ ->
        # Version mismatch - invalidate and refetch
        refetch_and_cache_season(cache_key, property, date)
    end
  end

  defp refetch_and_cache_season(cache_key, property, date) do
    Cachex.del(@cache_name, cache_key)
    season = Season.for_date_db(property, date)
    cache_with_version_and_ttl(cache_key, season)
    season
  end

  defp validate_cached_seasons_version(cache_key, version, seasons, property) do
    # Check if cache version is still valid
    case Cachex.get(@cache_name, @cache_version_key) do
      {:ok, current_version} when current_version == version ->
        seasons

      _ ->
        # Version mismatch - invalidate and refetch
        refetch_and_cache_seasons(cache_key, property)
    end
  end

  defp refetch_and_cache_seasons(cache_key, property) do
    Cachex.del(@cache_name, cache_key)
    seasons = Season.list_all_for_property_db(property)
    cache_with_version_and_ttl(cache_key, seasons)
    seasons
  end
end
