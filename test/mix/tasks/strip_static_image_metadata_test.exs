defmodule Mix.Tasks.StripStaticImageMetadataTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.StripStaticImageMetadata
  alias Vix.Vips.Image, as: VipsImage
  alias Vix.Vips.MutableImage

  @xmp ~s(<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"/></x:xmpmeta>)

  describe "strip/2" do
    for ext <- [".webp", ".jpg", ".png"] do
      test "removes XMP from #{ext} without touching pixels" do
        original = encode_with_xmp(unquote(ext))
        assert metadata_fields(original) != []

        assert {:ok, stripped} =
                 StripStaticImageMetadata.strip(original, unquote(ext))

        assert byte_size(stripped) < byte_size(original)
        assert metadata_fields(stripped) == []
        assert pixels(stripped) == pixels(original)
      end

      test "is idempotent for #{ext}" do
        {:ok, stripped} =
          StripStaticImageMetadata.strip(
            encode_with_xmp(unquote(ext)),
            unquote(ext)
          )

        assert StripStaticImageMetadata.strip(stripped, unquote(ext)) ==
                 :unchanged
      end
    end

    test "rejects data that does not match the extension" do
      png = encode_with_xmp(".png")

      assert {:error, :invalid_webp} =
               StripStaticImageMetadata.strip(png, ".webp")

      assert {:error, :invalid_jpeg} =
               StripStaticImageMetadata.strip(png, ".jpg")

      assert {:error, :invalid_png} =
               StripStaticImageMetadata.strip("nope", ".png")
    end

    test "rejects truncated files" do
      webp = encode_with_xmp(".webp")
      truncated = binary_part(webp, 0, byte_size(webp) - 20)

      assert {:error, :invalid_webp} =
               StripStaticImageMetadata.strip(truncated, ".webp")
    end

    test "rejects a JPEG whose scan has no end-of-image marker" do
      jpeg = encode_with_xmp(".jpg")
      no_eoi = binary_part(jpeg, 0, byte_size(jpeg) - 2)

      assert {:error, :invalid_jpeg} =
               StripStaticImageMetadata.strip(no_eoi, ".jpg")
    end

    test "rejects a JPEG with no frame header before the scan" do
      xmp = "http://ns.adobe.com/xap/1.0/" <> <<0>> <> @xmp
      sos_header = <<1, 1, 0, 0, 63, 0>>

      jpeg =
        <<0xFF, 0xD8, 0xFF, 0xE1, byte_size(xmp) + 2::16, xmp::binary, 0xFF,
          0xDA, byte_size(sos_header) + 2::16, sos_header::binary, 1, 2, 3,
          0xFF, 0xD9>>

      assert {:error, :invalid_jpeg} =
               StripStaticImageMetadata.strip(jpeg, ".jpg")
    end

    test "rejects a WebP whose RIFF size does not match the file" do
      webp = encode_with_xmp(".webp") <> <<0, 0>>

      assert {:error, :invalid_webp} =
               StripStaticImageMetadata.strip(webp, ".webp")
    end

    test "rejects a WebP with no image chunk" do
      xmp_chunk = <<"XMP ", byte_size(@xmp)::little-32, @xmp::binary>>

      xmp_chunk =
        if rem(byte_size(@xmp), 2) == 1, do: xmp_chunk <> <<0>>, else: xmp_chunk

      webp =
        <<"RIFF", byte_size(xmp_chunk) + 4::little-32, "WEBP",
          xmp_chunk::binary>>

      assert {:error, :invalid_webp} =
               StripStaticImageMetadata.strip(webp, ".webp")
    end

    test "rejects a PNG without IHDR first or without IDAT" do
      <<signature::binary-8, ihdr::binary-25, _::binary>> =
        png = encode_with_xmp(".png")

      iend = binary_part(png, byte_size(png) - 12, 12)
      text = png_chunk("tEXt", "Comment" <> <<0>> <> "hi")

      assert {:error, :invalid_png} =
               StripStaticImageMetadata.strip(
                 signature <> ihdr <> text <> iend,
                 ".png"
               )

      assert {:error, :invalid_png} =
               StripStaticImageMetadata.strip(signature <> text <> iend, ".png")
    end
  end

  defp png_chunk(type, data) do
    crc = :erlang.crc32(type <> data)
    <<byte_size(data)::32, type::binary, data::binary, crc::32>>
  end

  defp encode_with_xmp(ext) do
    {:ok, image} =
      Image.new!(16, 16, color: [200, 40, 40])
      |> VipsImage.mutate(fn mut ->
        MutableImage.set(mut, "xmp-data", :VipsBlob, @xmp)
      end)

    {:ok, binary} = Image.write(image, :memory, suffix: ext)
    binary
  end

  defp metadata_fields(binary) do
    {:ok, image} = Image.from_binary(binary)
    {:ok, fields} = VipsImage.header_field_names(image)
    Enum.filter(fields, &(&1 in ["exif-data", "xmp-data", "iptc-data"]))
  end

  defp pixels(binary) do
    {:ok, image} = Image.from_binary(binary)
    {:ok, pixels} = VipsImage.write_to_binary(image)
    pixels
  end
end
