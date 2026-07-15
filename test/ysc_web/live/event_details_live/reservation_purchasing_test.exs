defmodule YscWeb.EventDetailsLive.ReservationPurchasingTest do
  @moduledoc """
  LiveView tests for reservation-aware availability display and purchasing UI.

  Covers Get Tickets visibility, tier remaining counts, spots available, quantity
  controls, and checkout when inventory is publicly exhausted but the viewer holds
  active reservations.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.ReservationPurchasingTestHelpers
  import EventDetailsLiveHelpers
  import Mox

  import Ecto.Query

  alias Ysc.Events
  alias Ysc.Events.TicketReservation
  alias Ysc.MessagePassingEvents.TicketReservationCreated
  alias Ysc.Repo
  alias Ysc.Tickets
  alias Ysc.Tickets.BookingValidator

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

  defp log_in(conn, user), do: log_in_user(conn, user)

  defp increase_disabled?(view, tier_id) do
    has_element?(
      view,
      "button[data-ticket-action='increase'][data-tier-id='#{tier_id}'][disabled]"
    )
  end

  defp increase_enabled?(view, tier_id) do
    has_element?(
      view,
      "button[data-ticket-action='increase'][data-tier-id='#{tier_id}']:not([disabled])"
    )
  end

  defp open_tickets_modal(conn, event) do
    {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets")
    {view, render_async(view)}
  end

  describe "Get Tickets button and sold-out chrome" do
    test "holder sees Get Tickets when tier is publicly sold out but they have a hold",
         %{conn: conn} do
      ctx = setup_single_tier_event(tier_quantity: 3, max_attendees: 50)
      %{holder: holder, stranger: stranger, event: event} = ctx

      insert_sold_tickets!(3, %{user: stranger, event: event, tier: ctx.tier})
      insert_reservation!(ctx, 2)

      conn = log_in(conn, holder)
      {_view, html} = open_tickets_modal(conn, event)

      assert html =~ "Get Tickets"
      refute html =~ ~r/>Sold Out</
      refute html =~ "Sold Out (Event at capacity)"
    end

    test "stranger sees Sold Out when only holds remain", %{conn: conn} do
      ctx = setup_single_tier_event(tier_quantity: 3)
      %{stranger: stranger, event: event} = ctx

      insert_sold_tickets!(1, %{user: stranger, event: event, tier: ctx.tier})
      insert_reservation!(ctx, 2)

      conn = log_in(conn, stranger)
      {_view, html} = open_tickets_modal(conn, event)

      assert html =~ "Sold Out"
      refute html =~ ~r/phx-click="open-ticket-modal"[^>]*>[\s\S]*Get Tickets/
    end

    test "holder does not see hero Sold Out badge when event is publicly at capacity",
         %{conn: conn} do
      ctx = setup_single_tier_event(max_attendees: 4, tier_quantity: 20)
      %{holder: holder, stranger: stranger, event: event} = ctx

      insert_sold_tickets!(4, %{user: stranger, event: event, tier: ctx.tier})
      insert_reservation!(ctx, 2)

      conn = log_in(conn, holder)
      {_view, html} = open_tickets_modal(conn, event)

      refute html =~ ~r/>\s*Sold Out\s*</
    end

    test "stranger sees hero Sold Out badge when event is at capacity", %{
      conn: conn
    } do
      ctx = setup_single_tier_event(max_attendees: 3, tier_quantity: 20)
      %{stranger: stranger, event: event} = ctx

      insert_sold_tickets!(3, %{user: stranger, event: event, tier: ctx.tier})

      conn = log_in(conn, stranger)
      {_view, html} = open_tickets_modal(conn, event)

      assert html =~ "Sold Out"
    end
  end

  describe "availability display" do
    test "holder sees remaining count including their reservation", %{
      conn: conn
    } do
      ctx = setup_single_tier_event(tier_quantity: 5)
      %{holder: holder, stranger: stranger, event: event, tier: tier} = ctx

      insert_sold_tickets!(4, %{user: stranger, event: event, tier: tier})
      insert_reservation!(ctx, 2)

      conn = log_in(conn, holder)
      {_view, html} = open_tickets_modal(conn, event)

      assert html =~ "2 remaining"
      assert html =~ "You have 2"
    end

    test "stranger sees zero remaining when only holds are left", %{conn: conn} do
      ctx = setup_single_tier_event(tier_quantity: 4)
      %{stranger: stranger, event: event, tier: tier} = ctx

      insert_sold_tickets!(2, %{user: stranger, event: event, tier: tier})
      insert_reservation!(ctx, 2)

      conn = log_in(conn, stranger)
      {_view, html} = open_tickets_modal(conn, event)

      assert html =~ "Sold Out"
      refute html =~ "remaining"
    end

    test "holder sees Spots Available when event is publicly full", %{
      conn: conn
    } do
      ctx = setup_single_tier_event(max_attendees: 5, tier_quantity: 20)
      %{holder: holder, stranger: stranger, event: event} = ctx

      insert_sold_tickets!(4, %{user: stranger, event: event, tier: ctx.tier})
      insert_reservation!(ctx, 2)

      conn = log_in(conn, holder)
      {_view, html} = open_tickets_modal(conn, event)

      assert html =~ "Spots Available"
      assert html =~ "2 Spots Available"
    end

    test "stranger does not see Spots Available when event is publicly full", %{
      conn: conn
    } do
      ctx = setup_single_tier_event(max_attendees: 5, tier_quantity: 20)
      %{stranger: stranger, event: event} = ctx

      insert_sold_tickets!(4, %{user: stranger, event: event, tier: ctx.tier})
      insert_reservation!(ctx, 2)

      conn = log_in(conn, stranger)
      {_view, html} = open_tickets_modal(conn, event)

      refute html =~ "Spots Available"
    end
  end

  describe "quantity controls and checkout" do
    test "holder can increase quantity up to reserved amount when public pool is zero",
         %{conn: conn} do
      ctx = setup_single_tier_event(tier_quantity: 4)
      %{holder: holder, stranger: stranger, event: event, tier: tier} = ctx

      insert_sold_tickets!(3, %{user: stranger, event: event, tier: tier})
      insert_reservation!(ctx, 2)

      conn = log_in(conn, holder)
      {view, _html} = open_tickets_modal(conn, event)

      assert increase_enabled?(view, tier.id)
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      assert increase_enabled?(view, tier.id)
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      assert increase_disabled?(view, tier.id)
    end

    test "stranger cannot increase quantity when only holds remain", %{
      conn: conn
    } do
      ctx = setup_single_tier_event(tier_quantity: 3)
      %{stranger: stranger, event: event, tier: tier} = ctx

      insert_sold_tickets!(1, %{user: stranger, event: event, tier: tier})
      insert_reservation!(ctx, 2)

      conn = log_in(conn, stranger)
      {view, _html} = open_tickets_modal(conn, event)

      assert increase_disabled?(view, tier.id)
    end

    test "holder can proceed to checkout when tier is publicly sold out", %{
      conn: conn
    } do
      ctx =
        setup_single_tier_event(
          tier_quantity: 3,
          tier_price: Money.new(10, :USD)
        )

      %{holder: holder, stranger: stranger, event: event, tier: tier} = ctx

      insert_sold_tickets!(3, %{user: stranger, event: event, tier: tier})
      insert_reservation!(ctx, 1)

      conn = log_in(conn, holder)
      {view, _html} = open_tickets_modal(conn, event)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "proceed-to-checkout")

      html = render(view)
      assert is_binary(html)

      orders =
        from(o in Tickets.TicketOrder,
          where: o.user_id == ^holder.id and o.event_id == ^event.id
        )
        |> Repo.all()

      assert length(orders) == 1
    end

    test "stranger checkout is rejected when only holds remain" do
      ctx = setup_single_tier_event(tier_quantity: 2)
      %{stranger: stranger, event: event, tier: tier} = ctx

      insert_reservation!(ctx, 2)

      assert {:error, _} =
               BookingValidator.validate_booking(
                 stranger.id,
                 event.id,
                 %{tier.id => 1}
               )
    end
  end

  describe "PubSub reservation refresh" do
    test "TicketReservationCreated refreshes purchasable UI for the holder", %{
      conn: conn
    } do
      ctx = setup_single_tier_event(tier_quantity: 3)
      %{holder: holder, stranger: stranger, event: event, tier: tier} = ctx

      insert_sold_tickets!(3, %{user: stranger, event: event, tier: tier})

      conn = log_in(conn, holder)
      {view, html} = open_tickets_modal(conn, event)

      assert html =~ "Sold Out"

      reservation =
        %TicketReservation{}
        |> TicketReservation.changeset(%{
          ticket_tier_id: tier.id,
          user_id: holder.id,
          quantity: 1,
          created_by_id: holder.id,
          status: "active"
        })
        |> Repo.insert!()

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events",
        {Ysc.Events,
         %TicketReservationCreated{
           ticket_reservation: reservation,
           event_id: event.id
         }}
      )

      html = render(view)

      assert html =~ "Get Tickets"
      assert html =~ "1 remaining"
      refute html =~ "Sold Out (Event at capacity)"
    end
  end

  describe "multi-tier scenarios" do
    test "holder with reservation on sold-out tier can still select that tier only",
         %{
           conn: conn
         } do
      organizer = membership_user()
      holder = membership_user()
      stranger = membership_user()

      {:ok, event} =
        Events.create_event(%{
          title: "Multi-tier reservation event",
          description: "test",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              10,
              :day
            ),
          max_attendees: 50,
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, ga_tier} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(10, :USD),
          quantity: 2,
          event_id: event.id
        })

      {:ok, vip_tier} =
        Events.create_ticket_tier(%{
          name: "VIP",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 10,
          event_id: event.id
        })

      insert_sold_tickets!(2, %{user: stranger, event: event, tier: ga_tier})

      insert_reservation_for_user!(
        %{organizer: organizer, tier: ga_tier},
        holder,
        1
      )

      conn = log_in(conn, holder)
      {view, html} = open_tickets_modal(conn, event)

      assert html =~ "1 remaining"
      assert html =~ "VIP"

      assert increase_enabled?(view, ga_tier.id)
      render_click(view, "increase-ticket-quantity", %{"tier-id" => ga_tier.id})
      assert increase_disabled?(view, ga_tier.id)

      assert increase_enabled?(view, vip_tier.id)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => vip_tier.id})
    end
  end
end
