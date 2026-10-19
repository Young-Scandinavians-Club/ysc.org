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
end
