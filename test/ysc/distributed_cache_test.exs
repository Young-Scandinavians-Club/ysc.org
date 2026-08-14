defmodule Ysc.DistributedCacheTest do
  use ExUnit.Case, async: false

  alias Ysc.DistributedCache

  @cache_name :ysc_cache

  setup do
    id = System.unique_integer([:positive])
    key = "distributed_cache_test:#{id}"

    on_exit(fn -> Cachex.del(@cache_name, key) end)

    {:ok, key: key}
  end

  describe "put/4" do
    test "writes the value to the local cache", %{key: key} do
      assert {:ok, true} = DistributedCache.put(@cache_name, key, "value")
      assert {:ok, "value"} = Cachex.get(@cache_name, key)
    end

    test "broadcasts the write so other nodes can replicate it", %{key: key} do
      Phoenix.PubSub.subscribe(Ysc.PubSub, DistributedCache.topic())

      on_exit(fn ->
        Phoenix.PubSub.unsubscribe(Ysc.PubSub, DistributedCache.topic())
      end)

      DistributedCache.put(@cache_name, key, "value",
        expire: :timer.seconds(30)
      )

      this_node = node()

      assert_receive {:distributed_cache_put, ^this_node, @cache_name, ^key,
                      "value", [expire: 30_000]}
    end
  end

  describe "Sync" do
    test "applies writes broadcast from another node to the local cache", %{
      key: key
    } do
      send(
        Ysc.DistributedCache.Sync,
        {:distributed_cache_put, :other@nohost, @cache_name, key, "from remote",
         []}
      )

      # Forces this test to wait until Sync has processed the message above,
      # since GenServer handles its mailbox in order.
      :sys.get_state(Ysc.DistributedCache.Sync)

      assert {:ok, "from remote"} = Cachex.get(@cache_name, key)
    end

    test "ignores writes tagged with this node (already applied locally)", %{
      key: key
    } do
      Cachex.put(@cache_name, key, "local value")

      send(
        Ysc.DistributedCache.Sync,
        {:distributed_cache_put, node(), @cache_name, key, "should be ignored",
         []}
      )

      :sys.get_state(Ysc.DistributedCache.Sync)

      assert {:ok, "local value"} = Cachex.get(@cache_name, key)
    end
  end
end
