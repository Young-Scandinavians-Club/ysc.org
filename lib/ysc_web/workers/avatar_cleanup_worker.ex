defmodule YscWeb.Workers.AvatarCleanupWorker do
  @moduledoc """
  Deletes a single S3 object left behind after an avatar record is deleted.

  Enqueued once per object (original/thumb/profile/large) by
  `Ysc.Avatars.delete_avatar/2` in the same transaction as the database
  delete, so a transient S3 failure retries via Oban's backoff instead of
  leaving the object publicly accessible.
  """
  require Ysc.Logging

  use Oban.Worker, queue: :media, max_attempts: 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bucket" => bucket, "key" => key} = args}) do
    case bucket |> ExAws.S3.delete_object(key) |> ExAws.request() do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Ysc.Logging.warning("Avatar S3 object cleanup failed",
          extra: %{
            avatar_id: args["avatar_id"],
            key: key,
            reason: inspect(reason)
          }
        )

        {:error, reason}
    end
  end
end
