defmodule Ysc.Events.EventListCache do
  @moduledoc """
  Cache for public event index lists (past/upcoming) and counts.
  """

  require Ysc.Logging

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
    cache_key = "event_list:past:#{limit}"

    fetch_cached(cache_key, fn ->
      Ysc.Events.list_past_events_from_db(limit)
    end)
  end

  def list_upcoming_events(limit) when is_integer(limit) and limit > 0 do
    cache_key = "event_list:upcoming:#{limit}"

    fetch_cached(cache_key, fn ->
      Ysc.Events.list_upcoming_events_from_db(limit)
    end)
  end

  def count_upcoming_events do
    fetch_cached("event_list:upcoming_count", fn ->
      Ysc.Events.count_upcoming_events_from_db()
    end)
  end

  def invalidate do
    new_version = System.unique_integer([:monotonic, :positive])
    Cachex.put(@cache_name, @cache_version_key, new_version)

    if Process.whereis(Ysc.PubSub) do
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        @pubsub_topic,
        {:event_list_cache_invalidated, new_version}
      )
    end

    Ysc.PublicContentCache.invalidate_events()
    :ok
  end

  defp fetch_cached(cache_key, fetch_fun) when is_function(fetch_fun, 0) do
    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        value = fetch_fun.()
        cache_with_version_and_ttl(cache_key, value)
        value

      {:ok, {:version, version, ttl_expires_at, value}} ->
        now = System.system_time(:millisecond)

        if now < ttl_expires_at do
          validate_cached_version(cache_key, version, value, fetch_fun)
        else
          refetch_and_cache(cache_key, fetch_fun)
        end

      {:ok, value} ->
        cache_with_version_and_ttl(cache_key, value)
        value

      {:error, _reason} ->
        fetch_fun.()
    end
  end

  defp validate_cached_version(cache_key, version, value, fetch_fun) do
    case Cachex.get(@cache_name, @cache_version_key) do
      {:ok, current_version} when current_version == version ->
        value

      _ ->
        refetch_and_cache(cache_key, fetch_fun)
    end
  end

  defp refetch_and_cache(cache_key, fetch_fun) do
    Cachex.del(@cache_name, cache_key)
    value = fetch_fun.()
    cache_with_version_and_ttl(cache_key, value)
    value
  end

  defp cache_with_version_and_ttl(key, value) do
    ttl_ms = Application.get_env(:ysc, :event_list_cache_ttl_ms, @default_ttl)
    now = System.system_time(:millisecond)
    ttl_expires_at = now + ttl_ms

    case Cachex.get(@cache_name, @cache_version_key) do
      {:ok, version} when is_integer(version) ->
        Cachex.put(@cache_name, key, {:version, version, ttl_expires_at, value},
          expire: ttl_ms
        )

      _ ->
        version = System.unique_integer([:monotonic, :positive])
        Cachex.put(@cache_name, @cache_version_key, version)

        Cachex.put(@cache_name, key, {:version, version, ttl_expires_at, value},
          expire: ttl_ms
        )
    end
  end
end
