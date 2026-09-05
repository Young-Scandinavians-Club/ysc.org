defmodule Ysc.VersionedCacheTest do
  use ExUnit.Case, async: false

  alias Ysc.VersionedCache

  @cache_name :ysc_cache

  setup do
    id = System.unique_integer([:positive])
    version_key = "versioned_cache_test:#{id}:version"
    cache_key = "versioned_cache_test:#{id}:value"
    previous = Application.get_env(:ysc, :process_caches_enabled)

    on_exit(fn ->
      Application.put_env(:ysc, :process_caches_enabled, previous)
      Cachex.del(@cache_name, version_key)
      Cachex.del(@cache_name, cache_key)
    end)

    {:ok, version_key: version_key, cache_key: cache_key}
  end

  defp enable_process_cache do
    Application.put_env(:ysc, :process_caches_enabled, true)
  end

  defp disable_process_cache do
    Application.put_env(:ysc, :process_caches_enabled, false)
  end

  defp fetch_count(context, fun) do
    VersionedCache.fetch(context.version_key, context.cache_key, fun)
  end

  describe "fetch/3 when process caches are disabled" do
    test "always calls the loader and does not write Cachex", context do
      disable_process_cache()
      counter = :counters.new(1, [])

      result1 =
        fetch_count(context, fn ->
          :counters.add(counter, 1, 1)
          :fresh
        end)

      result2 =
        fetch_count(context, fn ->
          :counters.add(counter, 1, 1)
          :fresh
        end)

      assert result1 == :fresh
      assert result2 == :fresh
      assert :counters.get(counter, 1) == 2
      assert Cachex.get(@cache_name, context.cache_key) == {:ok, nil}
    end
  end

  describe "fetch/3 when process caches are enabled" do
    test "loads on miss, then serves the stamped value", context do
      enable_process_cache()
      counter = :counters.new(1, [])

      first =
        fetch_count(context, fn ->
          :counters.add(counter, 1, 1)
          :from_loader
        end)

      second =
        fetch_count(context, fn ->
          :counters.add(counter, 1, 1)
          :should_not_run
        end)

      assert first == :from_loader
      assert second == :from_loader
      assert :counters.get(counter, 1) == 1

      assert {:ok, {:version, version, :from_loader}} =
               Cachex.get(@cache_name, context.cache_key)

      assert is_integer(version)
      assert {:ok, ^version} = Cachex.get(@cache_name, context.version_key)
    end

    test "refetches after the version key is bumped", context do
      enable_process_cache()
      counter = :counters.new(1, [])

      fetch_count(context, fn ->
        :counters.add(counter, 1, 1)
        :original
      end)

      {:ok, {:version, old_version, :original}} =
        Cachex.get(@cache_name, context.cache_key)

      Cachex.put(@cache_name, context.version_key, old_version + 1)

      result =
        fetch_count(context, fn ->
          :counters.add(counter, 1, 1)
          :updated
        end)

      assert result == :updated
      assert :counters.get(counter, 1) == 2

      assert {:ok, {:version, new_version, :updated}} =
               Cachex.get(@cache_name, context.cache_key)

      assert new_version == old_version + 1
    end

    test "upgrades a legacy unversioned entry by refetching", context do
      enable_process_cache()
      Cachex.put(@cache_name, context.cache_key, :legacy)
      counter = :counters.new(1, [])

      result =
        fetch_count(context, fn ->
          :counters.add(counter, 1, 1)
          :upgraded
        end)

      assert result == :upgraded
      assert :counters.get(counter, 1) == 1

      assert {:ok, {:version, version, :upgraded}} =
               Cachex.get(@cache_name, context.cache_key)

      assert is_integer(version)
    end

    test "refetches when the version changes during the loader", context do
      enable_process_cache()
      counter = :counters.new(1, [])

      result =
        fetch_count(context, fn ->
          n = :counters.get(counter, 1)
          :counters.add(counter, 1, 1)

          if n == 0 do
            Cachex.put(
              @cache_name,
              context.version_key,
              System.unique_integer([:monotonic, :positive])
            )

            :stale
          else
            :stable
          end
        end)

      assert result == :stable
      assert :counters.get(counter, 1) == 2

      assert {:ok, {:version, _version, :stable}} =
               Cachex.get(@cache_name, context.cache_key)
    end
  end
end
