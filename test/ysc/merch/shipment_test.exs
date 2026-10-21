defmodule Ysc.Merch.ShipmentTest do
  use ExUnit.Case, async: true

  alias Ysc.Merch.{OrderItem, Shipment}

  describe "trackable?/1" do
    test "needs a tracking number" do
      assert Shipment.trackable?(%Shipment{tracking_number: "9400"})
      refute Shipment.trackable?(%Shipment{tracking_number: nil})
      refute Shipment.trackable?(%Shipment{tracking_number: ""})
      refute Shipment.trackable?(%Shipment{tracking_number: "   "})
    end

    test "a link alone is not enough" do
      refute Shipment.trackable?(%Shipment{
               tracking_number: nil,
               tracking_url: "https://myorders.co/tracking/1/"
             })
    end
  end

  describe "contents/2" do
    setup do
      %{
        pin: %OrderItem{id: "pin", name: "Flag Pin", quantity: 3},
        tee: %OrderItem{id: "tee", name: "Tee / Black / M", quantity: 1}
      }
    end

    test "pairs each recorded item with its order line", %{pin: pin, tee: tee} do
      shipment = %Shipment{
        items: [
          %{"order_item_id" => "tee", "quantity" => 1},
          %{"order_item_id" => "pin", "quantity" => 2}
        ]
      }

      assert Shipment.contents(shipment, [pin, tee]) == [{1, tee}, {2, pin}]
    end

    test "is empty when the shipment records nothing", %{pin: pin} do
      assert Shipment.contents(%Shipment{items: []}, [pin]) == []
      assert Shipment.contents(%Shipment{items: nil}, [pin]) == []
    end

    test "skips lines the order no longer has", %{pin: pin} do
      shipment = %Shipment{
        items: [
          %{"order_item_id" => "gone", "quantity" => 1},
          %{"order_item_id" => "pin", "quantity" => 1}
        ]
      }

      assert Shipment.contents(shipment, [pin]) == [{1, pin}]
    end

    test "is empty when the order's items are not loaded" do
      shipment = %Shipment{
        items: [%{"order_item_id" => "pin", "quantity" => 1}]
      }

      assert Shipment.contents(shipment, %Ecto.Association.NotLoaded{}) == []
    end
  end
end
