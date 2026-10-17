defmodule Ysc.Merch.VariantSelection do
  @moduledoc """
  Picks a variant from a product's color/size options.

  Products come in all shapes: a tee has colors and sizes, a sticker has
  neither, a mug has colors only. A variant counts as "chosen" once every
  option the product actually offers has a value.
  """
  alias Ysc.Merch.Variant

  @size_order ~w(XXS XS S M L XL 2XL XXL 3XL XXXL 4XL 5XL)

  @type selection :: %{color: String.t() | nil, size: String.t() | nil}

  @doc "Distinct colors, in the order variants list them."
  @spec colors([Variant.t()]) :: [String.t()]
  def colors(variants) do
    variants |> Enum.map(& &1.color) |> Enum.reject(&blank?/1) |> Enum.uniq()
  end

  @doc """
  The hex for `color`'s dot: Printful's real color when a variant carries it,
  else a guess from the color's name (`nil` if even that is unknown).
  """
  @spec color_hex([Variant.t()], String.t() | nil) :: String.t() | nil
  def color_hex(variants, color) do
    Enum.find_value(variants, fn variant ->
      if variant.color == color and variant.color_hex, do: variant.color_hex
    end) || Ysc.Merch.ColorSwatch.hex(color)
  end

  @doc """
  Distinct sizes, in shopper order (XS to 5XL, then anything else by name).
  When `color` is given, only sizes offered in that color.
  """
  @spec sizes([Variant.t()], String.t() | nil) :: [String.t()]
  def sizes(variants, color \\ nil) do
    variants
    |> Enum.filter(&(is_nil(color) or &1.color == color))
    |> Enum.map(& &1.size)
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
    |> Enum.sort_by(&size_key/1)
  end

  defp size_key(size) do
    case Enum.find_index(@size_order, &(&1 == String.upcase(size))) do
      nil -> {1, size}
      index -> {0, index}
    end
  end

  @doc """
  The starting selection: the first color (when the product has colors) and no
  size, so shoppers make an explicit size choice. A product with a single
  variant starts fully selected.
  """
  @spec default([Variant.t()]) :: selection()
  def default([only]), do: %{color: only.color, size: only.size}

  def default(variants) do
    %{color: List.first(colors(variants)), size: nil}
  end

  @doc """
  The variant for a selection, or `nil` while an option the product offers is
  still unchosen (or the combination does not exist).
  """
  @spec find([Variant.t()], selection()) :: Variant.t() | nil
  def find(variants, %{color: color, size: size}) do
    needs_color? = colors(variants) != []
    needs_size? = sizes(variants) != []

    cond do
      needs_color? and is_nil(color) ->
        nil

      needs_size? and is_nil(size) ->
        nil

      true ->
        Enum.find(
          variants,
          &matches?(&1, color, size, needs_color?, needs_size?)
        )
    end
  end

  defp matches?(variant, color, size, needs_color?, needs_size?) do
    (not needs_color? or variant.color == color) and
      (not needs_size? or variant.size == size)
  end

  @doc """
  Applies a chosen color, keeping the current size only if that color offers it.
  """
  @spec select_color([Variant.t()], selection(), String.t()) :: selection()
  def select_color(variants, selection, color) do
    if color in colors(variants) do
      size = if selection.size in sizes(variants, color), do: selection.size
      %{color: color, size: size}
    else
      selection
    end
  end

  @doc "Applies a chosen size if the current color offers it."
  @spec select_size([Variant.t()], selection(), String.t()) :: selection()
  def select_size(variants, selection, size) do
    if size in sizes(variants, selection.color) do
      %{selection | size: size}
    else
      selection
    end
  end

  @doc """
  Whether a color/size combination exists, used to grey out unavailable sizes.
  """
  @spec size_available?([Variant.t()], selection(), String.t()) :: boolean()
  def size_available?(variants, %{color: color}, size) do
    size in sizes(variants, color)
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
end
