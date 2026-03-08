defmodule YscWeb.Workers.ImageProcessorTest do
  @moduledoc """
  Tests for ImageProcessor worker module.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Media
  alias YscWeb.Workers.ImageProcessor
  import Ysc.TestDataFactory

  describe "perform/1" do
    test "returns error when image is not found" do
      missing_id = Ecto.ULID.generate()

      job = %Oban.Job{
        id: 1,
        args: %{"id" => missing_id},
        worker: "YscWeb.Workers.ImageProcessor",
        queue: "media",
        state: "available",
        attempt: 1
      }

      result = ImageProcessor.perform(job)
      assert {:error, "Image not found"} = result
    end

    test "returns error for non-existent image ID" do
      fake_id = Ecto.ULID.generate()

      job = %Oban.Job{
        id: 1,
        args: %{"id" => fake_id},
        worker: "YscWeb.Workers.ImageProcessor",
        queue: "media",
        state: "available",
        attempt: 1
      }

      result = ImageProcessor.perform(job)
      assert {:error, "Image not found"} = result
    end

    test "sets image processing_state to failed when download fails" do
      # URL that will fail immediately (connection refused; nothing on port 1)
      raw_url = "http://127.0.0.1:1/image.jpg"

      image =
        create_test_image(%{
          raw_image_path: raw_url,
          processing_state: "unprocessed"
        })

      job = %Oban.Job{
        id: 1,
        args: %{"id" => image.id},
        worker: "YscWeb.Workers.ImageProcessor",
        queue: "media",
        state: "available",
        attempt: 1
      }

      result = ImageProcessor.perform(job)
      assert match?({:error, _}, result)

      updated = Media.fetch_image(image.id)
      assert updated.processing_state == :failed
    end
  end

  describe "new/1" do
    test "builds a job with the given image id" do
      image = create_test_image()
      changeset = ImageProcessor.new(%{id: image.id})

      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :worker) ==
               "YscWeb.Workers.ImageProcessor"

      assert Ecto.Changeset.get_change(changeset, :queue) == "media"

      args = Ecto.Changeset.get_change(changeset, :args) || %{}
      assert args["id"] == image.id or args[:id] == image.id
    end
  end
end
