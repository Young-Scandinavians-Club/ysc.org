defmodule Ysc.RateLimitCache do
  @moduledoc """
  Writes rate-limit state to the local `Cachex` store and replicates the
  write to every other node via PubSub.

  Rate limiters (`Ysc.ResendRateLimiter`, `Ysc.SmsRateLimit`, ...) have no
  database to fall back to, so a plain invalidate-and-refetch pattern
  doesn't help across nodes — each node's cache is the only copy of that
  state. Without replication, a multi-node deployment effectively
  multiplies every limit by the number of nodes, since each node only sees
  the requests it personally handled. Broadcasting the write itself keeps
  every node's local cache converged instead.

  Reads stay a plain local `Cachex.get/2` — no need to route those through
  PubSub.
  """

  @pubsub Ysc.PubSub
  @topic "rate_limit_cache:sync"

  @doc false
  def topic, do: @topic

  @doc """
  Writes `key` to `cache_name` locally, then broadcasts the write so every
  other node applies the same value to its own local cache.
  """
  def put(cache_name, key, value, opts \\ []) do
    result = Cachex.put(cache_name, key, value, opts)

    # Tag with the originating node so Sync can ignore its own node's writes
    # on delivery (see Ysc.RateLimitCache.Sync) — same-node processes already
    # share this write via the local Cachex.put above, so re-applying it
    # asynchronously could race with (and clobber) a newer local write.
    Phoenix.PubSub.broadcast(
      @pubsub,
      @topic,
      {:rate_limit_cache_put, node(), cache_name, key, value, opts}
    )

    result
  end
end
