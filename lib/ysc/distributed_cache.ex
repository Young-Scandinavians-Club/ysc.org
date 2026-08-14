defmodule Ysc.DistributedCache do
  @moduledoc """
  Writes a value to the local `Cachex` store and replicates the write to
  every other node via PubSub.

  A general synced-write helper: anything that needs a `Cachex.put/4` to
  converge across nodes can use it. Rate limiters (`Ysc.ResendRateLimiter`,
  `Ysc.SmsRateLimit`, ...) have no database to fall back to, so a plain
  invalidate-and-refetch pattern doesn't help across nodes — each node's
  cache is the only copy of that state. Version-key invalidation caches
  (`Ysc.Events.EventPricingCache`, `Ysc.Events.EventListCache`,
  `Ysc.PublicContentCache`, `Ysc.Bookings.PricingRuleCache`,
  `Ysc.Bookings.BlackoutListCache`, `Ysc.Bookings.RoomsListCache`,
  `Ysc.Bookings.RefundPolicyCache`, `Ysc.Bookings.SeasonCache`) have the
  same problem: bumping the version locally only makes that node see the
  new data, so other nodes keep serving stale cached values until TTL
  expiry. Broadcasting the write itself keeps every node's local cache
  converged instead.

  Reads stay a plain local `Cachex.get/2` — no need to route those through
  PubSub.
  """

  @pubsub Ysc.PubSub
  @topic "distributed_cache:sync"

  @doc false
  def topic, do: @topic

  @doc """
  Writes `key` to `cache_name` locally, then broadcasts the write so every
  other node applies the same value to its own local cache.
  """
  def put(cache_name, key, value, opts \\ []) do
    result = Cachex.put(cache_name, key, value, opts)

    # Tag with the originating node so Sync can ignore its own node's writes
    # on delivery (see Ysc.DistributedCache.Sync) — same-node processes already
    # share this write via the local Cachex.put above, so re-applying it
    # asynchronously could race with (and clobber) a newer local write.
    Phoenix.PubSub.broadcast(
      @pubsub,
      @topic,
      {:distributed_cache_put, node(), cache_name, key, value, opts}
    )

    result
  end
end
