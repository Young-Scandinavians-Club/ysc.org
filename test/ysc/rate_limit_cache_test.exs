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

      assert_receive {:rate_limit_cache_put, from_node, :ysc_cache, ^key, true,
                      []},
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

      assert {:ok, :from_remote} = await_cache_value(key, :from_remote)
    end

    test "ignores same-node broadcasts to avoid clobbering newer local writes",
         %{
           key: key
         } do
      Phoenix.PubSub.subscribe(Ysc.PubSub, RateLimitCache.topic())

      Cachex.put(:ysc_cache, key, :current)

      this_node = node()

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        RateLimitCache.topic(),
        {:rate_limit_cache_put, this_node, :ysc_cache, key, :stale, []}
      )

      assert_receive {:rate_limit_cache_put, ^this_node, :ysc_cache, ^key,
                      :stale, []},
                     1000

      assert {:ok, :current} = Cachex.get(:ysc_cache, key)
    end
  end

  defp await_cache_value(key, expected, attempts \\ 100) do
    case Cachex.get(:ysc_cache, key) do
      {:ok, ^expected} = result ->
        result

      _ when attempts > 0 ->
        await_cache_value(key, expected, attempts - 1)

      other ->
        other
    end
  end
end
