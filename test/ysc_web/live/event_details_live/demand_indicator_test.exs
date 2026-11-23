defmodule YscWeb.EventDetailsLive.DemandIndicatorTest do
  @moduledoc """
  The ticket sidebar's "Demand is high" indicator must not claim scarcity
  the numbers do not support: a barely-sold event gets a compact line, and
  the fill bar only appears once the event is actually filling up.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.ReservationPurchasingTestHelpers

  @indicator "#event-demand-indicator"
  @bar "#event-demand-indicator [role=progressbar]"

  # Capacity 20 keeps fixtures small: 5 sold = 25%, 10 = 50%, 17 = 85%.
  defp render_event(conn, sold) do
    ctx = setup_single_tier_event(max_attendees: 20, tier_quantity: nil)

    if sold > 0 do
      insert_sold_tickets!(sold, %{
        user: ctx.stranger,
        event: ctx.event,
        tier: ctx.tier
      })
    end

    {:ok, view, _html} =
      live(log_in_user(conn, ctx.holder), ~p"/events/#{ctx.event.id}")

    render_async(view)
    view
  end

  test "shows nothing when sales are slow and the event is mostly empty", %{
    conn: conn
  } do
    view = render_event(conn, 2)

    refute has_element?(view, @indicator)
  end

  test "selling fast on a barely-sold event is a compact line without a bar", %{
    conn: conn
  } do
    view = render_event(conn, 5)

    assert has_element?(
             view,
             @indicator <> "[data-level=momentum]",
             "Demand is high"
           )

    refute has_element?(view, @bar)
    refute render(view) =~ "% full"
  end

  test "the fill bar appears once a fast-selling event is half full", %{
    conn: conn
  } do
    view = render_event(conn, 10)

    assert has_element?(
             view,
             @indicator <> "[data-level=filling]",
             "Demand is high"
           )

    assert has_element?(view, @bar <> "[aria-valuenow='50']")
    assert has_element?(view, @indicator, "50% full")
  end

  test "an almost-full event is scarce and states what is left", %{conn: conn} do
    view = render_event(conn, 17)

    assert has_element?(
             view,
             @indicator <> "[data-level=scarce]",
             "Demand is high"
           )

    assert has_element?(view, @indicator, "3 tickets left")
    assert has_element?(view, @bar <> "[aria-valuenow='85']")
  end
end
