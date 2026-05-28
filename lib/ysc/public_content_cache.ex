defmodule Ysc.PublicContentCache do
  @moduledoc """
  Cache for guest-facing post and event list slices (home, news).

  Uses per-domain version-based invalidation when posts or events change.
  """

  require Ysc.Logging

  @cache_name :ysc_cache
  @posts_version_key "public_content:version:posts"
  @events_version_key "public_content:version:events"
  @pubsub_topic "public_content:invalidate"
  @default_ttl 5 * 60 * 1000

  @doc """
  Subscribes the current process to public content cache invalidation events.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Ysc.PubSub, @pubsub_topic)
  end

  @doc """
  Unsubscribes the current process from public content cache invalidation events.
  """
  def unsubscribe do
    Phoenix.PubSub.unsubscribe(Ysc.PubSub, @pubsub_topic)
  end

  @doc """
  Recent published posts (non-featured), with preloads.
  """
  def list_recent_posts(limit) when is_integer(limit) and limit > 0 do
    cache_key = "public:posts:recent:#{limit}"

    fetch_cached(:posts, cache_key, fn ->
      Ysc.Posts.list_posts(limit)
    end)
  end

  @doc """
  Featured post for the news page, or nil.
  """
  def get_featured_post do
    fetch_cached(:posts, "public:posts:featured", fn ->
      case Ysc.Posts.get_featured_post() do
        nil ->
          nil

        post ->
          Ysc.Repo.preload(post, [{:author, :current_avatar}, :featured_image])
      end
    end)
  end

  @doc """
  Upcoming events list slice for public pages.
  """
  def list_upcoming_events(limit) when is_integer(limit) and limit > 0 do
    cache_key = "public:events:upcoming:#{limit}"

    fetch_cached(:events, cache_key, fn ->
      Ysc.Events.list_upcoming_events_from_db(limit)
    end)
  end

  @doc """
  Invalidates all public content list caches.
  """
  def invalidate do
    if Ysc.ProcessCache.enabled?() do
      bump_version(:posts)
      bump_version(:events)
    end

    :ok
  end

  @doc """
  Invalidates post-related caches only.
  """
  def invalidate_posts do
    if Ysc.ProcessCache.enabled?() do
      bump_version(:posts)
    end

    :ok
  end

  @doc """
  Invalidates event-related caches only.
  """
  def invalidate_events do
    if Ysc.ProcessCache.enabled?() do
      bump_version(:events)
    end

    :ok
  end

  defp fetch_cached(domain, cache_key, fetch_fun)
       when is_function(fetch_fun, 0) do
    if Ysc.ProcessCache.enabled?() do
      do_fetch_cached(domain, cache_key, fetch_fun)
    else
      fetch_fun.()
    end
  end

  defp do_fetch_cached(domain, cache_key, fetch_fun)
       when is_function(fetch_fun, 0) do
    version_key = version_key(domain)

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        fetch_and_cache(domain, cache_key, fetch_fun)

      {:ok, {:version, version, ttl_expires_at, value}} ->
        now = System.system_time(:millisecond)

        if now < ttl_expires_at do
          validate_cached_version(
            domain,
            version_key,
            cache_key,
            version,
            value,
            fetch_fun
          )
        else
          refetch_and_cache(domain, cache_key, fetch_fun)
        end

      {:ok, value} ->
        fetch_and_cache(domain, cache_key, fn -> value end)

      {:error, _reason} ->
        fetch_fun.()
    end
  end

  defp validate_cached_version(
         domain,
         version_key,
         cache_key,
         version,
         value,
         fetch_fun
       ) do
    case Cachex.get(@cache_name, version_key) do
      {:ok, current_version} when current_version == version ->
        value

      _ ->
        refetch_and_cache(domain, cache_key, fetch_fun)
    end
  end

  defp fetch_and_cache(domain, cache_key, fetch_fun) do
    version_before = current_version(domain)
    value = fetch_fun.()

    if current_version(domain) == version_before do
      cache_with_version_and_ttl(domain, cache_key, value, version_before)
      value
    else
      refetch_and_cache(domain, cache_key, fetch_fun)
    end
  end

  defp refetch_and_cache(domain, cache_key, fetch_fun) do
    Cachex.del(@cache_name, cache_key)
    fetch_and_cache(domain, cache_key, fetch_fun)
  end

  defp cache_with_version_and_ttl(domain, key, value, version) do
    version_key = version_key(domain)

    ttl_ms =
      Application.get_env(:ysc, :public_content_cache_ttl_ms, @default_ttl)

    now = System.system_time(:millisecond)
    ttl_expires_at = now + ttl_ms

    case version do
      version when is_integer(version) ->
        Cachex.put(@cache_name, key, {:version, version, ttl_expires_at, value},
          expire: ttl_ms
        )

      _ ->
        new_version = System.unique_integer([:monotonic, :positive])
        Cachex.put(@cache_name, version_key, new_version)

        Cachex.put(
          @cache_name,
          key,
          {:version, new_version, ttl_expires_at, value},
          expire: ttl_ms
        )
    end
  end

  defp current_version(domain) do
    case Cachex.get(@cache_name, version_key(domain)) do
      {:ok, version} when is_integer(version) -> version
      _ -> nil
    end
  end

  defp bump_version(domain) do
    version_key = version_key(domain)
    new_version = System.unique_integer([:monotonic, :positive])
    Cachex.put(@cache_name, version_key, new_version)

    if Process.whereis(Ysc.PubSub) do
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        @pubsub_topic,
        {:public_content_cache_invalidated, domain, new_version}
      )
    end

    Ysc.Logging.debug("Public content cache invalidated",
      domain: domain,
      version: new_version
    )

    :ok
  end

  defp version_key(:posts), do: @posts_version_key
  defp version_key(:events), do: @events_version_key
end
