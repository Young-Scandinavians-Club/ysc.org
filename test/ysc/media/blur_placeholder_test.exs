defmodule Ysc.Media.BlurPlaceholderTest do
  use ExUnit.Case, async: true

  alias Ysc.Media.BlurPlaceholder

  @hash "LlMF%n00%#MwS|WCWEM{R*bbWBbH"

  defp decode_png("data:image/png;base64," <> encoded) do
    png = Base.decode64!(encoded)
    <<137, 80, 78, 71, 13, 10, 26, 10, rest::binary>> = png
    chunks(rest, [])
  end

  defp chunks(<<>>, acc), do: Enum.reverse(acc)

  defp chunks(
         <<len::32, type::binary-size(4), data::binary-size(len), crc::32,
           rest::binary>>,
         acc
       ) do
    assert crc == :erlang.crc32(type <> data)
    chunks(rest, [{type, data} | acc])
  end

  test "builds a valid 16x16 RGB PNG" do
    chunks = @hash |> BlurPlaceholder.data_uri() |> decode_png()

    assert [{"IHDR", ihdr}, {"IDAT", idat}, {"IEND", ""}] = chunks
    assert <<16::32, 16::32, 8, 2, 0, 0, 0>> = ihdr

    # 16 rows, each a filter byte plus 16 RGB pixels.
    assert idat |> :zlib.uncompress() |> byte_size() == 16 * (1 + 16 * 3)
  end

  test "the same hash always gives the same placeholder" do
    assert BlurPlaceholder.data_uri(@hash) == BlurPlaceholder.data_uri(@hash)
  end

  test "has no placeholder for a missing or malformed hash" do
    assert BlurPlaceholder.data_uri(nil) == nil
    assert BlurPlaceholder.data_uri("") == nil
    assert BlurPlaceholder.data_uri("not a blur hash") == nil
  end
end
