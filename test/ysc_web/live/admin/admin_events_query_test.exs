defmodule YscWeb.AdminEventsQueryTest do
  @moduledoc """
  Query-count assertions for admin events organizer-filter caching.

  Runs with `async: false` so global Ecto telemetry handlers are not polluted
  by parallel admin LiveView tests in the main suite module.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  describe "organizer filter query caching" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "does not re-query event organizers on each search patch", %{
      conn: conn,
      admin: admin
    } do
      event_fixture(%{title: "Organizer Cache XYZ", organizer_id: admin.id})

      {:ok, view, _} = live(conn, ~p"/admin/events")

      # Drain connected mount work before measuring search patch queries.
      render(view)

      author_filter_pattern =
        ~r/DISTINCT ON \(.*"organizer_id"\).*FROM "events"/is

      {_patch, author_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            view
            |> form("#events-search-form", %{q: "Organizer Cache"})
            |> render_submit()
          end,
          pattern: author_filter_pattern
        )

      assert author_queries == 0
    end
  end

  describe "event editor deferred queries" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      ticket_tier_fixture(%{event_id: event.id, name: "General Admission"})

      %{conn: log_in_user(conn, admin), event: event}
    end

    test "dead render does not count ticket tiers before connect", %{
      conn: conn,
      event: event
    } do
      tier_count_pattern = ~r/FROM "ticket_tiers"/i

      {html, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/admin/events/#{event.id}/edit")
            |> html_response(200)
          end,
          pattern: tier_count_pattern
        )

      assert query_count == 0
      assert html =~ event.title
    end
  end
end
