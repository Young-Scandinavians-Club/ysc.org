defmodule Mix.Tasks.StripStaticImageMetadata do
  @moduledoc """
  Strips EXIF, IPTC, and XMP metadata from raster images under priv/static.
  Color profiles (ICC) are preserved for correct color rendering.

  Improves load times and privacy by removing unnecessary metadata from
  production assets (e.g. video poster images, any committed images).
  Run as part of assets.build and assets.deploy.

  ## Usage

      mix strip_static_image_metadata
  """
  use Mix.Task

  @shortdoc "Strip EXIF/metadata from static raster images"
  @raster_extensions [".jpg", ".jpeg", ".png", ".webp", ".gif"]

  @impl Mix.Task
  def run(_args) do
    # Ensure Image library is available (it's a compile-time dependency)
    _ = Application.ensure_all_started(:image)

    static_dir = Path.join(File.cwd!(), "priv/static")

    if File.dir?(static_dir) do
      strip_images_in_dir(static_dir)
    else
      Mix.shell().info("No priv/static directory, skipping.")
      :ok
    end
  end

  defp strip_images_in_dir(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.each(fn entry ->
          path = Path.join(dir, entry)

          cond do
            File.dir?(path) ->
              strip_images_in_dir(path)

            raster_file?(path) ->
              strip_metadata(path)

            true ->
              :ok
          end
        end)

      {:error, _} ->
        :ok
    end
  end

  defp raster_file?(path) do
    # Skip our own temp files (e.g. foo.strip_tmp.png)
    ext = Path.extname(path) |> String.downcase()
    not String.contains?(path, ".strip_tmp") and ext in @raster_extensions
  end

  defp strip_metadata(path) do
    case Image.open(path) do
      {:ok, img} ->
        # Remove EXIF, IPTC, XMP only; keep color profile (ICC) for correct rendering
        case Image.remove_metadata(img, [:exif, :iptc, :xmp]) do
          {:ok, stripped} ->
            # Write to temp file (same extension so Image knows format) then rename
            ext = Path.extname(path)
            base = Path.rootname(path)
            tmp = base <> ".strip_tmp" <> ext
            write_opts = write_options(path)

            case Image.write(stripped, tmp, write_opts) do
              {:ok, _image} ->
                File.rename!(tmp, path)
                Mix.shell().info("  ✓ Stripped metadata: #{path}")
                :ok

              {:error, reason} ->
                if File.exists?(tmp), do: File.rm(tmp)

                Mix.shell().error(
                  "  ✗ Failed to write #{path}: #{inspect(reason)}"
                )

                :error
            end

          {:error, reason} ->
            Mix.shell().error("  ✗ Failed to strip #{path}: #{inspect(reason)}")
            :error
        end

      {:error, reason} ->
        Mix.shell().error("  ✗ Failed to open #{path}: #{inspect(reason)}")
        :error
    end
  end

  defp write_options(path) do
    ext = Path.extname(path) |> String.downcase()

    case ext do
      ".jpg" -> [quality: 90]
      ".jpeg" -> [quality: 90]
      ".png" -> []
      ".webp" -> [quality: 90]
      ".gif" -> []
      _ -> []
    end
  end
end
