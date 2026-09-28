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
    ext = entry.client_name |> Path.extname() |> String.downcase()
    key = "event_photo_uploads/#{collection_id}/#{Ecto.ULID.generate()}#{ext}"

    DirectUpload.presign(socket,
      kind: :media,
      key: key,
      content_type: Limits.content_type_for_filename(entry.client_name),
      max_file_size: socket.assigns.uploads.photos.max_file_size,
      expires_in: :timer.hours(2)
    )
  end
end
