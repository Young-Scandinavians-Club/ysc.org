defmodule Ysc.GooglePhotos.Limits do
  @moduledoc """
  Google Photos Library API size and length limits.
  """

  @default_max_photo_bytes 200 * 1024 * 1024
  @default_max_video_bytes 20 * 1024 * 1024 * 1024
  @max_album_title_length 500
  @max_filename_length 255

  @video_extensions ~w(.mp4 .mov .m4v .avi .mkv .webm .3gp .3g2 .mpeg .mpg .wmv .asf .m2ts .mts)
  @photo_extensions ~w(.jpg .jpeg .png .heic .heif .webp .gif .bmp .tif .tiff)

  @doc "Maximum photo upload size in bytes (200 MB)."
  def max_photo_bytes do
    Application.get_env(
      :ysc,
      :google_photos_max_photo_bytes,
      @default_max_photo_bytes
    )
  end

  @doc "Maximum video upload size in bytes (20 GB)."
  def max_video_bytes do
    Application.get_env(
      :ysc,
      :google_photos_max_video_bytes,
      @default_max_video_bytes
    )
  end

  @doc "Largest allowed upload size (used for LiveView `max_file_size`)."
  def max_upload_bytes, do: max_video_bytes()

  @doc "File extensions accepted for uploads (including leading dot)."
  def accepted_extensions, do: @photo_extensions ++ @video_extensions

  @doc "Returns true when the filename has a supported video extension."
  def video?(filename) when is_binary(filename) do
    filename
    |> Path.extname()
    |> String.downcase()
    |> then(&(&1 in @video_extensions))
  end

  def video?(_), do: false

  @doc "Returns true when the filename has a supported photo extension."
  def photo?(filename) when is_binary(filename) do
    filename
    |> Path.extname()
    |> String.downcase()
    |> then(&(&1 in @photo_extensions))
  end

  def photo?(_), do: false

  @doc "Maximum byte size allowed for the given filename."
  def max_bytes_for_filename(filename) do
    if video?(filename), do: max_video_bytes(), else: max_photo_bytes()
  end

  @doc "Maximum album title length in characters."
  def max_album_title_length, do: @max_album_title_length

  @doc "Maximum filename length in characters."
  def max_filename_length, do: @max_filename_length

  @doc "Trims and truncates an album title to the API maximum."
  def normalize_album_title(title) when is_binary(title) do
    title
    |> String.trim()
    |> String.slice(0, @max_album_title_length)
  end

  def normalize_album_title(_), do: ""

  @doc "Normalizes a filename: basename only, truncated to API maximum."
  def normalize_filename(filename) when is_binary(filename) do
    filename
    |> Path.basename()
    |> String.trim()
    |> String.slice(0, @max_filename_length)
  end

  def normalize_filename(_), do: ""

  @doc """
  Validates upload metadata.

  Returns `:ok` or `{:error, reason}` where reason is an atom such as
  `:photo_too_large`, `:video_too_large`, `:filename_too_long`, or `:empty_filename`.
  """
  def validate_upload(filename, _size_bytes) when not is_binary(filename) do
    {:error, :invalid_filename}
  end

  def validate_upload(filename, size_bytes)
      when is_binary(filename) and is_integer(size_bytes) do
    basename =
      filename
      |> Path.basename()
      |> String.trim()

    normalized = normalize_filename(filename)

    cond do
      basename == "" ->
        {:error, :empty_filename}

      String.length(basename) > @max_filename_length ->
        {:error, :filename_too_long}

      not photo?(normalized) and not video?(normalized) ->
        {:error, :unsupported_type}

      video?(normalized) and size_bytes > max_video_bytes() ->
        {:error, :video_too_large}

      photo?(normalized) and size_bytes > max_photo_bytes() ->
        {:error, :photo_too_large}

      size_bytes < 0 ->
        {:error, :invalid_size}

      true ->
        :ok
    end
  end

  @doc "Human-readable error message for a validation reason atom."
  def error_message(:photo_too_large),
    do: "Photos must be 200 MB or smaller."

  def error_message(:video_too_large),
    do: "Videos must be 20 GB or smaller."

  def error_message(:file_too_large),
    do: "File exceeds the maximum allowed size."

  def error_message(:filename_too_long),
    do: "File name is too long (max 255 characters)."

  def error_message(:empty_filename),
    do: "File name is required."

  def error_message(:unsupported_type),
    do: "File type is not supported."

  def error_message(:album_title_too_long),
    do: "Album title is too long."

  def error_message(reason),
    do: "Invalid upload (#{reason})."
end
