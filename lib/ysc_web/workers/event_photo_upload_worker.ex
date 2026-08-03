defmodule YscWeb.Workers.EventPhotoUploadWorker do
  @moduledoc """
  Uploads event photos or videos to Google Photos (or DevStub in local development).

  The browser uploads directly to S3 (see `YscWeb.EventPhotoUpload`), so this
  worker downloads the object to local scratch space before handing it to the
  Google Photos API client, then removes both the scratch file and (on a
  terminal outcome) the S3 object.
  """
  require Ysc.Logging

  use Oban.Worker,
    queue: :media,
    max_attempts: 5

  alias Ysc.EventPhotos
  alias Ysc.GooglePhotos
  alias Ysc.GooglePhotos.Api
  alias Ysc.GooglePhotos.Limits
  alias Ysc.Repo
  alias Ysc.S3Config
  alias Ysc.SafeFile

  @terminal_errors [
    :photo_too_large,
    :video_too_large,
    :file_too_large,
    :filename_too_long,
    :empty_filename,
    :unsupported_type,
    :invalid_path
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{
        attempt: attempt,
        max_attempts: max_attempts,
        args: %{
          "collection_id" => collection_id,
          "s3_key" => s3_key,
          "filename" => filename,
          "user_id" => user_id
        }
      }) do
    final_attempt? = attempt >= max_attempts
    tmp_root = SafeFile.event_photo_tmp_root()
    scratch_id = Ecto.UUID.generate()

    result =
      with {:ok, dest} <-
             SafeFile.event_photo_tmp_path(collection_id, scratch_id, filename),
           :ok <- download_from_s3(s3_key, dest),
           {:ok, stat} <- SafeFile.stat_under_root(tmp_root, dest),
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
               dest,
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
        when reason in @terminal_errors ->
          Ysc.Logging.warning("Event media upload rejected",
            collection_id: collection_id,
            reason: reason,
            filename: filename
          )

          :ok

        {:error, reason} ->
          log_opts = [
            collection_id: collection_id,
            s3_key: s3_key,
            reason: inspect(reason)
          ]

          # Sentry-visible only once retries are exhausted — a lone transient
          # blip that a retry clears up on its own shouldn't page anyone.
          if final_attempt? do
            Ysc.Logging.error(
              "Event media upload permanently failed after #{max_attempts} attempts",
              log_opts
            )
          else
            Ysc.Logging.warning(
              "Event media upload failed, will retry",
              log_opts
            )
          end

          {:error, reason}
      end

    cleanup(
      tmp_root,
      collection_id,
      scratch_id,
      filename,
      s3_key,
      result,
      final_attempt?
    )

    result
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp download_from_s3(s3_key, dest) do
    case S3Config.bucket_name()
         |> ExAws.S3.download_file(s3_key, dest)
         |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:s3_download_failed, reason}}
    end
  end

  # Always clears the local scratch file (cheap to re-download on retry).
  # Only removes the S3 object once nothing will ever retry this job again —
  # a job that will be retried needs the object to still be there.
  defp cleanup(
         tmp_root,
         collection_id,
         scratch_id,
         filename,
         s3_key,
         result,
         final_attempt?
       ) do
    case SafeFile.event_photo_tmp_path(collection_id, scratch_id, filename) do
      {:ok, dest} -> SafeFile.rm_under_root(tmp_root, dest)
      :error -> :ok
    end

    if result == :ok or final_attempt? do
      case S3Config.bucket_name()
           |> ExAws.S3.delete_object(s3_key)
           |> ExAws.request() do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Ysc.Logging.warning("Event media S3 object cleanup failed",
            s3_key: s3_key,
            reason: inspect(reason)
          )
      end
    end
  end
end
