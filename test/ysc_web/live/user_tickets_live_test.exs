defmodule YscWeb.UserTicketsLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  describe "mount/3" do
    test "shows upcoming ticket order when user has completed order", %{
      conn: conn
    } do
      data = Ysc.TestDataFactory.complete_ticket_order()
      conn = log_in_user(conn, data.user)

      {:ok, view, _html} = live(conn, ~p"/users/tickets")
      html = render(view)

      assert html =~ data.event.title
      assert has_element?(view, "#ticket-orders-list")
    end

    test "renders slim-loaded order reference, ticket count, tiers, and total",
         %{
           conn: conn
         } do
      data = Ysc.TestDataFactory.complete_ticket_order()

      Enum.each(data.tickets, fn ticket ->
        ticket
        |> Ecto.Changeset.change(status: :confirmed)
        |> Ysc.Repo.update!()
      end)

      conn = log_in_user(conn, data.user)

      {:ok, view, _html} = live(conn, ~p"/users/tickets")
      render(view)

      row = "#ticket_orders-#{data.order.id}"
      formatted_total = Ysc.MoneyHelper.format_money!(data.order.total_amount)

      assert has_element?(view, row, data.event.title)
      assert has_element?(view, row, data.order.reference_id)
      assert has_element?(view, row, "2 Tickets")
      assert has_element?(view, row, "Paid")
      assert has_element?(view, row, "Total Paid")
      assert has_element?(view, row, formatted_total)
      assert has_element?(view, row, "Ready to use")

      Enum.each(data.tickets, fn ticket ->
        assert has_element?(view, row, ticket.reference_id)
        assert has_element?(view, row, ticket.ticket_tier.name)
      end)

      assert has_element?(view, "#show-checkin-tickets-#{data.order.id}")
    end

    test "donation-only orders do not offer check-in tickets", %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()

      user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()
        |> Ysc.Repo.reload!()

      event = event_fixture()

      donation_tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Donation",
          type: :donation,
          price: nil,
          quantity: nil
        })

      order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: donation_tier,
          status: :completed
        })

      loaded =
        Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
        |> Ysc.Repo.preload(tickets: :ticket_tier)

      Enum.each(loaded.tickets, fn ticket ->
        ticket
        |> Ecto.Changeset.change(status: :confirmed)
        |> Ysc.Repo.update!()
      end)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/users/tickets")
      render(view)

      row = "#ticket_orders-#{order.id}"

      assert has_element?(view, row, "1 Donation")
      refute has_element?(view, row, "1 Ticket")
      refute has_element?(view, "#show-checkin-tickets-#{order.id}")
      assert has_element?(view, row, "View order & receipt")
    end

    test "loads tickets page successfully", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/users/tickets")

      assert html =~ "Your Tickets"
      assert html =~ "Find More Events"
    end

    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/users/tickets")
      assert path == "/users/log-in"
    end

    test "displays empty state when user has no tickets", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/tickets")

      assert has_element?(view, "#ticket-orders-empty")
    end

    test "displays page structure with navigation elements", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/tickets")
      html = render(view)

      # Check for main page structure
      assert html =~ "Your account"
      assert html =~ "Browse Events"
    end

    test "displays title as page_title", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/tickets")

      assert page_title(view) =~ "My Tickets"
    end
  end

  describe "event handlers" do
    test "displays pending order actions with cancel checkout button", %{
      conn: conn
    } do
      data = Ysc.TestDataFactory.complete_ticket_order(status: :pending)
      conn = log_in_user(conn, data.user)

      {:ok, view, _html} = live(conn, ~p"/users/tickets")
      html = render(view)

      assert has_element?(view, "#ticket-orders-list")
      assert html =~ data.event.title
      assert has_element?(view, "button", "Cancel checkout")
      assert html =~ "will go back on sale so others can buy them"
      refute html =~ "member discount"
      refute html =~ "will be released"
      assert html =~ "Complete payment in"
      refute html =~ "Complete payment within"

      assert has_element?(
               view,
               "#order-status-#{data.order.id}",
               "Payment needed"
             )

      assert has_element?(
               view,
               "#resume-order-#{data.order.id}",
               "Finish payment"
             )

      refute has_element?(
               view,
               "#resume-order-#{data.order.id}",
               "Confirm free tickets"
             )
    end

    test "pending free holds ask to confirm tickets, not pay", %{conn: conn} do
      user = user_fixture()
      event = event_fixture()

      free_tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "RSVP",
          type: :free,
          price: Money.new(0, :USD),
          quantity: 50
        })

      order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: free_tier,
          status: :pending
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/users/tickets")
      render(view)

      assert has_element?(view, "#order-status-#{order.id}", "Confirm tickets")
      refute has_element?(view, "#order-status-#{order.id}", "Payment needed")

      assert has_element?(
               view,
               "#pending-order-deadline-#{order.id}",
               "Confirm your tickets in"
             )

      refute has_element?(
               view,
               "#pending-order-deadline-#{order.id}",
               "Complete payment"
             )

      assert has_element?(
               view,
               "#resume-order-#{order.id}",
               "Confirm free tickets"
             )

      refute has_element?(view, "#resume-order-#{order.id}", "Finish payment")
    end

    test "completed free orders say Confirmed and Total Free, not Paid", %{
      conn: conn
    } do
      user = user_fixture()
      event = event_fixture()

      free_tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "RSVP",
          type: :free,
          price: Money.new(0, :USD),
          quantity: 50
        })

      order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: free_tier,
          status: :completed
        })

      loaded =
        Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
        |> Ysc.Repo.preload(:tickets)

      Enum.each(loaded.tickets, fn ticket ->
        ticket
        |> Ecto.Changeset.change(status: :confirmed)
        |> Ysc.Repo.update!()
      end)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/users/tickets")
      render(view)

      assert has_element?(view, "#order-status-#{order.id}", "Confirmed")
      refute has_element?(view, "#order-status-#{order.id}", "Paid")
      assert has_element?(view, "#order-total-label-#{order.id}", "Total")
      refute has_element?(view, "#order-total-label-#{order.id}", "Total Paid")
      assert has_element?(view, "#order-total-amount-#{order.id}", "Free")
    end

    test "cancel-order event shows error when order not found", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/tickets")

      render_click(view, "cancel-order", %{"order-id" => Ecto.ULID.generate()})

      flash = :sys.get_state(view.pid).socket.assigns.flash

      assert Phoenix.Flash.get(flash, :error) =~
               "couldn't find that ticket purchase"
    end

    test "resume-order event shows error when order not found", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/tickets")

      render_click(view, "resume-order", %{"order-id" => Ecto.ULID.generate()})

      flash = :sys.get_state(view.pid).socket.assigns.flash

      assert Phoenix.Flash.get(flash, :error) =~
               "couldn't find that ticket purchase"
    end

    test "resume-order event shows error when order is no longer pending", %{
      conn: conn
    } do
      data = Ysc.TestDataFactory.complete_ticket_order()
      conn = log_in_user(conn, data.user)

      {:ok, view, _html} = live(conn, ~p"/users/tickets")

      render_click(view, "resume-order", %{"order-id" => data.order.id})

      flash = :sys.get_state(view.pid).socket.assigns.flash

      assert Phoenix.Flash.get(flash, :error) =~
               "This ticket purchase has expired or was already completed"
    end

    test "view-tickets event redirects to confirmation page", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/tickets")

      fake_order_id = Ecto.ULID.generate()

      assert {:error, {:live_redirect, %{to: path}}} =
               render_click(view, "view-tickets", %{"order-id" => fake_order_id})

      assert path == "/orders/#{fake_order_id}/confirmation"
    end
  end
end
