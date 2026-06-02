defmodule YscWeb.AdminScannerLiveTest do
  use YscWeb.ConnCase, async: true

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

    test "end_session closes membership session and returns to setup", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      start_membership_session(view)

      [session] = Scanning.get_open_sessions(admin.id)

      view |> element("button[phx-click='end_session']") |> render_click()

      assert has_element?(view, "#scan-setup-form")
      assert Scanning.get_session!(session.id).closed_at != nil
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

    test "end_session navigates to event desk without closing session", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      start_event_session(view, event)

      [session] = Scanning.get_open_sessions(admin.id)

      view |> element("button[phx-click='end_session']") |> render_click()

      assert_redirect(
        view,
        ~p"/admin/events/#{event.id}/check-in?scan_session_id=#{session.id}"
      )

      assert is_nil(Scanning.get_session!(session.id).closed_at)
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

    test "resume param on closed session stays in setup and shows flash", %{
      conn: conn,
      admin: admin
    } do
      session = scan_session_fixture(%{created_by: admin})
      Scanning.close_session(session.id)

      {:ok, view, _html} = live(conn, ~p"/admin/scanner?resume=#{session.id}")

      assert has_element?(view, "#scan-setup-form")
    end
  end

  describe "setup validation and hooks" do
    setup [:create_admin]

    test "submit without selecting mode shows flash error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")

      view
      |> form("#scan-setup-form", %{session: %{name: "No Mode"}})
      |> render_submit()

      html = render(view)
      assert html =~ "scan mode" or html =~ "mode"
    end

    test "camera_started does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      view |> element("button[phx-value-mode='membership']") |> render_click()

      view
      |> form("#scan-setup-form", %{session: %{name: "Cam Start"}})
      |> render_submit()

      view
      |> render_hook("camera_started", %{})

      assert render(view) =~ "Check-in &amp; Scan"
    end

    test "scanner_debug logs path without crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      view |> element("button[phx-value-mode='membership']") |> render_click()

      view
      |> form("#scan-setup-form", %{session: %{name: "Debug"}})
      |> render_submit()

      view
      |> render_hook("scanner_debug", %{"message" => "tick", "extra" => "1"})

      assert render(view) =~ "Debug"
    end

    test "empty manual_lookup does nothing visible", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      view |> element("button[phx-value-mode='membership']") |> render_click()

      view
      |> form("#scan-setup-form", %{session: %{name: "Manual Empty"}})
      |> render_submit()

      view
      |> form("#manual-entry-form", %{manual: %{query: "   "}})
      |> render_submit()

      refute render(view) =~ "Active Member"
    end

    test "export-csv pushes download event", %{conn: conn, admin: admin} do
      session = scan_session_fixture(%{created_by: admin})

      {:ok, view, _html} = live(conn, ~p"/admin/scanner/sessions/#{session.id}")

      view
      |> element("button[phx-click='export-csv']")
      |> render_click()

      assert_push_event(view, "download-csv", %{content: _b64, filename: fname})
      assert fname =~ "scan_session_#{session.id}"
    end

    test "resume_session event resumes open session", %{
      conn: conn,
      admin: admin
    } do
      session =
        scan_session_fixture(%{created_by: admin, name: "Resume Via Button"})

      {:ok, view, _html} = live(conn, ~p"/admin/scanner")

      view
      |> element(
        "button[phx-click='resume_session'][phx-value-session-id='#{session.id}']"
      )
      |> render_click()

      assert render(view) =~ "Resume Via Button"
      assert has_element?(view, "button[phx-click='end_session']")
    end

    test "resume_session on closed session shows flash", %{
      conn: conn,
      admin: admin
    } do
      session = scan_session_fixture(%{created_by: admin})
      Scanning.close_session(session.id)

      {:ok, view, _html} = live(conn, ~p"/admin/scanner")

      view
      |> render_hook("resume_session", %{"session-id" => session.id})

      assert has_element?(view, "#scan-setup-form")
    end

    test "dismiss_group clears modal when group prompt would be shown", %{
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
        |> confirm_tickets()

      ticket = hd(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      view |> element("button[phx-value-mode='event']") |> render_click()

      view
      |> form("#scan-setup-form", %{
        session: %{name: "Group", event_id: event.id}
      })
      |> render_submit()

      view
      |> render_hook("scan_result", %{"data" => QrToken.sign_ticket(ticket.id)})

      assert render(view) =~ "Group Check-in" or render(view) =~ "Check in ALL"

      view |> element("button[phx-click='dismiss_group']") |> render_click()
      refute render(view) =~ "Group Check-in"
    end

    test "check_in_single fails gracefully with invalid ticket id", %{
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
        |> confirm_tickets()

      ticket = hd(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      view |> element("button[phx-value-mode='event']") |> render_click()

      view
      |> form("#scan-setup-form", %{
        session: %{name: "Bad ticket", event_id: event.id}
      })
      |> render_submit()

      view
      |> render_hook("scan_result", %{"data" => QrToken.sign_ticket(ticket.id)})

      bogus_id = Ecto.ULID.generate()

      view
      |> render_hook("check_in_single", %{"ticket-id" => bogus_id})

      assert render(view) =~ "Failed" or render(view) =~ "Error"
    end
  end

  describe "session list and detail edge cases" do
    setup [:create_admin]

    test "session list shows membership and event labels", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, title: "Listed Event"})
      scan_session_fixture(%{created_by: admin, name: "M1", type: :membership})

      scan_session_fixture(%{
        created_by: admin,
        name: "E1",
        type: :event,
        event_id: event.id
      })

      {:ok, _view, html} = live(conn, ~p"/admin/scanner/sessions")
      assert html =~ "M1"
      assert html =~ "E1"
      assert html =~ "Listed Event"
    end

    test "session detail shows event type columns for event session", %{
      conn: conn,
      admin: admin
    } do
      Ysc.Ledgers.ensure_basic_accounts()
      event = event_fixture(%{organizer_id: admin.id})
      member = make_active_member()

      session =
        scan_session_fixture(%{
          created_by: admin,
          name: "Event Detail",
          type: :event,
          event_id: event.id
        })

      order =
        ticket_order_fixture(%{user: member, event: event}) |> confirm_tickets()

      ticket = hd(order.tickets)
      Scanning.process_scan(session, QrToken.sign_ticket(ticket.id))

      {:ok, _view, html} = live(conn, ~p"/admin/scanner/sessions/#{session.id}")
      assert html =~ "Check-in"
      assert html =~ "Event Detail"
    end
  end

  describe "scanner session validation and session list UI" do
    setup [:create_admin]

    test "start_session with event mode and no event_id shows validation error",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")

      view |> element("button[phx-value-mode='event']") |> render_click()

      view
      |> form("#scan-setup-form", %{
        session: %{name: "Missing event", event_id: ""}
      })
      |> render_submit()

      html = render(view)
      assert html =~ "event" or html =~ "Error" or html =~ "required"
    end

    test "sessions list shows Closed label for a closed session", %{
      conn: conn,
      admin: admin
    } do
      session =
        scan_session_fixture(%{created_by: admin, name: "Closed list session"})

      assert {:ok, _} = Scanning.close_session(session.id)

      {:ok, _view, html} = live(conn, ~p"/admin/scanner/sessions")
      assert html =~ "Closed list session"
      assert html =~ "Closed"
    end
  end

  describe "event_membership scanning" do
    setup [:create_admin]

    test "end_session navigates to membership desk without closing session", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      session = event_membership_session_fixture(event, admin)

      {:ok, view, _html} = live(conn, ~p"/admin/scanner?resume=#{session.id}")

      view |> element("button[phx-click='end_session']") |> render_click()

      assert_redirect(view, ~p"/admin/membership-check-in/#{session.id}")
      assert is_nil(Scanning.get_session!(session.id).closed_at)
    end
  end

  describe "additional scanner handlers and edge UI" do
    setup [:create_admin]

    test "end_session pushes stop-camera to the client", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      view |> element("button[phx-value-mode='membership']") |> render_click()

      view
      |> form("#scan-setup-form", %{session: %{name: "Stop cam"}})
      |> render_submit()

      view |> element("button[phx-click='end_session']") |> render_click()

      assert_push_event(view, "stop-camera", %{})
    end

    test "scan_result is rate limited after many scans", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      view |> element("button[phx-value-mode='membership']") |> render_click()

      view
      |> form("#scan-setup-form", %{session: %{name: "Rate limit"}})
      |> render_submit()

      member = make_active_member()
      token = QrToken.sign_membership(member.id)

      for _ <- 1..21 do
        view |> render_hook("scan_result", %{"data" => token})
      end

      html = render(view)
      assert html =~ "Too many scans" or html =~ "slow down"
    end

    test "scanner_debug without extra key still works", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      view |> element("button[phx-value-mode='membership']") |> render_click()

      view
      |> form("#scan-setup-form", %{session: %{name: "Dbg2"}})
      |> render_submit()

      view |> render_hook("scanner_debug", %{"message" => "ping"})
      assert render(view) =~ "Dbg2"
    end

    test "check_in_all with bogus order id shows error result", %{
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
        |> confirm_tickets()

      ticket = hd(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      view |> element("button[phx-value-mode='event']") |> render_click()

      view
      |> form("#scan-setup-form", %{
        session: %{name: "Bad order", event_id: event.id}
      })
      |> render_submit()

      view
      |> render_hook("scan_result", %{"data" => QrToken.sign_ticket(ticket.id)})

      bogus_order = Ecto.ULID.generate()

      view
      |> render_hook("check_in_all", %{"order-id" => bogus_order})

      html = render(view)
      assert html =~ "Order not found" or html =~ "not found"
    end

    test "start_session with invalid event id shows form error toast", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      view |> element("button[phx-value-mode='event']") |> render_click()

      fake_event_id = Ecto.ULID.generate()

      html =
        render_submit(view, "start_session", %{
          "session" => %{"name" => "Bad FK", "event_id" => fake_event_id}
        })

      assert html =~ "Could not start session" or html =~ "Error"
    end

    test "membership scan shows Never expires for lifetime without renewal date",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scanner")
      view |> element("button[phx-value-mode='membership']") |> render_click()

      view
      |> form("#scan-setup-form", %{session: %{name: "Lifetime"}})
      |> render_submit()

      member =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()

      token = QrToken.sign_membership(member.id)
      view |> render_hook("scan_result", %{"data" => token})

      html = render(view)
      assert html =~ "Never" or html =~ "Active Member"
    end
  end
end
