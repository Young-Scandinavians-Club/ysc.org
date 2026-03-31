defmodule YscWeb.Workers.AvatarProcessor do
  @moduledoc """
  Oban worker for processing avatar images.

  Downloads the raw upload from S3, strips metadata, generates three square-cropped
  WebP variants (50x50, 200x200, 500x500), uploads them back to S3, and updates the
  avatar record. If the user has no current avatar, sets this one automatically.
  """
  require Ysc.Logging

  use Oban.Worker, queue: :media

  alias Ysc.Avatars
  alias Ysc.S3Config

  @temp_dir "/tmp/avatar_processor"
  @thumb_size 50
  @profile_size 200
  @large_size 500
  @webp_quality 85

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id}}) do
    avatar = Avatars.get_avatar(id)

    if is_nil(avatar) do
      Ysc.Logging.warning("Avatar not found", extra: %{avatar_id: id})
      {:error, "Avatar not found"}
    else
      process_avatar(avatar)
    end
  end

  defp process_avatar(avatar) do
    ensure_temp_dir()
    base = Path.join(@temp_dir, avatar.id)
    raw_path = "#{base}_raw"

    try do
      Avatars.set_processing_state(avatar, :processing)

      download_from_url!(avatar.original_path, raw_path)

      {:ok, parsed} = Image.open(raw_path)
      {:ok, clean} = Image.remove_metadata(parsed, [:exif, :iptc, :xmp])

      stripped_path = "#{base}_stripped.webp"
      Image.write(clean, stripped_path, quality: @webp_quality)

      # Re-upload stripped original
      original_key = key_from_url(avatar.original_path)

      if original_key do
        Avatars.upload_to_s3(stripped_path, original_key,
          content_type: "image/webp"
        )
      end

      stripped_url =
        if original_key do
          S3Config.object_url(original_key, S3Config.avatars_bucket_name())
        else
          avatar.original_path
        end

      # Generate square-cropped variants
      {:ok, square} = crop_to_square(clean)

      thumb_path = "#{base}_thumb.webp"
      profile_path = "#{base}_profile.webp"
      large_path = "#{base}_large.webp"

      {:ok, thumb} = Image.thumbnail(square, @thumb_size)
      Image.write(thumb, thumb_path, quality: @webp_quality)

      {:ok, profile} = Image.thumbnail(square, @profile_size)
      Image.write(profile, profile_path, quality: @webp_quality)

      {:ok, large} = Image.thumbnail(square, @large_size)
      Image.write(large, large_path, quality: @webp_quality)

      # Upload variants to S3
      user_id = avatar.user_id
      avatar_id = avatar.id

      {:ok, thumb_url} =
        Avatars.upload_to_s3(thumb_path, "#{user_id}/#{avatar_id}/thumb.webp",
          content_type: "image/webp"
        )

      {:ok, profile_url} =
        Avatars.upload_to_s3(
          profile_path,
          "#{user_id}/#{avatar_id}/profile.webp",
          content_type: "image/webp"
        )

      {:ok, large_url} =
        Avatars.upload_to_s3(large_path, "#{user_id}/#{avatar_id}/large.webp",
          content_type: "image/webp"
        )

      {:ok, updated_avatar} =
        Avatars.update_processed_avatar(avatar, %{
          original_path: stripped_url,
          thumb_path: thumb_url,
          profile_path: profile_url,
          large_path: large_url,
          processing_state: :completed
        })

      maybe_set_as_current(updated_avatar)
      Avatars.broadcast_avatar_processed(avatar.user_id)

      Ysc.Logging.info("Avatar processing completed: #{avatar.id}")

      :ok
    rescue
      e ->
        Ysc.Logging.error(
          "Avatar processing failed for #{avatar.id}: #{inspect(e)}",
          error: e,
          stacktrace: __STACKTRACE__
        )

        try do
          Avatars.set_processing_state(avatar, :failed)
        rescue
          _ -> :ok
        end

        try do
          Avatars.broadcast_avatar_processed(avatar.user_id)
        rescue
          _ -> :ok
        end

        {:error, e}
    after
      cleanup_files(base)
    end
  end

  defp crop_to_square(image) do
    width = Image.width(image)
    height = Image.height(image)

    if width == height do
      {:ok, image}
    else
      size = min(width, height)
      x_offset = div(width - size, 2)
      y_offset = div(height - size, 2)
      Image.crop(image, x_offset, y_offset, size, size)
    end
  end

  defp maybe_set_as_current(avatar) do
    user = Ysc.Accounts.get_user!(avatar.user_id)

    if avatar.source == :upload || is_nil(user.current_avatar_id) do
      Avatars.set_current_avatar(user, avatar.id)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp download_from_url!(url, dest_path) do
    case Req.get(url, max_redirects: 5, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        File.write!(dest_path, body)

      {:ok, %Req.Response{status: status}} ->
        raise "Avatar download failed: HTTP #{status} for #{url}"

      {:error, reason} ->
        raise "Avatar download failed: #{inspect(reason)} for #{url}"
    end
  end

  defp key_from_url(url) when is_binary(url) do
    path = URI.parse(url).path || ""
    key = path |> String.trim_leading("/") |> URI.decode()
    if key != "", do: key, else: nil
  end

  defp key_from_url(_), do: nil

  # sobelow_skip ["Traversal.FileModule"]
  defp ensure_temp_dir do
    File.mkdir_p(@temp_dir)
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp cleanup_files(base) do
    suffixes = [
      "_raw",
      "_stripped.webp",
      "_thumb.webp",
      "_profile.webp",
      "_large.webp"
    ]

    Enum.each(suffixes, fn suffix ->
      path = "#{base}#{suffix}"
      if File.exists?(path), do: File.rm(path)
    end)
  end
end
