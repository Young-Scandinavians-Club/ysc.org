defmodule Ysc.Merch.CatalogSyncTest do
  use Ysc.DataCase, async: true

  import Mox
  import Ysc.MerchFixtures, only: [gallery_photo_fixture: 3]

  alias Ysc.Merch
  alias Ysc.Merch.{Product, Variant}
  alias Ysc.Printful.{ClientMock, Error}

  setup :verify_on_exit!

  @png File.read!(Path.expand("../../support/fixtures/tiny.png", __DIR__))

  setup do
    admin = Ysc.AccountsFixtures.user_fixture(%{role: "admin"})
    test_pid = self()

    Req.Test.stub(Ysc.Merch.ImageImport, fn conn ->
      send(test_pid, {:image_download, conn.request_path})

      conn
      |> Plug.Conn.put_resp_content_type("image/png")
      |> Plug.Conn.send_resp(200, @png)
    end)

    %{admin: admin}
  end

  defp downloads(acc \\ []) do
    receive do
      {:image_download, path} -> downloads([path | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp listed(id, name \\ nil) do
    %{
      "id" => id,
      "name" => name || "Product #{id}",
      "thumbnail_url" => "https://img/#{id}.png"
    }
  end

  defp sync_variant(id, attrs \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "variant_id" => id + 4000,
        "name" => "Tee / Black / M",
        "size" => "M",
        "color" => "Black",
        "sku" => "SKU-#{id}",
        "retail_price" => "25.00",
        "availability_status" => "active",
        "files" => [
          %{"type" => "preview", "preview_url" => "https://img/v#{id}.png"}
        ]
      },
      attrs
    )
  end

  defp detail(product, variants),
    do: {:ok, %{"sync_product" => product, "sync_variants" => variants}}

  test "creates products and variants from Printful", %{admin: admin} do
    expect(ClientMock, :list_sync_products, fn ->
      {:ok, [listed(1, "Club Tee")]}
    end)

    expect(ClientMock, :get_sync_product, fn 1 ->
      detail(listed(1, "Club Tee"), [
        sync_variant(10),
        sync_variant(11, %{"size" => "L", "retail_price" => "27.50"})
      ])
    end)

    assert {:ok, %{products: 1, variants: 2, removed: 0, failed: 0}} =
             Merch.sync_catalog(admin)

    product =
      Repo.get_by!(Product, printful_product_id: 1) |> Repo.preload(:variants)

    assert product.name == "Club Tee"
    assert product.status == :active
    assert product.source_image_url == "https://img/1.png"
    assert %Ysc.Media.Image{} = Repo.get!(Ysc.Media.Image, product.image_id)
    assert length(product.variants) == 2

    variant = Enum.find(product.variants, &(&1.printful_sync_variant_id == 11))
    assert variant.size == "L"
    assert variant.printful_variant_id == 4011
    assert variant.source_image_url == "https://img/v11.png"
    assert variant.image_id
    assert Money.equal?(variant.retail_price, Money.new(:USD, "27.50"))
  end

  test "re-sync updates Printful fields but keeps club-owned fields", %{
    admin: admin
  } do
    expect(ClientMock, :list_sync_products, 2, fn -> {:ok, [listed(1)]} end)

    expect(ClientMock, :get_sync_product, fn 1 ->
      detail(listed(1, "Old Name"), [sync_variant(10)])
    end)

    assert {:ok, _} = Merch.sync_catalog(admin)

    product = Repo.get_by!(Product, printful_product_id: 1)

    {:ok, _} =
      Merch.update_product(product, %{
        description: "Our tee",
        status: :hidden,
        sort_order: 5
      })

    expect(ClientMock, :get_sync_product, fn 1 ->
      detail(listed(1, "New Name"), [
        sync_variant(10, %{"retail_price" => "30.00"})
      ])
    end)

    assert {:ok, %{products: 1}} = Merch.sync_catalog(admin)

    product = Repo.get_by!(Product, printful_product_id: 1)
    assert product.name == "New Name"
    assert product.description == "Our tee"
    assert product.status == :hidden
    assert product.sort_order == 5

    variant = Repo.get_by!(Variant, printful_sync_variant_id: 10)
    assert Money.equal?(variant.retail_price, Money.new(:USD, "30.00"))
    assert Repo.aggregate(Variant, :count) == 1
  end

  test "variants dropped by Printful become unavailable, not deleted", %{
    admin: admin
  } do
    expect(ClientMock, :list_sync_products, 2, fn -> {:ok, [listed(1)]} end)

    expect(ClientMock, :get_sync_product, fn 1 ->
      detail(listed(1), [sync_variant(10), sync_variant(11)])
    end)

    assert {:ok, _} = Merch.sync_catalog(admin)

    expect(ClientMock, :get_sync_product, fn 1 ->
      detail(listed(1), [sync_variant(10)])
    end)

    assert {:ok, %{variants: 1}} = Merch.sync_catalog(admin)

    assert Repo.get_by!(Variant, printful_sync_variant_id: 10).available
    refute Repo.get_by!(Variant, printful_sync_variant_id: 11).available
  end

  test "non-active and ignored variants are handled", %{admin: admin} do
    expect(ClientMock, :list_sync_products, fn -> {:ok, [listed(1)]} end)

    expect(ClientMock, :get_sync_product, fn 1 ->
      detail(listed(1), [
        sync_variant(10, %{"availability_status" => "out_of_stock"}),
        sync_variant(11, %{"is_ignored" => true})
      ])
    end)

    assert {:ok, %{variants: 1}} = Merch.sync_catalog(admin)
    refute Repo.get_by!(Variant, printful_sync_variant_id: 10).available
    assert Repo.get_by(Variant, printful_sync_variant_id: 11) == nil
  end

  test "products missing from Printful are hidden, and return when they reappear",
       %{admin: admin} do
    expect(ClientMock, :list_sync_products, fn ->
      {:ok, [listed(1), listed(2)]}
    end)

    expect(ClientMock, :get_sync_product, 2, fn id ->
      detail(listed(id), [sync_variant(id * 10)])
    end)

    assert {:ok, %{products: 2, removed: 0}} = Merch.sync_catalog(admin)

    expect(ClientMock, :list_sync_products, fn -> {:ok, [listed(1)]} end)

    expect(ClientMock, :get_sync_product, fn 1 ->
      detail(listed(1), [sync_variant(10)])
    end)

    assert {:ok, %{products: 1, removed: 1}} = Merch.sync_catalog(admin)

    removed = Repo.get_by!(Product, printful_product_id: 2)
    assert removed.status == :hidden
    assert removed.removed_from_printful_at

    expect(ClientMock, :list_sync_products, fn ->
      {:ok, [listed(1), listed(2)]}
    end)

    expect(ClientMock, :get_sync_product, 2, fn id ->
      detail(listed(id), [sync_variant(id * 10)])
    end)

    assert {:ok, %{products: 2, removed: 0}} = Merch.sync_catalog(admin)

    back = Repo.get_by!(Product, printful_product_id: 2)
    assert back.status == :active
    assert back.removed_from_printful_at == nil
  end

  test "a product whose detail fetch fails is skipped and not swept as removed",
       %{admin: admin} do
    expect(ClientMock, :list_sync_products, 2, fn -> {:ok, [listed(1)]} end)

    expect(ClientMock, :get_sync_product, fn 1 ->
      detail(listed(1), [sync_variant(10)])
    end)

    assert {:ok, _} = Merch.sync_catalog(admin)

    expect(ClientMock, :get_sync_product, fn 1 ->
      {:error, %Error{type: :server, status: 503, message: "down"}}
    end)

    assert {:ok, %{products: 0, failed: 1, removed: 0}} =
             Merch.sync_catalog(admin)

    assert Repo.get_by!(Product, printful_product_id: 1).status == :active
  end

  test "a failed product list changes nothing", %{admin: admin} do
    expect(ClientMock, :list_sync_products, fn ->
      {:error, %Error{type: :auth, status: 401, message: "bad token"}}
    end)

    assert {:error, %Error{type: :auth}} = Merch.sync_catalog(admin)
    assert Repo.aggregate(Product, :count) == 0
  end

  test "a variant with no usable price fails only its product", %{admin: admin} do
    expect(ClientMock, :list_sync_products, fn ->
      {:ok, [listed(1), listed(2)]}
    end)

    expect(ClientMock, :get_sync_product, 2, fn
      1 -> detail(listed(1), [sync_variant(10, %{"retail_price" => nil})])
      2 -> detail(listed(2), [sync_variant(20)])
    end)

    assert {:ok, %{products: 1, failed: 1}} = Merch.sync_catalog(admin)
    assert Repo.get_by(Product, printful_product_id: 1) == nil
    assert Repo.get_by!(Product, printful_product_id: 2)
  end

  describe "images" do
    test "are copied into the media library and shared across variants", %{
      admin: admin
    } do
      expect(ClientMock, :list_sync_products, fn -> {:ok, [listed(1)]} end)

      same_preview = [
        %{"type" => "preview", "preview_url" => "https://img/black.png"}
      ]

      expect(ClientMock, :get_sync_product, fn 1 ->
        detail(listed(1), [
          sync_variant(10, %{"files" => same_preview}),
          sync_variant(11, %{"files" => same_preview, "size" => "L"})
        ])
      end)

      assert {:ok, %{images_failed: 0}} = Merch.sync_catalog(admin)

      # one download for the product thumbnail, one for the shared variant image
      assert Enum.sort(downloads()) == ["/1.png", "/black.png"]

      [v1, v2] =
        Repo.all(from(v in Variant, order_by: v.printful_sync_variant_id))

      assert v1.image_id && v1.image_id == v2.image_id

      image = Repo.get!(Ysc.Media.Image, v1.image_id)
      assert image.title == "Product 1 - Black"
      assert image.user_id == admin.id
      assert image.raw_image_path =~ "/merch/"
      assert %{"key" => "merch/" <> _} = image.upload_data
    end

    test "an unchanged source URL is not downloaded again", %{admin: admin} do
      expect(ClientMock, :list_sync_products, 2, fn -> {:ok, [listed(1)]} end)

      expect(ClientMock, :get_sync_product, 2, fn 1 ->
        detail(listed(1), [sync_variant(10)])
      end)

      assert {:ok, _} = Merch.sync_catalog(admin)
      assert length(downloads()) == 2

      image_id = Repo.get_by!(Product, printful_product_id: 1).image_id

      assert {:ok, _} = Merch.sync_catalog(admin)
      assert downloads() == []
      assert Repo.get_by!(Product, printful_product_id: 1).image_id == image_id
    end

    test "a changed source URL imports a fresh image", %{admin: admin} do
      expect(ClientMock, :list_sync_products, 2, fn -> {:ok, [listed(1)]} end)

      expect(ClientMock, :get_sync_product, fn 1 ->
        detail(listed(1), [sync_variant(10)])
      end)

      assert {:ok, _} = Merch.sync_catalog(admin)
      old = Repo.get_by!(Product, printful_product_id: 1)
      downloads()

      expect(ClientMock, :get_sync_product, fn 1 ->
        detail(Map.put(listed(1), "thumbnail_url", "https://img/new.png"), [
          sync_variant(10)
        ])
      end)

      assert {:ok, _} = Merch.sync_catalog(admin)

      assert "/new.png" in downloads()
      new = Repo.get_by!(Product, printful_product_id: 1)
      assert new.source_image_url == "https://img/new.png"
      assert new.image_id != old.image_id
    end

    test "a failed download does not fail the sync", %{admin: admin} do
      Req.Test.stub(Ysc.Merch.ImageImport, fn conn ->
        Plug.Conn.send_resp(conn, 404, "nope")
      end)

      expect(ClientMock, :list_sync_products, fn -> {:ok, [listed(1)]} end)

      expect(ClientMock, :get_sync_product, fn 1 ->
        detail(listed(1), [sync_variant(10)])
      end)

      assert {:ok, %{products: 1, variants: 1, failed: 0, images_failed: 2}} =
               Merch.sync_catalog(admin)

      product = Repo.get_by!(Product, printful_product_id: 1)
      assert product.image_id == nil
      assert product.source_image_url == nil
    end

    test "a failed re-import keeps the previous image and retries next time", %{
      admin: admin
    } do
      expect(ClientMock, :list_sync_products, 2, fn -> {:ok, [listed(1)]} end)

      expect(ClientMock, :get_sync_product, fn 1 ->
        detail(listed(1), [sync_variant(10)])
      end)

      assert {:ok, _} = Merch.sync_catalog(admin)
      old = Repo.get_by!(Product, printful_product_id: 1)

      Req.Test.stub(Ysc.Merch.ImageImport, fn conn ->
        Plug.Conn.send_resp(conn, 500, "boom")
      end)

      expect(ClientMock, :get_sync_product, fn 1 ->
        detail(Map.put(listed(1), "thumbnail_url", "https://img/new.png"), [
          sync_variant(10)
        ])
      end)

      assert {:ok, %{images_failed: 1}} = Merch.sync_catalog(admin)

      kept = Repo.get_by!(Product, printful_product_id: 1)
      assert kept.image_id == old.image_id
      # old URL retained, so the next sync sees it as changed and retries
      assert kept.source_image_url == old.source_image_url
    end

    test "a product with no image still syncs", %{admin: admin} do
      expect(ClientMock, :list_sync_products, fn -> {:ok, [listed(1)]} end)

      expect(ClientMock, :get_sync_product, fn 1 ->
        detail(Map.put(listed(1), "thumbnail_url", nil), [
          sync_variant(10, %{"files" => []})
        ])
      end)

      assert {:ok, %{products: 1, images_failed: 0}} = Merch.sync_catalog(admin)
      assert downloads() == []
      assert Repo.get_by!(Product, printful_product_id: 1).image_id == nil
    end
  end

  describe "gallery" do
    alias Ysc.Merch.ProductImage

    defp previews(urls),
      do: Enum.map(urls, &%{"type" => "preview", "preview_url" => &1})

    defp gallery(product_printful_id) do
      product = Repo.get_by!(Product, printful_product_id: product_printful_id)

      from(g in ProductImage,
        where: g.product_id == ^product.id,
        order_by: [asc: g.color, asc: g.position]
      )
      |> Repo.all()
    end

    test "each color gets its own mockups, in order", %{admin: admin} do
      expect(ClientMock, :list_sync_products, fn -> {:ok, [listed(1)]} end)

      expect(ClientMock, :get_sync_product, fn 1 ->
        detail(listed(1), [
          sync_variant(10, %{
            "color" => "Black",
            "size" => "S",
            "files" =>
              previews(["https://img/b-front.png", "https://img/b-back.png"])
          }),
          sync_variant(11, %{
            "color" => "Black",
            "size" => "M",
            "files" =>
              previews(["https://img/b-front.png", "https://img/b-back.png"])
          }),
          sync_variant(12, %{
            "color" => "White",
            "size" => "S",
            "files" => previews(["https://img/w-front.png"])
          })
        ])
      end)

      assert {:ok, %{images_failed: 0}} = Merch.sync_catalog(admin)

      photos = gallery(1)

      assert Enum.map(photos, &{&1.color, &1.position, &1.source}) == [
               {"Black", 0, :printful},
               {"Black", 1, :printful},
               {"White", 0, :printful}
             ]

      assert Enum.map(photos, & &1.source_image_url) == [
               "https://img/b-front.png",
               "https://img/b-back.png",
               "https://img/w-front.png"
             ]

      # Sizes of one color share photos, so each URL was downloaded once.
      fetched = downloads()

      for path <- ["/b-front.png", "/b-back.png", "/w-front.png"] do
        assert Enum.count(fetched, &(&1 == path)) == 1
      end

      product =
        Merch.get_shop_product(Repo.get_by!(Product, printful_product_id: 1).id)

      assert length(Merch.gallery(product, "Black")) == 2
      assert length(Merch.gallery(product, "White")) == 1
    end

    test "print artwork is not a product photo", %{admin: admin} do
      expect(ClientMock, :list_sync_products, fn -> {:ok, [listed(1)]} end)

      expect(ClientMock, :get_sync_product, fn 1 ->
        detail(listed(1), [
          sync_variant(10, %{
            "color" => "Black",
            "files" => [
              %{
                "type" => "default",
                "preview_url" => "https://img/artwork.png"
              },
              %{
                "type" => "back",
                "preview_url" => "https://img/back-artwork.png"
              },
              %{"type" => "preview", "preview_url" => "https://img/mockup.png"}
            ]
          })
        ])
      end)

      assert {:ok, _} = Merch.sync_catalog(admin)
      assert [%{source_image_url: "https://img/mockup.png"}] = gallery(1)
    end

    test "a product without colors gets general photos", %{admin: admin} do
      expect(ClientMock, :list_sync_products, fn -> {:ok, [listed(1)]} end)

      expect(ClientMock, :get_sync_product, fn 1 ->
        detail(listed(1), [
          sync_variant(10, %{
            "color" => nil,
            "files" => previews(["https://img/a.png", "https://img/b.png"])
          })
        ])
      end)

      assert {:ok, _} = Merch.sync_catalog(admin)

      assert [%{color: nil, position: 0}, %{color: nil, position: 1}] =
               gallery(1)
    end

    test "re-sync drops mockups Printful no longer has but keeps the club's photos",
         %{admin: admin} do
      expect(ClientMock, :list_sync_products, 2, fn -> {:ok, [listed(1)]} end)

      expect(ClientMock, :get_sync_product, fn 1 ->
        detail(listed(1), [
          sync_variant(10, %{
            "color" => "Black",
            "files" => previews(["https://img/a.png", "https://img/b.png"])
          })
        ])
      end)

      assert {:ok, _} = Merch.sync_catalog(admin)
      product = Repo.get_by!(Product, printful_product_id: 1)
      mine = gallery_photo_fixture(product, nil, %{color: "Black", position: 9})

      expect(ClientMock, :get_sync_product, fn 1 ->
        detail(listed(1), [
          sync_variant(10, %{
            "color" => "Black",
            "files" => previews(["https://img/a.png"])
          })
        ])
      end)

      assert {:ok, _} = Merch.sync_catalog(admin)

      remaining = gallery(1)
      assert Enum.sort(Enum.map(remaining, & &1.source)) == [:admin, :printful]
      assert Enum.any?(remaining, &(&1.id == mine.id))

      assert Enum.find(remaining, &(&1.source == :printful)).source_image_url ==
               "https://img/a.png"
    end

    test "re-sync does not duplicate or re-download photos", %{admin: admin} do
      expect(ClientMock, :list_sync_products, 2, fn -> {:ok, [listed(1)]} end)

      expect(ClientMock, :get_sync_product, 2, fn 1 ->
        detail(listed(1), [
          sync_variant(10, %{
            "color" => "Black",
            "files" => previews(["https://img/a.png"])
          })
        ])
      end)

      assert {:ok, _} = Merch.sync_catalog(admin)
      downloads()
      count = length(gallery(1))

      assert {:ok, _} = Merch.sync_catalog(admin)
      assert length(gallery(1)) == count
      assert downloads() == []
    end

    test "a photo that fails to download is skipped, the rest are kept", %{
      admin: admin
    } do
      Req.Test.stub(Ysc.Merch.ImageImport, fn conn ->
        if conn.request_path == "/bad.png",
          do: Plug.Conn.send_resp(conn, 404, "nope"),
          else:
            conn
            |> Plug.Conn.put_resp_content_type("image/png")
            |> Plug.Conn.send_resp(200, @png)
      end)

      expect(ClientMock, :list_sync_products, fn -> {:ok, [listed(1)]} end)

      expect(ClientMock, :get_sync_product, fn 1 ->
        detail(listed(1), [
          sync_variant(10, %{
            "color" => "Black",
            "files" => previews(["https://img/bad.png", "https://img/good.png"])
          })
        ])
      end)

      assert {:ok, %{products: 1}} = Merch.sync_catalog(admin)
      assert [%{source_image_url: "https://img/good.png"}] = gallery(1)
    end

    test "a photo the club already uses is left as the club's", %{admin: admin} do
      expect(ClientMock, :list_sync_products, 2, fn -> {:ok, [listed(1)]} end)

      expect(ClientMock, :get_sync_product, 2, fn 1 ->
        detail(listed(1), [
          sync_variant(10, %{
            "color" => "Black",
            "files" => previews(["https://img/a.png"])
          })
        ])
      end)

      assert {:ok, _} = Merch.sync_catalog(admin)
      product = Repo.get_by!(Product, printful_product_id: 1)
      [photo] = gallery(1)

      # The club takes over the photo, as if they had added it themselves.
      photo
      |> Ecto.Changeset.change(source: :admin, color: nil)
      |> Repo.update!()

      assert {:ok, _} = Merch.sync_catalog(admin)

      assert [%{id: id, source: :admin, color: nil}] = gallery(1)
      assert id == photo.id
      assert product.id == photo.product_id
    end
  end
end
