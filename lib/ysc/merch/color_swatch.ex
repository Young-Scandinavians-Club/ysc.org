defmodule Ysc.Merch.ColorSwatch do
  @moduledoc """
  Turns a Printful color name ("Heather Grey", "Navy", "Forest Green") into a
  hex color for the little dot next to the name on the product page.

  Printful's sync API gives color names only, so this knows the common apparel
  names, then falls back to a base color word in the name ("Light Blue" is
  blue). Unknown names return `nil`; callers should show a neutral dot rather
  than guess.
  """

  @exact %{
    "black" => "#18181b",
    "white" => "#ffffff",
    "navy" => "#1e2a4a",
    "navy blazer" => "#1e2a4a",
    "heather grey" => "#b4b4b8",
    "heather gray" => "#b4b4b8",
    "heather navy" => "#3b4a6b",
    "heather" => "#b4b4b8",
    "dark heather" => "#4b4b50",
    "charcoal" => "#3f3f46",
    "athletic heather" => "#c4c4c8",
    "sport grey" => "#a1a1aa",
    "ash" => "#d4d4d8",
    "red" => "#dc2626",
    "cardinal" => "#9f1239",
    "maroon" => "#7f1d1d",
    "burgundy" => "#7f1d3d",
    "royal" => "#1d4ed8",
    "royal blue" => "#1d4ed8",
    "light blue" => "#93c5fd",
    "carolina blue" => "#7bafd4",
    "sky blue" => "#7dd3fc",
    "forest green" => "#14532d",
    "kelly green" => "#16a34a",
    "military green" => "#4b5320",
    "olive" => "#5b6130",
    "irish green" => "#15803d",
    "mint" => "#a7f3d0",
    "sand" => "#d6c7a1",
    "natural" => "#f1ead8",
    "cream" => "#f5efdc",
    "tan" => "#c8a97e",
    "khaki" => "#b5a37a",
    "brown" => "#5c4033",
    "gold" => "#eab308",
    "yellow" => "#facc15",
    "orange" => "#f97316",
    "pink" => "#f472b6",
    "hot pink" => "#ec4899",
    "light pink" => "#fbcfe8",
    "purple" => "#7e22ce",
    "lavender" => "#c4b5fd",
    "teal" => "#0f766e",
    "turquoise" => "#14b8a6",
    "silver" => "#cbd5e1",
    "grey" => "#9ca3af",
    "gray" => "#9ca3af"
  }

  # Base color words, checked in order when the full name isn't known.
  @base_words [
    {"black", "#18181b"},
    {"white", "#ffffff"},
    {"navy", "#1e2a4a"},
    {"grey", "#9ca3af"},
    {"gray", "#9ca3af"},
    {"red", "#dc2626"},
    {"blue", "#2563eb"},
    {"green", "#16a34a"},
    {"yellow", "#facc15"},
    {"orange", "#f97316"},
    {"pink", "#f472b6"},
    {"purple", "#7e22ce"},
    {"brown", "#5c4033"},
    {"tan", "#c8a97e"},
    {"sand", "#d6c7a1"},
    {"cream", "#f5efdc"},
    {"gold", "#eab308"}
  ]

  @doc """
  The hex color (`"#rrggbb"`) for a color name, or `nil` when unknown.
  """
  @spec hex(String.t() | nil) :: String.t() | nil
  def hex(nil), do: nil

  def hex(name) when is_binary(name) do
    key = name |> String.downcase() |> String.trim()

    Map.get(@exact, key) ||
      Enum.find_value(@base_words, fn {word, hex} ->
        if String.contains?(key, word), do: hex
      end)
  end

  @doc "True when the dot needs an outline to be visible on a white page."
  @spec light?(String.t() | nil) :: boolean()
  def light?(nil), do: false

  def light?("#" <> hex) when byte_size(hex) == 6 do
    {r, g, b} = {parse(hex, 0), parse(hex, 2), parse(hex, 4)}
    # Perceived brightness, 0-255.
    r * 0.299 + g * 0.587 + b * 0.114 > 200
  end

  def light?(_), do: false

  defp parse(hex, offset),
    do: hex |> String.slice(offset, 2) |> String.to_integer(16)
end
