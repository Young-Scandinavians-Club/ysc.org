defmodule YscWeb.Emails.MerchHelpersTest do
  use Ysc.DataCase, async: true

  alias Ysc.Merch.{Order, ShippingAddress}
  alias YscWeb.Emails.MerchHelpers

  describe "address_lines/1" do
    test "omits blank address2 and formats city, state, ZIP" do
      address = %ShippingAddress{
        address1: "1 Market St",
        address2: nil,
        city: "San Francisco",
        state_code: "CA",
        zip: "94105"
      }

      assert MerchHelpers.address_lines(address) == [
               "1 Market St",
               "San Francisco, CA 94105"
             ]
    end

    test "keeps address2 when present" do
      address = %ShippingAddress{
        address1: "1 Market St",
        address2: "Ste 200",
        city: "San Francisco",
        state_code: "CA",
        zip: "94105"
      }

      assert MerchHelpers.address_lines(address) == [
               "1 Market St",
               "Ste 200",
               "San Francisco, CA 94105"
             ]
    end
  end

  describe "greeting_name/1" do
    test "uses the member first name when the order has a user" do
      order = %Order{
        user: %{first_name: "Ada"},
        recipient_name: "Ada Lovelace"
      }

      assert MerchHelpers.greeting_name(order) == "Ada"
    end

    test "uses the first word of recipient_name when there is no member" do
      order = %Order{user: nil, recipient_name: "Bar Staff"}
      assert MerchHelpers.greeting_name(order) == "Bar"
    end

    test "falls back when recipient_name is blank" do
      order = %Order{user: nil, recipient_name: nil}
      assert MerchHelpers.greeting_name(order) == "Valued Member"
    end
  end

  describe "member_order_url/1" do
    test "links members to the order page and strangers to the shop" do
      origin = YscWeb.Endpoint.url()
      id = "01merchorderurltest00000000"

      assert MerchHelpers.member_order_url(%Order{id: id, user_id: "01user"}) ==
               origin <> "/shop/orders/#{id}"

      assert MerchHelpers.member_order_url(%Order{id: id, user_id: nil}) ==
               origin <> "/shop"
    end
  end
end
