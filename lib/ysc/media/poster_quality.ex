defmodule Ysc.Media.PosterQuality do
  @moduledoc """
  Programmatic quality checks for event poster (cover) images.

  Posters are rendered in 16:9 frames (event cards, the event page hero and the
  1920×1080 cabin TV posters) with `object-cover`, so an image with another
  aspect ratio is silently cropped, and a small one is upscaled and looks soft.

  These checks only produce *warnings*; nothing here blocks an upload.
  Dimensions are the display dimensions stored on `Ysc.Media.Image` (EXIF
  orientation already applied).
  """

  alias Ysc.Media.Image

  @target_ratio 16 / 9
  # Relative tolerance around 16:9, so 1.78:1 and slightly trimmed exports pass.
  @ratio_tolerance 0.02
  @min_width 1280
  @min_height 720
  @recommended_width 1920
  @recommended_height 1080

  @type issue ::
          {:aspect_ratio, %{width: pos_integer(), height: pos_integer()}}
          | {:low_resolution, %{width: pos_integer(), height: pos_integer()}}

  @doc "Minimum accepted size as `{width, height}` before a warning is raised."
  def min_dimensions, do: {@min_width, @min_height}

  @doc "Recommended poster size as `{width, height}`."
  def recommended_dimensions, do: {@recommended_width, @recommended_height}

  @doc """
  Assesses an image.

  Returns `{:measured, issues}` (an empty list means the poster is fine) or
  `:unmeasured` when the image is missing or has no stored dimensions, in which
  case nothing can be said about it.
  """
  @spec assess(struct() | nil) :: {:measured, [issue()]} | :unmeasured
  def assess(%Image{width: width, height: height})
      when is_integer(width) and is_integer(height) and width > 0 and
             height > 0 do
    {:measured, check(width, height)}
  end

  def assess(_image), do: :unmeasured

  @doc """
  Checks raw pixel dimensions and returns a list of `t:issue/0`.
  """
  @spec check(pos_integer(), pos_integer()) :: [issue()]
  def check(width, height)
      when is_integer(width) and is_integer(height) and width > 0 and
             height > 0 do
    dims = %{width: width, height: height}

    []
    |> add_if(not sixteen_by_nine?(width, height), {:aspect_ratio, dims})
    |> add_if(low_resolution?(width, height), {:low_resolution, dims})
  end

  @doc "True when the dimensions are within tolerance of a 16:9 frame."
  @spec sixteen_by_nine?(pos_integer(), pos_integer()) :: boolean()
  def sixteen_by_nine?(width, height) do
    abs(width / height - @target_ratio) / @target_ratio <= @ratio_tolerance
  end

  @doc "True when the image is smaller than the minimum poster size."
  @spec low_resolution?(pos_integer(), pos_integer()) :: boolean()
  def low_resolution?(width, height) do
    width < @min_width or height < @min_height
  end

  @doc """
  Human-readable `{title, detail}` for an issue, suitable for an admin callout.
  """
  @spec describe(issue()) :: {String.t(), String.t()}
  def describe({:aspect_ratio, %{width: width, height: height}}) do
    {"Not 16:9",
     "This image is #{width}×#{height} (#{format_ratio(width, height)}). " <>
       "Posters are shown in a 16:9 frame, so the edges will be cropped. " <>
       "Crop it to 16:9, ideally #{@recommended_width}×#{@recommended_height}."}
  end

  def describe({:low_resolution, %{width: width, height: height}}) do
    {"Low resolution",
     "This image is only #{width}×#{height}. " <>
       "It will look soft on large screens and on the cabin TVs. " <>
       "Use at least #{@min_width}×#{@min_height}, ideally " <>
       "#{@recommended_width}×#{@recommended_height}."}
  end

  defp format_ratio(width, height) do
    :erlang.float_to_binary(width / height, decimals: 2) <> ":1"
  end

  defp add_if(list, true, issue), do: list ++ [issue]
  defp add_if(list, false, _issue), do: list
end
