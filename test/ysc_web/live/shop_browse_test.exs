defmodule YscWeb.ShopBrowseTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Merch.Cart

  defp tee_product do
    product = product_fixture(%{name: "Club Tee"})

    variants =
      for {color, size, price} <- [
            {"Black", "S", "25"},
            {"Black", "M", "25"},
            {"Black", "XL", "27"},
            {"White", "M", "25"}
          ] do
        variant_fixture(product, %{
          name: "Club Tee / #{color} / #{size}",
          color: color,
          size: size,
          retail_price: Money.new(:USD, price)
        })
      end

    %{product: product, variants: variants}
  end

  describe "access" do
    test "visitors are sent to sign in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/shop")
    end

    test "non-members are sent to the membership page", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      assert {:error, {:redirect, %{to: "/users/membership"}}} =
               live(conn, ~p"/shop")

      assert {:error, {:redirect, %{to: "/users/membership"}}} =
               live(conn, ~p"/shop/cart")
    end

    test "active members and admins can shop", %{conn: conn} do
      {:ok, _view, _html} = live(log_in_user(conn, member_fixture()), ~p"/shop")

      {:ok, _view, _html} =
        live(log_in_user(conn, user_fixture(%{role: "admin"})), ~p"/shop")
    end

    test "a lapsed member can still see their orders", %{conn: conn} do
      {:ok, view, _html} =
        live(log_in_user(conn, user_fixture()), ~p"/shop/orders")

      assert has_element?(view, "#orders-empty")
    end
  end

  describe "main navigation" do
    test "active members see a Shop link", %{conn: conn} do
      {:ok, view, _html} =
        live(log_in_user(conn, member_fixture()), ~p"/events")

      assert has_element?(view, "#nav-shop-desktop")
      assert has_element?(view, "#nav-shop-mobile")
    end

    test "non-members and visitors do not", %{conn: conn} do
      {:ok, view, _html} = live(log_in_user(conn, user_fixture()), ~p"/events")
      refute has_element?(view, "#nav-shop-desktop")

      {:ok, view, _html} = live(build_conn(), ~p"/events")
      refute has_element?(view, "#nav-shop-desktop")
    end
  end

  describe "shop index" do
    setup %{conn: conn} do
      member = member_fixture()
      %{conn: log_in_user(conn, member), member: member}
    end

    test "shows an empty state with nothing for sale", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop")
      assert has_element?(view, "#shop-empty")
      refute has_element?(view, "#shop-products")
    end

    test "lists products that can be bought, with a from-price", %{conn: conn} do
      %{product: product} = tee_product()
      sticker = product_fixture(%{name: "Sticker"})
      variant_fixture(sticker, %{retail_price: Money.new(:USD, "3")})

      hidden = product_fixture(%{name: "Secret Hoodie", status: :hidden})
      variant_fixture(hidden)

      {:ok, view, _html} = live(conn, ~p"/shop")

      assert has_element?(view, "#shop-product-#{product.id}", "Club Tee")
      assert has_element?(view, "#shop-product-#{product.id}", "From $25.00")
      assert has_element?(view, "#shop-product-#{sticker.id}", "$3.00")
      refute has_element?(view, "#shop-product-#{sticker.id}", "From")
      refute has_element?(view, "#shop-product-#{hidden.id}")
    end

    test "the nav shows the cart count", %{conn: conn, member: member} do
      %{variants: [variant | _]} = tee_product()
      {:ok, _} = Cart.add(member, variant.id, 3)

      {:ok, view, _html} = live(conn, ~p"/shop")
      assert has_element?(view, "#shop-cart-count", "3")
    end
  end

  describe "product page" do
    setup %{conn: conn} do
      member = member_fixture()

      %{conn: log_in_user(conn, member), member: member}
      |> Map.merge(tee_product())
    end

    test "needs a size before it can be added", %{conn: conn, product: product} do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      assert has_element?(view, "#add-to-cart[disabled]", "Choose a size")
      assert has_element?(view, "#shop-colors")
      assert has_element?(view, "#shop-sizes")
    end

    test "choosing options enables add to cart and shows the variant price", %{
      conn: conn,
      product: product
    } do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      view |> element("#size-xl") |> render_click()

      refute has_element?(view, "#add-to-cart[disabled]")
      assert has_element?(view, "#shop-product-price", "$27.00")
    end

    test "sizes a color lacks are disabled", %{conn: conn, product: product} do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      view |> element("#color-white") |> render_click()
      assert has_element?(view, "#size-xl[disabled]")
      assert has_element?(view, "#size-m:not([disabled])")
    end

    test "switching color drops a size that color lacks", %{
      conn: conn,
      product: product
    } do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      view |> element("#size-xl") |> render_click()
      refute has_element?(view, "#add-to-cart[disabled]")

      view |> element("#color-white") |> render_click()
      assert has_element?(view, "#add-to-cart[disabled]")
    end

    test "adds the chosen variant and quantity to the cart", %{
      conn: conn,
      product: product,
      member: member,
      variants: variants
    } do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      view |> element("#size-m") |> render_click()
      view |> form("#add-to-cart-form", %{quantity: "3"}) |> render_change()
      view |> form("#add-to-cart-form") |> render_submit()

      black_m = Enum.find(variants, &(&1.color == "Black" and &1.size == "M"))
      assert [%{variant: %{id: id}, quantity: 3}] = Cart.list(member)
      assert id == black_m.id
      assert has_element?(view, "#shop-cart-count", "3")
    end

    test "quantity is clamped", %{conn: conn, product: product, member: member} do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      view |> element("#size-m") |> render_click()
      view |> form("#add-to-cart-form", %{quantity: "9999"}) |> render_change()
      view |> form("#add-to-cart-form") |> render_submit()

      assert [%{quantity: 25}] = Cart.list(member)
    end

    test "an option that sold out meanwhile sends the member back to the shop",
         %{conn: conn, product: product, variants: variants} do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")
      view |> element("#size-m") |> render_click()

      black_m = Enum.find(variants, &(&1.color == "Black" and &1.size == "M"))
      black_m |> Ecto.Changeset.change(available: false) |> Ysc.Repo.update!()

      view |> form("#add-to-cart-form") |> render_submit()
      assert_redirect(view, ~p"/shop")
    end

    test "unknown and hidden products go back to the shop", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/shop"}}} =
               live(conn, ~p"/shop/products/#{Ecto.ULID.generate()}")

      assert {:error, {:live_redirect, %{to: "/shop"}}} =
               live(conn, ~p"/shop/products/not-an-id")

      hidden = product_fixture(%{status: :hidden})
      variant_fixture(hidden)

      assert {:error, {:live_redirect, %{to: "/shop"}}} =
               live(conn, ~p"/shop/products/#{hidden.id}")
    end

    test "products without options can be added straight away", %{
      conn: conn,
      member: member
    } do
      sticker = product_fixture(%{name: "Sticker"})
      variant = variant_fixture(sticker, %{color: nil, size: nil})

      {:ok, view, _html} = live(conn, ~p"/shop/products/#{sticker.id}")
      refute has_element?(view, "#shop-colors")
      refute has_element?(view, "#shop-sizes")
      refute has_element?(view, "#add-to-cart[disabled]")

      view |> form("#add-to-cart-form") |> render_submit()
      assert [%{variant: %{id: id}}] = Cart.list(member)
      assert id == variant.id
    end
  end

  describe "floating cart dock" do
    setup %{conn: conn} do
      member = member_fixture()

      %{conn: log_in_user(conn, member), member: member}
      |> Map.merge(tee_product())
    end

    defp add_tee(view, size \\ "#size-m", quantity \\ "1") do
      view |> element(size) |> render_click()

      view
      |> form("#add-to-cart-form", %{quantity: quantity})
      |> render_change()

      view |> form("#add-to-cart-form") |> render_submit()
    end

    test "is absent while the cart is empty", %{conn: conn, product: product} do
      {:ok, view, _html} = live(conn, ~p"/shop")
      refute has_element?(view, "#cart-dock")

      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")
      refute has_element?(view, "#cart-dock")
    end

    test "shows a pill with the count and subtotal when the cart has items", %{
      conn: conn,
      member: member,
      variants: [v | _]
    } do
      {:ok, _} = Cart.add(member, v.id, 2)

      {:ok, view, _html} = live(conn, ~p"/shop")

      assert has_element?(view, "#cart-pill[href='/shop/cart']")
      assert has_element?(view, "#cart-dock-count-2", "2")
      assert has_element?(view, "#cart-dock-subtotal", "$50.00")
      # No card until something is added in this visit.
      refute has_element?(view, "#cart-peek")
    end

    test "adding opens the card with what was added", %{
      conn: conn,
      product: product
    } do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")
      add_tee(view, "#size-m", "2")

      assert has_element?(view, ~s(#cart-peek[data-open="true"]))

      assert has_element?(
               view,
               "#cart-peek",
               "Viking Tee" |> then(fn _ -> product.name end)
             )

      assert has_element?(view, "#cart-peek", "Black / M")
      assert has_element?(view, "#cart-peek", "Qty 2")
      assert has_element?(view, "#cart-peek-view[href='/shop/cart']")
      assert has_element?(view, "#cart-peek-checkout[href='/shop/checkout']")
      assert has_element?(view, "#cart-dock-count-2")
      assert has_element?(view, "#cart-dock-subtotal", "$50.00")
      assert has_element?(view, "#cart-dock-status", "added to your cart")
    end

    test "the card can be dismissed, and stays rendered so it can animate out",
         %{conn: conn, product: product} do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")
      add_tee(view)

      view |> element("#cart-peek-dismiss") |> render_click()

      assert has_element?(view, ~s(#cart-peek[data-open="false"]))
      assert has_element?(view, ~s(#cart-peek[aria-hidden="true"]))
      assert has_element?(view, "#cart-pill")
      refute has_element?(view, "#cart-dock-status", "added")
    end

    test "Escape dismisses it", %{conn: conn, product: product} do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")
      add_tee(view)

      render_keydown(view, "dismiss_cart_peek", %{"key" => "Escape"})
      assert has_element?(view, ~s(#cart-peek[data-open="false"]))
    end

    test "closes itself when its timer fires", %{conn: conn, product: product} do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")
      add_tee(view)

      token = :sys.get_state(view.pid).socket.assigns.cart_peek_token
      send(view.pid, {:hide_cart_peek, token})

      assert render(view) =~ ~s(data-open="false")
    end

    test "a stale timer cannot close a card that was touched since", %{
      conn: conn,
      product: product
    } do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")
      add_tee(view)
      stale = :sys.get_state(view.pid).socket.assigns.cart_peek_token

      # Pointer arrives: the countdown is cancelled.
      render_hook(view, "pause_cart_peek", %{})
      send(view.pid, {:hide_cart_peek, stale})

      assert has_element?(view, ~s(#cart-peek[data-open="true"]))

      # Pointer leaves: a fresh countdown starts, and only its token closes it.
      render_hook(view, "resume_cart_peek", %{})
      fresh = :sys.get_state(view.pid).socket.assigns.cart_peek_token
      refute fresh == stale

      send(view.pid, {:hide_cart_peek, stale})
      assert has_element?(view, ~s(#cart-peek[data-open="true"]))

      send(view.pid, {:hide_cart_peek, fresh})
      assert render(view) =~ ~s(data-open="false")
    end

    test "adding again retargets the card and restarts the countdown", %{
      conn: conn,
      product: product
    } do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")
      add_tee(view, "#size-m")
      first = :sys.get_state(view.pid).socket.assigns.cart_peek_token

      view |> element("#size-s") |> render_click()
      view |> form("#add-to-cart-form") |> render_submit()

      assert has_element?(view, "#cart-peek", "Black / S")
      refute has_element?(view, "#cart-peek", "Black / M")
      assert has_element?(view, "#cart-dock-count-2")
      assert :sys.get_state(view.pid).socket.assigns.cart_peek_token != first

      # The first add's timer is now stale.
      send(view.pid, {:hide_cart_peek, first})
      assert has_element?(view, ~s(#cart-peek[data-open="true"]))
    end

    test "resuming after the card was dismissed does not reopen or schedule it",
         %{conn: conn, product: product} do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")
      add_tee(view)
      view |> element("#cart-peek-dismiss") |> render_click()
      token = :sys.get_state(view.pid).socket.assigns.cart_peek_token

      render_hook(view, "resume_cart_peek", %{})

      assert has_element?(view, ~s(#cart-peek[data-open="false"]))
      assert :sys.get_state(view.pid).socket.assigns.cart_peek_token == token
    end

    test "the dock is not on the cart page, where the cart is the page", %{
      conn: conn,
      member: member,
      variants: [v | _]
    } do
      {:ok, _} = Cart.add(member, v.id, 1)
      {:ok, view, _html} = live(conn, ~p"/shop/cart")
      refute has_element?(view, "#cart-dock")
    end
  end

  describe "product page: gallery, swatches, quantity" do
    setup %{conn: conn} do
      member = member_fixture()
      %{product: product} = tee = tee_product()

      black_front = image_fixture(%{title: "Black front"})
      black_back = image_fixture(%{title: "Black back"})
      white_front = image_fixture(%{title: "White front"})

      gallery_photo_fixture(product, black_front, %{color: "Black", position: 0})

      gallery_photo_fixture(product, black_back, %{color: "Black", position: 1})

      gallery_photo_fixture(product, white_front, %{color: "White", position: 0})

      Map.merge(
        %{
          conn: log_in_user(conn, member),
          member: member,
          black_front: black_front,
          black_back: black_back,
          white_front: white_front
        },
        tee
      )
    end

    test "shows the first photo of the selected color with thumbnails", %{
      conn: conn,
      product: product,
      black_front: front
    } do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      assert has_element?(view, "#image-product-photo-#{front.id}")
      assert has_element?(view, "#photo-thumbs li", "")
      assert has_element?(view, "#photo-thumb-0[aria-current=true]")
      assert has_element?(view, "#photo-thumb-1[aria-current=false]")
      assert has_element?(view, "#photo-counter", "1 / 2")
    end

    test "the main photo opens a full-screen viewer over the whole gallery", %{
      conn: conn,
      product: product
    } do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      assert has_element?(
               view,
               "#product-gallery[phx-hook=ProductLightbox][data-index='0']"
             )

      assert has_element?(view, "#photo-zoom[role=button][data-lightbox-open]")

      slides =
        view
        |> element("#product-gallery")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("data-slides")
        |> List.first()
        |> Jason.decode!()

      assert length(slides) == 2
      assert Enum.all?(slides, &is_binary(&1["href"]))
      assert Enum.all?(slides, &(&1["alt"] =~ product.name))
    end

    test "the viewer starts at the photo currently shown", %{
      conn: conn,
      product: product
    } do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      view |> element("#photo-thumb-1") |> render_click()
      assert has_element?(view, "#product-gallery[data-index='1']")

      # Swiping inside the viewer reports the slide back to the page.
      render_hook(view, "select_photo", %{"index" => 0})
      assert has_element?(view, "#product-gallery[data-index='0']")
    end

    test "choosing a thumbnail changes the main photo", %{
      conn: conn,
      product: product,
      black_back: back
    } do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      view |> element("#photo-thumb-1") |> render_click()

      assert has_element?(view, "#image-product-photo-#{back.id}")
      assert has_element?(view, "#photo-thumb-1[aria-current=true]")
      assert has_element?(view, "#photo-counter", "2 / 2")
    end

    test "next and previous wrap around", %{
      conn: conn,
      product: product,
      black_front: front,
      black_back: back
    } do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      view |> element("#photo-next") |> render_click()
      assert has_element?(view, "#image-product-photo-#{back.id}")

      view |> element("#photo-next") |> render_click()
      assert has_element?(view, "#image-product-photo-#{front.id}")

      view |> element("#photo-prev") |> render_click()
      assert has_element?(view, "#image-product-photo-#{back.id}")
    end

    test "picking a color swaps in that color's photos from the start", %{
      conn: conn,
      product: product,
      white_front: white,
      black_back: back
    } do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      view |> element("#photo-thumb-1") |> render_click()
      assert has_element?(view, "#image-product-photo-#{back.id}")

      view |> element("#color-white") |> render_click()

      assert has_element?(view, "#image-product-photo-#{white.id}")
      refute has_element?(view, "#photo-thumbs")
      refute has_element?(view, "#photo-next")

      view |> element("#color-black") |> render_click()
      assert has_element?(view, "#photo-thumb-0[aria-current=true]")
    end

    test "a bogus photo index is clamped", %{conn: conn, product: product} do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      render_click(view, "select_photo", %{"index" => "99"})
      assert has_element?(view, "#photo-counter", "2 / 2")

      render_click(view, "select_photo", %{"index" => "-5"})
      assert has_element?(view, "#photo-counter", "1 / 2")

      render_click(view, "select_photo", %{"index" => "abc"})
      assert has_element?(view, "#photo-counter", "1 / 2")
    end

    test "a single photo has no thumbnails or arrows", %{conn: conn} do
      product = product_fixture(%{name: "Sticker"})
      variant_fixture(product, %{color: nil, size: nil})
      gallery_photo_fixture(product)

      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      refute has_element?(view, "#photo-thumbs")
      refute has_element?(view, "#photo-next")
      refute has_element?(view, "#photo-counter")
    end

    test "a product with no photos still renders", %{conn: conn} do
      product = product_fixture(%{name: "Plain"})
      variant_fixture(product, %{color: nil, size: nil})

      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")
      assert has_element?(view, "#product-gallery")
      refute has_element?(view, "#photo-thumbs")
    end

    test "each color has a dot in its own color", %{
      conn: conn,
      product: product
    } do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      assert has_element?(view, ~s(#color-dot-black[style="--swatch: #18181b"]))
      assert has_element?(view, ~s(#color-dot-white[style="--swatch: #ffffff"]))
      assert has_element?(view, "#color-black #color-dot-black")
    end

    test "an unrecognised color still gets a neutral dot", %{conn: conn} do
      product = product_fixture()
      variant_fixture(product, %{color: "Mystery Mist", size: nil})
      variant_fixture(product, %{color: "Black", size: nil})

      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      assert has_element?(
               view,
               ~s(#color-dot-mystery-mist[style="--swatch: #d4d4d8"])
             )
    end

    test "the stepper adds and subtracts, within limits", %{
      conn: conn,
      product: product
    } do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      assert has_element?(view, "#quantity-decrement[disabled]")
      assert has_element?(view, ~s(#quantity[value="1"]))

      view |> element("#quantity-increment") |> render_click()
      view |> element("#quantity-increment") |> render_click()
      assert has_element?(view, ~s(#quantity[value="3"]))
      refute has_element?(view, "#quantity-decrement[disabled]")

      view |> element("#quantity-decrement") |> render_click()
      assert has_element?(view, ~s(#quantity[value="2"]))

      view |> form("#add-to-cart-form", %{quantity: "25"}) |> render_change()
      assert has_element?(view, "#quantity-increment[disabled]")
      assert has_element?(view, ~s(#quantity[value="25"]))

      # Even a forged click can't go past the cap.
      render_click(view, "increment", %{})
      assert has_element?(view, ~s(#quantity[value="25"]))
    end

    test "the stepper's quantity is what gets added, and the button shows the total",
         %{conn: conn, product: product, member: member} do
      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      view |> element("#size-m") |> render_click()
      assert has_element?(view, "#add-to-cart-total", "$25.00")

      view |> element("#quantity-increment") |> render_click()
      view |> element("#quantity-increment") |> render_click()
      assert has_element?(view, "#add-to-cart-total", "$75.00")

      view |> form("#add-to-cart-form") |> render_submit()
      assert [%{quantity: 3}] = Ysc.Merch.Cart.list(member)
    end

    test "the description is shown as paragraphs", %{conn: conn} do
      product =
        product_fixture(%{
          name: "Hoodie",
          description:
            "Heavyweight fleece.\n\nSoft inside, warm outside.\nRuns true to size."
        })

      variant_fixture(product, %{color: nil, size: nil})

      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")

      assert has_element?(view, "#product-description p", "Heavyweight fleece.")

      assert has_element?(
               view,
               "#product-description p",
               "Soft inside, warm outside."
             )

      assert has_element?(view, "#product-description p", "Runs true to size.")

      assert view
             |> element("#product-description")
             |> render()
             |> String.split("<p")
             |> length() == 3
    end

    test "no description, no description block", %{conn: conn} do
      product = product_fixture(%{name: "Bare"})
      variant_fixture(product, %{color: nil, size: nil})

      {:ok, view, _html} = live(conn, ~p"/shop/products/#{product.id}")
      refute has_element?(view, "#product-description")
    end
  end

  describe "cart page" do
    setup %{conn: conn} do
      member = member_fixture()
      %{conn: log_in_user(conn, member), member: member}
    end

    test "empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop/cart")
      assert has_element?(view, "#cart-empty")
      refute has_element?(view, "#cart-checkout")
    end

    test "shows lines and the subtotal", %{conn: conn, member: member} do
      tee = variant_fixture(nil, %{retail_price: Money.new(:USD, "25")})
      sticker = variant_fixture(nil, %{retail_price: Money.new(:USD, "3.50")})
      cart_lines_fixture(member, [{tee, 2}, {sticker, 4}])

      {:ok, view, _html} = live(conn, ~p"/shop/cart")

      assert has_element?(view, "#cart-line-#{tee.id}")
      assert has_element?(view, "#cart-line-#{sticker.id}")
      assert has_element?(view, "#cart-subtotal", "$64.00")
      assert has_element?(view, "#cart-checkout")
    end

    test "changing a quantity updates totals, zero removes the line", %{
      conn: conn,
      member: member
    } do
      tee = variant_fixture(nil, %{retail_price: Money.new(:USD, "25")})
      cart_lines_fixture(member, [{tee, 2}])
      {:ok, view, _html} = live(conn, ~p"/shop/cart")

      view
      |> form("#cart-qty-form-#{tee.id}", %{quantity: "5"})
      |> render_change()

      assert has_element?(view, "#cart-subtotal", "$125.00")

      view
      |> form("#cart-qty-form-#{tee.id}", %{quantity: "0"})
      |> render_change()

      refute has_element?(view, "#cart-line-#{tee.id}")
      assert has_element?(view, "#cart-empty")
    end

    test "the +/- buttons change the quantity one at a time", %{
      conn: conn,
      member: member
    } do
      tee = variant_fixture(nil, %{retail_price: Money.new(:USD, "25")})
      cart_lines_fixture(member, [{tee, 1}])
      {:ok, view, _html} = live(conn, ~p"/shop/cart")

      # Nothing to take away at 1; removing is the trash button's job.
      assert has_element?(view, "#cart-qty-decrement-#{tee.id}[disabled]")

      view |> element("#cart-qty-increment-#{tee.id}") |> render_click()
      assert has_element?(view, "#cart-subtotal", "$50.00")
      assert has_element?(view, "#cart-unit-price-#{tee.id}", "$25.00 each")

      view |> element("#cart-qty-decrement-#{tee.id}") |> render_click()
      assert has_element?(view, "#cart-subtotal", "$25.00")
      assert has_element?(view, "#cart-qty-decrement-#{tee.id}[disabled]")
    end

    test "remove deletes the line", %{conn: conn, member: member} do
      tee = variant_fixture()
      cart_lines_fixture(member, [{tee, 1}])
      {:ok, view, _html} = live(conn, ~p"/shop/cart")

      view |> element("#cart-remove-#{tee.id}") |> render_click()
      assert has_element?(view, "#cart-empty")
      assert Cart.list(member) == []
    end

    test "unavailable lines are flagged and excluded from the total", %{
      conn: conn,
      member: member
    } do
      keep = variant_fixture(nil, %{retail_price: Money.new(:USD, "10")})
      gone = variant_fixture(nil, %{retail_price: Money.new(:USD, "99")})
      cart_lines_fixture(member, [{keep, 1}, {gone, 1}])
      gone |> Ecto.Changeset.change(available: false) |> Ysc.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/shop/cart")

      assert has_element?(view, "#cart-unavailable-#{gone.id}")
      refute has_element?(view, "#cart-qty-form-#{gone.id}")
      assert has_element?(view, "#cart-subtotal", "$10.00")
      assert has_element?(view, "#cart-checkout:not([disabled])")
    end

    test "checkout is disabled when nothing in the cart can be bought", %{
      conn: conn,
      member: member
    } do
      gone = variant_fixture()
      cart_lines_fixture(member, [{gone, 1}])
      gone |> Ecto.Changeset.change(available: false) |> Ysc.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/shop/cart")
      assert has_element?(view, "#cart-checkout[disabled]")
    end
  end
end
