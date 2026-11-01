defmodule Ysc.Merch.GalleryTest do
  use Ysc.DataCase, async: true

  import Ysc.MerchFixtures

  alias Ysc.Merch
  alias Ysc.Merch.ProductImage

  defp product_with_colors do
    product = product_fixture(%{name: "Tee"})
    black = variant_fixture(product, %{color: "Black", size: "M"})
    white = variant_fixture(product, %{color: "White", size: "M"})
    %{product: product, black: black, white: white}
  end

  defp loaded(product), do: Merch.get_shop_product(product.id)
  defp ids(images), do: Enum.map(images, & &1.id)

  describe "colors/1" do
    # Names that sort Adobe first among equally priced variants, like the real
    # Printful hoodies where the default was Adobe, not Black.
    defp hoodie do
      product = product_fixture(%{name: "Hoodie"})

      for color <- ["Adobe", "Black", "Khaki"] do
        variant_fixture(product, %{
          name: "Hoodie / #{color} / M",
          color: color,
          size: "M"
        })
      end

      product
    end

    test "follow the variants when no photo says otherwise" do
      assert product_colors(hoodie()) == ["Adobe", "Black", "Khaki"]
    end

    test "the color whose photo is first leads" do
      product = hoodie()
      gallery_photo_fixture(product, nil, %{color: "Adobe", position: 0})

      black =
        gallery_photo_fixture(product, nil, %{color: "Black", position: 0})

      gallery_photo_fixture(product, nil, %{color: "Khaki", position: 0})

      assert product_colors(product) == ["Adobe", "Black", "Khaki"]

      assert :ok = Merch.move_photo_first(black.id)
      assert product_colors(product) == ["Black", "Adobe", "Khaki"]
    end

    test "colors without photos follow the ones with photos" do
      product = hoodie()
      gallery_photo_fixture(product, nil, %{color: "Khaki", position: 3})

      assert product_colors(product) == ["Khaki", "Adobe", "Black"]
    end

    test "photos for every color do not reorder colors" do
      product = hoodie()
      general = gallery_photo_fixture(product, nil, %{position: 0})
      assert :ok = Merch.move_photo_first(general.id)

      assert product_colors(product) == ["Adobe", "Black", "Khaki"]
    end

    defp product_colors(product), do: product |> loaded() |> Merch.colors()
  end

  describe "gallery/2" do
    test "orders the selected color's photos and the general ones by position" do
      %{product: product} = product_with_colors()
      black_1 = image_fixture()
      black_2 = image_fixture()
      white_1 = image_fixture()
      general = image_fixture()

      gallery_photo_fixture(product, general, %{position: 5})
      gallery_photo_fixture(product, black_2, %{color: "Black", position: 2})
      gallery_photo_fixture(product, black_1, %{color: "Black", position: 1})
      gallery_photo_fixture(product, white_1, %{color: "White", position: 3})

      product = loaded(product)

      assert product |> Merch.gallery("Black") |> ids() ==
               ids([black_1, black_2, general])

      assert product |> Merch.gallery("White") |> ids() ==
               ids([white_1, general])
    end

    test "a general photo moved to the front leads every color" do
      %{product: product} = product_with_colors()

      black =
        gallery_photo_fixture(product, nil, %{color: "Black", position: 0})

      white =
        gallery_photo_fixture(product, nil, %{color: "White", position: 0})

      lifestyle = gallery_photo_fixture(product, nil, %{position: 1})

      product = loaded(product)

      assert product |> Merch.gallery("Black") |> ids() == [
               black.image_id,
               lifestyle.image_id
             ]

      assert :ok = Merch.move_photo_first(lifestyle.id)

      product = loaded(product)

      assert product |> Merch.gallery("Black") |> ids() ==
               [lifestyle.image_id, black.image_id]

      assert product |> Merch.gallery("White") |> ids() ==
               [lifestyle.image_id, white.image_id]
    end

    test "a color's own photo wins a tie with a general one" do
      %{product: product} = product_with_colors()
      general = gallery_photo_fixture(product, nil, %{position: 0})
      own = gallery_photo_fixture(product, nil, %{color: "Black", position: 0})

      assert product |> loaded() |> Merch.gallery("Black") |> ids() ==
               [own.image_id, general.image_id]
    end

    test "with no color chosen, only photos for every color" do
      %{product: product} = product_with_colors()
      general = image_fixture()
      gallery_photo_fixture(product, general)
      gallery_photo_fixture(product, image_fixture(), %{color: "Black"})

      assert product |> loaded() |> Merch.gallery(nil) |> ids() == [general.id]
    end

    test "a color with no photos of its own falls back to the general ones" do
      %{product: product} = product_with_colors()
      general = image_fixture()
      gallery_photo_fixture(product, general)

      assert product |> loaded() |> Merch.gallery("White") |> ids() == [
               general.id
             ]
    end

    test "without a gallery it falls back to the color's variant image, then the product's" do
      product =
        product_fixture()
        |> Ecto.Changeset.change(image_id: image_fixture().id)
        |> Repo.update!()

      variant_image = image_fixture()

      variant_fixture(product, %{color: "Black"})
      |> Ecto.Changeset.change(image_id: variant_image.id)
      |> Repo.update!()

      variant_fixture(product, %{color: "White"})

      product = loaded(product)

      assert product |> Merch.gallery("Black") |> ids() == [variant_image.id]
      assert product |> Merch.gallery("White") |> ids() == [product.image_id]
    end

    test "is empty when there is nothing to show" do
      product = product_fixture()
      variant_fixture(product)
      assert product |> loaded() |> Merch.gallery(nil) == []
    end

    test "a photo is never listed twice" do
      %{product: product} = product_with_colors()
      image = image_fixture()
      gallery_photo_fixture(product, image, %{color: "Black"})

      assert product |> loaded() |> Merch.gallery("Black") |> length() == 1
    end
  end

  describe "admin photo management" do
    test "add_product_photo appends to the end and can tie a color" do
      %{product: product} = product_with_colors()
      first = image_fixture()
      second = image_fixture()

      assert {:ok, %ProductImage{position: 0, color: nil, source: :admin}} =
               Merch.add_product_photo(product, first.id)

      assert {:ok, %ProductImage{position: 1, color: "Black"}} =
               Merch.add_product_photo(product, second.id, "Black")
    end

    test "add_product_photos appends many photos in order" do
      %{product: product} = product_with_colors()
      first = image_fixture()
      second = image_fixture()
      third = image_fixture()

      {:ok, _} = Merch.add_product_photo(product, first.id)

      assert [
               {:ok, %ProductImage{position: 1, image_id: second_id}},
               {:ok, %ProductImage{position: 2, image_id: third_id}}
             ] =
               Merch.add_product_photos(product, [second.id, third.id])

      assert second_id == second.id
      assert third_id == third.id
    end

    test "add_product_photos uses a constant number of queries" do
      %{product: product} = product_with_colors()
      ids = Enum.map(1..8, fn _ -> image_fixture().id end)

      {results, count} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Merch.add_product_photos(product, ids) end,
          pattern: ~r/SELECT|INSERT/i,
          caller_pids: [self()]
        )

      assert Enum.all?(results, &match?({:ok, %ProductImage{}}, &1))
      assert length(results) == 8
      assert count <= 3
    end

    test "the same photo cannot be added twice" do
      %{product: product} = product_with_colors()
      image = image_fixture()
      {:ok, _} = Merch.add_product_photo(product, image.id)

      assert {:error, changeset} = Merch.add_product_photo(product, image.id)
      assert %{product_id: [_]} = errors_on(changeset)
    end

    test "add_product_photos reports duplicates and missing images without dropping the rest" do
      %{product: product} = product_with_colors()
      existing = image_fixture()
      fresh = image_fixture()
      {:ok, _} = Merch.add_product_photo(product, existing.id)

      missing_id = Ecto.ULID.generate()

      assert [
               {:error, duplicate},
               {:ok, %ProductImage{image_id: fresh_id}},
               {:error, missing},
               {:error, repeated}
             ] =
               Merch.add_product_photos(product, [
                 existing.id,
                 fresh.id,
                 missing_id,
                 fresh.id
               ])

      assert fresh_id == fresh.id
      assert %{product_id: [_]} = errors_on(duplicate)
      assert %{product_id: [_]} = errors_on(repeated)
      assert %{image_id: [_]} = errors_on(missing)
    end

    test "blank colors mean every color" do
      %{product: product} = product_with_colors()
      {:ok, photo} = Merch.add_product_photo(product, image_fixture().id, "  ")
      assert photo.color == nil
    end

    test "remove deletes club photos but never Printful's" do
      %{product: product} = product_with_colors()
      mine = gallery_photo_fixture(product)
      theirs = gallery_photo_fixture(product, nil, %{source: :printful})

      assert :ok = Merch.remove_product_photo(mine.id)
      assert Repo.get(ProductImage, mine.id) == nil

      assert {:error, :managed_by_printful} =
               Merch.remove_product_photo(theirs.id)

      assert Repo.get(ProductImage, theirs.id)

      assert {:error, :not_found} =
               Merch.remove_product_photo(Ecto.ULID.generate())
    end

    test "removing the photo from the media library removes it from the gallery" do
      %{product: product} = product_with_colors()
      photo = gallery_photo_fixture(product)

      Repo.delete!(photo.image)
      assert Repo.get(ProductImage, photo.id) == nil
    end

    test "set_photo_color retargets club photos only" do
      %{product: product} = product_with_colors()
      mine = gallery_photo_fixture(product)

      theirs =
        gallery_photo_fixture(product, nil, %{source: :printful, color: "Black"})

      assert {:ok, %ProductImage{color: "White"}} =
               Merch.set_photo_color(mine.id, "White")

      assert {:ok, %ProductImage{color: nil}} =
               Merch.set_photo_color(mine.id, "")

      assert {:ok, %ProductImage{color: nil}} =
               Merch.set_photo_color(mine.id, "  ")

      assert {:ok, %ProductImage{color: "Navy"}} =
               Merch.set_photo_color(mine.id, "  Navy  ")

      assert {:error, :managed_by_printful} =
               Merch.set_photo_color(theirs.id, "White")

      assert {:error, :not_found} =
               Merch.set_photo_color(Ecto.ULID.generate(), "White")
    end

    test "move_photo_first puts a photo at the front" do
      %{product: product} = product_with_colors()
      a = gallery_photo_fixture(product, nil, %{position: 0})
      b = gallery_photo_fixture(product, nil, %{position: 1})
      c = gallery_photo_fixture(product, nil, %{position: 2})

      assert :ok = Merch.move_photo_first(c.id)

      order = product |> loaded() |> Merch.gallery(nil) |> ids()
      assert order == [c.image_id, a.image_id, b.image_id]
      assert {:error, :not_found} = Merch.move_photo_first(Ecto.ULID.generate())
    end

    test "the shop loads gallery photos in order" do
      %{product: product} = product_with_colors()
      late = gallery_photo_fixture(product, nil, %{position: 5})
      early = gallery_photo_fixture(product, nil, %{position: 1})

      assert [%{id: first}, %{id: second}] = loaded(product).gallery_images
      assert [first, second] == [early.id, late.id]
    end
  end
end
