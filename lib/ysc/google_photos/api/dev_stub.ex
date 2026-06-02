defmodule Ysc.GooglePhotos.Api.DevStub do
  @moduledoc false

  require Ysc.Logging

  alias Ysc.GooglePhotos.Limits
  alias Ysc.SafeFile

  def create_album(_access_token, title, event_id) do
    Ysc.Logging.info("Google Photos DevStub: create_album",
      title: title,
      event_id: event_id
    )

    {:ok, "dev-album-#{event_id}"}
  end

  def upload_file(_access_token, file_path, filename, event_id, size) do
    upload_id = :erlang.unique_integer([:positive])
    upload_token = "dev-upload-#{upload_id}"

    with :ok <- validate_event_id(event_id),
         :ok <- Limits.validate_upload(filename, size),
         normalized <- Limits.normalize_filename(filename),
         storage_name <- unique_storage_filename(normalized, upload_id),
         {:ok, dest} <- SafeFile.dev_event_photo_path(event_id, storage_name),
         :ok <- SafeFile.copy_upload_to(file_path, dest) do
      Ysc.Logging.info("Google Photos DevStub: upload_file",
        filename: storage_name,
        size: size,
        event_id: event_id
      )

      {:ok, upload_token}
    else
      :error -> {:error, :invalid_event_id}
      {:error, reason} -> {:error, reason}
    end
  end

  def upload_bytes(_access_token, bytes, filename, event_id) do
    upload_id = :erlang.unique_integer([:positive])
    upload_token = "dev-upload-#{upload_id}"

    with :ok <- validate_event_id(event_id),
         :ok <- Limits.validate_upload(filename, byte_size(bytes)),
         normalized <- Limits.normalize_filename(filename),
         storage_name <- unique_storage_filename(normalized, upload_id),
         :ok <- SafeFile.write_dev_event_photo(event_id, storage_name, bytes) do
      Ysc.Logging.info("Google Photos DevStub: upload_bytes",
        filename: storage_name,
        size: byte_size(bytes),
        event_id: event_id
      )

      {:ok, upload_token}
    else
      :error -> {:error, :invalid_event_id}
      {:error, reason} -> {:error, reason}
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

  defp validate_event_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
  defp validate_event_id(_), do: :error

  defp unique_storage_filename(filename, unique_id) do
    ext = Path.extname(filename)
    base = Path.rootname(filename)
    "#{base}-#{unique_id}#{ext}"
  end
end
