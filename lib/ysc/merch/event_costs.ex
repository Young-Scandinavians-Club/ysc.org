defmodule Ysc.Merch.EventCosts do
  @moduledoc """
  Club-paid merch linked to an event, for the event's cost dashboard.

  Only admin (club-paid) orders count, and only once Printful has accepted
  them: pending, failed, canceled and refunded orders cost the club nothing.
  Each order contributes Printful's actual charge when known, else the
  estimate quoted when it was placed (see `Ysc.Merch.Order.cost/1`).
  """
  import Ecto.Query, warn: false

  alias Ysc.Accounts.User
  alias Ysc.Merch.{Order, OrderItem}
  alias Ysc.Repo

  # Cost table: who placed it, purpose, item qty, status, Printful cost.
  # Skip address / Stripe / Printful payload and a full users.* granted_by.
  @order_fields [
    :id,
    :purpose,
    :status,
    :printful_cost,
    :estimated_cost,
    :granted_by_id,
    :inserted_at
  ]
  @granted_by_fields [:id, :first_name, :last_name]
  @item_fields [:id, :order_id, :quantity]

  @doc """
  Billable club-paid orders linked to `event_id`, newest first, with the
  admin who placed each and its items loaded.
  """
  def list_orders(event_id) do
    event_id
    |> orders_query()
    |> Repo.all()
  end

  @doc """
  Totals for a list returned by `list_orders/1`.

  `estimated?` is true when any order's cost is still a quote rather than
  Printful's actual charge.
  """
  def totals(orders) when is_list(orders) do
    %{
      cost_total:
        Enum.reduce(orders, Money.new(0, :USD), fn order, acc ->
          case Money.add(acc, Order.cost(order)) do
            {:ok, sum} -> sum
            _ -> acc
          end
        end),
      order_count: length(orders),
      estimated?: Enum.any?(orders, &Order.cost_estimated?/1)
    }
  end

  defp orders_query(event_id) do
    from(o in Order,
      where:
        o.event_id == ^event_id and o.kind == :admin_comp and
          o.status in ^Order.billed_statuses(),
      order_by: [desc: o.inserted_at],
      select: struct(o, ^@order_fields),
      preload: [
        granted_by: ^granted_by_query(),
        items: ^items_query()
      ]
    )
  end

  defp granted_by_query do
    from(u in User, select: struct(u, ^@granted_by_fields))
  end

  defp items_query do
    from(i in OrderItem, select: struct(i, ^@item_fields))
  end

  @doc false
  def ci_query_explain_query do
    orders_query(Ysc.Ci.QueryExplain.Fixtures.ulid())
  end
end
