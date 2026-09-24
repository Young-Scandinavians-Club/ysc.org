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
