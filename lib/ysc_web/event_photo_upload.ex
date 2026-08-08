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
  alias Ysc.S3Config
  alias YscWeb.S3.SimpleS3Upload

  @doc """
  Presigns a direct event photo/video upload for the given collection.
  """
  def presign(entry, socket, collection_id) when is_binary(collection_id) do
    ext = entry.client_name |> Path.extname() |> String.downcase()
    key = "event_photo_uploads/#{collection_id}/#{Ecto.ULID.generate()}#{ext}"

    config = %{
      region: S3Config.region(),
      access_key_id: S3Config.aws_access_key_id(),
      secret_access_key: S3Config.aws_secret_access_key()
    }

    max_file_size = socket.assigns.uploads.photos.max_file_size

    {:ok, fields} =
      SimpleS3Upload.sign_form_upload(config, S3Config.bucket_name(),
        key: key,
        content_type: Limits.content_type_for_filename(entry.client_name),
        max_file_size: max_file_size,
        expires_in: :timer.hours(2),
        server_side_encryption: S3Config.server_side_encryption?()
      )

    upload_url = S3Config.upload_url()
    :ok = S3Config.assert_direct_upload_url!(upload_url, :media)

    meta = %{
      uploader: "S3",
      key: key,
      url: upload_url,
      fields: fields
    }

    {:ok, meta, socket}
  end
end
