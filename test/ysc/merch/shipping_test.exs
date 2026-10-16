defmodule Ysc.Merch.ShippingTest do
  use Ysc.DataCase, async: true

  import Mox
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Shipping, ShippingAddress}
  alias Ysc.Printful.{ClientMock, Error}

  setup :verify_on_exit!

  defp address(attrs \\ %{}) do
    {:ok, address} =
      ShippingAddress.validate(
        Map.merge(
          %{
            "name" => "Ada Lovelace",
            "address1" => "1 Market St",
            "city" => "San Francisco",
            "state_code" => "ca",
            "zip" => "94105",
            "phone" => "415-555-0100"
          },
          attrs
        )
      )

    address
  end

  describe "ShippingAddress" do
    test "normalizes and accepts a US address" do
      a = address()
      assert a.state_code == "CA"
      assert a.country_code == "US"
    end

    test "requires the essentials" do
      assert {:error, cs} = ShippingAddress.validate(%{})
      errors = errors_on(cs)

      for field <- [:name, :address1, :city, :state_code, :zip],
          do: assert(errors[field])
    end

    test "rejects non-US, bad state and bad ZIP" do
      assert {:error, cs} =
               ShippingAddress.validate(%{
                 "name" => "A",
                 "address1" => "1 St",
                 "city" => "Stockholm",
                 "state_code" => "XX",
                 "zip" => "111 22",
                 "country_code" => "SE"
               })

      errors = errors_on(cs)
      assert errors[:country_code]
      assert errors[:state_code]
      assert errors[:zip]
    end

    test "accepts ZIP+4" do
      assert {:ok, _} =
               ShippingAddress.validate(%{
                 "name" => "A",
                 "address1" => "1",
                 "city" => "C",
                 "state_code" => "WA",
                 "zip" => "98101-1234"
               })
    end

    test "recipient omits blank optional fields" do
      recipient =
        address(%{"address2" => "  ", "email" => ""})
        |> ShippingAddress.to_recipient()

      refute Map.has_key?(recipient, :address2)
      refute Map.has_key?(recipient, :email)
      assert recipient.state_code == "CA"
    end
  end

  describe "options/2" do
    test "sends catalog variant ids and returns cheapest first" do
      variant = variant_fixture()

      expect(ClientMock, :shipping_rates, fn recipient, items ->
        assert recipient.zip == "94105"

        assert items == [
                 %{variant_id: variant.printful_variant_id, quantity: 3}
               ]

        {:ok,
         [
           %{
             "id" => "EXPRESS",
             "name" => "Express",
             "rate" => "14.50",
             "currency" => "USD",
             "minDeliveryDays" => 1,
             "maxDeliveryDays" => 2
           },
           %{
             "id" => "STANDARD",
             "name" => "Flat Rate",
             "rate" => "5.95",
             "currency" => "USD",
             "minDeliveryDays" => 3,
             "maxDeliveryDays" => 5
           }
         ]}
      end)

      assert {:ok, [first, second]} =
               Shipping.options(address(), [%{variant: variant, quantity: 3}])

      assert first.id == "STANDARD"
      assert Money.equal?(first.rate, Money.new(:USD, "5.95"))
      assert second.id == "EXPRESS"
      assert Shipping.delivery_window(first) == "3-5 business days"

      assert Shipping.delivery_window(%{min_days: 2, max_days: 2}) ==
               "2 business days"

      assert Shipping.delivery_window(%{min_days: nil, max_days: nil}) == nil
    end

    test "tidies Printful's names, which embed the delivery dates" do
      variant = variant_fixture()

      expect(ClientMock, :shipping_rates, fn _, _ ->
        # Captured from POST /shipping/rates on the live API: a word-joiner
        # (U+2060) inside the dates and a trailing space.
        {:ok,
         [
           %{
             "id" => "STANDARD",
             "name" => "Flat Rate (Estimated delivery: Oct 21\u2060\u201323) ",
             "rate" => "7.15",
             "currency" => "USD",
             "minDeliveryDays" => 4,
             "maxDeliveryDays" => 6
           }
         ]}
      end)

      assert {:ok, [option]} =
               Shipping.options(address(), [%{variant: variant, quantity: 1}])

      assert option.name == "Flat Rate"
      assert Shipping.delivery_window(option) == "4-6 business days"
    end

    test "ignores non-USD and malformed rates" do
      expect(ClientMock, :shipping_rates, fn _, _ ->
        {:ok,
         [
           %{"id" => "A", "name" => "A", "rate" => "3", "currency" => "EUR"},
           %{"id" => "B"},
           %{"id" => "C", "name" => "C", "rate" => "oops"}
         ]}
      end)

      assert {:error, :unavailable} =
               Shipping.options(address(), [
                 %{variant: variant_fixture(), quantity: 1}
               ])
    end

    test "a rejected address surfaces Printful's message" do
      expect(ClientMock, :shipping_rates, fn _, _ ->
        {:error,
         %Error{
           type: :invalid,
           status: 400,
           message: "Zip code does not match state"
         }}
      end)

      assert {:error, {:rejected, "Zip code does not match state"}} =
               Shipping.options(address(), [
                 %{variant: variant_fixture(), quantity: 1}
               ])
    end

    test "outages are :unavailable" do
      for type <- [:server, :network, :rate_limited, :auth, :not_configured] do
        expect(ClientMock, :shipping_rates, fn _, _ ->
          {:error, %Error{type: type, message: "x"}}
        end)

        assert {:error, :unavailable} =
                 Shipping.options(address(), [
                   %{variant: variant_fixture(), quantity: 1}
                 ])
      end
    end
  end

  describe "requote/3" do
    test "returns the same method priced for the current lines (Finding 92)" do
      variant = variant_fixture()
      lines = [%{variant: variant, quantity: 1}]

      expect(ClientMock, :shipping_rates, fn _, items ->
        assert hd(items).quantity == 1

        {:ok,
         [
           %{
             "id" => "STANDARD",
             "name" => "Flat Rate",
             "rate" => "5.95",
             "currency" => "USD"
           }
         ]}
      end)

      assert {:ok, [first]} =
               Shipping.options(address(), lines)

      heavier = [%{variant: variant, quantity: 8}]

      expect(ClientMock, :shipping_rates, fn _, items ->
        assert hd(items).quantity == 8

        {:ok,
         [
           %{
             "id" => "STANDARD",
             "name" => "Flat Rate",
             "rate" => "24.00",
             "currency" => "USD"
           }
         ]}
      end)

      assert {:ok, quoted} = Shipping.requote(address(), heavier, first)
      assert quoted.id == "STANDARD"
      assert Money.equal?(quoted.rate, Money.new(:USD, "24.00"))
    end

    test "errors when the chosen method is no longer offered" do
      expect(ClientMock, :shipping_rates, fn _, _ ->
        {:ok,
         [
           %{
             "id" => "EXPRESS",
             "name" => "Express",
             "rate" => "18.00",
             "currency" => "USD"
           }
         ]}
      end)

      assert {:error, :method_unavailable} =
               Shipping.requote(
                 address(),
                 [%{variant: variant_fixture(), quantity: 1}],
                 %{
                   id: "STANDARD"
                 }
               )
    end

    test "empty cart is :empty_cart without calling Printful" do
      assert {:error, :empty_cart} =
               Shipping.requote(address(), [], %{id: "STANDARD"})
    end
  end
end
