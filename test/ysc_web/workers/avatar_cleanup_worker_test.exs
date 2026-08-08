defmodule YscWeb.Workers.AvatarCleanupWorkerTest do
  @moduledoc """
  Tests for AvatarCleanupWorker against real local MinIO (see
  `config/test.exs` / CI's "Start MinIO and create buckets" step).
  """

  use Ysc.DataCase, async: false

  alias Ysc.S3Config
  alias YscWeb.Workers.AvatarCleanupWorker

  @tiny_png Base.decode64!(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
            )

  defp make_job(args) do
    %Oban.Job{
      id: 1,
      args: args,
      worker: "YscWeb.Workers.AvatarCleanupWorker",
      queue: "media",
      state: "available",
      attempt: 1
    }
  end

  describe "perform/1" do
    test "deletes the S3 object at the given bucket and key" do
      bucket = S3Config.avatars_bucket_name()
      key = "cleanup-worker-test/#{Ecto.ULID.generate()}/original.png"

      bucket |> ExAws.S3.put_object(key, @tiny_png) |> ExAws.request!()
      assert {:ok, _} = bucket |> ExAws.S3.head_object(key) |> ExAws.request()

      assert :ok =
               AvatarCleanupWorker.perform(
                 make_job(%{
                   "bucket" => bucket,
                   "key" => key,
                   "avatar_id" => "a1"
                 })
               )

      assert {:error, {:http_error, 404, _}} =
               bucket |> ExAws.S3.head_object(key) |> ExAws.request()
    end

    test "returns an error tuple (so Oban retries) when S3 deletion fails" do
      key = "cleanup-worker-test/#{Ecto.ULID.generate()}/original.png"

      assert {:error, _reason} =
               AvatarCleanupWorker.perform(
                 make_job(%{
                   "bucket" => "nonexistent-bucket-#{Ecto.ULID.generate()}",
                   "key" => key,
                   "avatar_id" => "a1"
                 })
               )
    end
  end
end
