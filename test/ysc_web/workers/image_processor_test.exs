defmodule YscWeb.Workers.ImageProcessorTest do
  @moduledoc """
  Tests for ImageProcessor worker module.
  """
  use Ysc.DataCase, async: false

  alias YscWeb.Workers.ImageProcessor

  describe "perform/1" do
    test "handles missing image gracefully" do
      job = %Oban.Job{
        id: 1,
        args: %{"id" => Ecto.ULID.generate()},
        worker: "YscWeb.Workers.ImageProcessor",
        queue: "media",
        state: "available",
        attempt: 1
      }

      # Should handle missing image gracefully (fetch_image returns nil)
      # The perform function will try to access image.id which will fail
      # So we expect an error or the function should handle nil
      result = ImageProcessor.perform(job)
      assert match?({:error, _}, result)
    end

    test "handles invalid image ID" do
      # Use a valid ULID format but non-existent ID
      fake_id = Ecto.ULID.generate()

      job = %Oban.Job{
        id: 1,
        args: %{"id" => fake_id},
        worker: "YscWeb.Workers.ImageProcessor",
        queue: "media",
        state: "available",
        attempt: 1
      }

      # fetch_image will return nil for non-existent ID
      result = ImageProcessor.perform(job)
      assert match?({:error, _}, result)
    end
  end
end
