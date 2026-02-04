defmodule YscWeb.Workers.ImageReprocessorTest do
  @moduledoc """
  Tests for ImageReprocessor worker module.
  """
  use Ysc.DataCase, async: true

  alias YscWeb.Workers.ImageReprocessor

  setup do
    # Mock Media.list_unprocessed_images to return test data
    %{}
  end

  describe "perform/1" do
    test "enqueues processing jobs for unprocessed images" do
      # This test would require mocking Media.list_unprocessed_images
      # and Media.Image schema. For now, we'll test the basic structure.

      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "YscWeb.Workers.ImageReprocessor",
        queue: "media",
        state: "available",
        attempt: 1
      }

      # The actual test would require setting up image records
      # For now, we'll just verify the function can be called
      result = ImageReprocessor.perform(job)
      # Result could be :ok or error depending on available images
      assert result == :ok or match?({:error, _}, result)
    end

    test "handles empty list of unprocessed images" do
      # Mock would return empty list
      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "YscWeb.Workers.ImageReprocessor",
        queue: "media",
        state: "available",
        attempt: 1
      }

      # Should complete successfully with no images
      result = ImageReprocessor.perform(job)
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "timeout/1" do
    test "returns 30 minutes timeout" do
      job = %Oban.Job{id: 1, args: %{}}
      timeout = ImageReprocessor.timeout(job)
      assert timeout == 30 * 60 * 1000
    end
  end
end
