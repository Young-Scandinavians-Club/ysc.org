defmodule Ysc.VersionedCache do
  @moduledoc """
  Shared Cachex helpers for version-stamped entries.

  Callers store a global integer under `version_key` (bumped on invalidate)
  and stamp each entry as `{:version, version, value}`. `fetch/3` returns the
  cached value when the stamp still matches, otherwise it refetches.

  Pass `:ttl` (milliseconds) to expire entries via Cachex. `fetch/3` also
  accepts the legacy 4-tuple stamp
  `{:version, version, ttl_expires_at, value}` used by SeasonCache,
  EventListCache, and PublicContentCache before this helper grew TTL support.

  When `Ysc.ProcessCache` is disabled (tests), `fetch/3` always calls the
  loader and never reads or writes Cachex.

  ## Examples

      VersionedCache.fetch("rooms_list:version", "rooms:list:tahoe", fn ->
        Bookings.list_rooms_from_db(:tahoe)
      end)

      VersionedCache.fetch(
        "season:version",
        "season:tahoe:2024-12-15",
        fn -> Season.for_date_db(:tahoe, ~D[2024-12-15]) end,
        ttl: :timer.minutes(10)
      )
  """

  @default_cache :ysc_cache

  @doc """
  Returns a cached value or loads and stamps it with the current `version_key`.

  `opts` accepts:

  - `:cache_name` (default `:ysc_cache`)
  - `:ttl` — positive milliseconds; when set, Cachex expires the entry
  """
  def fetch(version_key, cache_key, fetch_fun, opts \\ [])
      when is_binary(version_key) and is_binary(cache_key) and
             is_function(fetch_fun, 0) do
    cache_name = Keyword.get(opts, :cache_name, @default_cache)
    ttl = Keyword.get(opts, :ttl)

    if Ysc.ProcessCache.enabled?() do
      do_fetch(cache_name, version_key, cache_key, fetch_fun, ttl)
    else
      fetch_fun.()
    end
  end

  defp do_fetch(cache_name, version_key, cache_key, fetch_fun, ttl) do
    case Cachex.get(cache_name, cache_key) do
      {:ok, nil} ->
        fetch_and_cache(cache_name, version_key, cache_key, fetch_fun, ttl)

      {:ok, {:version, version, value}} ->
        serve_or_refetch(
          cache_name,
          version_key,
          cache_key,
          fetch_fun,
          ttl,
          version,
          value
        )

      {:ok, {:version, version, ttl_expires_at, value}}
      when is_integer(ttl_expires_at) ->
        serve_legacy_ttl_entry(
          cache_name,
          version_key,
          cache_key,
          fetch_fun,
          ttl,
          version,
          ttl_expires_at,
          value
        )

      {:ok, _value} ->
        fetch_and_cache(cache_name, version_key, cache_key, fetch_fun, ttl)

      {:error, _reason} ->
        fetch_fun.()
    end
  end

  defp serve_legacy_ttl_entry(
         cache_name,
         version_key,
         cache_key,
         fetch_fun,
         ttl,
         version,
         ttl_expires_at,
         value
       ) do
    now = System.system_time(:millisecond)

    if now < ttl_expires_at do
      serve_or_refetch(
        cache_name,
        version_key,
        cache_key,
        fetch_fun,
        ttl,
        version,
        value
      )
    else
      refetch_and_cache(cache_name, version_key, cache_key, fetch_fun, ttl)
    end
  end

  defp serve_or_refetch(
         cache_name,
         version_key,
         cache_key,
         fetch_fun,
         ttl,
         version,
         value
       ) do
    case current_version(cache_name, version_key) do
      ^version -> value
      _ -> refetch_and_cache(cache_name, version_key, cache_key, fetch_fun, ttl)
    end
  end

  defp fetch_and_cache(cache_name, version_key, cache_key, fetch_fun, ttl) do
    version_before = current_version(cache_name, version_key)
    value = fetch_fun.()

    if current_version(cache_name, version_key) == version_before do
      cache_with_version(cache_name, version_key, cache_key, value, ttl)
      value
    else
      refetch_and_cache(cache_name, version_key, cache_key, fetch_fun, ttl)
    end
  end

  defp refetch_and_cache(cache_name, version_key, cache_key, fetch_fun, ttl) do
    Cachex.del(cache_name, cache_key)
    fetch_and_cache(cache_name, version_key, cache_key, fetch_fun, ttl)
  end

  defp cache_with_version(cache_name, version_key, key, value, ttl) do
    put_opts = expire_opts(ttl)

    case current_version(cache_name, version_key) do
      version when is_integer(version) ->
        Cachex.put(cache_name, key, {:version, version, value}, put_opts)

      _ ->
        version = System.unique_integer([:monotonic, :positive])
        Cachex.put(cache_name, version_key, version)
        Cachex.put(cache_name, key, {:version, version, value}, put_opts)
    end
  end

  defp expire_opts(ttl) when is_integer(ttl) and ttl > 0, do: [expire: ttl]
  defp expire_opts(_), do: []

  defp current_version(cache_name, version_key) do
    case Cachex.get(cache_name, version_key) do
      {:ok, version} when is_integer(version) -> version
      _ -> nil
    end
  end
end
