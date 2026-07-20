defmodule Ysc.Media.ImageOps do
  @moduledoc """
  Shared image operation helpers.
  """

  @blur_hash_target_width 32

  @spec autorotate(Vix.Vips.Image.t()) ::
          {:ok, Vix.Vips.Image.t()} | {:error, term()}
  def autorotate(image) do
    case Image.autorotate(image) do
      {:ok, {%Vix.Vips.Image{} = oriented, _orientation}} -> {:ok, oriented}
      {:error, _} = error -> error
    end
  end

  @doc """
  Generates a BlurHash string from an image file.

  Downscales to #{@blur_hash_target_width}px on the longest side before encoding,
  matching the BlurHash algorithm's recommendation.
  """
  @spec blur_hash_from_path(Path.t(), pos_integer(), pos_integer()) ::
          {:ok, String.t()} | {:error, term()}
  def blur_hash_from_path(path, comp_x, comp_y) do
    with {:ok, image} <- Image.open(path),
         {:ok, thumbnail} <- Image.thumbnail(image, @blur_hash_target_width),
         {:ok, rows} <- Image.to_list(thumbnail) do
      width = Image.width(thumbnail)
      height = Image.height(thumbnail)

      pixels =
        rows
        |> Enum.concat()
        |> Enum.flat_map(&rgb_triplet/1)

      {:ok, BlurHash.encode(pixels, width, height, comp_x, comp_y)}
    end
  end

  defp rgb_triplet([r, g, b]), do: [r, g, b]
  defp rgb_triplet([r, g, b, _alpha]), do: [r, g, b]
end
