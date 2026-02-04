defmodule YscWeb.Workers.ImageProcessor do
  @moduledoc """
  Oban worker for processing and optimizing images.

  Handles image transformations, resizing, and optimization tasks asynchronously.
  """
  require Logger

  use Oban.Worker, queue: :media

  alias HTTP
  alias Ysc.Media
  alias YscWeb.Validators.FileValidator

  @temp_dir "/tmp/image_processor"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id} = _args}) do
    image = Media.fetch_image(id)

    if is_nil(image) do
      Logger.warning("Image not found", image_id: id)
      {:error, "Image not found"}
    else
      tmp_output_file = "#{@temp_dir}/#{image.id}"
      # Format will be determined dynamically in process_image_upload
      # Use placeholder extensions - they'll be corrected by the processing function
      optimized_output_path = "#{tmp_output_file}_optimized"
      thumbnail_output_path = "#{tmp_output_file}_thumb"

      Logger.info(tmp_output_file)
      Logger.info(optimized_output_path)
      Logger.info(thumbnail_output_path)

      make_temp_dir(@temp_dir)

      Logger.info("Started work on Image: #{image.id}")

      try do
        # Start working on this image
        Media.set_image_processing_state(image, :processing)

        # Download from the internet and cache locally
        {:ok, :saved_to_file} =
          :httpc.request(
            :get,
            {to_charlist(URI.encode(image.raw_image_path)), []},
            [],
            stream: to_charlist(tmp_output_file)
          )

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
            Logger.error("Image validation failed for #{image.id}: #{reason}")
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

        Logger.info("Image processing completed successfully for: #{image.id}")
        Logger.info("Result: #{inspect(result)}")

        # Get the actual file paths with correct extensions for cleanup
        # The process_image_upload function will have set the correct extensions
        # We need to detect them from the uploaded paths or use a pattern
        _optimized_path = find_file_with_pattern("#{tmp_output_file}_optimized")
        _thumbnail_path = find_file_with_pattern("#{tmp_output_file}_thumb")

        {:ok, result}
      rescue
        e ->
          Logger.error("Image processing failed for #{image.id}: #{inspect(e)}")
          Logger.error("Error type: #{inspect(e.__struct__)}")
          Logger.error("Stacktrace:")
          Logger.error(Exception.format_stacktrace(__STACKTRACE__))

          # Update image state to failed
          try do
            Media.set_image_processing_state(image, :failed)
          rescue
            _ -> :ok
          end

          {:error, e}
      catch
        kind, reason ->
          Logger.error(
            "Image processing caught error for #{image.id}: #{inspect(kind)}, #{inspect(reason)}"
          )

          Logger.error("Stacktrace:")
          Logger.error(Exception.format_stacktrace(__STACKTRACE__))

          # Update image state to failed
          try do
            Media.set_image_processing_state(image, :failed)
          rescue
            _ -> :ok
          end

          {:error, {kind, reason}}
      after
        Logger.info("Cleaning up generated files")
        # Clean up files - try multiple possible extensions
        cleanup_file(tmp_output_file)
        cleanup_file_with_extensions("#{tmp_output_file}_optimized")
        cleanup_file_with_extensions("#{tmp_output_file}_thumb")
      end
    end
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
