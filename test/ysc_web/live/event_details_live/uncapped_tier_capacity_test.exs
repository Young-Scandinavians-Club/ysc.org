defmodule YscWeb.EventDetailsLive.UncappedTierCapacityTest do
  @moduledoc """
  Regression tests for event-level remaining capacity on uncapped ticket tiers.

  A tier with `quantity: nil` used to always render "Unlimited", even when the
  event itself had `max_attendees`. Checkout still enforced the event cap, so
  members could be shown unlimited inventory and then fail at purchase.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.ReservationPurchasingTestHelpers
  import EventDetailsLiveHelpers
  import Mox

  setup :verify_on_exit!

  setup %{conn: conn} do
    setup_stripe_mocks()

    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    stub(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
      {:ok, build_payment_intent(%{amount: params.amount})}
    end)

    stub(Ysc.StripeMock, :retrieve_payment_intent, fn id, _opts ->
      {:ok, build_payment_intent(%{id: id, status: "requires_payment_method"})}
    end)

    %{conn: conn}
  end

  defp open_tickets_modal(conn, event) do
    {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets")
    html = render_async(view)
    {view, html}
  end

  defp availability_text(view, tier_id) do
    view
    |> element("#tier-availability-#{tier_id}")
    |> render()
  end

  describe "uncapped tier availability label" do
    test "shows remaining event capacity instead of Unlimited", %{conn: conn} do
      ctx = setup_single_tier_event(max_attendees: 12, tier_quantity: nil)
      conn = log_in_user(conn, ctx.holder)

      {view, _html} = open_tickets_modal(conn, ctx.event)
      label = availability_text(view, ctx.tier.id)

      assert label =~ "12 remaining"
      refute label =~ "Unlimited"
    end

    test "remaining count falls as confirmed tickets are sold", %{conn: conn} do
      ctx = setup_single_tier_event(max_attendees: 10, tier_quantity: nil)

      insert_sold_tickets!(3, %{
        user: ctx.stranger,
        event: ctx.event,
        tier: ctx.tier
      })

      conn = log_in_user(conn, ctx.holder)

      {view, _html} = open_tickets_modal(conn, ctx.event)
      label = availability_text(view, ctx.tier.id)

      assert label =~ "7 remaining"
      refute label =~ "Unlimited"
    end

    test "still shows Unlimited when the event has no attendee cap", %{
      conn: conn
    } do
      ctx = setup_single_tier_event(max_attendees: nil, tier_quantity: nil)
      conn = log_in_user(conn, ctx.holder)

      {view, _html} = open_tickets_modal(conn, ctx.event)
      label = availability_text(view, ctx.tier.id)

      assert label =~ "Unlimited"
      refute label =~ "remaining"
    end

    test "event-at-capacity label wins over Unlimited for an uncapped tier", %{
      conn: conn
    } do
      ctx = setup_single_tier_event(max_attendees: 3, tier_quantity: nil)

      insert_sold_tickets!(3, %{
        user: ctx.stranger,
        event: ctx.event,
        tier: ctx.tier
      })

      conn = log_in_user(conn, ctx.holder)

      {view, _html} = open_tickets_modal(conn, ctx.event)
      label = availability_text(view, ctx.tier.id)

      assert label =~ "Sold Out (Event at capacity)"
      refute label =~ "Unlimited"
    end
  end
end
