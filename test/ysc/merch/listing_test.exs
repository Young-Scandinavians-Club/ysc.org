defmodule Ysc.Merch.ListingTest do
  use Ysc.DataCase, async: true

  import Ysc.MerchFixtures

  alias Ysc.Merch
  alias Ysc.Merch.Listing

  defp product_with(name, variants, attrs \\ %{}) do
    product = product_fixture(Map.put(attrs, :name, name))

    for {color, size, price} <- variants do
      variant_fixture(product, %{
        color: color,
        size: size,
        retail_price: Money.new(:USD, price)
      })
    end

    product
  end

  defp loaded do
    Merch.list_shop_products()
  end

  setup do
    tee =
      product_with("Tee", [
        {"Black", "S", "25"},
        {"Black", "XL", "25"},
        {"Navy", "M", "25"}
      ])

    sticker = product_with("Sticker", [{nil, nil, "3"}])
    hoodie = product_with("Hoodie", [{"Navy", "M", "55"}])
    %{tee: tee, sticker: sticker, hoodie: hoodie}
  end

  describe "parse_sort/1" do
    test "keeps known sorts and falls back to featured" do
      assert Listing.parse_sort("price_asc") == "price_asc"
      assert Listing.parse_sort("bogus") == "featured"
      assert Listing.parse_sort(nil) == "featured"
    end
  end

  describe "sort/2" do
    test "orders by price and name" do
      names = fn key -> loaded() |> Listing.sort(key) |> Enum.map(& &1.name) end

      assert names.("price_asc") == ["Sticker", "Tee", "Hoodie"]
      assert names.("price_desc") == ["Hoodie", "Tee", "Sticker"]
      assert names.("name") == ["Hoodie", "Sticker", "Tee"]
    end

    test "featured keeps the club's order" do
      assert loaded() |> Listing.sort("featured") |> Enum.map(& &1.name) ==
               ["Hoodie", "Sticker", "Tee"]
    end
  end

  describe "available_colors/1 and filter/2" do
    test "lists each color once, with its dot color" do
      colors = Listing.available_colors(loaded())

      assert colors |> Enum.map(& &1.name) |> Enum.sort() == ["Black", "Navy"]
      assert Enum.find(colors, &(&1.name == "Black")).hex == "#18181b"
    end

    test "keeps products offered in any chosen color", %{
      tee: tee,
      hoodie: hoodie
    } do
      products = loaded()

      assert products
             |> Listing.filter(["Navy"])
             |> Enum.map(& &1.id)
             |> Enum.sort() ==
               Enum.sort([tee.id, hoodie.id])

      assert [only] = Listing.filter(products, ["Black"])
      assert only.id == tee.id
      assert length(Listing.filter(products, [])) == 3
    end
  end

  describe "color dots" do
    test "prefer Printful's real color over a guess from the name" do
      product = product_fixture(%{name: "Hoodie Colors"})

      for {color, hex} <- [{"Black", "#080808"}, {"Adobe", "#d06e26"}] do
        variant_fixture(product, %{
          color: color,
          color_hex: hex,
          size: "M",
          retail_price: Money.new(:USD, "30")
        })
      end

      loaded = loaded() |> Enum.find(&(&1.id == product.id))
      tile = Listing.tile(loaded)

      assert Enum.find(tile.colors, &(&1.name == "Black")).hex == "#080808"
      # The name alone knows nothing about "Adobe".
      assert Enum.find(tile.colors, &(&1.name == "Adobe")).hex == "#d06e26"

      options = Listing.available_colors([loaded])
      assert Enum.find(options, &(&1.name == "Adobe")).hex == "#d06e26"
    end

    test "fall back to the name when no real color was stored", %{tee: tee} do
      tile = loaded() |> Enum.find(&(&1.id == tee.id)) |> Listing.tile()
      assert Enum.find(tile.colors, &(&1.name == "Black")).hex == "#18181b"
    end
  end

  describe "tile/2" do
    test "has a swatch per color, size range and no swatches without colors",
         %{tee: tee, sticker: sticker} do
      products = loaded()

      tile = products |> Enum.find(&(&1.id == tee.id)) |> Listing.tile()
      # Variants list by price then name, so which color is first is not fixed.
      assert tile.colors |> Enum.map(& &1.name) |> Enum.sort() == [
               "Black",
               "Navy"
             ]

      assert tile.active.name == hd(tile.colors).name
      assert tile.sizes == "S–XL"
      assert tile.hidden_colors == 0

      tile = products |> Enum.find(&(&1.id == sticker.id)) |> Listing.tile()
      assert tile.active.name == nil
      assert tile.sizes == nil
    end

    test "opens on the filtered color", %{tee: tee} do
      tile = loaded() |> Enum.find(&(&1.id == tee.id)) |> Listing.tile(["Navy"])
      assert tile.active.name == "Navy"
    end

    test "collapses colors past the swatch limit into a count" do
      colors = ~w(Black White Red Navy Olive Gold Pink)
      product = product_with("Rainbow", Enum.map(colors, &{&1, "M", "20"}))

      tile = loaded() |> Enum.find(&(&1.id == product.id)) |> Listing.tile()
      assert length(tile.colors) == 5
      assert tile.hidden_colors == 2

      # A chosen color beyond the limit still gets its own swatch.
      [hidden_name | _] = colors -- Enum.map(tile.colors, & &1.name)

      tile =
        loaded()
        |> Enum.find(&(&1.id == product.id))
        |> Listing.tile([hidden_name])

      assert hidden_name in Enum.map(tile.colors, & &1.name)
      assert tile.active.name == hidden_name
      assert tile.hidden_colors == 1
    end

    test "uses each color's own photo, and a second photo for hover", %{
      tee: tee
    } do
      black = gallery_photo_fixture(tee, nil, %{color: "Black", position: 0})

      black_two =
        gallery_photo_fixture(tee, nil, %{color: "Black", position: 1})

      navy = gallery_photo_fixture(tee, nil, %{color: "Navy", position: 2})

      tile = loaded() |> Enum.find(&(&1.id == tee.id)) |> Listing.tile()
      black_color = Enum.find(tile.colors, &(&1.name == "Black"))
      navy_color = Enum.find(tile.colors, &(&1.name == "Navy"))

      assert black_color.image.id == black.image_id
      assert black_color.hover_image.id == black_two.image_id
      assert navy_color.image.id == navy.image_id
      assert navy_color.hover_image == nil
    end
  end
end
