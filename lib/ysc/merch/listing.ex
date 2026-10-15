defmodule Ysc.Merch.Listing do
  @moduledoc """
  What the shop listing page shows for a set of products: sorting, filtering
  by color, and the per-color photos behind each tile's swatches.

  Pure functions over products as `Ysc.Merch.list_shop_products/0` loads them
  (variants, image and gallery images preloaded).
  """
  alias Ysc.Merch
  alias Ysc.Merch.{ColorSwatch, Product, VariantSelection}

  @sorts [
    {"featured", "Featured"},
    {"newest", "Newest"},
    {"price_asc", "Price: low to high"},
    {"price_desc", "Price: high to low"},
    {"name", "Name: A to Z"}
  ]

  # Swatches shown on a tile; the rest collapse into a "+N" link.
  @max_swatches 5
  @new_for_days 30

  @type color :: %{
          name: String.t(),
          slug: String.t(),
          hex: String.t() | nil,
          light?: boolean(),
          image: struct() | nil,
          hover_image: struct() | nil
        }

  @type tile :: %{
          product: Product.t(),
          colors: [color()],
          hidden_colors: non_neg_integer(),
          active: color() | nil,
          sizes: String.t() | nil,
          new?: boolean()
        }

  @doc "Sort options as `{value, label}`, in menu order."
  @spec sorts() :: [{String.t(), String.t()}]
  def sorts, do: @sorts

  @doc "A known sort key, defaulting to `\"featured\"`."
  @spec parse_sort(term()) :: String.t()
  def parse_sort(value) do
    if is_binary(value) and List.keymember?(@sorts, value, 0),
      do: value,
      else: "featured"
  end

  @doc "Every color any product offers, in first-seen order, with its dot color."
  @spec available_colors([Product.t()]) :: [
          %{name: String.t(), slug: String.t(), hex: String.t() | nil}
        ]
  def available_colors(products) do
    products
    |> Enum.flat_map(&VariantSelection.colors(&1.variants))
    |> Enum.uniq()
    |> Enum.map(&%{name: &1, slug: slug(&1), hex: ColorSwatch.hex(&1)})
  end

  @doc "Keeps products offered in at least one of `colors` (all when empty)."
  @spec filter([Product.t()], [String.t()]) :: [Product.t()]
  def filter(products, []), do: products

  def filter(products, colors) do
    Enum.filter(products, fn product ->
      Enum.any?(VariantSelection.colors(product.variants), &(&1 in colors))
    end)
  end

  @doc "Orders products by a key from `sorts/0`."
  @spec sort([Product.t()], String.t()) :: [Product.t()]
  def sort(products, "newest"),
    do: Enum.sort_by(products, & &1.inserted_at, {:desc, DateTime})

  def sort(products, "price_asc"),
    do: Enum.sort_by(products, &price/1, {:asc, Decimal})

  def sort(products, "price_desc"),
    do: Enum.sort_by(products, &price/1, {:desc, Decimal})

  def sort(products, "name"),
    do: Enum.sort_by(products, &String.downcase(&1.name))

  def sort(products, _featured), do: products

  defp price(product),
    do: product |> Merch.starting_price() |> Money.to_decimal()

  @doc """
  The tile for a product. `preferred` is the shopper's color filter: the tile
  opens on the first of those colors the product offers.
  """
  @spec tile(Product.t(), [String.t()]) :: tile()
  def tile(%Product{} = product, preferred \\ []) do
    names = VariantSelection.colors(product.variants)
    colors = Enum.map(names, &color(product, &1))

    {shown, rest} = Enum.split(colors, @max_swatches)
    active = Enum.find(colors, &(&1.name in preferred)) || List.first(colors)

    # A preferred color past the swatch limit still needs its own swatch.
    shown = if active in shown, do: shown, else: shown ++ [active]
    hidden = Enum.count(rest, &(&1 != active))

    %{
      product: product,
      colors: if(colors == [], do: [color(product, nil)], else: shown),
      hidden_colors: hidden,
      active: active || color(product, nil),
      sizes: size_range(product),
      new?: new?(product)
    }
  end

  defp color(product, name) do
    {image, hover_image} =
      case Merch.gallery(product, name) do
        [] -> {nil, nil}
        [only] -> {only, nil}
        [first, second | _] -> {first, second}
      end

    hex = ColorSwatch.hex(name)

    %{
      name: name,
      slug: if(name, do: slug(name), else: "default"),
      hex: hex,
      light?: ColorSwatch.light?(hex),
      image: image,
      hover_image: hover_image
    }
  end

  defp size_range(product) do
    case VariantSelection.sizes(product.variants) do
      [] -> nil
      [only] -> only
      sizes -> "#{List.first(sizes)}–#{List.last(sizes)}"
    end
  end

  defp new?(%Product{inserted_at: %DateTime{} = at}),
    do: DateTime.diff(DateTime.utc_now(), at, :day) < @new_for_days

  defp new?(_), do: false

  @doc "The color's URL-safe id, used in DOM ids."
  @spec slug(String.t()) :: String.t()
  def slug(value),
    do: value |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
end
