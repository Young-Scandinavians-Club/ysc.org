defmodule Ysc.GooglePhotos.Api.DevStub do
  @moduledoc false

  require Ysc.Logging

  alias Ysc.GooglePhotos.Limits

  @dev_dir "tmp/dev_event_photos"

  def create_album(_access_token, title, event_id) do
    Ysc.Logging.info("Google Photos DevStub: create_album",
      title: title,
      event_id: event_id
    )

    {:ok, "dev-album-#{event_id}"}
  end

  def upload_bytes(_access_token, bytes, filename, event_id) do
    with :ok <- Limits.validate_upload(filename, byte_size(bytes)),
         normalized <- Limits.normalize_filename(filename),
         :ok <- write_dev_copy(event_id, normalized, bytes) do
      upload_token = "dev-upload-#{:erlang.unique_integer([:positive])}"

      Ysc.Logging.info("Google Photos DevStub: upload_bytes",
        filename: normalized,
        size: byte_size(bytes),
        event_id: event_id
      )

      {:ok, upload_token}
    end
  end

  def create_media_item(_access_token, upload_token, album_id, filename) do
    Ysc.Logging.info("Google Photos DevStub: create_media_item",
      album_id: album_id,
      filename: filename,
      upload_token: upload_token
    )

    {:ok, %{"id" => "dev-media-#{upload_token}"}}
  end

  defp write_dev_copy(event_id, filename, bytes) do
    dir = Path.join([@dev_dir, event_id])
    path = Path.join(dir, filename)

    case File.mkdir_p(dir) do
      :ok ->
        case File.write(path, bytes) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
