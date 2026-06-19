defmodule YscWeb.AdminEventCheckInQueryTest do
  @moduledoc """
  Query-count assertions for admin event check-in deferred ticket loading.

  Runs with `async: false` so global Ecto telemetry handlers are not polluted
  by parallel admin LiveView tests in the main suite module.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  alias Ysc.Repo

  defp make_member(attrs \\ %{}) do
    user = user_fixture(attrs)

    user
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Repo.update!()
    |> Repo.reload!()
  end

  defp confirm_order(order) do
    loaded =
      Repo.get!(Ysc.Tickets.TicketOrder, order.id) |> Repo.preload([:tickets])

    Enum.each(loaded.tickets, fn t ->
      t |> Ecto.Changeset.change(status: :confirmed) |> Repo.update!()
    end)

    Repo.get!(Ysc.Tickets.TicketOrder, order.id)
    |> Repo.preload(tickets: [:ticket_tier, :registration, :user])
  end

  defp setup_event_with_tickets(admin) do
    event = event_fixture(%{organizer_id: admin.id, state: :published})
    tier = ticket_tier_fixture(%{event_id: event.id})
    buyer = make_member()
    order = ticket_order_fixture(%{user: buyer, event: event, tier: tier})
    confirmed_order = confirm_order(order)

    %{event: event, tier: tier, buyer: buyer, order: confirmed_order}
  end

  describe "deferred ticket loading" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "initial connect issues at most one ticket list query", %{
      conn: conn,
      admin: admin
    } do
      %{event: event} = setup_event_with_tickets(admin)
      tickets_pattern = ~r/FROM "tickets"/i

      {{:ok, view, _html}, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} =
              live(conn, ~p"/admin/events/#{event.id}/check-in")

            render(view)
            {:ok, view, html}
          end,
          pattern: tickets_pattern
        )

      assert query_count <= 1
      assert has_element?(view, "#pending-groups")
    end
  end
end
