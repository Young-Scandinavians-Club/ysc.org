defmodule Ysc.Bookings.BlackoutListCache do
  @moduledoc """
  Cache for blackout lists used in availability calculations.
  """

  @cache_name :ysc_cache
  @cache_version_key "blackout_list:version"

  def list(property, start_date, end_date) do
    cache_key =
      "blackouts:#{property}:#{Date.to_iso8601(start_date)}:#{Date.to_iso8601(end_date)}"

    fetch_cached(cache_key, fn ->
      Ysc.Bookings.get_overlapping_blackouts_from_db(
        property,
        start_date,
        end_date
      )
    end)
  end

  def invalidate do
    new_version = System.unique_integer([:monotonic, :positive])
    Cachex.put(@cache_name, @cache_version_key, new_version)
    Ysc.Bookings.AvailabilityCache.invalidate()
    :ok
  end

  defp fetch_cached(cache_key, fetch_fun) when is_function(fetch_fun, 0) do
    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        value = fetch_fun.()
        cache_with_version(cache_key, value)
        value

      {:ok, {:version, version, value}} ->
        case Cachex.get(@cache_name, @cache_version_key) do
          {:ok, current_version} when current_version == version ->
            value

          _ ->
            refetch_and_cache(cache_key, fetch_fun)
        end

      {:ok, value} ->
        cache_with_version(cache_key, value)
        value

      {:error, _reason} ->
        fetch_fun.()
    end
  end

  defp refetch_and_cache(cache_key, fetch_fun) do
    Cachex.del(@cache_name, cache_key)
    value = fetch_fun.()
    cache_with_version(cache_key, value)
    value
  end

  defp cache_with_version(key, value) do
    case Cachex.get(@cache_name, @cache_version_key) do
      {:ok, version} when is_integer(version) ->
        Cachex.put(@cache_name, key, {:version, version, value})

      _ ->
        version = System.unique_integer([:monotonic, :positive])
        Cachex.put(@cache_name, @cache_version_key, version)
        Cachex.put(@cache_name, key, {:version, version, value})
    end
  end
end
