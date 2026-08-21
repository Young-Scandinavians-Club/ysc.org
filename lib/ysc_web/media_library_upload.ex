defmodule YscWeb.MediaLibraryUpload do
  @moduledoc """
  Presigns direct-to-S3 uploads for the volunteer media library.

  Object keys are unique per upload so a volunteer cannot overwrite another
  public-read object by reusing a filename. Content-Type is derived from the
  file extension, not the browser-supplied MIME type.
  """

  alias Ysc.Media
  alias Ysc.S3Config
  alias YscWeb.S3.SimpleS3Upload

  @doc """
  Presigns a direct media-library image upload.
  """
  def presign(entry, socket) do
    uploads = socket.assigns.uploads
    key = Media.public_image_storage_key(entry.client_name)

    config = %{
      region: S3Config.region(),
      access_key_id: S3Config.aws_access_key_id(),
      secret_access_key: S3Config.aws_secret_access_key()
    }

    {:ok, fields} =
      SimpleS3Upload.sign_form_upload(config, S3Config.bucket_name(),
        key: key,
        content_type: Media.image_content_type_from_filename(entry.client_name),
        max_file_size: uploads[entry.upload_config].max_file_size,
        expires_in: :timer.hours(1),
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
