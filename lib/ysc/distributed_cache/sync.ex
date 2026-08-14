defmodule Ysc.DistributedCache.Sync do
  @moduledoc """
  Subscribes to `Ysc.DistributedCache` writes broadcast by other nodes and
  applies them to this node's local `Cachex` store, keeping cache state
  converged across the cluster.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Ysc.PubSub, Ysc.DistributedCache.topic())
    {:ok, nil}
  end

  @impl true
  def handle_info(
        {:distributed_cache_put, from_node, cache_name, key, value, opts},
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
