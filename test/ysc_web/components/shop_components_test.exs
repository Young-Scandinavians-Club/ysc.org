defmodule YscWeb.ShopComponentsTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.ShopComponents

  alias Ysc.Merch.ShippingAddress

  defp address(attrs) do
    struct!(
      %ShippingAddress{
        address1: "1 Market St",
        address2: nil,
        city: "San Francisco",
        state_code: "CA",
        zip: "94105"
      },
      attrs
    )
  end

  describe "shipping_address_lines/1" do
    test "renders a name, street, and city line, omitting blank address2" do
      assigns = %{address: address(%{})}

      html =
        rendered_to_string(~H"""
        <.shipping_address_lines address={@address} name="Ada Lovelace" />
        """)

      assert html =~ "Ada Lovelace"
      assert html =~ "1 Market St"
      assert html =~ "San Francisco, CA 94105"
      assert html =~ "<br"
      refute html =~ "Ste 200"
    end

    test "includes address2 when present and can omit the name" do
      assigns = %{address: address(%{address2: "Ste 200"})}

      html =
        rendered_to_string(~H"""
        <.shipping_address_lines address={@address} />
        """)

      refute html =~ "Ada Lovelace"
      assert html =~ "1 Market St"
      assert html =~ "Ste 200"
      assert html =~ "San Francisco, CA 94105"
    end
  end

  describe "status_display/1" do
    test "uses everyday words instead of printer or factory jargon" do
      assert status_display(:submitting) == {"Getting ready", "sky"}
      assert status_display(:submitted) == {"Being prepared", "sky"}
      assert status_display(:in_production) == {"Being made", "sky"}
    end
  end

  describe "shop_empty_state/1" do
    test "renders title, copy, and bag icon without a browse button" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.shop_empty_state id="shop-empty" title="The shop is stocking up">
          New club gear is on the way. Check back soon.
        </.shop_empty_state>
        """)

      assert html =~ ~s(id="shop-empty")
      assert html =~ "The shop is stocking up"
      assert html =~ "New club gear is on the way. Check back soon."
      assert html =~ "rounded-3xl bg-zinc-50 px-6 py-24 text-center"
      assert html =~ "hero-shopping-bag"
      assert html =~ ~s(<h2 class="type-title text-2xl text-zinc-900")
      refute html =~ "Browse the shop"
      refute html =~ ~s(id="cart-browse")
    end

    test "renders the browse-the-shop button when browse_id is set" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.shop_empty_state
          id="cart-empty"
          title="Your cart is empty"
          browse_id="cart-browse"
        >
          Find something you like in the shop.
        </.shop_empty_state>
        """)

      assert html =~ ~s(id="cart-empty")
      assert html =~ "Your cart is empty"
      assert html =~ "Find something you like in the shop."
      assert html =~ ~s(id="cart-browse")
      assert html =~ "Browse the shop"
      assert html =~ ~s(href="/shop")
      assert html =~ "mt-8 motion-safe:active:scale-[0.98]"
    end
  end
end
