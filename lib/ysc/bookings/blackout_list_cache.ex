defmodule Ysc.Bookings.BlackoutListCache do
  @moduledoc """
  Cache for blackout lists used in availability calculations.
  """

  alias Ysc.Bookings.ConfigCacheTelemetry
  alias Ysc.VersionedCache

  @cache_name :ysc_cache
  @cache_version_key "blackout_list:version"
  @pubsub_topic "blackout_list_cache:invalidate"

  @doc """
  Subscribes the current process to blackout-list cache invalidation events.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Ysc.PubSub, @pubsub_topic)
  end

  def list(property, start_date, end_date) do
    cache_key =
      "blackouts:#{property}:#{Date.to_iso8601(start_date)}:#{Date.to_iso8601(end_date)}"

    VersionedCache.fetch(
      @cache_version_key,
      cache_key,
      fn ->
        Ysc.Bookings.get_overlapping_blackouts_from_db(
          property,
          start_date,
          end_date
        )
      end,
      cache_name: @cache_name
    )
  end

  def invalidate do
    new_version = System.unique_integer([:monotonic, :positive])

    if Ysc.ProcessCache.enabled?() do
      Ysc.DistributedCache.put(@cache_name, @cache_version_key, new_version)
    end

    # Clear Lake availability maps depend on blackouts.
    Ysc.Bookings.AvailabilityCache.invalidate()

    if Process.whereis(Ysc.PubSub) do
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        @pubsub_topic,
        {:blackout_list_cache_invalidated, new_version}
      )
    end

    ConfigCacheTelemetry.invalidated(:blackout)
    :ok
  end
end
