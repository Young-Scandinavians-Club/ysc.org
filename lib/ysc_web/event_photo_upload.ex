defmodule YscWeb.EventPhotoUpload do
  @moduledoc """
  Presigns direct-to-S3 uploads for event photo/video contributions.

  Uploads go straight from the browser to object storage instead of being
  buffered through the LiveView socket onto local disk: local disk is
  per-machine and Oban jobs can execute on any app instance, so a job
  referencing a locally-staged file can silently find nothing there. S3 is
  durable and reachable from whichever instance runs the upload job.
  """

  alias Ysc.GooglePhotos.Limits
  alias YscWeb.S3.DirectUpload

  @doc """
  Presigns a direct event photo/video upload for the given collection.
  """
  def presign(entry, socket, collection_id) when is_binary(collection_id) do
    filename = entry.client_name || ""

    # Finding 100: the LiveView `max_file_size` is the video cap (20 GB) so
    # a 4 GB `.jpg` can otherwise land on the public-read media bucket
    # before `Limits.validate_upload/2` runs. Bind the S3 POST policy to
    # the per-type limit. Refuse to mint a policy for unsupported names.
    if Limits.photo?(filename) or Limits.video?(filename) do
      ext = filename |> Path.extname() |> String.downcase()
      key = "event_photo_uploads/#{collection_id}/#{Ecto.ULID.generate()}#{ext}"

      DirectUpload.presign(socket,
        kind: :media,
        key: key,
        content_type: Limits.content_type_for_filename(filename),
        max_file_size: Limits.max_bytes_for_filename(filename),
        expires_in: :timer.hours(2)
      )
    else
      {:error, %{reason: Limits.error_message(:unsupported_type)}, socket}
    end
  end
end
