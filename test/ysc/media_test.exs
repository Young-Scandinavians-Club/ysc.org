defmodule Ysc.MediaTest do
  @moduledoc """
  Tests for Ysc.Media context module.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Media
  alias Ysc.Media.Image
  import Ysc.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "list_images/0" do
    test "returns all images" do
      {:ok, images} = Media.list_images()
      assert is_list(images)
    end
  end

  describe "get_available_years/0" do
    test "returns list of years" do
      years = Media.get_available_years()
      assert is_list(years)
      assert Enum.all?(years, &is_integer/1)
    end
  end

  describe "fetch_image/1" do
    test "returns image when found" do
      # Create an image
      user = user_fixture()

      {:ok, image} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://example.com/image.jpg",
          processing_state: :unprocessed
        }
        |> Repo.insert()

      found = Media.fetch_image(image.id)
      assert found.id == image.id
    end

    test "returns nil when not found" do
      assert Media.fetch_image(Ecto.ULID.generate()) == nil
    end
  end

  describe "list_unprocessed_images/0" do
    test "returns images in unprocessed or processing state" do
      images = Media.list_unprocessed_images()
      assert is_list(images)
    end
  end

  describe "set_image_processing_state/2" do
    test "updates image processing state", %{user: user} do
      {:ok, image} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://example.com/image.jpg",
          processing_state: :unprocessed
        }
        |> Repo.insert()

      assert {:ok, updated} =
               Media.set_image_processing_state(image, :processing)

      assert updated.processing_state == :processing
    end
  end

  describe "get_image!/1" do
    test "returns image by id", %{user: user} do
      {:ok, image} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://example.com/image.jpg",
          processing_state: :unprocessed
        }
        |> Repo.insert()

      found = Media.get_image!(image.id)
      assert found.id == image.id
    end

    test "raises for non-existent image" do
      assert_raise Ecto.NoResultsError, fn ->
        Media.get_image!(Ecto.ULID.generate())
      end
    end
  end

  describe "get_timeline_indices/0" do
    test "returns timeline indices with year and count" do
      indices = Media.get_timeline_indices()
      assert is_list(indices)

      assert Enum.all?(indices, fn idx ->
               Map.has_key?(idx, :year) && Map.has_key?(idx, :count)
             end)
    end
  end

  describe "list_images_cursor/1" do
    test "returns images with cursor pagination" do
      images = Media.list_images_cursor(limit: 10)
      assert is_list(images)
      assert length(images) <= 10
    end

    test "filters by before_date" do
      before_date = DateTime.utc_now()
      images = Media.list_images_cursor(before_date: before_date, limit: 10)
      assert is_list(images)
    end

    test "filters by start_at_year" do
      current_year = Date.utc_today().year
      images = Media.list_images_cursor(start_at_year: current_year, limit: 10)
      assert is_list(images)
    end

    test "filters by search on title", %{user: user} do
      {:ok, _img} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://example.com/a.jpg",
          processing_state: :unprocessed,
          title: "Sunset at beach"
        }
        |> Repo.insert()

      {:ok, _img} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://example.com/b.jpg",
          processing_state: :unprocessed,
          title: "Mountain view"
        }
        |> Repo.insert()

      results = Media.list_images_cursor(search: "sunset", limit: 50)
      assert results != []

      assert Enum.all?(
               results,
               &String.contains?(String.downcase(&1.title || ""), "sunset")
             )
    end

    test "filters by search on alt_text", %{user: user} do
      {:ok, _img} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://example.com/c.jpg",
          processing_state: :unprocessed,
          alt_text: "A golden retriever playing"
        }
        |> Repo.insert()

      results = Media.list_images_cursor(search: "golden", limit: 50)
      assert results != []
    end

    test "search returns empty list for non-matching term" do
      results =
        Media.list_images_cursor(search: "zzz_nonexistent_xyz", limit: 50)

      assert results == []
    end

    test "search with empty string returns all images" do
      all = Media.list_images_cursor(limit: 50)
      with_empty_search = Media.list_images_cursor(search: "", limit: 50)
      assert length(all) == length(with_empty_search)
    end

    test "second page items are strictly before the cursor", %{user: user} do
      now = DateTime.utc_now()

      for i <- 1..4 do
        {:ok, _} =
          %Image{
            user_id: user.id,
            raw_image_path: "https://example.com/cursor-#{i}.jpg",
            processing_state: :unprocessed,
            inserted_at:
              DateTime.truncate(DateTime.add(now, -i * 60, :second), :second),
            updated_at:
              DateTime.truncate(DateTime.add(now, -i * 60, :second), :second)
          }
          |> Repo.insert()
      end

      page1 = Media.list_images_cursor(limit: 2)
      assert length(page1) == 2

      cursor = List.last(page1).inserted_at
      page2 = Media.list_images_cursor(limit: 2, before_date: cursor)

      assert Enum.all?(page2, fn img ->
               DateTime.compare(img.inserted_at, cursor) == :lt
             end)
    end
  end

  describe "list_images_grouped_by_year/1" do
    test "returns images grouped by year" do
      grouped = Media.list_images_grouped_by_year()
      assert is_map(grouped)
    end

    test "filters by year when provided" do
      current_year = Date.utc_today().year
      grouped = Media.list_images_grouped_by_year(current_year)
      assert is_map(grouped)
    end
  end

  describe "count_images/0" do
    test "returns total image count" do
      count = Media.count_images()
      assert is_integer(count)
      assert count >= 0
    end
  end

  describe "list_images_per_year/0" do
    test "returns images per year" do
      result = Media.list_images_per_year()
      # Function returns a map with year as keys and lists of images as values
      assert is_map(result)
    end
  end
end
