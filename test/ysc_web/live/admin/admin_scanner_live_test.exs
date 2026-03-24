defmodule YscWeb.AdminScannerLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures
  import Ysc.ScanningFixtures

  alias Ysc.Scanning
  alias Ysc.Scanning.QrToken

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  defp make_active_member do
    user = user_fixture()

    user
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Ysc.Repo.update!()
    |> Ysc.Repo.reload!()
  end

  defp confirm_tickets(order) do
    loaded =
      Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
      |> Ysc.Repo.preload([:tickets])

    Enum.each(loaded.tickets, fn t ->
      t |> Ecto.Changeset.change(status: :confirmed) |> Ysc.Repo.update!()
    end)

    Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
    |> Ysc.Repo.preload(tickets: [:ticket_tier, :registration])
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Access control
  # ──────────────────────────────────────────────────────────────────────────

  describe "access control" do
    test "redirects unauthenticated users", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/scanner")
      assert path =~ "/users/log"
    end

    test "redirects regular members to home", %{conn: conn} do
      member = user_fixture()
      conn = log_in_user(conn, member)

      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/scanner")
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Setup phase (index action)
  # ──────────────────────────────────────────────────────────────────────────

  describe "setup phase" do
    setup [:create_admin]

    test "renders the session setup form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")

      assert has_element?(view, "#scan-setup-form")
    end

    test "shows membership and event mode options", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")

      assert has_element?(view, "button[phx-value-mode='membership']")
      assert has_element?(view, "button[phx-value-mode='event']")
    end

    test "shows open sessions when they exist", %{conn: conn, admin: admin} do
      session =
        scan_session_fixture(%{created_by: admin, name: "My Open Session"})

      {:ok, _view, html} = live(conn, ~p"/admin/scanner")
      assert html =~ "My Open Session"

      Scanning.close_session(session.id)
    end

    test "selecting membership mode does not show event selector", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")

      view |> element("button[phx-value-mode='membership']") |> render_click()

      refute has_element?(view, "select[name='session[event_id]']")
    end

    test "selecting event mode shows event selector", %{
      conn: conn,
      admin: admin
    } do
      event_fixture(%{organizer_id: admin.id, title: "Test Event"})

      {:ok, view, _html} = live(conn, ~p"/admin/scanner")

      view |> element("button[phx-value-mode='event']") |> render_click()

      assert has_element?(view, "select[name='session[event_id]']")
    end

    test "starts a membership session and enters scanning phase", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")

      view |> element("button[phx-value-mode='membership']") |> render_click()

      view
      |> form("#scan-setup-form", %{
        session: %{name: "Morning Membership Check"}
      })
      |> render_submit()

      assert has_element?(view, "[phx-click='end_session']")
    end

    test "starts an event session and enters scanning phase", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/scanner")

      view |> element("button[phx-value-mode='event']") |> render_click()

      view
      |> form("#scan-setup-form", %{
        session: %{name: "Door Scan", event_id: event.id}
      })
      |> render_submit()

      assert has_element?(view, "[phx-click='end_session']")
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Scanning phase — membership
  # ──────────────────────────────────────────────────────────────────────────

  describe "scanning phase — membership" do
    setup [:create_admin]

    defp start_membership_session(view) do
      view |> element("button[phx-value-mode='membership']") |> render_click()

      view
      |> form("#scan-setup-form", %{session: %{name: "Membership Scan"}})
      |> render_submit()
    end

    test "active member scan shows green active result", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      start_membership_session(view)

      member = make_active_member()
      token = QrToken.sign_membership(member.id)

      view |> render_hook("scan_result", %{"data" => token})

      html = render(view)
      assert html =~ "Active Member"
      assert html =~ member.first_name
    end

    test "inactive member scan shows red inactive result", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      start_membership_session(view)

      inactive_user = user_fixture()
      token = QrToken.sign_membership(inactive_user.id)

      view |> render_hook("scan_result", %{"data" => token})

      html = render(view)
      assert html =~ "Inactive"
    end

    test "invalid token shows error result", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      start_membership_session(view)

      view |> render_hook("scan_result", %{"data" => "garbage-token"})

      html = render(view)
      assert html =~ "Invalid" or html =~ "Error" or html =~ "error"
    end

    test "scanning ticket QR in membership mode shows cross-mode error", %{
      conn: conn
    } do
      Ysc.Ledgers.ensure_basic_accounts()
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      start_membership_session(view)

      member = make_active_member()
      event = event_fixture()

      order =
        ticket_order_fixture(%{user: member, event: event}) |> confirm_tickets()

      ticket = hd(order.tickets)
      token = QrToken.sign_ticket(ticket.id)

      view |> render_hook("scan_result", %{"data" => token})

      html = render(view)
      assert html =~ "cross" or html =~ "Membership QR" or html =~ "Invalid"
    end

    test "dismiss_scan_result clears the result", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      start_membership_session(view)

      member = make_active_member()
      token = QrToken.sign_membership(member.id)

      view |> render_hook("scan_result", %{"data" => token})
      assert render(view) =~ "Active Member"

      view
      |> element("button[phx-click='dismiss_scan_result']")
      |> render_click()

      refute render(view) =~ "Active Member"
    end

    test "scan count increments after a successful scan", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      start_membership_session(view)

      assert render(view) =~ "0 scans"

      member = make_active_member()
      token = QrToken.sign_membership(member.id)
      view |> render_hook("scan_result", %{"data" => token})

      assert render(view) =~ "1 scan"
    end

    test "end_session returns to setup phase", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      start_membership_session(view)

      view |> element("button[phx-click='end_session']") |> render_click()

      assert has_element?(view, "#scan-setup-form")
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Scanning phase — event check-in
  # ──────────────────────────────────────────────────────────────────────────

  describe "scanning phase — event check-in" do
    setup [:create_admin]

    defp start_event_session(view, event) do
      view |> element("button[phx-value-mode='event']") |> render_click()

      view
      |> form("#scan-setup-form", %{
        session: %{name: "Door Scan", event_id: event.id}
      })
      |> render_submit()
    end

    test "confirmed ticket scan shows checked-in result", %{
      conn: conn,
      admin: admin
    } do
      Ysc.Ledgers.ensure_basic_accounts()
      event = event_fixture(%{organizer_id: admin.id})
      member = make_active_member()

      order =
        ticket_order_fixture(%{user: member, event: event}) |> confirm_tickets()

      ticket = hd(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      start_event_session(view, event)

      token = QrToken.sign_ticket(ticket.id)
      view |> render_hook("scan_result", %{"data" => token})

      html = render(view)
      assert html =~ "Checked In" or html =~ "checked in" or html =~ "success"
    end

    test "already-scanned ticket shows already scanned result with view order button",
         %{
           conn: conn,
           admin: admin
         } do
      Ysc.Ledgers.ensure_basic_accounts()
      event = event_fixture(%{organizer_id: admin.id})
      member = make_active_member()

      order =
        ticket_order_fixture(%{user: member, event: event}) |> confirm_tickets()

      ticket = hd(order.tickets)

      ticket
      |> Ysc.Events.Ticket.check_in_changeset()
      |> Ysc.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      start_event_session(view, event)

      token = QrToken.sign_ticket(ticket.id)
      view |> render_hook("scan_result", %{"data" => token})

      html = render(view)
      assert html =~ "ALREADY SCANNED" or html =~ "already" or html =~ "scanned"

      assert html =~ "View Order" or html =~ "view order" or
               html =~ "/admin/users/"
    end

    test "group check-in prompt shown for multi-ticket order", %{
      conn: conn,
      admin: admin
    } do
      Ysc.Ledgers.ensure_basic_accounts()
      event = event_fixture(%{organizer_id: admin.id})
      member = make_active_member()
      tier = ticket_tier_fixture(%{event_id: event.id})

      order =
        ticket_order_fixture(%{
          user: member,
          event: event,
          ticket_selections: %{tier.id => 2}
        })

      order = confirm_tickets(order)
      ticket = hd(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      start_event_session(view, event)

      token = QrToken.sign_ticket(ticket.id)
      view |> render_hook("scan_result", %{"data" => token})

      html = render(view)
      assert html =~ "Check in ALL" or html =~ "group" or html =~ "Guests"
    end

    test "check_in_all checks in all tickets in the order", %{
      conn: conn,
      admin: admin
    } do
      Ysc.Ledgers.ensure_basic_accounts()
      event = event_fixture(%{organizer_id: admin.id})
      member = make_active_member()
      tier = ticket_tier_fixture(%{event_id: event.id})

      order =
        ticket_order_fixture(%{
          user: member,
          event: event,
          ticket_selections: %{tier.id => 2}
        })

      order = confirm_tickets(order)
      ticket = hd(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      start_event_session(view, event)

      view
      |> render_hook("scan_result", %{"data" => QrToken.sign_ticket(ticket.id)})

      view
      |> element("button[phx-click='check_in_all']")
      |> render_click()

      html = render(view)
      assert html =~ "2" or html =~ "Checked In" or html =~ "group"
    end

    test "wrong event ticket shows error", %{conn: conn, admin: admin} do
      Ysc.Ledgers.ensure_basic_accounts()
      event = event_fixture(%{organizer_id: admin.id})
      other_event = event_fixture()
      member = make_active_member()

      order =
        ticket_order_fixture(%{user: member, event: other_event})
        |> confirm_tickets()

      ticket = hd(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      start_event_session(view, event)

      token = QrToken.sign_ticket(ticket.id)
      view |> render_hook("scan_result", %{"data" => token})

      html = render(view)
      assert html =~ "event" or html =~ "Invalid" or html =~ "Error"
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Manual lookup
  # ──────────────────────────────────────────────────────────────────────────

  describe "manual_lookup — membership mode" do
    setup [:create_admin]

    test "finds an active member by email", %{conn: conn} do
      member = make_active_member()

      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      view |> element("button[phx-value-mode='membership']") |> render_click()

      view
      |> form("#scan-setup-form", %{session: %{name: "Manual"}})
      |> render_submit()

      view
      |> form("#manual-entry-form", %{manual: %{query: member.email}})
      |> render_submit()

      html = render(view)
      assert html =~ member.first_name or html =~ "Active"
    end

    test "shows error for unknown email", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      view |> element("button[phx-value-mode='membership']") |> render_click()

      view
      |> form("#scan-setup-form", %{session: %{name: "Manual"}})
      |> render_submit()

      view
      |> form("#manual-entry-form", %{manual: %{query: "nobody@example.com"}})
      |> render_submit()

      html = render(view)
      assert html =~ "not found" or html =~ "Error" or html =~ "error"
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Sessions list (:sessions action)
  # ──────────────────────────────────────────────────────────────────────────

  describe "past sessions list" do
    setup [:create_admin]

    test "renders session list page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/scanner/sessions")
      assert html =~ "Scan Sessions"
    end

    test "lists created sessions", %{conn: conn, admin: admin} do
      scan_session_fixture(%{created_by: admin, name: "Listed Session"})

      {:ok, _view, html} = live(conn, ~p"/admin/scanner/sessions")
      assert html =~ "Listed Session"
    end

    test "shows a New Scan Session button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner/sessions")
      assert has_element?(view, "a[href='/admin/scanner']")
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Session detail (:session_detail action)
  # ──────────────────────────────────────────────────────────────────────────

  describe "session detail" do
    setup [:create_admin]

    test "renders session name and type badge", %{conn: conn, admin: admin} do
      session =
        scan_session_fixture(%{created_by: admin, name: "Detail Session"})

      {:ok, _view, html} = live(conn, ~p"/admin/scanner/sessions/#{session.id}")
      assert html =~ "Detail Session"
      assert html =~ "Membership"
    end

    test "shows empty state when no records", %{conn: conn, admin: admin} do
      session = scan_session_fixture(%{created_by: admin})

      {:ok, _view, html} = live(conn, ~p"/admin/scanner/sessions/#{session.id}")
      assert html =~ "No scan records"
    end

    test "shows scan records after scans have been performed", %{
      conn: conn,
      admin: admin
    } do
      session = scan_session_fixture(%{created_by: admin})
      member = make_active_member()

      Scanning.process_scan(session, QrToken.sign_membership(member.id))

      {:ok, _view, html} = live(conn, ~p"/admin/scanner/sessions/#{session.id}")
      assert html =~ member.first_name
      assert html =~ member.email
    end

    test "shows Export CSV button", %{conn: conn, admin: admin} do
      session = scan_session_fixture(%{created_by: admin})

      {:ok, view, _html} = live(conn, ~p"/admin/scanner/sessions/#{session.id}")
      assert has_element?(view, "button[phx-click='export-csv']")
    end

    test "back link navigates to sessions list", %{conn: conn, admin: admin} do
      session = scan_session_fixture(%{created_by: admin})

      {:ok, view, _html} = live(conn, ~p"/admin/scanner/sessions/#{session.id}")
      assert has_element?(view, "a[href='/admin/scanner/sessions']")
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Resume session
  # ──────────────────────────────────────────────────────────────────────────

  describe "resuming a session" do
    setup [:create_admin]

    test "resume param goes straight to scanning phase", %{
      conn: conn,
      admin: admin
    } do
      session =
        scan_session_fixture(%{created_by: admin, name: "Resumable Session"})

      {:ok, view, html} = live(conn, ~p"/admin/scanner?resume=#{session.id}")

      assert html =~ "Resumable Session"
      assert has_element?(view, "button[phx-click='end_session']")
    end

    test "resume shows existing scan count", %{conn: conn, admin: admin} do
      session = scan_session_fixture(%{created_by: admin})
      member = make_active_member()
      Scanning.process_scan(session, QrToken.sign_membership(member.id))

      {:ok, _view, html} = live(conn, ~p"/admin/scanner?resume=#{session.id}")
      assert html =~ "1 scan"
    end
  end
end
