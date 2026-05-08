defmodule YscWeb.UploadsConsumeEntryTest do
  @moduledoc """
  Tests for the deduplication path inside YscWeb.Uploads.consume_entry/3.

  consume_entry/3 is the server-side entry point for the MediaPickerComponent
  upload flow. When a file with a matching content_hash already exists, it
  returns the existing image ID without uploading to S3 or creating a new
  record.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Media
  alias Ysc.Media.Image
  alias YscWeb.Uploads

  @tiny_png_path Path.expand("../support/fixtures/tiny.png", __DIR__)

  setup do
    admin = user_fixture(%{role: :admin})
    %{user: admin}
  end

  describe "consume_entry/3 — deduplication" do
    test "returns the existing image ID without hitting S3 when the hash matches",
         %{user: user} do
      hash = Media.compute_file_hash(@tiny_png_path)

      {:ok, existing} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://s3.example.com/raw.png",
          optimized_image_path: "https://cdn.example.com/opt.webp",
          thumbnail_path: "https://cdn.example.com/thumb.webp",
          blur_hash: "L6Pj0^jE",
          width: 1,
          height: 1,
          processing_state: :completed,
          content_hash: hash
        }
        |> Repo.insert()

      count_before = Media.count_images()

      result = Uploads.consume_entry(%{path: @tiny_png_path}, %{}, user)

      assert result == {:ok, existing.id}
      assert Media.count_images() == count_before
    end

    test "does not create a duplicate DB record when the same file is consumed twice",
         %{user: user} do
      hash = Media.compute_file_hash(@tiny_png_path)

      {:ok, existing} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://s3.example.com/raw.png",
          optimized_image_path: "https://cdn.example.com/opt.webp",
          processing_state: :completed,
          content_hash: hash
        }
        |> Repo.insert()

      {:ok, id1} = Uploads.consume_entry(%{path: @tiny_png_path}, %{}, user)
      {:ok, id2} = Uploads.consume_entry(%{path: @tiny_png_path}, %{}, user)

      assert id1 == existing.id
      assert id2 == existing.id
    end

    test "returns the existing image even when uploaded by a different user",
         %{user: original_uploader} do
      second_uploader = user_fixture(%{role: :admin})

      hash = Media.compute_file_hash(@tiny_png_path)

      {:ok, existing} =
        %Image{
          user_id: original_uploader.id,
          raw_image_path: "https://s3.example.com/raw.png",
          optimized_image_path: "https://cdn.example.com/opt.webp",
          processing_state: :completed,
          content_hash: hash
        }
        |> Repo.insert()

      assert {:ok, id} =
               Uploads.consume_entry(
                 %{path: @tiny_png_path},
                 %{},
                 second_uploader
               )

      assert id == existing.id
    end
  end
end
