defmodule YscWeb.AdminCancellationRefundModalLiveTest do
  use YscWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events.Ticket
  alias Ysc.Ledgers
  alias Ysc.Repo
  alias Ysc.Tickets
  alias Ysc.Tickets.TicketOrder

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  defp create_volunteer(%{conn: conn}) do
    user = user_fixture(%{role: "volunteer"})
    %{conn: log_in_user(conn, user), volunteer: user}
  end

  # Mirrors AdminTicketListLiveTest's helper: a real paid order with a
  # completed Stripe payment and confirmed tickets.
  defp completed_ticket_order_with_payment!(opts) do
    quantity = Keyword.get(opts, :quantity, 1)
    user = Keyword.get_lazy(opts, :user, fn -> user_fixture() end)

    user =
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Repo.update!()

    event = Keyword.get_lazy(opts, :event, fn -> event_fixture() end)

    tier =
      Keyword.get_lazy(opts, :tier, fn ->
        ticket_tier_fixture(%{event_id: event.id})
      end)

    {:ok, order} =
      Tickets.create_ticket_order(user.id, event.id, %{tier.id => quantity})

    {:ok, {payment, _transaction, _entries}} =
      Ledgers.process_event_payment_with_donations(%{
        user_id: user.id,
        total_amount: order.total_amount,
        event_amount: order.total_amount,
        donation_amount: Money.new(0, :USD),
        event_id: event.id,
        external_payment_id:
          "pi_cancellation_refund_#{System.unique_integer([:positive])}",
        stripe_fee: Money.new(320, :USD),
        description: "Event tickets",
        payment_method_id: nil
      })

    {:ok, completed} = Tickets.complete_ticket_order(order, payment.id)

    from(t in Ticket, where: t.ticket_order_id == ^order.id)
    |> Repo.update_all(set: [status: :confirmed])

    tickets =
      from(t in Ticket, where: t.ticket_order_id == ^order.id, order_by: t.id)
      |> Repo.all()

    %{
      user: user,
      event: event,
      payment: payment,
      ticket_order: completed,
      tickets: tickets
    }
  end

  defp grant_ticket_order!(event, buyer, granted_by) do
    tier = ticket_tier_fixture(%{event_id: event.id, price: Money.new(0, :USD)})

    {:ok, order} =
      Tickets.grant_admin_tickets(
        granted_by.id,
        buyer.id,
        event.id,
        %{tier.id => 1},
        skip_email: true
      )

    order
  end

  describe "cancelling a published event" do
    setup [:create_admin]

    test "opens a refund modal listing the event's paid orders", %{
      conn: conn
    } do
      event = event_fixture(%{state: :published})

      %{ticket_order: order, user: buyer} =
        completed_ticket_order_with_payment!(event: event)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      view
      |> element("#cancel-event-btn")
      |> render_click()

      assert Repo.get!(Ysc.Events.Event, event.id).state == :cancelled
      assert has_element?(view, "#cancellation-refund-modal")

      assert has_element?(
               view,
               "#cancellation-refund-order-#{order.id}",
               "#{buyer.first_name} #{buyer.last_name}"
             )

      assert has_element?(
               view,
               "#cancellation-refund-order-#{order.id} input[type=checkbox]"
             )
    end

    test "refunding a selected order cancels its tickets and issues a Stripe refund",
         %{conn: conn} do
      event = event_fixture(%{state: :published})

      %{ticket_order: order, tickets: [ticket], payment: payment} =
        completed_ticket_order_with_payment!(event: event)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      view
      |> element("#cancel-event-btn")
      |> render_click()

      view
      |> element("#cancellation-refund-order-#{order.id} input[type=checkbox]")
      |> render_click()

      view
      |> element("button[phx-click='refund-selected']")
      |> render_click()

      assert Repo.get!(Ticket, ticket.id).status == :cancelled
      assert Repo.get!(TicketOrder, order.id).status == :cancelled

      refunds =
        Repo.all(
          from(r in Ysc.Ledgers.Refund, where: r.payment_id == ^payment.id)
        )

      assert length(refunds) == 1
    end

    test "refunding still cancels tickets when the event has already started",
         %{conn: conn} do
      event = event_fixture(%{state: :published})

      %{ticket_order: order, tickets: [ticket], payment: payment} =
        completed_ticket_order_with_payment!(event: event)

      event
      |> Ecto.Changeset.change(%{
        start_date:
          DateTime.utc_now()
          |> DateTime.add(-2, :day)
          |> DateTime.truncate(:second),
        end_date:
          DateTime.utc_now()
          |> DateTime.add(-1, :day)
          |> DateTime.truncate(:second)
      })
      |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      view
      |> element("#cancel-event-btn")
      |> render_click()

      view
      |> element("#cancellation-refund-order-#{order.id} input[type=checkbox]")
      |> render_click()

      view
      |> element("button[phx-click='refund-selected']")
      |> render_click()

      assert Repo.get!(Ticket, ticket.id).status == :cancelled
      assert Repo.get!(TicketOrder, order.id).status == :cancelled

      refunds =
        Repo.all(
          from(r in Ysc.Ledgers.Refund, where: r.payment_id == ^payment.id)
        )

      assert length(refunds) == 1
    end

    test "an already-refunded order shows a Refunded badge with no checkbox",
         %{conn: conn} do
      event = event_fixture(%{state: :published})

      %{ticket_order: order, tickets: [ticket], payment: payment} =
        completed_ticket_order_with_payment!(event: event)

      {:ok, {_refund, _transaction, _entries}} =
        Tickets.refund_via_stripe(
          payment,
          order.total_amount,
          "Pre-cancelled refund",
          ticket_ids: [ticket.id]
        )

      {:ok, _refund_info} =
        Tickets.refund_tickets(order, [ticket.id], "Pre-cancelled refund")

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      view
      |> element("#cancel-event-btn")
      |> render_click()

      assert has_element?(
               view,
               "#cancellation-refund-order-#{order.id}",
               "Refunded"
             )

      refute has_element?(
               view,
               "#cancellation-refund-order-#{order.id} input[type=checkbox]"
             )
    end

    test "a cancelled order with no recorded refund is flagged for manual follow-up",
         %{conn: conn} do
      event = event_fixture(%{state: :published})

      %{ticket_order: order, tickets: [ticket]} =
        completed_ticket_order_with_payment!(event: event)

      # Cancels the ticket without ever issuing a Stripe/ledger refund --
      # simulates a gap this modal must surface rather than hide behind a
      # false "Refunded" badge.
      {:ok, _refund_info} =
        Tickets.refund_tickets(order, [ticket.id], "Cancelled without refund")

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      view
      |> element("#cancel-event-btn")
      |> render_click()

      assert has_element?(
               view,
               "#cancellation-refund-order-#{order.id}",
               "no refund on record"
             )

      refute has_element?(
               view,
               "#cancellation-refund-order-#{order.id}",
               "Refunded"
             )

      refute has_element?(
               view,
               "#cancellation-refund-order-#{order.id} input[type=checkbox]"
             )
    end

    test "a free/complimentary order shows a no-payment badge and cannot be selected",
         %{conn: conn, admin: admin} do
      event = event_fixture(%{state: :published})
      buyer = user_fixture()
      order = grant_ticket_order!(event, buyer, admin)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      view
      |> element("#cancel-event-btn")
      |> render_click()

      assert has_element?(
               view,
               "#cancellation-refund-order-#{order.id}",
               "nothing to refund"
             )

      refute has_element?(
               view,
               "#cancellation-refund-order-#{order.id} input[type=checkbox]"
             )
    end

    test "opening the refund modal does not N+1 ticket queries", %{
      conn: conn
    } do
      event = event_fixture(%{state: :published})

      refundable_orders =
        for _i <- 1..3 do
          completed_ticket_order_with_payment!(event: event)
        end

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      {_html, ticket_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            Ysc.QueryCounter.track_caller_pid(view.pid)

            view
            |> element("#cancel-event-btn")
            |> render_click()
          end,
          pattern: ~r/FROM "tickets"/i,
          caller_pids: [self(), view.pid]
        )

      assert ticket_queries <= 1

      for %{ticket_order: order} <- refundable_orders do
        assert has_element?(view, "#cancellation-refund-order-#{order.id}")
      end
    end

    test "opening the refund modal batches refund existence into one query", %{
      conn: conn
    } do
      event = event_fixture(%{state: :published})

      refunded_orders =
        for _i <- 1..3 do
          %{ticket_order: order, tickets: [ticket], payment: payment} =
            completed_ticket_order_with_payment!(event: event)

          {:ok, {_refund, _transaction, _entries}} =
            Tickets.refund_via_stripe(
              payment,
              order.total_amount,
              "Pre-cancelled refund",
              ticket_ids: [ticket.id]
            )

          {:ok, _refund_info} =
            Tickets.refund_tickets(order, [ticket.id], "Pre-cancelled refund")

          order
        end

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      {_html, refund_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            Ysc.QueryCounter.track_caller_pid(view.pid)

            view
            |> element("#cancel-event-btn")
            |> render_click()
          end,
          pattern: ~r/FROM "refunds"/i,
          caller_pids: [self(), view.pid]
        )

      assert refund_queries == 1

      for order <- refunded_orders do
        assert has_element?(
                 view,
                 "#cancellation-refund-order-#{order.id}",
                 "Refunded"
               )
      end
    end
  end

  describe "permissions" do
    setup [:create_volunteer]

    test "a volunteer cannot cancel the event or see the refund modal", %{
      conn: conn
    } do
      event = event_fixture(%{state: :published})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      refute has_element?(view, "#cancel-event-btn")

      render_click(view, "cancel-event")

      assert Repo.get!(Ysc.Events.Event, event.id).state == :published
      refute has_element?(view, "#cancellation-refund-modal")
    end
  end
end
