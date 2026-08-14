defmodule Ysc.Bookings.RoomsListCache do
  @moduledoc """
  Cache for property room lists (preloaded categories and images).
  """

  alias Ysc.Bookings.ConfigCacheTelemetry

  @cache_name :ysc_cache
  @cache_version_key "rooms_list:version"
  @pubsub_topic "rooms_list_cache:invalidate"

  @doc """
  Subscribes the current process to rooms-list cache invalidation events.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Ysc.PubSub, @pubsub_topic)
  end

  def list(property) when is_atom(property) do
    cache_key = "rooms:list:#{property}"

    fetch_cached(cache_key, fn ->
      Ysc.Bookings.list_rooms_from_db(property)
    end)
  end

  def invalidate do
    new_version = System.unique_integer([:monotonic, :positive])

    if Ysc.ProcessCache.enabled?() do
      Ysc.DistributedCache.put(@cache_name, @cache_version_key, new_version)
    end

    # Always notify LiveViews so in-memory assigns rebuild even when Cachex is off.
    if Process.whereis(Ysc.PubSub) do
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        @pubsub_topic,
        {:rooms_list_cache_invalidated, new_version}
      )
    end

    ConfigCacheTelemetry.invalidated(:rooms)
    :ok
  end

  defp fetch_cached(cache_key, fetch_fun) when is_function(fetch_fun, 0) do
    if Ysc.ProcessCache.enabled?() do
      do_fetch_cached(cache_key, fetch_fun)
    else
      fetch_fun.()
    end
  end

  defp do_fetch_cached(cache_key, fetch_fun) when is_function(fetch_fun, 0) do
    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        fetch_and_cache(cache_key, fetch_fun)

      {:ok, {:version, version, value}} ->
        case current_version() do
          ^version -> value
          _ -> refetch_and_cache(cache_key, fetch_fun)
        end

      {:ok, _value} ->
        fetch_and_cache(cache_key, fetch_fun)

      {:error, _reason} ->
        fetch_fun.()
    end
  end

  defp fetch_and_cache(cache_key, fetch_fun) do
    version_before = current_version()
    value = fetch_fun.()

    if current_version() == version_before do
      cache_with_version(cache_key, value)
      value
    else
      refetch_and_cache(cache_key, fetch_fun)
    end
  end

  defp refetch_and_cache(cache_key, fetch_fun) do
    Cachex.del(@cache_name, cache_key)
    fetch_and_cache(cache_key, fetch_fun)
  end

  defp cache_with_version(key, value) do
    case current_version() do
      version when is_integer(version) ->
        Cachex.put(@cache_name, key, {:version, version, value})

      _ ->
        version = System.unique_integer([:monotonic, :positive])
        Cachex.put(@cache_name, @cache_version_key, version)
        Cachex.put(@cache_name, key, {:version, version, value})
    end
  end

  defp current_version do
    case Cachex.get(@cache_name, @cache_version_key) do
      {:ok, version} when is_integer(version) -> version
      _ -> nil
    end
  end
end
