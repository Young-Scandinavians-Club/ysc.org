defmodule Ysc.Printful.DemoEventsTest do
  use Ysc.DataCase, async: false

  import Swoosh.TestAssertions
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Orders, Shipment}
  alias Ysc.Printful.{DemoClient, DemoEvents}

  setup do
    original = Application.get_env(:ysc, :printful_client)
    Application.put_env(:ysc, :printful_client, DemoClient)
    on_exit(fn -> Application.put_env(:ysc, :printful_client, original) end)

    member = member_fixture()
    order = purchase_order_fixture(member, :submitted)

    # Register the order with the demo printer as submission would.
    {:ok, demo} =
      DemoClient.create_order(
        %{
          external_id: order.reference_id,
          shipping: "STANDARD",
          recipient: %{},
          items: []
        },
        true
      )

    order
    |> Ecto.Changeset.change(printful_order_id: demo["id"])
    |> Repo.update!()

    %{order: Orders.get_order!(order.id), demo_id: demo["id"]}
  end

  defp status(order), do: Orders.get_order!(order.id).status

  test "production moves the order into production", %{
    order: order,
    demo_id: id
  } do
    assert {:ok, "order_updated"} = DemoEvents.trigger(id, :production)
    assert status(order) == :in_production
  end

  test "ship records a shipment with tracking and emails the member", %{
    order: order,
    demo_id: id
  } do
    assert {:ok, "package_shipped"} = DemoEvents.trigger(id, :ship)

    assert status(order) == :shipped

    assert [
             %Shipment{
               tracking_number: "9400DEMO" <> _,
               tracking_url: "https://" <> _
             }
           ] = Repo.all(Shipment)

    assert_email_sent(subject: ~r/on its way/)
  end

  test "each ship action is a new parcel", %{order: order, demo_id: id} do
    {:ok, _} = DemoEvents.trigger(id, :ship)
    {:ok, _} = DemoEvents.trigger(id, :ship)

    assert Repo.aggregate(Shipment, :count) == 2
    assert status(order) == :shipped
  end

  test "deliver completes a shipped order", %{order: order, demo_id: id} do
    {:ok, _} = DemoEvents.trigger(id, :ship)
    assert {:ok, "package_delivered"} = DemoEvents.trigger(id, :deliver)

    assert status(order) == :delivered
    assert [%Shipment{status: :delivered}] = Repo.all(Shipment)
  end

  test "return, fail, cancel and hold all reach the order", %{
    order: order,
    demo_id: id
  } do
    {:ok, _} = DemoEvents.trigger(id, :ship)
    assert {:ok, "package_returned"} = DemoEvents.trigger(id, :return)
    assert [%Shipment{status: :returned}] = Repo.all(Shipment)

    other = purchase_order_fixture(member_fixture(), :submitted)

    {:ok, demo} =
      DemoClient.create_order(
        %{
          external_id: other.reference_id,
          shipping: "S",
          recipient: %{},
          items: []
        },
        true
      )

    other
    |> Ecto.Changeset.change(printful_order_id: demo["id"])
    |> Repo.update!()

    assert {:ok, "order_put_hold"} = DemoEvents.trigger(demo["id"], :hold)
    assert status(other) == :submitted

    assert {:ok, "order_failed"} = DemoEvents.trigger(demo["id"], :fail)
    assert status(other) == :failed
    assert Orders.get_order!(other.id).failure_reason == "Demo: out of stock"
    assert order.id != other.id
  end

  test "cancel closes the order", %{order: order, demo_id: id} do
    assert {:ok, "order_canceled"} = DemoEvents.trigger(id, :cancel)
    assert status(order) == :canceled
  end

  test "an unknown demo order is an error" do
    assert {:error, _} = DemoEvents.trigger(123_456_789, :ship)
  end

  test "the demo order record tracks what was triggered", %{demo_id: id} do
    {:ok, _} = DemoEvents.trigger(id, :ship)
    {:ok, demo} = DemoClient.get_order(id)
    assert demo["status"] == "fulfilled"
    assert length(demo["shipments"]) == 1
  end
end
