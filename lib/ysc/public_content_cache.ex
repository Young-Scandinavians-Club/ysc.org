defmodule Ysc.PublicContentCache do
  @moduledoc """
  Cache for guest-facing post and event list slices (home, news).

  Uses per-domain version-based invalidation when posts or events change.
  """

  require Ysc.Logging

  alias Ysc.VersionedCache

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
    VersionedCache.fetch(
      version_key(domain),
      cache_key,
      fetch_fun,
      cache_name: @cache_name,
      ttl: ttl_ms()
    )
  end

  defp ttl_ms do
    Application.get_env(:ysc, :public_content_cache_ttl_ms, @default_ttl)
  end

  defp bump_version(domain) do
    version_key = version_key(domain)
    new_version = System.unique_integer([:monotonic, :positive])
    Ysc.DistributedCache.put(@cache_name, version_key, new_version)

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
