defmodule YscWeb.EventDetailsQueryTest do
  @moduledoc """
  Query-count assertions for EventDetailsLive tier loading.

  Runs with `async: false` so global Ecto telemetry handlers are not polluted
  by parallel LiveView tests.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.EventsFixtures

  alias Ysc.Events.EventPricingCache

  @ticket_tiers_pattern ~r/FROM "ticket_tiers"/i

  describe "tier loading" do
    setup do
      EventPricingCache.invalidate()
      :ok
    end

    test "dead render and connect load ticket tiers at most once", %{conn: conn} do
      event =
        event_fixture(%{
          title: "Single Tier Fetch Event XYZ",
          state: :published
        })

      ticket_tier_fixture(%{event_id: event.id})

      {{:ok, view, _html}, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} = live(conn, ~p"/events/#{event.id}")
            render_async(view)
            {view, html}
          end,
          pattern: @ticket_tiers_pattern
        )

      assert query_count <= 1
      assert has_element?(view, "#event-cover-#{event.id}")
    end

    test "dead render does not preload ticket tiers via association", %{conn: conn} do
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
          pattern: @ticket_tiers_pattern
        )

      # Pricing enrichment may issue one grouped tier query; a second preload-style
      # fetch on connect is what we avoid (covered by the connected test above).
      assert query_count <= 1
    end
  end
end
