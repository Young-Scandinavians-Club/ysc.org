defmodule YscWeb.OrderConfirmationDeferredTest do
  @moduledoc """
  Query-count assertions for order confirmation deferred loading (#624).
  """
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Repo
  alias Ysc.Tickets.TicketOrder

  setup %{conn: conn} do
    user =
      user_fixture()
      |> Ecto.Changeset.change(%{
        lifetime_membership_awarded_at:
          DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()

    event = event_fixture(%{state: :published})
    tier = ticket_tier_fixture(%{event_id: event.id})

    {:ok, order} =
      %TicketOrder{}
      |> TicketOrder.create_changeset(%{
        user_id: user.id,
        event_id: event.id,
        reference_id: "ORD-#{System.unique_integer([:positive])}",
        status: :confirmed,
        total_amount: tier.price,
        expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
      })
      |> Repo.insert()

    {:ok, conn: log_in_user(conn, user), order: order}
  end

  test "dead render skips ticket order queries and shows loading state", %{
    conn: conn,
    order: order
  } do
    ticket_orders_pattern = ~r/FROM "ticket_orders"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get(~p"/orders/#{order.id}/confirmation")
          |> html_response(200)
        end,
        pattern: ticket_orders_pattern
      )

    assert query_count == 0
    assert html =~ "Loading order confirmation"
    refute html =~ "Order Confirmed"
  end
end
