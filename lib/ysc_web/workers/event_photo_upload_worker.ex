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
  alias Ysc.SafeFile

  @terminal_errors [
    :photo_too_large,
    :video_too_large,
    :file_too_large,
    :filename_too_long,
    :empty_filename,
    :unsupported_type,
    :invalid_path,
    :enoent
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "collection_id" => collection_id,
          "file_path" => file_path,
          "filename" => filename,
          "user_id" => user_id
        }
      }) do
    tmp_root = SafeFile.event_photo_tmp_root()

    result =
      with {:ok, stat} <- SafeFile.stat_under_root(tmp_root, file_path),
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
        {:error, :enoent} ->
          Ysc.Logging.warning(
            "Event media upload temp file missing, discarding job",
            collection_id: collection_id,
            file_path: file_path
          )

          :ok

        {:error, reason}
        when reason in @terminal_errors ->
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

    if should_remove_temp_file?(result) do
      SafeFile.rm_under_root(tmp_root, file_path)
    end

    result
  end

  defp should_remove_temp_file?(:ok), do: true
  defp should_remove_temp_file?({:error, _}), do: false
end
