defmodule Ysc.Bookings.RoomsListCache do
  @moduledoc """
  Cache for property room lists (preloaded categories and images).
  """

  require Ysc.Logging

  @cache_name :ysc_cache
  @cache_version_key "rooms_list:version"

  def list(property) when is_atom(property) do
    cache_key = "rooms:list:#{property}"

    fetch_cached(cache_key, fn ->
      Ysc.Bookings.list_rooms_from_db(property)
    end)
  end

  def invalidate do
    new_version = System.unique_integer([:monotonic, :positive])
    Cachex.put(@cache_name, @cache_version_key, new_version)

    if Process.whereis(Ysc.PubSub) do
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "rooms_list_cache:invalidate",
        {:rooms_list_cache_invalidated, new_version}
      )
    end

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
