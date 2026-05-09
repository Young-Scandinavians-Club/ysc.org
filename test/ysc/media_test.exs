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

  describe "total_image_count_from_timeline/1" do
    test "sums per-year counts" do
      timeline = [
        %{year: 2026, count: 3},
        %{year: 2025, count: 7}
      ]

      assert Media.total_image_count_from_timeline(timeline) == 10
      assert Media.total_image_count_from_timeline([]) == 0
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

    test "limit 0 returns empty list" do
      assert Media.list_images_cursor(limit: 0) == []
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

  describe "add_new_image/2, update_image/3, delete_image/2" do
    test "admin can create, update, and delete an image" do
      admin = user_fixture(%{role: "admin"})

      assert {:ok, image} =
               Media.add_new_image(
                 %{
                   raw_image_path: "https://example.com/new.jpg",
                   title: "Original title"
                 },
                 admin
               )

      assert {:ok, updated} =
               Media.update_image(image, %{title: "Updated title"}, admin)

      assert updated.title == "Updated title"

      assert {:ok, _} = Media.delete_image(updated, admin)
      assert Media.fetch_image(updated.id) == nil
    end

    test "member cannot create an image", %{user: user} do
      assert {:error, _} =
               Media.add_new_image(
                 %{
                   raw_image_path: "https://example.com/denied.jpg"
                 },
                 user
               )
    end
  end

  describe "compute_file_hash/1" do
    defp tmp_path(content) do
      path = "/tmp/media_hash_test_#{System.unique_integer([:positive])}"
      File.write!(path, content)
      on_exit(fn -> File.rm(path) end)
      path
    end

    test "returns a 64-character lowercase hex string" do
      hash = Media.compute_file_hash(tmp_path("hello"))
      assert String.length(hash) == 64
      assert hash =~ ~r/^[0-9a-f]{64}$/
    end

    test "same file content produces the same hash" do
      assert Media.compute_file_hash(tmp_path("deterministic")) ==
               Media.compute_file_hash(tmp_path("deterministic"))
    end

    test "different file content produces different hashes" do
      refute Media.compute_file_hash(tmp_path("content_a")) ==
               Media.compute_file_hash(tmp_path("content_b"))
    end

    test "matches the expected SHA-256 of the file content" do
      content = "known content for hashing"
      expected = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      assert Media.compute_file_hash(tmp_path(content)) == expected
    end

    test "works correctly on binary file content" do
      content = :crypto.strong_rand_bytes(4096)
      expected = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      assert Media.compute_file_hash(tmp_path(content)) == expected
    end
  end

  describe "find_image_by_content_hash/1" do
    test "returns nil when no image has the given hash" do
      assert Media.find_image_by_content_hash("hashnotinthisdatabase") == nil
    end

    test "returns the image matching the given hash", %{user: user} do
      {:ok, image} =
        %Media.Image{
          user_id: user.id,
          raw_image_path: "https://example.com/img.jpg",
          processing_state: :unprocessed,
          content_hash: "deadbeef01234567890a"
        }
        |> Repo.insert()

      found = Media.find_image_by_content_hash("deadbeef01234567890a")
      assert found.id == image.id
    end

    test "does not return an image with a different hash", %{user: user} do
      {:ok, _image} =
        %Media.Image{
          user_id: user.id,
          raw_image_path: "https://example.com/other.jpg",
          processing_state: :unprocessed,
          content_hash: "aaaaaaaabbbbbbbb"
        }
        |> Repo.insert()

      assert Media.find_image_by_content_hash("ccccccccdddddddd") == nil
    end
  end

  describe "set_content_hash/2" do
    test "persists the content hash on the image record", %{user: user} do
      {:ok, image} =
        %Media.Image{
          user_id: user.id,
          raw_image_path: "https://example.com/img.jpg",
          processing_state: :unprocessed
        }
        |> Repo.insert()

      assert {:ok, updated} = Media.set_content_hash(image, "myhash123")
      assert updated.content_hash == "myhash123"
      assert Media.fetch_image(image.id).content_hash == "myhash123"
    end

    test "overwrites an existing hash", %{user: user} do
      {:ok, image} =
        %Media.Image{
          user_id: user.id,
          raw_image_path: "https://example.com/img.jpg",
          processing_state: :unprocessed,
          content_hash: "oldhash"
        }
        |> Repo.insert()

      assert {:ok, _} = Media.set_content_hash(image, "newhash")
      assert Media.fetch_image(image.id).content_hash == "newhash"
    end
  end

  describe "reuse_existing_processed_image/2" do
    test "copies all processed fields from source to target", %{user: user} do
      {:ok, source} =
        %Media.Image{
          user_id: user.id,
          raw_image_path: "https://example.com/source.jpg",
          optimized_image_path: "https://cdn.example.com/source_opt.webp",
          thumbnail_path: "https://cdn.example.com/source_thumb.webp",
          blur_hash: "L6Pj0^jE.AyX_3t7",
          width: 1920,
          height: 1080,
          processing_state: :completed,
          content_hash: "sourcehash999"
        }
        |> Repo.insert()

      {:ok, target} =
        %Media.Image{
          user_id: user.id,
          raw_image_path: "https://example.com/duplicate.jpg",
          processing_state: :unprocessed
        }
        |> Repo.insert()

      result = Media.reuse_existing_processed_image(target, source)

      assert result.processing_state == :completed
      assert result.optimized_image_path == source.optimized_image_path
      assert result.thumbnail_path == source.thumbnail_path
      assert result.blur_hash == source.blur_hash
      assert result.width == source.width
      assert result.height == source.height
      # content_hash is NOT copied — only one record can own a given hash
      assert result.content_hash == nil
    end

    test "persisted record reflects the reused values", %{user: user} do
      {:ok, source} =
        %Media.Image{
          user_id: user.id,
          raw_image_path: "https://example.com/source.jpg",
          optimized_image_path: "https://cdn.example.com/opt.webp",
          thumbnail_path: "https://cdn.example.com/thumb.webp",
          blur_hash: "L6Pj0^jE",
          width: 800,
          height: 600,
          processing_state: :completed,
          content_hash: "persistedhash"
        }
        |> Repo.insert()

      {:ok, target} =
        %Media.Image{
          user_id: user.id,
          raw_image_path: "https://example.com/dup.jpg",
          processing_state: :unprocessed
        }
        |> Repo.insert()

      Media.reuse_existing_processed_image(target, source)

      reloaded = Media.fetch_image(target.id)
      assert reloaded.processing_state == :completed
      assert reloaded.optimized_image_path == source.optimized_image_path
      assert reloaded.thumbnail_path == source.thumbnail_path
      assert reloaded.content_hash == nil
    end
  end

  describe "content_hash uniqueness constraint" do
    test "rejects two images with the same content_hash", %{user: user} do
      {:ok, _} =
        %Media.Image{user_id: user.id}
        |> Media.Image.add_image_changeset(%{
          raw_image_path: "https://example.com/a.jpg",
          content_hash: "uniquehash_xyz"
        })
        |> Repo.insert()

      assert {:error, changeset} =
               %Media.Image{user_id: user.id}
               |> Media.Image.add_image_changeset(%{
                 raw_image_path: "https://example.com/b.jpg",
                 content_hash: "uniquehash_xyz"
               })
               |> Repo.insert()

      assert {:content_hash, _} =
               List.keyfind(changeset.errors, :content_hash, 0)
    end

    test "allows two images with nil content_hash", %{user: user} do
      {:ok, _} =
        %Media.Image{
          user_id: user.id,
          raw_image_path: "https://example.com/a.jpg",
          processing_state: :unprocessed
        }
        |> Repo.insert()

      assert {:ok, _} =
               %Media.Image{
                 user_id: user.id,
                 raw_image_path: "https://example.com/b.jpg",
                 processing_state: :unprocessed
               }
               |> Repo.insert()
    end
  end

  describe "update_processed_image/2" do
    test "updates image processing fields", %{user: user} do
      {:ok, image} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://example.com/raw.jpg",
          processing_state: :processing
        }
        |> Repo.insert()

      updated =
        Media.update_processed_image(image, %{
          optimized_image_path: "https://cdn.example.com/opt.jpg",
          thumbnail_path: "https://cdn.example.com/thumb.jpg",
          blur_hash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
          width: 800,
          height: 600,
          processing_state: "completed"
        })

      assert updated.optimized_image_path =~ "opt.jpg"
      assert updated.thumbnail_path =~ "thumb.jpg"
      assert updated.width == 800
      assert updated.height == 600
      assert updated.processing_state == :completed
    end
  end
end
