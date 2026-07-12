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

    test "dead render does not query events before connect", %{conn: conn, admin: admin} do
      event =
        event_fixture(%{
          organizer_id: admin.id,
          title: "Deferred Event Title XYZ",
          state: :published
        })

      events_pattern = ~r/FROM "events"/i

      {html, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/admin/events/#{event.id}/check-in")
            |> html_response(200)
          end,
          pattern: events_pattern
        )

      assert query_count == 0
      refute html =~ "Deferred Event Title XYZ"
      assert html =~ ~s|id="check-in-search-form"|
    end

    test "connected mount loads event at most once", %{conn: conn, admin: admin} do
      event =
        event_fixture(%{
          organizer_id: admin.id,
          title: "Single Fetch Event XYZ",
          state: :published
        })

      events_pattern = ~r/FROM "events"/i

      {{:ok, view, _html}, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} =
              live(conn, ~p"/admin/events/#{event.id}/check-in")

            render(view)
            {:ok, view, html}
          end,
          pattern: events_pattern
        )

      assert query_count == 1
      assert render(view) =~ "Single Fetch Event XYZ"
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

    test "single check-in avoids reloading the full ticket list", %{
      conn: conn,
      admin: admin
    } do
      %{event: event, order: order} = setup_event_with_tickets(admin)
      ticket = List.first(order.tickets)
      list_pattern = ~r/FROM "tickets" AS t0 LEFT OUTER JOIN/i

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      {_html, list_query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            view
            |> element(
              "#pending-groups button[phx-value-ticket-id='#{ticket.id}']"
            )
            |> render_click()

            render(view)
          end,
          pattern: list_pattern
        )

      assert list_query_count == 0
      assert render(view) =~ "1 / 1"
    end

    test "check-in with active search avoids aggregate recount query", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, state: :published})
      tier = ticket_tier_fixture(%{event_id: event.id})

      alice = make_member(%{first_name: "QueryCountAlice", last_name: "Test"})
      bob = make_member(%{first_name: "QueryCountBob", last_name: "Test"})

      alice_order =
        ticket_order_fixture(%{user: alice, event: event, tier: tier})
        |> confirm_order()

      ticket_order_fixture(%{user: bob, event: event, tier: tier})
      |> confirm_order()

      alice_ticket = List.first(alice_order.tickets)
      aggregate_pattern = ~r/count\(.*"id"\).*FILTER/i

      {:ok, view, _html} =
        live(conn, ~p"/admin/events/#{event.id}/check-in?q=QueryCountAlice")

      assert render(view) =~ "0 / 2"

      {_html, aggregate_query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            view
            |> element(
              "#pending-groups button[phx-value-ticket-id='#{alice_ticket.id}']"
            )
            |> render_click()

            render(view)
          end,
          pattern: aggregate_pattern
        )

      assert aggregate_query_count == 0
      assert render(view) =~ "1 / 2"
    end
  end
end
