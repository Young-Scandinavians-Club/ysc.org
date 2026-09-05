defmodule Ysc.Bookings.RoomsListCache do
  @moduledoc """
  Cache for property room lists (preloaded categories and images).
  """

  alias Ysc.Bookings.ConfigCacheTelemetry
  alias Ysc.VersionedCache

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
    VersionedCache.fetch(
      @cache_version_key,
      "rooms:list:#{property}",
      fn -> Ysc.Bookings.list_rooms_from_db(property) end,
      cache_name: @cache_name
    )
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
end
