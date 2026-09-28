defmodule YscWeb.MediaLibraryUpload do
  @moduledoc """
  Presigns direct-to-S3 uploads for the volunteer media library.

  Object keys are unique per upload so a volunteer cannot overwrite another
  public-read object by reusing a filename. Content-Type is derived from the
  file extension, not the browser-supplied MIME type.
  """

  alias Ysc.Media
  alias YscWeb.S3.DirectUpload

  @doc """
  Presigns a direct media-library image upload.
  """
  def presign(entry, socket) do
    uploads = socket.assigns.uploads
    key = Media.public_image_storage_key(entry.client_name)

    DirectUpload.presign(socket,
      kind: :media,
      key: key,
      content_type: Media.image_content_type_from_filename(entry.client_name),
      max_file_size: uploads[entry.upload_config].max_file_size
    )
  end
end
