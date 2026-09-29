defmodule Mix.Tasks.StripStaticImageMetadata do
  @moduledoc """
  Strips EXIF, IPTC, XMP and text metadata from raster images under priv/static.
  Color profiles (ICC) are preserved for correct color rendering.

  Stripping is lossless: metadata chunks/segments are removed from the
  container (JPEG APP1/APP13 segments, WebP `EXIF`/`XMP ` chunks, PNG
  `eXIf`/`tEXt`/`zTXt`/`iTXt` chunks) and the pixel data is copied byte for
  byte. Decoding and re-encoding would add generational loss on every build
  and, for already-optimized WebP/JPEG files, make them larger. Files without
  metadata are left untouched, and files that cannot be parsed are skipped
  with a warning.

  Run as part of assets.build and assets.deploy.

  ## Usage

      mix strip_static_image_metadata
  """
  use Mix.Task

  import Bitwise

  @shortdoc "Strip EXIF/metadata from static raster images"
  @raster_extensions [".jpg", ".jpeg", ".png", ".webp"]

  # WebP VP8X feature flags for the EXIF and XMP chunks
  @vp8x_exif_flag 0x08
  @vp8x_xmp_flag 0x04

  # Chunks that carry the actual image (still, lossless, or animated)
  @webp_image_chunks ["VP8 ", "VP8L", "ANIM"]

  @png_signature <<137, "PNG", 13, 10, 26, 10>>
  @png_metadata_chunks ["eXIf", "tEXt", "zTXt", "iTXt"]

  @impl Mix.Task
  def run(_args) do
    static_dir = Path.join(File.cwd!(), "priv/static")

    if File.dir?(static_dir) do
      strip_images_in_dir(static_dir)
    else
      Mix.shell().info("No priv/static directory, skipping.")
      :ok
    end
  end

  @doc """
  Removes metadata from an encoded image binary without re-encoding it.

  `ext` is the lowercase file extension (e.g. `".webp"`). Returns
  `{:ok, stripped}` when metadata was removed, `:unchanged` when there was
  none, or `{:error, reason}` when the file is not a well-formed image of
  that type.
  """
  @spec strip(binary(), String.t()) ::
          {:ok, binary()} | :unchanged | {:error, atom()}
  def strip(data, ext) when ext in [".jpg", ".jpeg"], do: strip_jpeg(data)
  def strip(data, ".webp"), do: strip_webp(data)
  def strip(data, ".png"), do: strip_png(data)
  def strip(_data, _ext), do: {:error, :unsupported_format}

  defp strip_images_in_dir(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.each(entries, fn entry ->
          path = Path.join(dir, entry)

          cond do
            File.dir?(path) -> strip_images_in_dir(path)
            raster_file?(path) -> strip_file(path)
            true -> :ok
          end
        end)

      {:error, _} ->
        :ok
    end
  end

  defp raster_file?(path) do
    # Skip our own temp files (e.g. foo.strip_tmp.png)
    not String.contains?(path, ".strip_tmp") and
      extension(path) in @raster_extensions
  end

  defp extension(path), do: path |> Path.extname() |> String.downcase()

  defp strip_file(path) do
    with {:ok, data} <- File.read(path),
         {:ok, stripped} <- strip(data, extension(path)) do
      replace_file(path, data, stripped)
    else
      :unchanged ->
        :ok

      {:error, reason} ->
        Mix.shell().error("  ✗ Skipped #{path}: #{inspect(reason)}")
    end
  end

  # Writes to a temp file then renames, so a failure never leaves a partial
  # image. Errors are logged and skipped rather than aborting the asset build.
  defp replace_file(path, original, stripped) do
    tmp = Path.rootname(path) <> ".strip_tmp" <> Path.extname(path)

    with :ok <- File.write(tmp, stripped),
         :ok <- File.rename(tmp, path) do
      Mix.shell().info(
        "  ✓ Stripped metadata: #{path} (#{byte_size(original)} → #{byte_size(stripped)} bytes)"
      )
    else
      {:error, reason} ->
        _ = File.rm(tmp)
        Mix.shell().error("  ✗ Skipped #{path}: #{inspect(reason)}")
    end
  end

  # JPEG: drop APP1 (EXIF, XMP) and APP13 (IPTC/Photoshop) segments before the
  # start-of-scan marker; everything from SOS on is entropy-coded data we copy.

  defp strip_jpeg(<<0xFF, 0xD8, rest::binary>>),
    do: strip_jpeg_segments(rest, [<<0xFF, 0xD8>>], false)

  defp strip_jpeg(_data), do: {:error, :invalid_jpeg}

  defp strip_jpeg_segments(<<0xFF, 0xDA, _::binary>> = scan, acc, stripped?) do
    cond do
      not Enum.any?(acc, &jpeg_frame_header?/1) -> {:error, :invalid_jpeg}
      not jpeg_scan_complete?(scan) -> {:error, :invalid_jpeg}
      stripped? -> {:ok, IO.iodata_to_binary(Enum.reverse([scan | acc]))}
      true -> :unchanged
    end
  end

  # Fill bytes: any marker may be preceded by extra 0xFF padding.
  defp strip_jpeg_segments(<<0xFF, 0xFF, rest::binary>>, acc, stripped?),
    do: strip_jpeg_segments(<<0xFF, rest::binary>>, acc, stripped?)

  defp strip_jpeg_segments(
         <<0xFF, marker, length::16, rest::binary>>,
         acc,
         stripped?
       )
       when length >= 2 and byte_size(rest) >= length - 2 do
    payload_size = length - 2
    <<payload::binary-size(^payload_size), rest::binary>> = rest

    if marker in [0xE1, 0xED] do
      strip_jpeg_segments(rest, acc, true)
    else
      segment = <<0xFF, marker, length::16, payload::binary>>
      strip_jpeg_segments(rest, [segment | acc], stripped?)
    end
  end

  defp strip_jpeg_segments(_data, _acc, _stripped?),
    do: {:error, :invalid_jpeg}

  # SOFn markers (0xC0-0xCF) except DHT (C4), JPG (C8) and DAC (CC).
  defp jpeg_frame_header?(<<0xFF, marker, _::binary>>),
    do: marker in 0xC0..0xCF and marker not in [0xC4, 0xC8, 0xCC]

  defp jpeg_frame_header?(_segment), do: false

  # SOS header, then entropy-coded data, then EOI. 0xFF bytes inside scan data
  # are always stuffed or restart markers, so FF D9 can only be EOI.
  defp jpeg_scan_complete?(<<0xFF, 0xDA, length::16, rest::binary>>)
       when byte_size(rest) > length do
    header_size = length - 2
    <<_header::binary-size(^header_size), scan_data::binary>> = rest

    case :binary.match(scan_data, <<0xFF, 0xD9>>) do
      {pos, 2} -> pos > 0
      :nomatch -> false
    end
  end

  defp jpeg_scan_complete?(_scan), do: false

  # WebP: drop the EXIF and XMP RIFF chunks and clear their VP8X feature flags.

  defp strip_webp(<<"RIFF", size::little-32, "WEBP", body::binary>>)
       when size == byte_size(body) + 4 do
    with {:ok, chunks} <- parse_riff_chunks(body, []),
         :ok <- validate_webp(chunks) do
      kept =
        Enum.reject(chunks, fn {fourcc, _} -> fourcc in ["EXIF", "XMP "] end)

      if length(kept) == length(chunks) do
        :unchanged
      else
        body =
          kept
          |> Enum.map(&clear_vp8x_metadata_flags/1)
          |> Enum.map(&riff_chunk/1)

        body = IO.iodata_to_binary(body)
        {:ok, <<"RIFF", byte_size(body) + 4::little-32, "WEBP", body::binary>>}
      end
    end
  end

  defp strip_webp(_data), do: {:error, :invalid_webp}

  defp validate_webp(chunks) do
    if Enum.any?(chunks, fn {fourcc, _} -> fourcc in @webp_image_chunks end),
      do: :ok,
      else: {:error, :invalid_webp}
  end

  defp parse_riff_chunks(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_riff_chunks(
         <<fourcc::binary-4, size::little-32, rest::binary>>,
         acc
       )
       when byte_size(rest) >= size do
    <<data::binary-size(^size), rest::binary>> = rest

    # Chunks are padded to an even size; tolerate a missing pad byte at EOF.
    rest =
      case {rem(size, 2), rest} do
        {1, <<_pad, rest::binary>>} -> rest
        _ -> rest
      end

    parse_riff_chunks(rest, [{fourcc, data} | acc])
  end

  defp parse_riff_chunks(_data, _acc), do: {:error, :invalid_webp}

  defp clear_vp8x_metadata_flags({"VP8X", <<flags, rest::binary>>}) do
    {"VP8X",
     <<band(flags, bnot(@vp8x_exif_flag ||| @vp8x_xmp_flag)), rest::binary>>}
  end

  defp clear_vp8x_metadata_flags(chunk), do: chunk

  defp riff_chunk({fourcc, data}) do
    pad = if rem(byte_size(data), 2) == 1, do: <<0>>, else: <<>>
    [fourcc, <<byte_size(data)::little-32>>, data, pad]
  end

  # PNG: drop EXIF and textual chunks (XMP lives in iTXt). iCCP is kept.

  defp strip_png(<<@png_signature, body::binary>>) do
    with {:ok, chunks, trailer} <- parse_png_chunks(body, []),
         :ok <- validate_png(chunks) do
      kept =
        Enum.reject(chunks, fn {type, _raw} -> type in @png_metadata_chunks end)

      if length(kept) == length(chunks) do
        :unchanged
      else
        raw = Enum.map(kept, fn {_type, raw} -> raw end)
        {:ok, IO.iodata_to_binary([@png_signature, raw, trailer])}
      end
    end
  end

  defp strip_png(_data), do: {:error, :invalid_png}

  defp validate_png([{"IHDR", _} | _] = chunks) do
    if Enum.any?(chunks, &match?({"IDAT", _}, &1)),
      do: :ok,
      else: {:error, :invalid_png}
  end

  defp validate_png(_chunks), do: {:error, :invalid_png}

  defp parse_png_chunks(
         <<length::32, type::binary-4, rest::binary>> = data,
         acc
       )
       when byte_size(rest) >= length + 4 do
    chunk_size = length + 12
    <<raw::binary-size(^chunk_size), rest::binary>> = data
    acc = [{type, raw} | acc]

    if type == "IEND",
      do: {:ok, Enum.reverse(acc), rest},
      else: parse_png_chunks(rest, acc)
  end

  defp parse_png_chunks(_data, _acc), do: {:error, :invalid_png}
end
