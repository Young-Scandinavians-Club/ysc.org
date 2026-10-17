defmodule Ysc.Media.BlurPlaceholder do
  @moduledoc """
  Turns a stored blur hash into a tiny PNG data URI that can be used as a CSS
  background from the very first byte of HTML.

  The `BlurHashCanvas` hook paints the same hash, but only once LiveView has
  connected, so until then the image slot is an empty box. A server-rendered
  placeholder fills that gap.
  """

  @size 16

  @doc "A `data:image/png;base64,...` URI for `blur_hash`, or `nil` if it is missing or invalid."
  @spec data_uri(String.t() | nil) :: String.t() | nil
  def data_uri(blur_hash) when is_binary(blur_hash) do
    pixels = BlurHash.decode(blur_hash, @size, @size)
    "data:image/png;base64," <> Base.encode64(png(@size, @size, pixels))
  rescue
    # A malformed hash must never break the page; the box just stays plain.
    _ -> nil
  end

  def data_uri(_), do: nil

  # Minimal PNG: 8-bit RGB, no interlace, filter 0 on every row.
  defp png(width, height, pixels) do
    rows =
      pixels
      |> Enum.chunk_every(width * 3)
      |> Enum.map(&[0, &1])

    raw = rows |> IO.iodata_to_binary()

    [
      <<137, 80, 78, 71, 13, 10, 26, 10>>,
      chunk("IHDR", <<width::32, height::32, 8, 2, 0, 0, 0>>),
      chunk("IDAT", :zlib.compress(raw)),
      chunk("IEND", <<>>)
    ]
    |> IO.iodata_to_binary()
  end

  defp chunk(type, data) do
    body = type <> data
    <<byte_size(data)::32, body::binary, :erlang.crc32(body)::32>>
  end
end
