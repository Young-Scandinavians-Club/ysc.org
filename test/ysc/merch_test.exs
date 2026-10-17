defmodule Ysc.MerchTest do
  use Ysc.DataCase, async: true

  import Ysc.MerchFixtures, only: [image_fixture: 1, gallery_photo_fixture: 3]

  alias Ysc.Merch
  alias Ysc.Merch.{Product, Variant}

  defp product!(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    %Product{}
    |> Product.sync_changeset(%{printful_product_id: n, name: "Product #{n}"})
    |> Ecto.Changeset.change(Map.take(attrs, [:status, :sort_order]))
    |> Repo.insert!()
  end

  defp variant!(product, price, attrs \\ %{}) do
    n = System.unique_integer([:positive])

    %Variant{}
    |> Variant.sync_changeset(
      Map.merge(
        %{
          product_id: product.id,
          printful_sync_variant_id: n,
          printful_variant_id: n + 1,
          name: "Variant #{n}",
          retail_price: Money.new(:USD, price)
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  describe "list_shop_products/0" do
    test "includes only active products that have an available variant" do
      visible = product!()
      variant!(visible, "30")
      variant!(visible, "20")

      hidden = product!(%{status: :hidden})
      variant!(hidden, "10")

      sold_out = product!()
      variant!(sold_out, "10", %{available: false})

      _no_variants = product!()

      assert [shown] = Merch.list_shop_products()
      assert shown.id == visible.id
    end

    test "preloads only available variants, cheapest first" do
      product = product!()
      variant!(product, "30")
      variant!(product, "20")
      variant!(product, "5", %{available: false})

      assert [%Product{variants: variants} = shown] = Merch.list_shop_products()

      assert Enum.map(variants, & &1.retail_price) == [
               Money.new(:USD, "20"),
               Money.new(:USD, "30")
             ]

      assert Money.equal?(Merch.starting_price(shown), Money.new(:USD, "20"))
    end

    test "orders by sort_order then name" do
      b = product!(%{sort_order: 2})
      a = product!(%{sort_order: 1})
      for p <- [a, b], do: variant!(p, "10")

      assert Enum.map(Merch.list_shop_products(), & &1.id) == [a.id, b.id]
    end

    test "omits descriptions, Printful ids, and image upload_data" do
      image =
        image_fixture(%{
          upload_data: %{"original" => "fat-json"},
          content_hash: "abc123"
        })

      product =
        product!()
        |> Ecto.Changeset.change(%{
          description: "Club-written copy the listing never shows.",
          image_id: image.id
        })
        |> Repo.update!()

      variant!(product, "20", %{
        sku: "TEE-BLK-M",
        source_image_url: "https://printful.example/tee.png",
        image_id: image.id
      })

      gallery_photo_fixture(product, image, %{position: 0})

      {listed, fat_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Merch.list_shop_products() end,
          pattern:
            ~r/description|printful_product_id|printful_sync_variant_id|printful_variant_id|source_image_url|upload_data|content_hash|sku/i,
          caller_pids: [self()]
        )

      shown = Enum.find(listed, &(&1.id == product.id))
      assert shown
      assert shown.name
      assert is_nil(shown.description)
      assert is_nil(shown.printful_product_id)
      assert hd(shown.variants).printful_variant_id == nil
      assert shown.image.id == image.id
      assert is_nil(shown.image.upload_data)
      assert fat_cols == 0
    end
  end

  describe "get_shop_product/1" do
    test "returns nil for hidden products" do
      hidden = product!(%{status: :hidden})
      variant!(hidden, "10")
      assert Merch.get_shop_product(hidden.id) == nil
    end

    test "returns the product with its variants" do
      product = product!()
      variant = variant!(product, "10")

      assert %Product{variants: [%Variant{id: id}]} =
               Merch.get_shop_product(product.id)

      assert id == variant.id
    end

    test "keeps the description and omits image upload_data" do
      image = image_fixture(%{upload_data: %{"original" => "fat-json"}})

      product =
        product!()
        |> Ecto.Changeset.change(%{
          description: "Soft cotton club tee.",
          image_id: image.id
        })
        |> Repo.update!()

      variant!(product, "10", %{image_id: image.id})

      {shown, fat_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Merch.get_shop_product(product.id) end,
          pattern: ~r/upload_data|content_hash|printful_product_id|sku/i,
          caller_pids: [self()]
        )

      assert shown.description == "Soft cotton club tee."
      assert shown.image.id == image.id
      assert is_nil(shown.image.upload_data)
      assert fat_cols == 0
    end
  end

  describe "update_product/2" do
    test "updates club-managed fields only" do
      product = product!()

      {:ok, updated} =
        Merch.update_product(product, %{
          description: "Nice",
          name: "Hacked",
          status: :hidden
        })

      assert updated.description == "Nice"
      assert updated.status == :hidden
      assert updated.name == product.name
    end
  end

  describe "list_admin_products/0" do
    test "includes hidden products with all variants" do
      hidden = product!(%{status: :hidden})
      variant!(hidden, "10", %{available: false})

      assert [%Product{variants: [_]}] = Merch.list_admin_products()
    end

    test "omits descriptions, Printful ids, and image upload_data" do
      image =
        image_fixture(%{
          upload_data: %{"original" => "fat-json"},
          content_hash: "abc123"
        })

      product =
        product!()
        |> Ecto.Changeset.change(%{
          description: "Club-written copy the catalog table never shows.",
          image_id: image.id
        })
        |> Repo.update!()

      variant!(product, "20", %{
        sku: "TEE-BLK-M",
        source_image_url: "https://printful.example/tee.png",
        image_id: image.id
      })

      gallery_photo_fixture(product, image, %{position: 0})

      {listed, fat_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Merch.list_admin_products() end,
          pattern:
            ~r/description|printful_product_id|printful_sync_variant_id|printful_variant_id|source_image_url|upload_data|content_hash|sku/i,
          caller_pids: [self()]
        )

      shown = Enum.find(listed, &(&1.id == product.id))
      assert shown
      assert shown.name
      assert is_nil(shown.description)
      assert is_nil(shown.printful_product_id)
      assert hd(shown.variants).printful_variant_id == nil
      assert length(shown.gallery_images) == 1
      assert shown.image.id == image.id
      assert is_nil(shown.image.upload_data)
      assert fat_cols == 0
    end
  end

  describe "get_admin_product/1" do
    test "keeps the description, gallery source, and omits image upload_data" do
      image = image_fixture(%{upload_data: %{"original" => "fat-json"}})

      product =
        product!()
        |> Ecto.Changeset.change(%{
          description: "Soft cotton club tee.",
          image_id: image.id
        })
        |> Repo.update!()

      variant!(product, "10")

      photo =
        gallery_photo_fixture(product, image, %{
          source: :printful,
          color: "Black"
        })

      {shown, fat_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Merch.get_admin_product(product.id) end,
          pattern:
            ~r/printful_product_id|printful_sync_variant_id|printful_variant_id|source_image_url|upload_data|content_hash|sku/i,
          caller_pids: [self()]
        )

      assert shown.description == "Soft cotton club tee."

      assert [%{id: photo_id, source: :printful, color: "Black"}] =
               shown.gallery_images

      assert photo_id == photo.id
      assert shown.image.id == image.id
      assert is_nil(shown.image.upload_data)
      assert is_nil(shown.printful_product_id)
      assert fat_cols == 0
    end

    test "returns nil for missing or invalid ids" do
      assert Merch.get_admin_product(Ecto.ULID.generate()) == nil
      assert Merch.get_admin_product("garbage") == nil
    end
  end

  describe "list_orderable_products/0" do
    test "includes hidden products and skips removed or sold-out ones" do
      hidden = product!(%{status: :hidden})
      hidden_variant = variant!(hidden, "10")

      removed =
        product!()
        |> Ecto.Changeset.change(%{
          removed_from_printful_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

      variant!(removed, "10")

      sold_out = product!()
      variant!(sold_out, "10", %{available: false})

      pairs = Merch.list_orderable_products()

      assert [{product, [variant]}] =
               Enum.filter(pairs, fn {p, _} -> p.id == hidden.id end)

      assert product.name == hidden.name
      assert variant.id == hidden_variant.id
      refute Enum.any?(pairs, fn {p, _} -> p.id == removed.id end)
      refute Enum.any?(pairs, fn {p, _} -> p.id == sold_out.id end)
    end

    test "omits descriptions, Printful ids, and images" do
      image =
        image_fixture(%{
          upload_data: %{"original" => "fat-json"},
          content_hash: "abc123"
        })

      product =
        product!()
        |> Ecto.Changeset.change(%{
          description: "Not needed on the order form.",
          image_id: image.id
        })
        |> Repo.update!()

      variant!(product, "20", %{
        sku: "TEE-BLK-M",
        source_image_url: "https://printful.example/tee.png",
        image_id: image.id
      })

      {pairs, fat_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Merch.list_orderable_products() end,
          pattern:
            ~r/description|printful_product_id|printful_sync_variant_id|printful_variant_id|source_image_url|upload_data|content_hash|sku/i,
          caller_pids: [self()]
        )

      {shown, [variant]} = Enum.find(pairs, fn {p, _} -> p.id == product.id end)
      assert shown.name
      assert is_nil(shown.description)
      assert is_nil(shown.printful_product_id)
      assert variant.printful_variant_id == nil
      assert fat_cols == 0
    end
  end
end
