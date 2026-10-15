defmodule Ysc.Merch.EventCostsTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Merch.EventCosts

  setup do
    admin = user_fixture(%{role: "admin"})
    event = event_fixture(%{organizer_id: admin.id})
    %{admin: admin, event: event}
  end

  defp usd(amount), do: Money.new(:USD, amount)

  test "uses the estimate until Printful reports the real charge", %{
    admin: admin,
    event: event
  } do
    estimated =
      admin_order_fixture(admin, %{
        event_id: event.id,
        status: :submitted,
        estimated_cost: usd("50")
      })

    actual =
      admin_order_fixture(admin, %{
        event_id: event.id,
        status: :shipped,
        estimated_cost: usd("30"),
        printful_cost: usd("34.25")
      })

    orders = EventCosts.list_orders(event.id)

    assert Enum.sort(Enum.map(orders, & &1.id)) ==
             Enum.sort([estimated.id, actual.id])

    totals = EventCosts.totals(orders)
    assert Money.equal?(totals.cost_total, usd("84.25"))
    assert totals.order_count == 2
    assert totals.estimated?
  end

  test "is not flagged as estimated when every order has a real charge", %{
    admin: admin,
    event: event
  } do
    admin_order_fixture(admin, %{
      event_id: event.id,
      status: :delivered,
      printful_cost: usd("12")
    })

    totals = event.id |> EventCosts.list_orders() |> EventCosts.totals()
    assert Money.equal?(totals.cost_total, usd("12"))
    refute totals.estimated?
  end

  test "ignores orders Printful never billed", %{admin: admin, event: event} do
    for status <- [:pending, :paid, :failed, :canceled, :refunded] do
      admin_order_fixture(admin, %{event_id: event.id, status: status})
    end

    assert EventCosts.list_orders(event.id) == []
  end

  test "ignores other events, unlinked orders and member purchases", %{
    admin: admin,
    event: event
  } do
    other = event_fixture(%{organizer_id: admin.id})

    admin_order_fixture(admin, %{event_id: other.id, status: :submitted})
    admin_order_fixture(admin, %{status: :submitted})

    admin_order_fixture(admin, %{
      event_id: event.id,
      status: :submitted,
      kind: :purchase
    })

    assert EventCosts.list_orders(event.id) == []
  end

  test "totals of nothing are zero" do
    totals = EventCosts.totals([])
    assert Money.zero?(totals.cost_total)
    assert totals.order_count == 0
    refute totals.estimated?
  end

  test "preloads who placed the order and the items", %{
    admin: admin,
    event: event
  } do
    variant = variant_fixture()

    admin_order_fixture(admin, %{
      event_id: event.id,
      status: :submitted,
      items: [{variant, 20}]
    })

    assert [order] = EventCosts.list_orders(event.id)
    assert order.granted_by.id == admin.id
    assert [%{quantity: 20}] = order.items
  end
end
