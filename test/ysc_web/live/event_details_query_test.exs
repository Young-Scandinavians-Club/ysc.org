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

  import Ysc.TestDataFactory,
    only: [event_with_state: 2, user_with_membership: 2]

  alias Ysc.Events.EventPricingCache
  alias Ysc.Subscriptions

  @tier_list_pattern ~r/FROM "ticket_tiers".*GROUP BY/s
  @images_pattern ~r/FROM "images"/i
  @subscription_exists_pattern ~r/SELECT TRUE FROM "subscriptions"/i

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
            Ysc.QueryCounter.track_caller_pid(view.pid)
            render_async(view)
            {:ok, view, html}
          end,
          pattern: tier_list_pattern,
          caller_pids: [self()]
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
          pattern: @tier_list_pattern,
          caller_pids: [self()]
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

    test "primed pricing cache dead render does not query images", %{
      conn: conn
    } do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "Cached Cover Event"}
        )

      ticket_tier_fixture(%{event_id: event.id})
      EventPricingCache.enrich_event(event)

      {_html, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/events/#{event.id}")
            |> html_response(200)
          end,
          pattern: @images_pattern,
          caller_pids: [self()]
        )

      # Before: Repo.preload(:cover_image) even when the pricing cache already
      # holds the image. After: SEO and the hero reuse the cached payload.
      assert query_count == 0
    end

    test "cold pricing cache dead render loads the cover once", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "Cold Cover Event"}
        )

      ticket_tier_fixture(%{event_id: event.id})

      {_html, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/events/#{event.id}")
            |> html_response(200)
          end,
          pattern: @images_pattern,
          caller_pids: [self()]
        )

      # Before: preload + EventPricingCache batch_load_images (2). After: enrich only.
      assert query_count == 1
    end

    test "dead render does not SELECT raw_details and still shows rendered body",
         %{
           conn: conn
         } do
      marker = "toast-#{System.unique_integer([:positive])}"

      event =
        event_fixture(%{
          title: "Public Body Toast Event",
          state: :published,
          raw_details: "<p>raw #{marker}</p>",
          rendered_details: "<p>rendered #{marker}</p>"
        })

      ticket_tier_fixture(%{event_id: event.id})

      {html, raw_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/events/#{event.id}")
            |> html_response(200)
          end,
          pattern: ~r/raw_details/i,
          caller_pids: [self()]
        )

      # Before: get_public_event selected events.* including Trix source.
      # After: public page fields omit raw_details; the article uses
      # rendered_details.
      assert raw_cols == 0
      assert html =~ "rendered #{marker}"
      refute html =~ "raw #{marker}"
    end
  end

  describe "membership extras on first paint" do
    setup do
      EventPricingCache.invalidate()
      :ok
    end

    test "Repo.exists? subscription lookup matches the SELECT TRUE pattern" do
      user = user_with_membership(:none, %{})

      {_result, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn -> Subscriptions.has_any_subscription?(user) end,
          pattern: @subscription_exists_pattern,
          caller_pids: [self()]
        )

      assert query_count == 1
    end

    test "lapsed member dead render reuses membership cache and shows renew copy",
         %{
           conn: conn
         } do
      user = user_with_membership(:none, %{state: :active})

      {:ok, _expired_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_expired_query_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Expired Subscription",
          current_period_end: DateTime.add(DateTime.utc_now(), -1, :day)
        })

      conn = log_in_user(conn, user)
      event = event_fixture(%{title: "Lapsed Member Event", state: :published})
      ticket_tier_fixture(%{event_id: event.id})

      {html, exists_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/events/#{event.id}")
            |> html_response(200)
          end,
          pattern: @subscription_exists_pattern,
          caller_pids: [self()]
        )

      # UserAuth already loaded subscriptions for current_membership. Do not
      # issue a second EXISTS for expired-vs-never copy.
      assert exists_count == 0
      assert html =~ "Your membership has expired"
      assert html =~ "renew to buy tickets"
    end

    test "never-subscribed member dead render skips subscription EXISTS", %{
      conn: conn
    } do
      user = user_with_membership(:none, %{state: :active})
      conn = log_in_user(conn, user)
      event = event_fixture(%{title: "New Member Event", state: :published})
      ticket_tier_fixture(%{event_id: event.id})

      {html, exists_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/events/#{event.id}")
            |> html_response(200)
          end,
          pattern: @subscription_exists_pattern,
          caller_pids: [self()]
        )

      assert exists_count == 0
      assert html =~ "Choose a membership and pay your dues to buy tickets"
    end
  end
end
