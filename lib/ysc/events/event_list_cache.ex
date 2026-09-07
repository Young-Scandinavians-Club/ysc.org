defmodule Ysc.Events.EventListCache do
  @moduledoc """
  Cache for public event index lists (past/upcoming) and counts.
  """

  alias Ysc.VersionedCache

  @cache_name :ysc_cache
  @cache_version_key "event_list:version"
  @pubsub_topic "event_list_cache:invalidate"
  @default_ttl 3 * 60 * 1000

  @doc """
  Subscribes the current process to event list cache invalidation events.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Ysc.PubSub, @pubsub_topic)
  end

  @doc """
  Unsubscribes the current process from event list cache invalidation events.
  """
  def unsubscribe do
    Phoenix.PubSub.unsubscribe(Ysc.PubSub, @pubsub_topic)
  end

  def list_past_events(limit) when is_integer(limit) and limit > 0 do
    fetch_cached("event_list:past:#{limit}", fn ->
      Ysc.Events.list_past_events_from_db(limit)
    end)
  end

  def list_upcoming_events(limit) when is_integer(limit) and limit > 0 do
    fetch_cached("event_list:upcoming:#{limit}", fn ->
      Ysc.Events.list_upcoming_events_from_db(limit)
    end)
  end

  def count_upcoming_events do
    fetch_cached("event_list:upcoming_count", fn ->
      Ysc.Events.count_upcoming_events_from_db()
    end)
  end

  def invalidate do
    if Ysc.ProcessCache.enabled?() do
      new_version = System.unique_integer([:monotonic, :positive])
      Ysc.DistributedCache.put(@cache_name, @cache_version_key, new_version)

      if Process.whereis(Ysc.PubSub) do
        Phoenix.PubSub.broadcast(
          Ysc.PubSub,
          @pubsub_topic,
          {:event_list_cache_invalidated, new_version}
        )
      end

      Ysc.PublicContentCache.invalidate_events()
    end

    :ok
  end

  defp fetch_cached(cache_key, fetch_fun) when is_function(fetch_fun, 0) do
    VersionedCache.fetch(
      @cache_version_key,
      cache_key,
      fetch_fun,
      cache_name: @cache_name,
      ttl: ttl_ms()
    )
  end

  defp ttl_ms do
    Application.get_env(:ysc, :event_list_cache_ttl_ms, @default_ttl)
  end
end
