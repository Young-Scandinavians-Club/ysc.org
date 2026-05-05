defmodule YscWeb.Workers.ImageProcessor do
  @moduledoc """
  Oban worker for processing and optimizing images.

  Handles image transformations, resizing, and optimization tasks asynchronously.
  """
  require Ysc.Logging

  use Oban.Worker, queue: :media

  alias Ysc.Http.UrlFetchGuard
  alias Ysc.Media
  alias YscWeb.Validators.FileValidator

  @temp_dir "/tmp/image_processor"
  @download_timeout_ms 120_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id} = _args}) do
    image = Media.fetch_image(id)

    if is_nil(image) do
      Ysc.Logging.warning("Image not found", image_id: id)
      {:error, "Image not found"}
    else
      tmp_output_file = "#{@temp_dir}/#{image.id}"
      # Format will be determined dynamically in process_image_upload
      # Use placeholder extensions - they'll be corrected by the processing function
      optimized_output_path = "#{tmp_output_file}_optimized"
      thumbnail_output_path = "#{tmp_output_file}_thumb"

      Ysc.Logging.info(tmp_output_file)
      Ysc.Logging.info(optimized_output_path)
      Ysc.Logging.info(thumbnail_output_path)

      make_temp_dir(@temp_dir)

      Ysc.Logging.info("Started work on Image: #{image.id}")

      try do
        # Start working on this image
        Media.set_image_processing_state(image, :processing)

        case download_raw_to_temp(image, tmp_output_file) do
          {:error, _} = err ->
            err

          :ok ->
            # Validate file MIME type before processing (security check for external uploads)
            case FileValidator.validate_image(tmp_output_file, [
                   ".jpg",
                   ".jpeg",
                   ".png",
                   ".gif",
                   ".webp"
                 ]) do
              {:ok, _mime_type} ->
                :ok

              {:error, reason} ->
                Ysc.Logging.error(
                  "Image validation failed for #{image.id}: #{reason}"
                )

                Media.set_image_processing_state(image, :failed)
                raise "File validation failed: #{reason}"
            end

            result =
              Media.process_image_upload(
                image,
                tmp_output_file,
                thumbnail_output_path,
                optimized_output_path
              )

            # Strip EXIF/metadata from raw and overwrite on S3 so the raw URL also serves clean bytes
            strip_and_replace_raw_on_s3(image, tmp_output_file)

            Ysc.Logging.info(
              "Image processing completed successfully for: #{image.id}"
            )

            Ysc.Logging.info("Result: #{inspect(result)}")

            # Get the actual file paths with correct extensions for cleanup
            # The process_image_upload function will have set the correct extensions
            # We need to detect them from the uploaded paths or use a pattern
            _optimized_path =
              find_file_with_pattern("#{tmp_output_file}_optimized")

            _thumbnail_path = find_file_with_pattern("#{tmp_output_file}_thumb")

            {:ok, result}
        end
      rescue
        e ->
          Ysc.Logging.error(
            "Image processing failed for #{image.id}: #{inspect(e)}"
          )

          Ysc.Logging.error("Error type: #{inspect(e.__struct__)}")
          Ysc.Logging.error("Stacktrace:")
          Ysc.Logging.error(Exception.format_stacktrace(__STACKTRACE__))

          # Update image state to failed
          try do
            Media.set_image_processing_state(image, :failed)
          rescue
            _ -> :ok
          end

          {:error, e}
      catch
        kind, reason ->
          Ysc.Logging.error(
            "Image processing caught error for #{image.id}: #{inspect(kind)}, #{inspect(reason)}"
          )

          Ysc.Logging.error("Stacktrace:")
          Ysc.Logging.error(Exception.format_stacktrace(__STACKTRACE__))

          # Update image state to failed
          try do
            Media.set_image_processing_state(image, :failed)
          rescue
            _ -> :ok
          end

          {:error, {kind, reason}}
      after
        Ysc.Logging.info("Cleaning up generated files")
        # Clean up files - try multiple possible extensions
        cleanup_file(tmp_output_file)
        cleanup_file_with_extensions("#{tmp_output_file}_optimized")
        cleanup_file_with_extensions("#{tmp_output_file}_thumb")
        cleanup_file_with_extensions("#{tmp_output_file}.stripped")
      end
    end
  end

  defp download_raw_to_temp(%Media.Image{} = image, dest_path) do
    url = image.raw_image_path

    case UrlFetchGuard.validate_url_for_server_fetch(url) do
      {:error, reason} ->
        Ysc.Logging.warning(
          "ImageProcessor: blocked or invalid raw_image URL",
          image_id: image.id,
          reason: reason
        )

        Media.set_image_processing_state(image, :failed)
        {:error, {:url_not_allowed, reason}}

      :ok ->
        case Req.get(url,
               into: dest_path,
               receive_timeout: @download_timeout_ms,
               max_redirects: 5,
               retry: false
             ) do
          {:ok, %Req.Response{status: status}} when status in 200..299 ->
            :ok

          {:ok, %Req.Response{status: status}} ->
            Ysc.Logging.warning(
              "ImageProcessor: raw image download returned non-success status",
              image_id: image.id,
              status: status
            )

            Media.set_image_processing_state(image, :failed)
            {:error, {:http_status, status}}

          {:error, exception} ->
            Ysc.Logging.warning(
              "ImageProcessor: raw image download failed",
              image_id: image.id,
              reason: Exception.message(exception)
            )

            Media.set_image_processing_state(image, :failed)
            {:error, {:download_failed, exception}}
        end
    end
  end

  # Strip EXIF/metadata from the raw file and upload to S3 at the same key (overwrite).
  # So the raw URL serves metadata-free bytes and load times/privacy improve.
  defp strip_and_replace_raw_on_s3(image, raw_path) do
    with raw_key when is_binary(raw_key) <- raw_key_from_image(image),
         ext when ext != "" <- Path.extname(raw_path),
         stripped_path <- raw_path <> ".stripped" <> ext,
         {:ok, parsed} <- Image.open(raw_path),
         # Remove EXIF, IPTC, XMP only; keep color profile (ICC)
         {:ok, stripped} <- Image.remove_metadata(parsed, [:exif, :iptc, :xmp]),
         {:ok, _} <- write_stripped_image(stripped, stripped_path, ext),
         _ <- Media.upload_file_to_s3(stripped_path, raw_key) do
      Ysc.Logging.info(
        "Replaced raw S3 object with metadata-stripped version: #{image.id}"
      )
    else
      nil ->
        Ysc.Logging.debug(
          "No S3 key for image #{image.id}, skipping raw replace"
        )

      "" ->
        Ysc.Logging.debug("No extension for raw path, skipping raw replace")

      {:error, reason} ->
        Ysc.Logging.warning(
          "Could not strip/replace raw on S3 for image #{image.id}: #{inspect(reason)}"
        )
    end
  end

  defp write_stripped_image(stripped, path, ext) do
    opts =
      case String.downcase(ext) do
        ".jpg" -> [quality: 90]
        ".jpeg" -> [quality: 90]
        ".webp" -> [quality: 90]
        _ -> []
      end

    Image.write(stripped, path, opts)
  end

  defp raw_key_from_image(image) do
    case image.upload_data do
      %{key: k} when is_binary(k) -> k
      %{"key" => k} when is_binary(k) -> k
      _ -> key_from_object_url(image.raw_image_path)
    end
  end

  defp key_from_object_url(url) when is_binary(url) do
    path = URI.parse(url).path || ""
    key = path |> String.trim_leading("/") |> URI.decode()
    if key != "", do: key, else: nil
  end

  # Find file with any image extension
  defp find_file_with_pattern(base_path) do
    extensions = [".jpg", ".jpeg", ".png", ".webp"]

    Enum.find_value(extensions, fn ext ->
      path = "#{base_path}#{ext}"
      if File.exists?(path), do: path, else: nil
    end)
  end

  # Clean up a file if it exists
  # sobelow_skip ["Traversal.FileModule"]
  defp cleanup_file(path) do
    if File.exists?(path), do: File.rm(path)
  end

  # Clean up file with any possible extension
  # sobelow_skip ["Traversal.FileModule"]
  defp cleanup_file_with_extensions(base_path) do
    extensions = [".jpg", ".jpeg", ".png", ".webp"]

    Enum.each(extensions, fn ext ->
      path = "#{base_path}#{ext}"
      if File.exists?(path), do: File.rm(path)
    end)
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp make_temp_dir(path) do
    File.mkdir(path)
  end
end
