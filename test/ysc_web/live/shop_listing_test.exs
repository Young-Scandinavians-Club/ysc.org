defmodule YscWeb.ShopListingTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.MerchFixtures
  import YscWeb.ShopLiveHelpers

  setup %{conn: conn} do
    tee = product_fixture(%{name: "Club Tee"})

    for {color, size} <- [{"Black", "S"}, {"Black", "XL"}, {"Navy", "M"}] do
      variant_fixture(tee, %{
        name: "Club Tee / #{color} / #{size}",
        color: color,
        size: size,
        retail_price: Money.new(:USD, "25")
      })
    end

    sticker = product_fixture(%{name: "Sticker"})
    variant_fixture(sticker, %{retail_price: Money.new(:USD, "3")})

    hoodie = product_fixture(%{name: "Hoodie"})

    variant_fixture(hoodie, %{
      color: "Navy",
      size: "M",
      retail_price: Money.new(:USD, "55")
    })

    %{
      conn: log_in_user(conn, member_fixture()),
      tee: tee,
      sticker: sticker,
      hoodie: hoodie
    }
  end

  defp live_shop(conn, path \\ ~p"/shop") do
    {:ok, view, _html} = live(conn, path)
    html = render_async(view)
    {:ok, view, html}
  end

  defp product_ids(view) do
    render_async(view)

    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#shop-products > li")
    |> LazyHTML.attribute("id")
  end

  test "static HTML paints a catalog skeleton before products load", %{
    conn: conn
  } do
    html = conn |> get(~p"/shop") |> html_response(200)
    assert html =~ ~s(id="shop-loading")
    refute html =~ ~s(id="shop-products")
    refute html =~ ~s(id="shop-empty")
  end

  test "static HTML paints a product skeleton before the product loads", %{
    conn: conn,
    tee: tee
  } do
    html = conn |> get(~p"/shop/products/#{tee.id}") |> html_response(200)
    assert html =~ ~s(id="shop-product-loading")
    refute html =~ ~s(id="add-to-cart-form")
  end

  test "shows how many items there are", %{conn: conn} do
    {:ok, view, _html} = live_shop(conn)
    assert has_element?(view, "#shop-count", "3 items")
  end

  test "tiles show a swatch per color and details", %{
    conn: conn,
    tee: tee,
    sticker: sticker
  } do
    {:ok, view, _html} = live_shop(conn)

    assert has_element?(view, "#shop-swatch-#{tee.id}-black[aria-pressed=true]")
    assert has_element?(view, "#shop-swatch-#{tee.id}-navy[aria-pressed=false]")
    assert has_element?(view, "#shop-details-#{tee.id}", "S–XL")
    assert has_element?(view, "#shop-layer-#{tee.id}-navy")

    # No colors, no swatches.
    refute has_element?(view, "#shop-swatches-#{sticker.id}")
  end

  test "photos show a server-rendered blur preview until they load", %{
    conn: conn,
    tee: tee
  } do
    image = image_fixture(%{blur_hash: "LlMF%n00%#MwS|WCWEM{R*bbWBbH"})
    gallery_photo_fixture(tee, image, %{color: "Black"})

    {:ok, view, _html} = live_shop(conn)

    assert has_element?(
             view,
             "#shop-layer-#{tee.id}-black .shop-photo-bg[style*='data:image/png;base64,']"
           )

    assert has_element?(
             view,
             "#shop-layer-#{tee.id}-black img.shop-photo-img[loading=lazy]"
           )
  end

  test "a photo with an unusable blur hash still renders, with no preview", %{
    conn: conn,
    tee: tee
  } do
    image = image_fixture(%{blur_hash: "not a blur hash"})
    gallery_photo_fixture(tee, image, %{color: "Black"})

    {:ok, view, _html} = live_shop(conn)

    assert has_element?(view, "#shop-layer-#{tee.id}-black img.shop-photo-img")

    refute has_element?(
             view,
             "#shop-layer-#{tee.id}-black .shop-photo-bg[style*='data:image']"
           )
  end

  test "making a color's photo first makes it the default color", %{
    conn: conn,
    tee: tee
  } do
    # "Black" sorts before "Navy" among equal prices, so Black leads by default.
    navy = gallery_photo_fixture(tee, nil, %{color: "Navy", position: 0})
    gallery_photo_fixture(tee, nil, %{color: "Black", position: 0})
    assert :ok = Ysc.Merch.move_photo_first(navy.id)

    {:ok, view, _html} = live_shop(conn)

    assert has_element?(view, "#shop-swatch-#{tee.id}-navy[aria-pressed=true]")
    assert has_element?(view, "#shop-layer-#{tee.id}-navy[data-active]")

    assert has_element?(
             view,
             "#shop-product-link-#{tee.id}[href='/shop/products/#{tee.id}?color=Navy']"
           )

    {:ok, view, _html} = live_shop_page(conn, ~p"/shop/products/#{tee.id}")
    assert has_element?(view, "#color-navy[aria-pressed=true]")
  end

  test "a tile opens the product in its color", %{conn: conn, tee: tee} do
    {:ok, view, _html} = live_shop(conn)

    assert has_element?(
             view,
             "#shop-product-link-#{tee.id}[href='/shop/products/#{tee.id}?color=Black']"
           )
  end

  test "the product page opens on the chosen color", %{conn: conn, tee: tee} do
    {:ok, view, _html} =
      live_shop_page(conn, ~p"/shop/products/#{tee.id}?color=Navy")

    assert has_element?(view, "#color-navy[aria-pressed=true]")

    {:ok, view, _html} =
      live_shop_page(conn, ~p"/shop/products/#{tee.id}?color=Nonsense")

    assert has_element?(view, "#color-black[aria-pressed=true]")
  end

  describe "sorting" do
    test "orders the tiles and keeps the choice in the URL", %{
      conn: conn,
      tee: tee,
      sticker: sticker,
      hoodie: hoodie
    } do
      {:ok, view, _html} = live_shop(conn)

      view |> form("#shop-sort-form", %{sort: "price_desc"}) |> render_change()
      assert_patch(view, ~p"/shop?#{[sort: "price_desc"]}")

      assert product_ids(view) == [
               "shop-product-#{hoodie.id}",
               "shop-product-#{tee.id}",
               "shop-product-#{sticker.id}"
             ]
    end

    test "a link with a sort opens already sorted", %{
      conn: conn,
      sticker: sticker
    } do
      {:ok, view, _html} = live_shop(conn, ~p"/shop?#{[sort: "price_asc"]}")
      assert List.first(product_ids(view)) == "shop-product-#{sticker.id}"
      assert has_element?(view, "#shop-sort option[value=price_asc][selected]")
    end
  end

  describe "color filter" do
    test "narrows the list and shows removable pills", %{
      conn: conn,
      tee: tee,
      sticker: sticker,
      hoodie: hoodie
    } do
      {:ok, view, _html} = live_shop(conn)

      view |> element("#shop-filter-color-black") |> render_click()
      assert_patch(view, ~p"/shop?#{[colors: ["Black"]]}")

      assert product_ids(view) == ["shop-product-#{tee.id}"]
      assert has_element?(view, "#shop-count", "1 item")
      assert has_element?(view, "#shop-filter-count", "1")
      assert has_element?(view, "#shop-remove-filter-black")
      refute has_element?(view, "#shop-product-#{sticker.id}")
      refute has_element?(view, "#shop-product-#{hoodie.id}")
    end

    test "tiles open on the filtered color", %{conn: conn, tee: tee} do
      {:ok, view, _html} = live_shop(conn, ~p"/shop?#{[colors: ["Navy"]]}")

      assert has_element?(
               view,
               "#shop-swatch-#{tee.id}-navy[aria-pressed=true]"
             )
    end

    test "colors combine, and pills remove one at a time", %{conn: conn} do
      {:ok, view, _html} =
        live_shop(conn, ~p"/shop?#{[colors: ["Black", "Navy"]]}")

      assert has_element?(view, "#shop-count", "2 items")

      view |> element("#shop-remove-filter-black") |> render_click()
      refute has_element?(view, "#shop-remove-filter-black")
      assert has_element?(view, "#shop-remove-filter-navy")
    end

    test "Clear all brings everything back", %{conn: conn} do
      {:ok, view, _html} = live_shop(conn, ~p"/shop?#{[colors: ["Black"]]}")
      view |> element("#shop-clear-filters") |> render_click()

      assert_patch(view, ~p"/shop")
      assert has_element?(view, "#shop-count", "3 items")
      refute has_element?(view, "#shop-active-filters")
    end

    test "ignores colors no product has", %{conn: conn} do
      {:ok, view, _html} =
        live_shop(conn, ~p"/shop?#{[colors: ["Chartreuse"]]}")

      assert has_element?(view, "#shop-count", "3 items")
      refute has_element?(view, "#shop-active-filters")
    end

    test "sorting keeps the filter", %{conn: conn} do
      {:ok, view, _html} = live_shop(conn, ~p"/shop?#{[colors: ["Navy"]]}")
      view |> form("#shop-sort-form", %{sort: "name"}) |> render_change()

      assert_patch(view, ~p"/shop?#{[sort: "name", colors: ["Navy"]]}")
      assert has_element?(view, "#shop-count", "2 items")
    end
  end

  describe "good to know" do
    test "answers the questions members have, collapsed by default", %{
      conn: conn
    } do
      {:ok, view, _html} = live_shop(conn)

      assert has_element?(view, "#shop-faq")
      assert has_element?(view, "#shop-faq-does-the-club-make-money summary")

      assert has_element?(
               view,
               "#shop-faq-does-the-club-make-money",
               "does not"
             )

      assert has_element?(view, "#shop-faq-delivery-time", "printed to order")
      assert has_element?(view, "#shop-faq-contact[href='mailto:info@ysc.org']")
      refute has_element?(view, "#shop-faq details[open]")
    end

    test "survives sorting and filtering", %{conn: conn} do
      {:ok, view, _html} = live_shop(conn)
      view |> element("#shop-filter-color-black") |> render_click()
      assert has_element?(view, "#shop-faq")
    end

    test "is not shown while the shop is empty", %{conn: conn} do
      Ysc.Repo.delete_all(Ysc.Merch.Variant)
      {:ok, view, _html} = live_shop(conn)
      assert has_element?(view, "#shop-empty")
      refute has_element?(view, "#shop-faq")
    end
  end
end
