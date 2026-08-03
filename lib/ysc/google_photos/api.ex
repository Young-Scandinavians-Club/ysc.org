defmodule Ysc.GooglePhotos.Api do
  @moduledoc """
  Google Photos Library API client for app-created albums and uploads.
  """

  require Ysc.Logging

  alias Ysc.EventPhotos
  alias Ysc.EventPhotos.Collection
  alias Ysc.Events.Event
  alias Ysc.GooglePhotos
  alias Ysc.GooglePhotos.Limits

  @photos_api_base "https://photoslibrary.googleapis.com/v1"
  @upload_url "https://photoslibrary.googleapis.com/v1/uploads"
  @stream_chunk_size 5_242_880

  @doc "Creates an album with a normalized title."
  def create_album(access_token, title, event_id \\ nil) do
    normalized = Limits.normalize_album_title(title)

    if normalized == "" do
      {:error, :empty_album_title}
    else
      if use_dev_stub?() do
        Ysc.GooglePhotos.Api.DevStub.create_album(
          access_token,
          normalized,
          event_id
        )
      else
        create_album_http(access_token, normalized)
      end
    end
  end

  @doc "Uploads raw bytes and returns an upload token."
  def upload_bytes(access_token, bytes, filename, event_id \\ nil)
      when is_binary(bytes) do
    with :ok <- Limits.validate_upload(filename, byte_size(bytes)) do
      normalized = Limits.normalize_filename(filename)

      if use_dev_stub?() do
        Ysc.GooglePhotos.Api.DevStub.upload_bytes(
          access_token,
          bytes,
          normalized,
          event_id
        )
      else
        upload_bytes_http(access_token, bytes, normalized)
      end
    end
  end

  @doc "Creates a media item in an album from an upload token."
  def create_media_item(access_token, upload_token, album_id, filename) do
    normalized = Limits.normalize_filename(filename)
    token = String.trim(upload_token)

    if use_dev_stub?() do
      Ysc.GooglePhotos.Api.DevStub.create_media_item(
        access_token,
        token,
        album_id,
        normalized
      )
    else
      create_media_item_http(access_token, token, album_id, normalized)
    end
  end

  @doc """
  Ensures a Google album exists for the collection, then uploads the file.

  Persists `google_album_id` on first album creation only.
  """
  def ensure_album_and_upload(
        %Collection{} = collection,
        %Event{} = event,
        access_token,
        file_path,
        filename
      ) do
    tmp_root = Ysc.SafeFile.event_photo_tmp_root()

    with {:ok, stat} <- Ysc.SafeFile.stat_under_root(tmp_root, file_path),
         :ok <- Limits.validate_upload(filename, stat.size),
         {:ok, album_id} <- ensure_album_id(collection, event, access_token),
         {:ok, upload_token} <-
           upload_file(access_token, file_path, filename, event.id, stat.size),
         {:ok, _item} <-
           create_media_item(access_token, upload_token, album_id, filename) do
      {:ok, album_id}
    end
  end

  defp upload_file(access_token, file_path, filename, event_id, size) do
    normalized = Limits.normalize_filename(filename)

    if use_dev_stub?() do
      Ysc.GooglePhotos.Api.DevStub.upload_file(
        access_token,
        file_path,
        normalized,
        event_id,
        size
      )
    else
      if size > Limits.max_photo_bytes() do
        upload_file_stream_http(access_token, file_path, normalized, size)
      else
        tmp_root = Ysc.SafeFile.event_photo_tmp_root()

        with {:ok, bytes} <- Ysc.SafeFile.read_under_root(tmp_root, file_path) do
          upload_bytes_http(access_token, bytes, normalized)
        end
      end
    end
  end

  defp ensure_album_id(%Collection{google_album_id: id}, _event, _token)
       when is_binary(id) and id != "" do
    {:ok, id}
  end

  defp ensure_album_id(collection, event, access_token) do
    title = EventPhotos.album_title(event)

    with {:ok, album_id} <- create_album(access_token, title, event.id),
         {:ok, updated} <- EventPhotos.set_google_album_id(collection, album_id) do
      {:ok, updated.google_album_id}
    end
  end

  defp use_dev_stub? do
    if GooglePhotos.dev_stub_enabled?() do
      GooglePhotos.get_connection() == nil
    else
      false
    end
  end

  defp create_album_http(access_token, title) do
    body = %{"album" => %{"title" => title}}

    case req_post("#{@photos_api_base}/albums",
           json: body,
           headers: auth_headers(access_token),
           receive_timeout: 30_000
         ) do
      {:ok, %{status: status, body: %{"id" => id}}} when status in 200..299 ->
        {:ok, id}

      {:ok, %{status: status, body: body}} ->
        log_api_error("create_album", status, body)
        {:error, {:api_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # File path is validated under the event-photo tmp root before this runs.
  # sobelow_skip ["Traversal.FileModule"]
  defp upload_file_stream_http(access_token, file_path, filename, size) do
    content_type = content_type_for_filename(filename)
    timeout = upload_receive_timeout(size)
    stream = File.stream!(file_path, @stream_chunk_size)

    case req_post(@upload_url,
           body: stream,
           headers:
             upload_raw_headers(access_token, filename, content_type,
               size: size
             ),
           receive_timeout: timeout
         ) do
      {:ok, %{status: status, body: upload_token}}
      when status in 200..299 and is_binary(upload_token) and upload_token != "" ->
        {:ok, String.trim(upload_token)}

      {:ok, %{status: status, body: body}} ->
        log_api_error("upload", status, body)
        {:error, {:api_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upload_bytes_http(access_token, bytes, filename) do
    content_type = content_type_for_filename(filename)
    timeout = upload_receive_timeout(byte_size(bytes))

    case req_post(@upload_url,
           body: bytes,
           headers: upload_raw_headers(access_token, filename, content_type),
           receive_timeout: timeout
         ) do
      {:ok, %{status: status, body: upload_token}}
      when status in 200..299 and is_binary(upload_token) and upload_token != "" ->
        {:ok, String.trim(upload_token)}

      {:ok, %{status: status, body: body}} ->
        log_api_error("upload", status, body)
        {:error, {:api_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_media_item_http(access_token, upload_token, album_id, filename) do
    body = %{
      "albumId" => album_id,
      "newMediaItems" => [
        %{
          "description" => filename,
          "simpleMediaItem" => %{"uploadToken" => upload_token}
        }
      ]
    }

    case req_post("#{@photos_api_base}/mediaItems:batchCreate",
           json: body,
           headers: auth_headers(access_token),
           receive_timeout: 30_000
         ) do
      {:ok, %{status: status, body: %{"newMediaItemResults" => [first | _]}}}
      when status in 200..299 ->
        case first do
          %{"status" => %{"message" => "Success"}, "mediaItem" => item} ->
            {:ok, item}

          %{"status" => status_map} ->
            Ysc.Logging.error("Google Photos: batchCreate item failed",
              status: inspect(status_map)
            )

            {:error, :media_item_failed}
        end

      {:ok, %{status: status, body: body}} ->
        log_api_error("batchCreate", status, body)
        {:error, {:api_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp req_post(url, opts) do
    Req.post(url, Keyword.merge(req_opts(), opts))
  end

  defp req_opts do
    Application.get_env(:ysc, :google_photos_req_opts, [])
  end

  defp auth_headers(access_token) do
    [{"authorization", "Bearer #{access_token}"}]
  end

  defp upload_raw_headers(access_token, filename, content_type, opts \\ []) do
    headers =
      auth_headers(access_token) ++
        [
          {"content-type", "application/octet-stream"},
          {"x-goog-upload-protocol", "raw"},
          {"x-goog-upload-content-type", content_type},
          {"x-goog-upload-file-name", filename}
        ]

    case Keyword.get(opts, :size) do
      nil -> headers
      size -> headers ++ [{"content-length", to_string(size)}]
    end
  end

  defp content_type_for_filename(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".png" -> "image/png"
      ".webp" -> "image/webp"
      ".heic" -> "image/heic"
      ".heif" -> "image/heif"
      ".gif" -> "image/gif"
      ".bmp" -> "image/bmp"
      ".tif" -> "image/tiff"
      ".tiff" -> "image/tiff"
      ".mp4" -> "video/mp4"
      ".mov" -> "video/quicktime"
      ".m4v" -> "video/x-m4v"
      ".avi" -> "video/x-msvideo"
      ".mkv" -> "video/x-matroska"
      ".webm" -> "video/webm"
      ".3gp" -> "video/3gpp"
      ".3g2" -> "video/3gpp2"
      ".mpeg" -> "video/mpeg"
      ".mpg" -> "video/mpeg"
      ".wmv" -> "video/x-ms-wmv"
      ".asf" -> "video/x-ms-asf"
      ".m2ts" -> "video/mp2t"
      ".mts" -> "video/mp2t"
      ext when ext in [".jpg", ".jpeg"] -> "image/jpeg"
      _ -> "application/octet-stream"
    end
  end

  defp upload_receive_timeout(size) when size > 200 * 1024 * 1024,
    do: :timer.minutes(30)

  defp upload_receive_timeout(_), do: 120_000

  defp log_api_error(operation, status, body) do
    Ysc.Logging.error("Google Photos API: #{operation} failed",
      status: status,
      body: inspect(body, limit: 300)
    )
  end
end
