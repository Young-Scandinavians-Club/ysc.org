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

  describe "update_counter/4" do
    test "updates the local counter and broadcasts the op" do
      table = new_counter_table()
      Phoenix.PubSub.subscribe(Ysc.PubSub, DistributedCache.topic())

      on_exit(fn ->
        Phoenix.PubSub.unsubscribe(Ysc.PubSub, DistributedCache.topic())
      end)

      assert DistributedCache.update_counter(table, :k, {2, 3}, {:k, 0}) == 3
      assert DistributedCache.update_counter(table, :k, {2, -1}, {:k, 0}) == 2
      assert :ets.lookup(table, :k) == [{:k, 2}]

      this_node = node()

      assert_receive {:distributed_counter_update, ^this_node, ^table, :k,
                      {2, 3}, {:k, 0}}

      assert_receive {:distributed_counter_update, ^this_node, ^table, :k,
                      {2, -1}, {:k, 0}}
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

    test "applies counter updates broadcast from another node" do
      table = new_counter_table()

      for _ <- 1..2 do
        send(
          Ysc.DistributedCache.Sync,
          {:distributed_counter_update, :other@nohost, table, :k, {2, 1},
           {:k, 0}}
        )
      end

      :sys.get_state(Ysc.DistributedCache.Sync)

      assert :ets.lookup(table, :k) == [{:k, 2}]
    end

    test "ignores counter updates tagged with this node" do
      table = new_counter_table()

      send(
        Ysc.DistributedCache.Sync,
        {:distributed_counter_update, node(), table, :k, {2, 1}, {:k, 0}}
      )

      :sys.get_state(Ysc.DistributedCache.Sync)

      assert :ets.lookup(table, :k) == []
    end

    test "skips counter updates for a table this node doesn't have" do
      sync = Process.whereis(Ysc.DistributedCache.Sync)

      send(
        Ysc.DistributedCache.Sync,
        {:distributed_counter_update, :other@nohost, :no_such_counter_table, :k,
         {2, 1}, {:k, 0}}
      )

      :sys.get_state(Ysc.DistributedCache.Sync)

      assert Process.whereis(Ysc.DistributedCache.Sync) == sync
    end
  end

  # Public so Sync (another process) can update it; owned by the test
  # process, so it goes away with the test.
  defp new_counter_table, do: :ets.new(:distributed_counter_test, [:public])
end
