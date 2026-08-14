defmodule Ysc.RateLimitCacheTest do
  use ExUnit.Case, async: false

  alias Ysc.RateLimitCache

  setup do
    key = "rate_limit_cache_test:#{System.unique_integer([:positive])}"

    Cachex.del(:ysc_cache, key)

    on_exit(fn ->
      Cachex.del(:ysc_cache, key)
    end)

    {:ok, key: key}
  end

  describe "put/4" do
    test "stores value in local cache", %{key: key} do
      assert {:ok, true} =
               RateLimitCache.put(:ysc_cache, key, :limited, expire: 1000)

      assert {:ok, :limited} = Cachex.get(:ysc_cache, key)
    end

    test "broadcasts write to PubSub topic", %{key: key} do
      Phoenix.PubSub.subscribe(Ysc.PubSub, RateLimitCache.topic())

      RateLimitCache.put(:ysc_cache, key, true, [])

      assert_receive {:rate_limit_cache_put, from_node, :ysc_cache, ^key, true, []},
                     1000

      assert from_node == node()
    end
  end

  describe "Sync GenServer" do
    test "applies writes broadcast from other nodes", %{key: key} do
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        RateLimitCache.topic(),
        {:rate_limit_cache_put, :other_node, :ysc_cache, key, :from_remote, []}
      )

      assert {:ok, :from_remote} = wait_for_cache(key)
    end

    test "ignores same-node broadcasts to avoid clobbering newer local writes", %{
      key: key
    } do
      Cachex.put(:ysc_cache, key, :current)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        RateLimitCache.topic(),
        {:rate_limit_cache_put, node(), :ysc_cache, key, :stale, []}
      )

      Process.sleep(50)

      assert {:ok, :current} = Cachex.get(:ysc_cache, key)
    end
  end

  defp wait_for_cache(key, attempts \\ 10) do
    case Cachex.get(:ysc_cache, key) do
      {:ok, nil} when attempts > 0 ->
        Process.sleep(10)
        wait_for_cache(key, attempts - 1)

      result ->
        result
    end
  end
end
