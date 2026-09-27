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

  Counters are different: replicating a whole value loses counts when two
  nodes write at the same time (both go from 1 to 2 and send "2"). So
  `update_counter/4` broadcasts the delta instead, and each node applies it
  to its own copy of the counter with `:ets.update_counter/4`. Deltas add up
  in any order, so every node converges on the cluster-wide total. Used by
  `Ysc.RegistrationRateLimit`.
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

  @doc """
  Applies `op` to the counter at `key` in the public ETS `table` locally
  (inserting `default` if the key is missing, as `:ets.update_counter/4`
  does), then broadcasts it so every other node applies the same op to its
  own copy of the table. Returns the local result.

  Use plain increments and decrements (or ones clamped at a floor), which
  add up to the same total whatever order nodes receive them in.
  """
  def update_counter(table, key, op, default) do
    result = :ets.update_counter(table, key, op, default)
    broadcast_counter_update(table, key, op, default)
    result
  end

  @doc """
  Broadcasts a counter update that was already applied locally, so every
  other node applies it too. For callers that update locally first and only
  replicate the update once they decide to keep it.
  """
  def broadcast_counter_update(table, key, op, default) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      @topic,
      {:distributed_counter_update, node(), table, key, op, default}
    )
  end
end
