defmodule YscWeb.AdminMerchLiveTest do
  use YscWeb.ConnCase, async: false, mox_global_first: true

  import Mox
  import Phoenix.LiveViewTest

  import Ysc.MerchFixtures,
    only: [
      gallery_photo_fixture: 1,
      gallery_photo_fixture: 3,
      image_fixture: 0,
      image_fixture: 1
    ]

  import Ysc.AccountsFixtures

  alias Ysc.Merch.{Product, Variant}
  alias Ysc.Printful.ClientMock
  alias Ysc.Repo

  setup :verify_on_exit!

  defp product!(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    product =
      %Product{}
      |> Product.sync_changeset(%{printful_product_id: n, name: "Tee #{n}"})
      |> Ecto.Changeset.change(Map.take(attrs, [:status]))
      |> Repo.insert!()

    %Variant{}
    |> Variant.sync_changeset(%{
      product_id: product.id,
      printful_sync_variant_id: n,
      printful_variant_id: n + 1,
      name: "Tee / M",
      retail_price: Money.new(:USD, "25")
    })
    |> Repo.insert!()

    product
  end

  describe "as a full admin" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(conn, admin)}
    end

    test "shows an empty state before the first sync", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/merch")
      assert has_element?(view, "#merch-empty")
      assert has_element?(view, "#sync-merch-catalog")
    end

    test "warns that merch is a work in progress", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/merch")
      assert has_element?(view, "#merch-wip-banner")
      assert has_element?(view, "#merch-nav-wip-badge", "WIP")
    end

    test "lists products with their visibility", %{conn: conn} do
      shown = product!()
      hidden = product!(%{status: :hidden})

      {:ok, view, _html} = live(conn, ~p"/admin/merch")

      assert has_element?(view, "#merch-product-#{shown.id}")
      assert has_element?(view, "#merch-product-status-#{shown.id}", "Visible")
      assert has_element?(view, "#merch-product-status-#{hidden.id}", "Hidden")
    end

    test "hide and show toggles the product", %{conn: conn} do
      product = product!()
      {:ok, view, _html} = live(conn, ~p"/admin/merch")

      view |> element("#toggle-merch-product-#{product.id}") |> render_click()
      assert Repo.reload!(product).status == :hidden
      assert has_element?(view, "#merch-product-status-#{product.id}", "Hidden")

      view |> element("#toggle-merch-product-#{product.id}") |> render_click()
      assert Repo.reload!(product).status == :active
    end

    test "edits the description", %{conn: conn} do
      product = product!()

      {:ok, view, _html} =
        live(conn, ~p"/admin/merch/products/#{product.id}/edit")

      assert has_element?(view, "#merch-product-form")

      view
      |> form("#merch-product-form", product: %{description: "Soft cotton tee"})
      |> render_submit()

      assert_patch(view, ~p"/admin/merch")
      assert Repo.reload!(product).description == "Soft cotton tee"
    end

    test "unknown product id redirects back to the list", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/merch"}}} =
               live(
                 conn,
                 ~p"/admin/merch/products/#{Ecto.ULID.generate()}/edit"
               )
    end

    test "sync pulls the catalog from Printful", %{conn: conn} do
      expect(ClientMock, :list_sync_products, fn ->
        {:ok, [%{"id" => 7, "name" => "Sticker", "thumbnail_url" => nil}]}
      end)

      expect(ClientMock, :get_sync_product, fn 7 ->
        {:ok,
         %{
           "sync_product" => %{"id" => 7, "name" => "Sticker"},
           "sync_variants" => [
             %{
               "id" => 70,
               "variant_id" => 700,
               "name" => "Sticker",
               "retail_price" => "3.00"
             }
           ]
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/merch")
      view |> element("#sync-merch-catalog") |> render_click()
      render_async(view)

      assert %Product{name: "Sticker"} =
               Repo.get_by!(Product, printful_product_id: 7)

      assert has_element?(view, "#merch-products")
    end

    test "a failed sync leaves the page usable", %{conn: conn} do
      expect(ClientMock, :list_sync_products, fn ->
        {:error,
         %Ysc.Printful.Error{type: :auth, status: 401, message: "bad token"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/merch")
      view |> element("#sync-merch-catalog") |> render_click()
      render_async(view)

      assert has_element?(view, "#sync-merch-catalog:not([disabled])")
    end
  end

  describe "webhook registration" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(conn, admin)}
    end

    test "registers the callback with Printful", %{conn: conn} do
      expect(ClientMock, :set_webhooks, fn url, types ->
        assert url =~ "/webhooks/printful/test-printful-webhook-secret"
        assert "package_shipped" in types
        {:ok, %{"url" => url}}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/merch")
      view |> element("#register-merch-webhooks") |> render_click()
      render_async(view)

      assert has_element?(view, "#register-merch-webhooks:not([disabled])")
    end

    test "tells the admin when no secret is configured", %{conn: conn} do
      original = Application.get_env(:ysc, :printful)
      on_exit(fn -> Application.put_env(:ysc, :printful, original) end)
      Application.put_env(:ysc, :printful, api_token: "t", webhook_secret: nil)

      {:ok, view, _html} = live(conn, ~p"/admin/merch")
      view |> element("#register-merch-webhooks") |> render_click()
      render_async(view)

      assert has_element?(view, "#register-merch-webhooks:not([disabled])")
    end

    test "survives a Printful error", %{conn: conn} do
      expect(ClientMock, :set_webhooks, fn _, _ ->
        {:error,
         %Ysc.Printful.Error{
           type: :invalid,
           status: 400,
           message: "URL must be https"
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/merch")
      view |> element("#register-merch-webhooks") |> render_click()
      render_async(view)

      assert has_element?(view, "#register-merch-webhooks:not([disabled])")
    end
  end

  describe "product photos" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      product = product!()

      for color <- ["Black", "White"] do
        %Variant{}
        |> Variant.sync_changeset(%{
          product_id: product.id,
          printful_sync_variant_id: System.unique_integer([:positive]),
          printful_variant_id: System.unique_integer([:positive]),
          name: "Tee / #{color}",
          color: color,
          retail_price: Money.new(:USD, "25")
        })
        |> Repo.insert!()
      end

      %{conn: log_in_user(conn, admin), product: product}
    end

    defp edit_path(product), do: ~p"/admin/merch/products/#{product.id}/edit"

    test "shows the empty state and the picker", %{conn: conn, product: product} do
      {:ok, view, _html} = live(conn, edit_path(product))

      assert has_element?(view, "#merch-photos-empty")
      assert has_element?(view, "#merch-add-photo")
    end

    test "Printful photos are listed but cannot be edited or removed", %{
      conn: conn,
      product: product
    } do
      photo =
        gallery_photo_fixture(product, nil, %{source: :printful, color: "Black"})

      {:ok, view, _html} = live(conn, edit_path(product))

      assert has_element?(view, "#merch-photo-#{photo.id}", "From Printful")
      assert has_element?(view, "#merch-photo-#{photo.id}", "Black")
      assert has_element?(view, "#merch-photo-first-#{photo.id}")
      refute has_element?(view, "#merch-photo-remove-#{photo.id}")
      refute has_element?(view, "#merch-photo-color-#{photo.id}")
    end

    test "a photo from the media library is added to the gallery", %{
      conn: conn,
      product: product
    } do
      image = image_fixture(%{title: "Back print"})
      {:ok, view, _html} = live(conn, edit_path(product))

      send(view.pid, {YscWeb.MediaPickerComponent, :merch_add_photo, image.id})
      _ = render(view)

      assert [%{image_id: image_id, source: :admin, color: nil}] =
               Repo.all(Ysc.Merch.ProductImage)

      assert image_id == image.id
      assert render(view) =~ "Back print"
      refute has_element?(view, "#merch-photos-empty")
    end

    test "adding the same photo twice is explained, not a crash", %{
      conn: conn,
      product: product
    } do
      image = image_fixture()
      {:ok, view, _html} = live(conn, edit_path(product))

      send(view.pid, {YscWeb.MediaPickerComponent, :merch_add_photo, image.id})
      send(view.pid, {YscWeb.MediaPickerComponent, :merch_add_photo, image.id})
      render(view)

      assert Repo.aggregate(Ysc.Merch.ProductImage, :count) == 1
    end

    test "clearing the picker does nothing", %{conn: conn, product: product} do
      {:ok, view, _html} = live(conn, edit_path(product))
      send(view.pid, {YscWeb.MediaPickerComponent, :merch_add_photo, :cleared})
      assert render(view) =~ "Photos"
    end

    test "a club photo can be tied to a color, then to all colors again", %{
      conn: conn,
      product: product
    } do
      photo = gallery_photo_fixture(product)
      {:ok, view, _html} = live(conn, edit_path(product))

      view
      |> form("#merch-photo-color-form-#{photo.id}", %{"color" => "White"})
      |> render_change()

      assert Repo.reload!(photo).color == "White"

      view
      |> form("#merch-photo-color-form-#{photo.id}", %{"color" => ""})
      |> render_change()

      assert Repo.reload!(photo).color == nil
    end

    test "only the product's own colors are offered", %{
      conn: conn,
      product: product
    } do
      photo = gallery_photo_fixture(product)
      {:ok, view, _html} = live(conn, edit_path(product))

      html = view |> element("#merch-photo-color-#{photo.id}") |> render()
      assert html =~ "Black"
      assert html =~ "White"
      assert html =~ "All colors"
    end

    test "make first reorders", %{conn: conn, product: product} do
      first = gallery_photo_fixture(product, nil, %{position: 0})
      second = gallery_photo_fixture(product, nil, %{position: 1})
      {:ok, view, _html} = live(conn, edit_path(product))

      view |> element("#merch-photo-first-#{second.id}") |> render_click()

      assert Repo.reload!(second).position < Repo.reload!(first).position
    end

    test "a club photo can be removed", %{conn: conn, product: product} do
      photo = gallery_photo_fixture(product)
      {:ok, view, _html} = live(conn, edit_path(product))

      view |> element("#merch-photo-remove-#{photo.id}") |> render_click()

      assert Repo.get(Ysc.Merch.ProductImage, photo.id) == nil
      assert has_element?(view, "#merch-photos-empty")
    end

    test "acting on a photo that vanished meanwhile is handled", %{
      conn: conn,
      product: product
    } do
      photo = gallery_photo_fixture(product)
      {:ok, view, _html} = live(conn, edit_path(product))

      Repo.delete!(photo)
      render_click(view, "photo_remove", %{"id" => photo.id})
      render_click(view, "photo_first", %{"id" => photo.id})

      assert has_element?(view, "#merch-photos-empty")
    end

    test "a forged remove of a Printful photo is refused", %{
      conn: conn,
      product: product
    } do
      photo = gallery_photo_fixture(product, nil, %{source: :printful})
      {:ok, view, _html} = live(conn, edit_path(product))

      render_click(view, "photo_remove", %{"id" => photo.id})

      render_change(view, "photo_color", %{
        "photo_id" => photo.id,
        "color" => "Black"
      })

      reloaded = Repo.reload!(photo)
      assert reloaded.color == nil
      assert reloaded.source == :printful
    end
  end

  describe "access control" do
    test "members are redirected away", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {kind, _}} = live(conn, ~p"/admin/merch")
      assert kind in [:redirect, :live_redirect]
    end

    test "anonymous visitors are redirected", %{conn: conn} do
      assert {:error, {kind, _}} = live(conn, ~p"/admin/merch")
      assert kind in [:redirect, :live_redirect]
    end
  end
end
