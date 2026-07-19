defmodule YscWeb.EventDetailsQueryTest do
  @moduledoc """
  Query-count assertions for EventDetailsLive tier loading.

  Runs with `async: false` so global Ecto telemetry handlers are not polluted
  by parallel LiveView tests.
  """
  use YscWeb.ConnCase, async: false

  @moduletag process_caches: true

  import Phoenix.LiveViewTest
  import Ysc.EventsFixtures
  import Ysc.TestDataFactory, only: [event_with_state: 2]

  alias Ysc.Events.EventPricingCache

  @tier_list_pattern ~r/FROM "ticket_tiers".*GROUP BY/s

  describe "tier loading" do
    setup do
      EventPricingCache.invalidate()
      :ok
    end

    test "dead render and connect avoid duplicate tier list fetches", %{
      conn: conn
    } do
      event =
        event_fixture(%{
          title: "Single Tier Fetch Event XYZ",
          state: :published
        })

      ticket_tier_fixture(%{event_id: event.id})

      # Grouped tier-list queries (preload, enrich batch load, list_ticket_tiers_for_event).
      # event_selling_fast?/1 also joins ticket_tiers but is unrelated to the duplicate we remove.
      tier_list_pattern = ~r/FROM "ticket_tiers".*GROUP BY/s

      {{:ok, view, _html}, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} = live(conn, ~p"/events/#{event.id}")
            render_async(view)
            {:ok, view, html}
          end,
          pattern: tier_list_pattern
        )

      # Before: dead-render preload + async list_ticket_tiers_for_event (2 grouped queries).
      # After: EventPricingCache enrich once, reused on connect (1 grouped query).
      assert query_count == 1
      assert render(view) =~ "Single Tier Fetch Event XYZ"
    end

    test "dead render loads tiers via pricing cache not association preload", %{
      conn: conn
    } do
      event =
        event_fixture(%{
          title: "Dead Render Tier Query XYZ",
          state: :published
        })

      ticket_tier_fixture(%{event_id: event.id})

      {_html, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/events/#{event.id}")
            |> html_response(200)
          end,
          pattern: @tier_list_pattern
        )

      assert query_count == 1
    end

    test "dead render emits SEO tags from Event struct when pricing cache is primed",
         %{
           conn: conn
         } do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{
            title: "Cached SEO Event",
            description: "Tickets and cover image must stay in meta tags."
          }
        )

      ticket_tier_fixture(%{event_id: event.id})

      # Prime pricing cache so mount reuses enriched payload instead of Event struct.
      EventPricingCache.enrich_event(event)

      html =
        conn
        |> get(~p"/events/#{event.id}")
        |> html_response(200)

      assert html =~ ~s(property="og:title")
      assert html =~ "Cached SEO Event"
      assert html =~ ~s(property="og:description")
      assert html =~ "Tickets and cover image must stay in meta tags."
      assert html =~ ~s(property="og:image")
      assert html =~ "/uploads/test_image_optimized.jpg"
      assert html =~ ~s(rel="canonical")
      assert html =~ "/events/#{event.id}"
    end
  end
end
