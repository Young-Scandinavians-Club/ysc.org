defmodule Ysc.RateLimitCache.Sync do
  @moduledoc """
  Subscribes to `Ysc.RateLimitCache` writes broadcast by other nodes and
  applies them to this node's local `Cachex` store, keeping rate-limit
  state converged across the cluster.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Ysc.PubSub, Ysc.RateLimitCache.topic())
    {:ok, nil}
  end

  @impl true
  def handle_info(
        {:rate_limit_cache_put, from_node, cache_name, key, value, opts},
        state
      ) do
    # Same-node writers already updated this node's Cachex table directly;
    # only apply writes that came from another node.
    if from_node != node() do
      Cachex.put(cache_name, key, value, opts)
    end

    {:noreply, state}
  end
end
