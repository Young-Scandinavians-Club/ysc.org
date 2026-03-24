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

      assert {:error, {:live_redirect, %{to: "/users/tickets"}}} =
               live(conn, ~p"/tickets/#{order.id}/qr")
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
      {:ok, _view, html} = live(conn, ~p"/tickets/#{order.id}/qr")

      assert html =~ "Test Venue"
      assert html =~ "123 Test St"
    end

    test "renders ticket tier name for each confirmed ticket", %{
      conn: conn,
      member: member,
      order: order
    } do
      conn = log_in_user(conn, member)
      {:ok, _view, html} = live(conn, ~p"/tickets/#{order.id}/qr")

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
      {:ok, _view, html} = live(conn, ~p"/tickets/#{order.id}/qr")

      assert html =~ "Show this QR code to event staff"
    end

    test "renders order reference link", %{
      conn: conn,
      member: member,
      order: order
    } do
      conn = log_in_user(conn, member)
      {:ok, view, _html} = live(conn, ~p"/tickets/#{order.id}/qr")

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
      {:ok, _view, html} = live(conn, ~p"/tickets/#{order.id}/qr")

      assert html =~ "1 ticket"
    end
  end
end
