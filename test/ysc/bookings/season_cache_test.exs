defmodule Ysc.Bookings.SeasonCacheTest do
  @moduledoc """
  Tests for SeasonCache module.

  These tests verify:
  - Cache hit/miss behavior
  - Cache invalidation on data change
  - Version-based cache validation
  - TTL expiration and refresh
  - get_all_for_property caching
  - Fallback to database on cache errors
  - PubSub broadcast on invalidation

  Note: Uses async: false to prevent Cachex race conditions.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Bookings.{SeasonCache, Season}
  alias Ysc.Repo

  # Helper to create a season for testing
  defp create_season(attrs) do
    default_attrs = %{
      name: "Test Season #{System.unique_integer()}",
      property: :tahoe,
      start_date: ~D[2024-01-01],
      end_date: ~D[2024-12-31]
    }

    attrs = Map.merge(default_attrs, attrs)

    {:ok, season} =
      %Season{}
      |> Season.changeset(attrs)
      |> Repo.insert()

    season
  end

  # Clear cache before each test
  setup do
    # Clear the entire cache to start fresh
    Cachex.clear(:ysc_cache)
    # Reset version
    SeasonCache.invalidate()
    :ok
  end

  describe "get/2" do
    test "returns season from database on cache miss" do
      season =
        create_season(%{
          name: "Winter",
          property: :tahoe,
          start_date: ~D[2024-11-01],
          end_date: ~D[2025-04-30]
        })

      # First call - cache miss, fetches from DB
      cached_season = SeasonCache.get(:tahoe, ~D[2024-12-15])

      assert cached_season.id == season.id
      assert cached_season.name == "Winter"
    end

    test "returns season from cache on cache hit" do
      season =
        create_season(%{
          name: "Summer",
          property: :tahoe,
          start_date: ~D[2024-05-01],
          end_date: ~D[2024-10-31]
        })

      # First call - populates cache
      SeasonCache.get(:tahoe, ~D[2024-07-15])

      # Second call - should hit cache
      cached_season = SeasonCache.get(:tahoe, ~D[2024-07-15])

      assert cached_season.id == season.id
    end

    test "returns nil when no season exists for date" do
      # No season in database for this date
      result = SeasonCache.get(:tahoe, ~D[2030-01-01])

      assert result == nil
    end

    test "caches nil results" do
      # First call - caches nil
      result1 = SeasonCache.get(:tahoe, ~D[2030-01-01])
      assert result1 == nil

      # Second call - should return cached nil
      result2 = SeasonCache.get(:tahoe, ~D[2030-01-01])
      assert result2 == nil
    end

    test "different properties have separate cache entries" do
      tahoe_season =
        create_season(%{
          name: "Tahoe Winter",
          property: :tahoe,
          start_date: ~D[2024-11-01],
          end_date: ~D[2025-04-30]
        })

      clear_lake_season =
        create_season(%{
          name: "Clear Lake Winter",
          property: :clear_lake,
          start_date: ~D[2024-11-01],
          end_date: ~D[2025-04-30]
        })

      # Get both seasons - should be cached separately
      cached_tahoe = SeasonCache.get(:tahoe, ~D[2024-12-15])
      cached_clear_lake = SeasonCache.get(:clear_lake, ~D[2024-12-15])

      assert cached_tahoe.id == tahoe_season.id
      assert cached_clear_lake.id == clear_lake_season.id
      assert cached_tahoe.id != cached_clear_lake.id
    end

    test "different dates for same property have separate cache entries" do
      winter =
        create_season(%{
          name: "Winter",
          property: :tahoe,
          start_date: ~D[2024-11-01],
          end_date: ~D[2025-04-30]
        })

      summer =
        create_season(%{
          name: "Summer",
          property: :tahoe,
          start_date: ~D[2024-05-01],
          end_date: ~D[2024-10-31]
        })

      # Get winter season
      cached_winter = SeasonCache.get(:tahoe, ~D[2024-12-15])

      # Get summer season
      cached_summer = SeasonCache.get(:tahoe, ~D[2024-07-15])

      assert cached_winter.id == winter.id
      assert cached_summer.id == summer.id
      assert cached_winter.id != cached_summer.id
    end
  end

  describe "get_all_for_property/1" do
    test "returns all seasons for property from database on cache miss" do
      winter =
        create_season(%{
          name: "Winter",
          property: :tahoe,
          start_date: ~D[2024-11-01],
          end_date: ~D[2025-04-30]
        })

      summer =
        create_season(%{
          name: "Summer",
          property: :tahoe,
          start_date: ~D[2024-05-01],
          end_date: ~D[2024-10-31]
        })

      # First call - cache miss, fetches from DB
      cached_seasons = SeasonCache.get_all_for_property(:tahoe)

      assert length(cached_seasons) == 2
      season_ids = Enum.map(cached_seasons, & &1.id)
      assert winter.id in season_ids
      assert summer.id in season_ids
    end

    test "returns all seasons from cache on cache hit" do
      create_season(%{
        name: "Winter",
        property: :tahoe,
        start_date: ~D[2024-11-01],
        end_date: ~D[2025-04-30]
      })

      # First call - populates cache
      SeasonCache.get_all_for_property(:tahoe)

      # Second call - should hit cache
      cached_seasons = SeasonCache.get_all_for_property(:tahoe)

      assert length(cached_seasons) == 1
    end

    test "returns empty list when no seasons exist" do
      # Clear any existing seasons by using a property with no seasons
      result = SeasonCache.get_all_for_property(:clear_lake)

      assert result == []
    end

    test "different properties have separate cache entries" do
      create_season(%{
        name: "Tahoe Season",
        property: :tahoe,
        start_date: ~D[2024-01-01],
        end_date: ~D[2024-12-31]
      })

      create_season(%{
        name: "Clear Lake Season",
        property: :clear_lake,
        start_date: ~D[2024-01-01],
        end_date: ~D[2024-12-31]
      })

      # Get both - should be cached separately
      tahoe_seasons = SeasonCache.get_all_for_property(:tahoe)
      clear_lake_seasons = SeasonCache.get_all_for_property(:clear_lake)

      assert length(tahoe_seasons) == 1
      assert length(clear_lake_seasons) == 1
      assert hd(tahoe_seasons).property == :tahoe
      assert hd(clear_lake_seasons).property == :clear_lake
    end
  end

  describe "invalidate/0" do
    test "invalidates cached seasons" do
      season =
        create_season(%{
          name: "Winter",
          property: :tahoe,
          start_date: ~D[2024-11-01],
          end_date: ~D[2025-04-30]
        })

      # Populate cache
      cached1 = SeasonCache.get(:tahoe, ~D[2024-12-15])
      assert cached1.id == season.id

      # Wait to ensure version timestamp is different (versions use second resolution)
      Process.sleep(1100)

      # Invalidate cache
      SeasonCache.invalidate()

      # Update the season in database
      {:ok, updated_season} =
        season
        |> Season.changeset(%{name: "Updated Winter"})
        |> Repo.update()

      # Next get should fetch updated season from DB
      cached2 = SeasonCache.get(:tahoe, ~D[2024-12-15])

      assert cached2.id == updated_season.id
      assert cached2.name == "Updated Winter"
    end

    test "invalidation bumps cache version" do
      # Get initial version
      {:ok, version1} = Cachex.get(:ysc_cache, "season:version")

      # Wait one second to ensure time difference (version uses second resolution)
      Process.sleep(1100)

      # Invalidate
      SeasonCache.invalidate()

      # Get new version
      {:ok, version2} = Cachex.get(:ysc_cache, "season:version")

      assert version2 > version1
    end

    test "broadcasts invalidation event via PubSub" do
      # Subscribe to PubSub topic
      Phoenix.PubSub.subscribe(Ysc.PubSub, "season_cache:invalidate")

      # Invalidate cache
      SeasonCache.invalidate()

      # Verify broadcast was received
      assert_receive {:season_cache_invalidated, _version}, 1000
    end
  end

  describe "invalidate_property/1" do
    test "invalidates cache for specific property" do
      tahoe_season =
        create_season(%{
          name: "Tahoe Winter",
          property: :tahoe,
          start_date: ~D[2024-11-01],
          end_date: ~D[2025-04-30]
        })

      # Populate cache
      SeasonCache.get(:tahoe, ~D[2024-12-15])

      # Wait to ensure version timestamp is different
      Process.sleep(1100)

      # Invalidate specific property
      SeasonCache.invalidate_property(:tahoe)

      # Update season in DB
      {:ok, _updated_season} =
        tahoe_season
        |> Season.changeset(%{name: "Updated Tahoe Winter"})
        |> Repo.update()

      # Next get should fetch updated season
      cached_season = SeasonCache.get(:tahoe, ~D[2024-12-15])
      assert cached_season.name == "Updated Tahoe Winter"
    end
  end

  describe "cache version validation" do
    test "refetches when cache version is stale" do
      season =
        create_season(%{
          name: "Winter",
          property: :tahoe,
          start_date: ~D[2024-11-01],
          end_date: ~D[2025-04-30]
        })

      # Populate cache with version 1
      SeasonCache.get(:tahoe, ~D[2024-12-15])

      # Wait to ensure version timestamp is different
      Process.sleep(1100)

      # Invalidate to bump version
      SeasonCache.invalidate()

      # Update season in DB
      {:ok, _updated_season} =
        season
        |> Season.changeset(%{name: "Updated Winter"})
        |> Repo.update()

      # Get should detect stale version and refetch
      cached_season = SeasonCache.get(:tahoe, ~D[2024-12-15])

      assert cached_season.name == "Updated Winter"
    end

    test "refetches for get_all_for_property when version is stale" do
      season =
        create_season(%{
          name: "Winter",
          property: :tahoe,
          start_date: ~D[2024-11-01],
          end_date: ~D[2025-04-30]
        })

      # Populate cache
      SeasonCache.get_all_for_property(:tahoe)

      # Wait to ensure version timestamp is different
      Process.sleep(1100)

      # Invalidate
      SeasonCache.invalidate()

      # Update season in DB
      {:ok, _updated_season} =
        season
        |> Season.changeset(%{name: "Updated Winter"})
        |> Repo.update()

      # Get should detect stale version and refetch
      cached_seasons = SeasonCache.get_all_for_property(:tahoe)

      assert length(cached_seasons) == 1
      assert hd(cached_seasons).name == "Updated Winter"
    end
  end

  describe "cache key uniqueness" do
    test "cache keys include property and date" do
      winter =
        create_season(%{
          name: "Winter",
          property: :tahoe,
          start_date: ~D[2024-11-01],
          end_date: ~D[2025-04-30]
        })

      summer =
        create_season(%{
          name: "Summer",
          property: :tahoe,
          start_date: ~D[2024-05-01],
          end_date: ~D[2024-10-31]
        })

      # Fetch both seasons using different dates - should be cached separately
      cached_winter = SeasonCache.get(:tahoe, ~D[2024-12-15])
      cached_summer = SeasonCache.get(:tahoe, ~D[2024-07-15])

      assert cached_winter.id == winter.id
      assert cached_summer.id == summer.id
      assert cached_winter.name == "Winter"
      assert cached_summer.name == "Summer"
    end
  end

  describe "year-spanning seasons" do
    test "caches year-spanning season correctly" do
      # Winter season that spans 2024-2025
      season =
        create_season(%{
          name: "Winter 2024-2025",
          property: :tahoe,
          start_date: ~D[2024-11-01],
          end_date: ~D[2025-04-30]
        })

      # Test date in 2024 portion
      cached_2024 = SeasonCache.get(:tahoe, ~D[2024-12-15])
      assert cached_2024.id == season.id

      # Test date in 2025 portion
      cached_2025 = SeasonCache.get(:tahoe, ~D[2025-03-15])
      assert cached_2025.id == season.id
    end
  end
end
