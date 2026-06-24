defmodule YscWeb.TicketQrLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  defp setup_member_with_order(_context) do
    Ysc.Ledgers.ensure_basic_accounts()
    member = user_fixture()

    member =
      member
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()
      |> Ysc.Repo.reload!()

    event = event_fixture()
    order = ticket_order_fixture(%{user: member, event: event})

    loaded_order =
      Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
      |> Ysc.Repo.preload([:tickets])

    Enum.each(loaded_order.tickets, fn ticket ->
      ticket
      |> Ecto.Changeset.change(status: :confirmed)
      |> Ysc.Repo.update!()
    end)

    final_order =
      Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
      |> Ysc.Repo.preload([:tickets, :event])

    %{member: member, event: event, order: final_order}
  end

  describe "access control" do
    test "redirects unauthenticated users to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/tickets/some-order-id/qr")

      assert path =~ "/users/log"
    end

    test "redirects when order does not belong to the logged-in user", %{
      conn: conn
    } do
      Ysc.Ledgers.ensure_basic_accounts()

      other_user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()
        |> Ysc.Repo.reload!()

      event = event_fixture()
      order = ticket_order_fixture(%{user: other_user, event: event})

      requester = user_fixture()
      conn = log_in_user(conn, requester)

      {:ok, view, _html} = live(conn, ~p"/tickets/#{order.id}/qr")

      assert_redirect(view, "/users/tickets")
    end
  end

  describe "page rendering" do
    setup [:setup_member_with_order]

    test "renders the event title and ticket count", %{
      conn: conn,
      member: member,
      event: event,
      order: order
    } do
      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/tickets/#{order.id}/qr")
      render_async(view)

      assert has_element?(view, "#event-title", event.title)
      assert has_element?(view, "[data-slide]")
    end

    test "renders event date and location when present", %{
      conn: conn,
      member: member,
      event: event,
      order: order
    } do
      {:ok, _event} =
        Ysc.Events.update_event(event, %{
          location_name: "Test Venue",
          address: "123 Test St"
        })

      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/tickets/#{order.id}/qr")
      html = render_async(view)

      assert html =~ "Test Venue"
      assert html =~ "123 Test St"
    end

    test "renders ticket tier name for each confirmed ticket", %{
      conn: conn,
      member: member,
      order: order
    } do
      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/tickets/#{order.id}/qr")
      html = render_async(view)

      ticket = hd(order.tickets)
      assert html =~ "General Admission"
      assert html =~ ticket.reference_id
    end

    test "renders QR code element for each ticket", %{
      conn: conn,
      member: member,
      order: order
    } do
      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/tickets/#{order.id}/qr")
      render_async(view)

      ticket = hd(order.tickets)
      assert has_element?(view, "#ticket-qr-#{ticket.reference_id}")
      assert has_element?(view, "#ticket-qr-#{ticket.reference_id} svg")
    end

    test "renders the footer instruction text", %{
      conn: conn,
      member: member,
      order: order
    } do
      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/tickets/#{order.id}/qr")
      html = render_async(view)

      assert html =~ "Show this QR code to event staff"
    end

    test "renders order reference link", %{
      conn: conn,
      member: member,
      order: order
    } do
      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/tickets/#{order.id}/qr")
      render_async(view)

      assert has_element?(view, "#confirmation-link")
    end

    test "shows navigation controls when order has multiple tickets", %{
      conn: conn,
      member: member,
      event: event
    } do
      Ysc.Ledgers.ensure_basic_accounts()

      tier = ticket_tier_fixture(%{event_id: event.id})

      multi_order =
        ticket_order_fixture(%{
          user: member,
          event: event,
          ticket_selections: %{tier.id => 2}
        })

      loaded_multi =
        Ysc.Repo.get!(Ysc.Tickets.TicketOrder, multi_order.id)
        |> Ysc.Repo.preload([:tickets])

      Enum.each(loaded_multi.tickets, fn t ->
        t |> Ecto.Changeset.change(status: :confirmed) |> Ysc.Repo.update!()
      end)

      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/tickets/#{multi_order.id}/qr")
      render_async(view)

      assert has_element?(view, "[data-slider-prev]")
      assert has_element?(view, "[data-slider-next]")
      assert has_element?(view, "[data-slider-dots]")
    end

    test "hides navigation controls for a single ticket", %{
      conn: conn,
      member: member,
      order: order
    } do
      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/tickets/#{order.id}/qr")
      render_async(view)

      refute has_element?(view, "[data-slider-prev]")
    end
  end

  describe "return_to parameter" do
    setup [:setup_member_with_order]

    test "back link uses return_to path when provided", %{
      conn: conn,
      member: member,
      order: order
    } do
      conn = log_in_user(conn, member)

      {:ok, view, _html} =
        live(conn, ~p"/tickets/#{order.id}/qr" <> "?return_to=/events/abc")

      assert has_element?(view, "#back-link[href='/events/abc']")
    end

    test "back link defaults to /users/tickets when return_to is absent", %{
      conn: conn,
      member: member,
      order: order
    } do
      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/tickets/#{order.id}/qr")

      assert has_element?(view, "#back-link[href='/users/tickets']")
    end

    test "rejects absolute return_to URLs and falls back to default", %{
      conn: conn,
      member: member,
      order: order
    } do
      conn = log_in_user(conn, member)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/tickets/#{order.id}/qr" <> "?return_to=https://evil.example.com"
        )

      assert has_element?(view, "#back-link[href='/users/tickets']")
      refute has_element?(view, "#back-link[href='https://evil.example.com']")
    end

    test "rejects encoded protocol-relative return_to URLs", %{
      conn: conn,
      member: member,
      order: order
    } do
      conn = log_in_user(conn, member)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/tickets/#{order.id}/qr" <> "?return_to=/%2f%2fevil.example.com"
        )

      assert has_element?(view, "#back-link[href='/users/tickets']")
      refute has_element?(view, "#back-link[href*='evil.example.com']")
    end
  end

  describe "filters out donation tickets" do
    test "excludes donations from QR slider and ticket count", %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()

      member =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()
        |> Ysc.Repo.reload!()

      event = event_fixture()

      paid_tier =
        ticket_tier_fixture(%{event_id: event.id, name: "General Admission"})

      donation_tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Donation",
          type: :donation,
          price: nil,
          quantity: nil
        })

      order =
        ticket_order_fixture(%{user: member, event: event, tier: paid_tier})

      loaded_order =
        Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
        |> Ysc.Repo.preload([:tickets])

      Enum.each(loaded_order.tickets, fn ticket ->
        ticket
        |> Ecto.Changeset.change(status: :confirmed)
        |> Ysc.Repo.update!()
      end)

      {:ok, donation_ticket} =
        %Ysc.Events.Ticket{}
        |> Ysc.Events.Ticket.changeset(%{
          ticket_order_id: order.id,
          ticket_tier_id: donation_tier.id,
          event_id: event.id,
          user_id: member.id,
          reference_id: "TKT-DON-#{System.unique_integer()}",
          status: :confirmed,
          expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
        })
        |> Ysc.Repo.insert()

      paid_ticket =
        loaded_order.tickets
        |> Enum.find(&(&1.ticket_tier_id == paid_tier.id))
        |> Ysc.Repo.preload(:ticket_tier)

      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/tickets/#{order.id}/qr")
      render_async(view)

      assert has_element?(view, "#event-ticket-count", "1 ticket")
      assert has_element?(view, "#ticket-qr-#{paid_ticket.reference_id}")
      refute has_element?(view, "#ticket-qr-#{donation_ticket.reference_id}")
    end

    test "redirects when order only has confirmed donations", %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()

      member =
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
        ticket_order_fixture(%{user: member, event: event, tier: donation_tier})

      loaded_order =
        Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
        |> Ysc.Repo.preload([:tickets])

      Enum.each(loaded_order.tickets, fn ticket ->
        ticket
        |> Ecto.Changeset.change(status: :confirmed)
        |> Ysc.Repo.update!()
      end)

      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/tickets/#{order.id}/qr")

      assert_redirect(view, "/users/tickets")
    end
  end

  describe "filters out non-confirmed tickets" do
    test "only shows confirmed tickets", %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()

      member =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()
        |> Ysc.Repo.reload!()

      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      order =
        ticket_order_fixture(%{
          user: member,
          event: event,
          ticket_selections: %{tier.id => 2}
        })

      loaded =
        Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
        |> Ysc.Repo.preload([:tickets])

      [t1, t2] = loaded.tickets

      t1 |> Ecto.Changeset.change(status: :confirmed) |> Ysc.Repo.update!()
      t2 |> Ecto.Changeset.change(status: :cancelled) |> Ysc.Repo.update!()

      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/tickets/#{order.id}/qr")
      html = render_async(view)

      assert html =~ "1 ticket"
    end
  end

  describe "event-scoped QR route" do
    test "redirects unauthenticated users to login", %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()
      event = event_fixture()

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/events/#{event.id}/tickets/qr")

      assert path =~ "/users/log"
    end

    test "redirects when event has no confirmed tickets for the user", %{
      conn: conn
    } do
      Ysc.Ledgers.ensure_basic_accounts()
      member = user_fixture()
      event = event_fixture()

      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets/qr")

      assert_redirect(view, "/users/tickets")
    end

    test "renders event title and combined ticket count from multiple orders",
         %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()

      member =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()
        |> Ysc.Repo.reload!()

      event = event_fixture()
      order1 = ticket_order_fixture(%{user: member, event: event})
      order2 = ticket_order_fixture(%{user: member, event: event})

      for order <- [order1, order2] do
        Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
        |> Ysc.Repo.preload([:tickets])
        |> Map.fetch!(:tickets)
        |> Enum.each(fn t ->
          t |> Ecto.Changeset.change(status: :confirmed) |> Ysc.Repo.update!()
        end)
      end

      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets/qr")
      html = render_async(view)

      assert has_element?(view, "#event-title", event.title)
      assert html =~ "2 tickets"
    end

    test "shows all-orders link instead of single order reference", %{
      conn: conn
    } do
      Ysc.Ledgers.ensure_basic_accounts()

      member =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()
        |> Ysc.Repo.reload!()

      event = event_fixture()
      order = ticket_order_fixture(%{user: member, event: event})

      Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
      |> Ysc.Repo.preload([:tickets])
      |> Map.fetch!(:tickets)
      |> Enum.each(fn t ->
        t |> Ecto.Changeset.change(status: :confirmed) |> Ysc.Repo.update!()
      end)

      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets/qr")
      render_async(view)

      refute has_element?(view, "#confirmation-link")
      assert has_element?(view, "#all-orders-link")
    end

    test "shows navigation controls when tickets from multiple orders are combined",
         %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()

      member =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()
        |> Ysc.Repo.reload!()

      event = event_fixture()
      order1 = ticket_order_fixture(%{user: member, event: event})
      order2 = ticket_order_fixture(%{user: member, event: event})

      for order <- [order1, order2] do
        Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
        |> Ysc.Repo.preload([:tickets])
        |> Map.fetch!(:tickets)
        |> Enum.each(fn t ->
          t |> Ecto.Changeset.change(status: :confirmed) |> Ysc.Repo.update!()
        end)
      end

      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets/qr")
      render_async(view)

      assert has_element?(view, "[data-slider-prev]")
      assert has_element?(view, "[data-slider-next]")
      assert has_element?(view, "[data-slider-dots]")
    end

    test "back link uses return_to path when provided", %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()

      member =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()
        |> Ysc.Repo.reload!()

      event = event_fixture()
      order = ticket_order_fixture(%{user: member, event: event})

      Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
      |> Ysc.Repo.preload([:tickets])
      |> Map.fetch!(:tickets)
      |> Enum.each(fn t ->
        t |> Ecto.Changeset.change(status: :confirmed) |> Ysc.Repo.update!()
      end)

      conn = log_in_user(conn, member)

      {:ok, view, _html} =
        live(conn, ~p"/events/#{event.id}/tickets/qr" <> "?return_to=/")

      assert has_element?(view, "#back-link[href='/']")
    end
  end
end
