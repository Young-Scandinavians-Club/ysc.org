defmodule YscWeb.Workers.EventPhotoUploadWorker do
  @moduledoc """
  Uploads event photos or videos to Google Photos (or DevStub in local development).
  """
  require Ysc.Logging

  use Oban.Worker,
    queue: :media,
    max_attempts: 3

  alias Ysc.EventPhotos
  alias Ysc.GooglePhotos
  alias Ysc.GooglePhotos.Api
  alias Ysc.GooglePhotos.Limits
  alias Ysc.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "collection_id" => collection_id,
          "file_path" => file_path,
          "filename" => filename,
          "user_id" => user_id
        }
      }) do
    try do
      with {:ok, stat} <- File.stat(file_path),
           :ok <- Limits.validate_upload(filename, stat.size),
           collection <-
             EventPhotos.Collection
             |> Repo.get!(collection_id)
             |> Repo.preload(:event),
           {:ok, access_token} <- GooglePhotos.get_access_token(),
           {:ok, _album_id} <-
             Api.ensure_album_and_upload(
               collection,
               collection.event,
               access_token,
               file_path,
               filename
             ) do
        Ysc.Logging.info("Event media uploaded",
          collection_id: collection_id,
          event_id: collection.event_id,
          user_id: user_id,
          filename: filename
        )

        :ok
      else
        {:error, reason}
        when reason in [
               :photo_too_large,
               :video_too_large,
               :file_too_large,
               :filename_too_long,
               :empty_filename,
               :unsupported_type
             ] ->
          Ysc.Logging.warning("Event media upload rejected",
            collection_id: collection_id,
            reason: reason,
            filename: filename
          )

          :ok

        {:error, reason} ->
          Ysc.Logging.error("Event media upload failed",
            collection_id: collection_id,
            reason: inspect(reason)
          )

          {:error, reason}
      end
    after
      _ = File.rm(file_path)
    end
  end
end
