defmodule Ysc.VersionedCache do
  @moduledoc """
  Shared Cachex helpers for version-stamped entries.

  Callers store a global integer under `version_key` (bumped on invalidate)
  and stamp each entry as `{:version, version, value}`. `fetch/3` returns the
  cached value when the stamp still matches, otherwise it refetches.

  When `Ysc.ProcessCache` is disabled (tests), `fetch/3` always calls the
  loader and never reads or writes Cachex.

  ## Examples

      VersionedCache.fetch("rooms_list:version", "rooms:list:tahoe", fn ->
        Bookings.list_rooms_from_db(:tahoe)
      end)
  """

  @default_cache :ysc_cache

  @doc """
  Returns a cached value or loads and stamps it with the current `version_key`.

  `opts` accepts `:cache_name` (default `:ysc_cache`).
  """
  def fetch(version_key, cache_key, fetch_fun, opts \\ [])
      when is_binary(version_key) and is_binary(cache_key) and
             is_function(fetch_fun, 0) do
    cache_name = Keyword.get(opts, :cache_name, @default_cache)

    if Ysc.ProcessCache.enabled?() do
      do_fetch(cache_name, version_key, cache_key, fetch_fun)
    else
      fetch_fun.()
    end
  end

  defp do_fetch(cache_name, version_key, cache_key, fetch_fun) do
    case Cachex.get(cache_name, cache_key) do
      {:ok, nil} ->
        fetch_and_cache(cache_name, version_key, cache_key, fetch_fun)

      {:ok, {:version, version, value}} ->
        case current_version(cache_name, version_key) do
          ^version -> value
          _ -> refetch_and_cache(cache_name, version_key, cache_key, fetch_fun)
        end

      {:ok, _value} ->
        fetch_and_cache(cache_name, version_key, cache_key, fetch_fun)

      {:error, _reason} ->
        fetch_fun.()
    end
  end

  defp fetch_and_cache(cache_name, version_key, cache_key, fetch_fun) do
    version_before = current_version(cache_name, version_key)
    value = fetch_fun.()

    if current_version(cache_name, version_key) == version_before do
      cache_with_version(cache_name, version_key, cache_key, value)
      value
    else
      refetch_and_cache(cache_name, version_key, cache_key, fetch_fun)
    end
  end

  defp refetch_and_cache(cache_name, version_key, cache_key, fetch_fun) do
    Cachex.del(cache_name, cache_key)
    fetch_and_cache(cache_name, version_key, cache_key, fetch_fun)
  end

  defp cache_with_version(cache_name, version_key, key, value) do
    case current_version(cache_name, version_key) do
      version when is_integer(version) ->
        Cachex.put(cache_name, key, {:version, version, value})

      _ ->
        version = System.unique_integer([:monotonic, :positive])
        Cachex.put(cache_name, version_key, version)
        Cachex.put(cache_name, key, {:version, version, value})
    end
  end

  defp current_version(cache_name, version_key) do
    case Cachex.get(cache_name, version_key) do
      {:ok, version} when is_integer(version) -> version
      _ -> nil
    end
  end
end
