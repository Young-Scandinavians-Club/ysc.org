defmodule ULIDColor do
  @moduledoc """
  Utility module for generating colors from ULIDs.

  Provides functions to generate consistent, light pastel colors from ULID strings
  using Tailwind color palettes.
  """
  @doc """
  Generates a light pastel color from a given ULID using the lightest Tailwind colors (*-100).
  """

  def generate_color_from_idx(nil, :dark), do: "#9CA3AF"
  def generate_color_from_idx(nil, _), do: "#F3F4F6"

  def generate_color_from_idx(idx, :dark) do
    palette = [
      # Red-400
      "#F87171",
      # Amber-400
      "#FBBF24",
      # Green-400
      "#4ADE80",
      # Blue-400
      "#60A5FA",
      # Purple-400
      "#A78BFA",
      # Pink-400
      "#FB7185",
      # Yellow-400
      "#FCD34D",
      # Sky-400
      "#38BDF8",
      # Emerald-400
      "#34D399",
      # Indigo-400
      "#818CF8",
      # Rose-400
      "#FB7185",
      # Orange-400
      "#FB923C",
      # Neutral-400
      "#A3A3A3",
      # Cyan-400
      "#22D3EE",
      # Violet-400
      "#C084FC"
    ]

    Enum.at(palette, rem(idx, length(palette)))
  end

  def generate_color_from_idx(idx, _) do
    palette = [
      # Red-100
      "#FEE2E2",
      # Amber-100
      "#FEF9C3",
      # Green-100
      "#DCFCE7",
      # Blue-100
      "#DBEAFE",
      # Purple-100
      "#EDE9FE",
      # Pink-100
      "#FCE7F3",
      # Yellow-100
      "#FEF3C7",
      # Sky-100
      "#E0F2FE",
      # Emerald-100
      "#D1FAE5",
      # Indigo-100
      "#E0E7FF",
      # Rose-100
      "#FDE8E9",
      # Orange-100
      "#FFF7ED",
      # Neutral-100
      "#F3F4F6",
      # Cyan-100
      "#E8F5FF",
      # Violet-100
      "#FAE8FF"
    ]

    Enum.at(palette, rem(idx, length(palette)))
  end

  def generate_color_from_idx(idx), do: generate_color_from_idx(idx, :light)

  def generate_color(nil) do
    # Default to a light gray
    "#F3F4F6"
  end

  def generate_color(ulid) when is_binary(ulid) do
    # Lightest pastel shades from Tailwind's *-100 palette
    palette = [
      # Red-100
      "#FEE2E2",
      # Amber-100
      "#FEF9C3",
      # Green-100
      "#DCFCE7",
      # Blue-100
      "#DBEAFE",
      # Purple-100
      "#EDE9FE",
      # Pink-100
      "#FCE7F3",
      # Yellow-100
      "#FEF3C7",
      # Sky-100
      "#E0F2FE",
      # Emerald-100
      "#D1FAE5",
      # Indigo-100
      "#E0E7FF",
      # Rose-100
      "#FDE8E9",
      # Orange-100
      "#FFF7ED",
      # Neutral-100
      "#F3F4F6",
      # Cyan-100
      "#E8F5FF",
      # Violet-100
      "#FAE8FF"
    ]

    # Hash the ULID using :crypto and take a portion of the hash
    hash = :crypto.hash(:sha256, ulid)
    <<byte, _rest::binary>> = hash

    # Use the byte to index into the palette
    index = rem(byte, length(palette))
    Enum.at(palette, index)
  end

  def generate_darker_color(nil) do
    # Default to a dark gray
    "#9CA3AF"
  end

  def generate_darker_color(ulid) when is_binary(ulid) do
    # Brighter shades from Tailwind's *-400 palette for borders
    palette = [
      # Red-400
      "#F87171",
      # Amber-400
      "#FBBF24",
      # Green-400
      "#4ADE80",
      # Blue-400
      "#60A5FA",
      # Purple-400
      "#A78BFA",
      # Pink-400
      "#FB7185",
      # Yellow-400
      "#FCD34D",
      # Sky-400
      "#38BDF8",
      # Emerald-400
      "#34D399",
      # Indigo-400
      "#818CF8",
      # Rose-400
      "#FB7185",
      # Orange-400
      "#FB923C",
      # Neutral-400
      "#A3A3A3",
      # Cyan-400
      "#22D3EE",
      # Violet-400
      "#C084FC"
    ]

    # Hash the ULID using :crypto and take a portion of the hash
    hash = :crypto.hash(:sha256, ulid)
    <<byte, _rest::binary>> = hash

    # Use the byte to index into the palette
    index = rem(byte, length(palette))
    Enum.at(palette, index)
  end
end
