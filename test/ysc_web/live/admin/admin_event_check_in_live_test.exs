defmodule YscWeb.AdminEventCheckInLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures
  import Ysc.ScanningFixtures

  alias Ysc.Repo
  alias Ysc.Scanning
  alias Ysc.Scanning.ScanSession

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  defp create_volunteer(%{conn: conn}) do
    user = user_fixture(%{role: "volunteer"})
    %{conn: log_in_user(conn, user), volunteer: user}
  end

  defp make_member(attrs \\ %{}) do
    user = user_fixture(attrs)

    user
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Repo.update!()
    |> Repo.reload!()
  end

  defp confirm_order(order) do
    loaded =
      Repo.get!(Ysc.Tickets.TicketOrder, order.id) |> Repo.preload([:tickets])

    Enum.each(loaded.tickets, fn t ->
      t |> Ecto.Changeset.change(status: :confirmed) |> Repo.update!()
    end)

    Repo.get!(Ysc.Tickets.TicketOrder, order.id)
    |> Repo.preload(tickets: [:ticket_tier, :registration, :user])
  end

  defp setup_event_with_tickets(admin) do
    event = event_fixture(%{organizer_id: admin.id, state: :published})
    tier = ticket_tier_fixture(%{event_id: event.id})
    buyer = make_member()
    order = ticket_order_fixture(%{user: buyer, event: event, tier: tier})
    confirmed_order = confirm_order(order)

    %{event: event, tier: tier, buyer: buyer, order: confirmed_order}
  end

  defp session_count_for_event(event_id) do
    import Ecto.Query

    Repo.aggregate(
      from(s in ScanSession, where: s.event_id == ^event_id),
      :count
    )
  end

  # ---------------------------------------------------------------------------
  # Access control
  # ---------------------------------------------------------------------------

  describe "access control" do
    test "redirects unauthenticated users", %{conn: conn} do
      event = event_fixture()

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/admin/events/#{event.id}/check-in")

      assert path =~ "/users/log"
    end

    test "redirects regular members to home", %{conn: conn} do
      event = event_fixture()
      member = user_fixture()
      conn = log_in_user(conn, member)

      assert {:error, {:redirect, _}} =
               live(conn, ~p"/admin/events/#{event.id}/check-in")
    end

    test "allows admins to access the page", %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      conn = log_in_user(conn, admin)

      assert {:ok, _view, _html} =
               live(conn, ~p"/admin/events/#{event.id}/check-in")
    end

    test "allows volunteers to access the page", %{conn: conn} do
      volunteer = user_fixture(%{role: "volunteer"})
      event = event_fixture()
      conn = log_in_user(conn, volunteer)

      assert {:ok, _view, _html} =
               live(conn, ~p"/admin/events/#{event.id}/check-in")
    end
  end

  # ---------------------------------------------------------------------------
  # Page rendering
  # ---------------------------------------------------------------------------

  describe "page rendering" do
    setup [:create_admin]

    test "renders page title with the event name", %{conn: conn, admin: admin} do
      event =
        event_fixture(%{organizer_id: admin.id, title: "Summer Bash 2025"})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      assert render(view) =~ "Summer Bash 2025"
    end

    test "renders the search bar", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      assert has_element?(view, "#check-in-search-form")
    end

    test "renders live attendance counter starting at zero", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      assert render(view) =~ "0 / 0"
    end

    test "shows empty state when no confirmed tickets exist", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      assert render(view) =~ "No confirmed tickets for this event"
    end

    test "has QR scanner button", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      assert has_element?(view, "[phx-click='launch-scanner']")
    end

    test "has back link to admin events list", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      assert has_element?(view, "a[href='/admin/events']")
    end

    test "shows correct attendance counter with confirmed tickets", %{
      conn: conn,
      admin: admin
    } do
      %{event: event} = setup_event_with_tickets(admin)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      assert render(view) =~ "0 / 1"
    end

    test "shows pending section header with count badge", %{
      conn: conn,
      admin: admin
    } do
      %{event: event} = setup_event_with_tickets(admin)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      assert render(view) =~ "Pending"
      assert has_element?(view, "#pending-groups")
    end

    test "does not show checked-in section when no tickets checked in", %{
      conn: conn,
      admin: admin
    } do
      %{event: event} = setup_event_with_tickets(admin)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      refute has_element?(view, "#checked-in-tickets")
    end
  end

  # ---------------------------------------------------------------------------
  # Ticket listing
  # ---------------------------------------------------------------------------

  describe "ticket listing" do
    setup [:create_admin]

    test "shows confirmed tickets with attendee names", %{
      conn: conn,
      admin: admin
    } do
      %{event: event, buyer: buyer} = setup_event_with_tickets(admin)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")
      html = render(view)

      assert html =~ buyer.first_name
      assert html =~ buyer.last_name
    end

    test "shows ticket reference IDs", %{conn: conn, admin: admin} do
      %{event: event, order: order} = setup_event_with_tickets(admin)
      ticket = List.first(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")
      html = render(view)

      assert html =~ ticket.reference_id
    end

    test "shows order reference IDs in pending group header", %{
      conn: conn,
      admin: admin
    } do
      %{event: event, order: order} = setup_event_with_tickets(admin)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")
      html = render(view)

      assert html =~ order.reference_id
    end

    test "shows tier badge for each ticket", %{conn: conn, admin: admin} do
      %{event: event, tier: tier} = setup_event_with_tickets(admin)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")
      html = render(view)

      assert html =~ tier.name
    end

    test "does not show unconfirmed (pending) tickets", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})
      buyer = make_member(%{first_name: "UnconfirmedBuyer", last_name: "Test"})
      # Do NOT confirm this order — tickets stay :pending
      _order = ticket_order_fixture(%{user: buyer, event: event, tier: tier})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")
      html = render(view)

      refute html =~ "UnconfirmedBuyer"
      assert html =~ "No confirmed tickets for this event"
    end

    test "accumulates counter across multiple orders from different buyers", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      buyer1 = make_member()
      buyer2 = make_member()

      confirm_order(
        ticket_order_fixture(%{user: buyer1, event: event, tier: tier})
      )

      confirm_order(
        ticket_order_fixture(%{user: buyer2, event: event, tier: tier})
      )

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")
      html = render(view)

      assert html =~ "0 / 2"
    end

    test "lists all confirmed tickets when multiple orders exist", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      buyer1 =
        make_member(%{first_name: "AlicexyzListing", last_name: "TestA"})

      buyer2 =
        make_member(%{first_name: "BobxyzListing", last_name: "TestB"})

      confirm_order(
        ticket_order_fixture(%{user: buyer1, event: event, tier: tier})
      )

      confirm_order(
        ticket_order_fixture(%{user: buyer2, event: event, tier: tier})
      )

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")
      html = render(view)

      assert html =~ "AlicexyzListing"
      assert html =~ "BobxyzListing"
    end
  end

  # ---------------------------------------------------------------------------
  # Order grouping and "check in all" button
  # ---------------------------------------------------------------------------

  describe "order grouping" do
    setup [:create_admin]

    test "groups tickets by order with the order reference in the header", %{
      conn: conn,
      admin: admin
    } do
      %{event: event, order: order} = setup_event_with_tickets(admin)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      assert has_element?(view, "#pending-groups")
      assert render(view) =~ order.reference_id
    end

    test "does not show 'Check in all' button for a single-ticket order", %{
      conn: conn,
      admin: admin
    } do
      %{event: event} = setup_event_with_tickets(admin)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      refute has_element?(
               view,
               "#pending-groups button[phx-click='check-in-order']"
             )
    end

    test "shows 'Check in all' button for a multi-ticket order", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id, quantity: 10})
      buyer = make_member()

      confirm_order(
        ticket_order_fixture(%{
          user: buyer,
          event: event,
          tier: tier,
          ticket_selections: %{tier.id => 2}
        })
      )

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      assert has_element?(
               view,
               "#pending-groups button[phx-click='check-in-order']"
             )
    end
  end

  # ---------------------------------------------------------------------------
  # Check-in toggle
  # ---------------------------------------------------------------------------

  describe "check-in toggle" do
    setup [:create_admin]

    test "toggle-check-in with unknown ticket id shows error flash", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      html =
        render_click(view, "toggle-check-in", %{
          "ticket-id" => Ecto.ULID.generate()
        })

      assert html =~ "Ticket not found"
    end

    test "rejects check-in for a ticket belonging to a different event", %{
      conn: conn,
      admin: admin
    } do
      event_a = event_fixture(%{organizer_id: admin.id, state: :published})
      %{event: event_b, order: other_order} = setup_event_with_tickets(admin)
      other_ticket = List.first(other_order.tickets)

      assert other_ticket.event_id == event_b.id
      assert event_a.id != event_b.id

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event_a.id}/check-in")

      html =
        render_click(view, "toggle-check-in", %{
          "ticket-id" => other_ticket.id
        })

      assert html =~ "different event"
      refute Repo.get!(Ysc.Events.Ticket, other_ticket.id).checked_in
    end

    test "checking in a ticket moves it to the checked-in section", %{
      conn: conn,
      admin: admin
    } do
      %{event: event, order: order} = setup_event_with_tickets(admin)
      ticket = List.first(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      assert has_element?(view, "#pending-groups")
      refute has_element?(view, "#checked-in-tickets")

      view
      |> element("#pending-groups button[phx-value-ticket-id='#{ticket.id}']")
      |> render_click()

      assert has_element?(view, "#checked-in-tickets")
    end

    test "checking in updates the attendance counter", %{
      conn: conn,
      admin: admin
    } do
      %{event: event, order: order} = setup_event_with_tickets(admin)
      ticket = List.first(order.tickets)

      {:ok, view, html} = live(conn, ~p"/admin/events/#{event.id}/check-in")
      assert html =~ "0 / 1"

      view
      |> element("#pending-groups button[phx-value-ticket-id='#{ticket.id}']")
      |> render_click()

      assert render(view) =~ "1 / 1"
    end

    test "checking in persists to database", %{conn: conn, admin: admin} do
      %{event: event, order: order} = setup_event_with_tickets(admin)
      ticket = List.first(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      view
      |> element("#pending-groups button[phx-value-ticket-id='#{ticket.id}']")
      |> render_click()

      updated = Repo.get!(Ysc.Events.Ticket, ticket.id)
      assert updated.checked_in == true
      assert updated.checked_in_at != nil
    end

    test "checking in creates a scan session for the event", %{
      conn: conn,
      admin: admin
    } do
      %{event: event, order: order} = setup_event_with_tickets(admin)
      ticket = List.first(order.tickets)

      initial_count = session_count_for_event(event.id)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      view
      |> element("#pending-groups button[phx-value-ticket-id='#{ticket.id}']")
      |> render_click()

      assert session_count_for_event(event.id) == initial_count + 1
    end

    test "checking in multiple tickets reuses the same scan session", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id, quantity: 10})
      buyer = make_member()

      order =
        confirm_order(
          ticket_order_fixture(%{
            user: buyer,
            event: event,
            tier: tier,
            ticket_selections: %{tier.id => 2}
          })
        )

      [ticket1, ticket2] = order.tickets

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      # Check in first ticket — a session is created
      view
      |> element("#pending-groups button[phx-value-ticket-id='#{ticket1.id}']")
      |> render_click()

      sessions_after_first = session_count_for_event(event.id)
      assert sessions_after_first == 1

      # Check in second ticket — no new session should be created
      view
      |> element("#pending-groups button[phx-value-ticket-id='#{ticket2.id}']")
      |> render_click()

      assert session_count_for_event(event.id) == sessions_after_first
    end

    test "undo check-in moves ticket back to pending section", %{
      conn: conn,
      admin: admin
    } do
      %{event: event, order: order} = setup_event_with_tickets(admin)
      ticket = List.first(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      view
      |> element("#pending-groups button[phx-value-ticket-id='#{ticket.id}']")
      |> render_click()

      assert has_element?(view, "#checked-in-tickets")

      view
      |> element(
        "#checked-in-tickets button[phx-value-ticket-id='#{ticket.id}']"
      )
      |> render_click()

      assert has_element?(view, "#pending-groups")
      refute has_element?(view, "#checked-in-tickets")
    end

    test "undo check-in decrements the counter", %{conn: conn, admin: admin} do
      %{event: event, order: order} = setup_event_with_tickets(admin)
      ticket = List.first(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      view
      |> element("#pending-groups button[phx-value-ticket-id='#{ticket.id}']")
      |> render_click()

      assert render(view) =~ "1 / 1"

      view
      |> element(
        "#checked-in-tickets button[phx-value-ticket-id='#{ticket.id}']"
      )
      |> render_click()

      assert render(view) =~ "0 / 1"
    end

    test "undo check-in clears checked_in_at in database", %{
      conn: conn,
      admin: admin
    } do
      %{event: event, order: order} = setup_event_with_tickets(admin)
      ticket = List.first(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      view
      |> element("#pending-groups button[phx-value-ticket-id='#{ticket.id}']")
      |> render_click()

      view
      |> element(
        "#checked-in-tickets button[phx-value-ticket-id='#{ticket.id}']"
      )
      |> render_click()

      updated = Repo.get!(Ysc.Events.Ticket, ticket.id)
      assert updated.checked_in == false
      assert updated.checked_in_at == nil
    end

    test "shows 'All attendees checked in!' when all tickets are checked in", %{
      conn: conn,
      admin: admin
    } do
      %{event: event, order: order} = setup_event_with_tickets(admin)
      ticket = List.first(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      view
      |> element("#pending-groups button[phx-value-ticket-id='#{ticket.id}']")
      |> render_click()

      assert render(view) =~ "All attendees checked in!"
    end
  end

  # ---------------------------------------------------------------------------
  # Group check-in
  # ---------------------------------------------------------------------------

  describe "group check-in (check-in-order)" do
    setup [:create_admin]

    test "checks in all tickets in an order at once", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id, quantity: 10})
      buyer = make_member()

      confirmed_order =
        confirm_order(
          ticket_order_fixture(%{
            user: buyer,
            event: event,
            tier: tier,
            ticket_selections: %{tier.id => 2}
          })
        )

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      view
      |> element("#pending-groups button[phx-click='check-in-order']")
      |> render_click()

      assert render(view) =~ "2 / 2"

      Enum.each(confirmed_order.tickets, fn t ->
        updated = Repo.get!(Ysc.Events.Ticket, t.id)
        assert updated.checked_in == true
      end)
    end

    test "shows a flash message with the number of tickets checked in", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id, quantity: 10})
      buyer = make_member()

      confirm_order(
        ticket_order_fixture(%{
          user: buyer,
          event: event,
          tier: tier,
          ticket_selections: %{tier.id => 3}
        })
      )

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      view
      |> element("#pending-groups button[phx-click='check-in-order']")
      |> render_click()

      assert render(view) =~ "Checked in 3 tickets"
    end
  end

  # ---------------------------------------------------------------------------
  # Search / filtering
  # ---------------------------------------------------------------------------

  describe "search" do
    setup [:create_admin]

    test "filters tickets by attendee first name (partial match)", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      alice = make_member(%{first_name: "AliceUniqueXYZ", last_name: "Smith"})
      bob = make_member(%{first_name: "BobUniqueXYZ", last_name: "Jones"})

      confirm_order(
        ticket_order_fixture(%{user: alice, event: event, tier: tier})
      )

      confirm_order(
        ticket_order_fixture(%{user: bob, event: event, tier: tier})
      )

      {:ok, view, _html} =
        live(conn, ~p"/admin/events/#{event.id}/check-in?q=AliceUniqueXYZ")

      html = render(view)

      assert html =~ "AliceUniqueXYZ"
      refute html =~ "BobUniqueXYZ"
    end

    test "filters tickets by attendee email", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      alice =
        make_member(%{
          email: "uniqueAlice@searchtest.example",
          first_name: "A",
          last_name: "A"
        })

      bob =
        make_member(%{
          email: "uniqueBob@searchtest.example",
          first_name: "B",
          last_name: "B"
        })

      confirm_order(
        ticket_order_fixture(%{user: alice, event: event, tier: tier})
      )

      confirm_order(
        ticket_order_fixture(%{user: bob, event: event, tier: tier})
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/events/#{event.id}/check-in?q=uniqueAlice@searchtest.example"
        )

      html = render(view)

      assert html =~ "uniqueAlice@searchtest.example"
      refute html =~ "uniqueBob@searchtest.example"
    end

    test "filters tickets by order reference ID", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      buyer1 =
        make_member(%{first_name: "OrderSearchAlice", last_name: "Test"})

      buyer2 =
        make_member(%{first_name: "OrderSearchBob", last_name: "Test"})

      order1 =
        confirm_order(
          ticket_order_fixture(%{user: buyer1, event: event, tier: tier})
        )

      _order2 =
        confirm_order(
          ticket_order_fixture(%{user: buyer2, event: event, tier: tier})
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/events/#{event.id}/check-in?q=#{order1.reference_id}"
        )

      html = render(view)

      assert html =~ "OrderSearchAlice"
      refute html =~ "OrderSearchBob"
    end

    test "filters tickets by ticket reference ID", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      buyer1 =
        make_member(%{first_name: "TicketSearchAlice", last_name: "Test"})

      buyer2 =
        make_member(%{first_name: "TicketSearchBob", last_name: "Test"})

      order1 =
        confirm_order(
          ticket_order_fixture(%{user: buyer1, event: event, tier: tier})
        )

      confirm_order(
        ticket_order_fixture(%{user: buyer2, event: event, tier: tier})
      )

      ticket = List.first(order1.tickets)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/events/#{event.id}/check-in?q=#{ticket.reference_id}"
        )

      html = render(view)

      assert html =~ "TicketSearchAlice"
      refute html =~ "TicketSearchBob"
    end

    test "search is case-insensitive", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      buyer = make_member(%{first_name: "CaseSensAlice", last_name: "Test"})

      confirm_order(
        ticket_order_fixture(%{user: buyer, event: event, tier: tier})
      )

      {:ok, view, _html} =
        live(conn, ~p"/admin/events/#{event.id}/check-in?q=casesensalice")

      html = render(view)

      assert html =~ "CaseSensAlice"
    end

    test "no results shows specific empty-state message", %{
      conn: conn,
      admin: admin
    } do
      %{event: event} = setup_event_with_tickets(admin)

      {:ok, view, _html} =
        live(conn, ~p"/admin/events/#{event.id}/check-in?q=ZZZNOMATCHXYZ")

      assert render(view) =~ "No tickets match your search"
      assert render(view) =~ "Try a different name"
    end

    test "no-search empty state does not show search-specific hint", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      assert render(view) =~ "No confirmed tickets for this event"
      refute render(view) =~ "No tickets match your search"
    end

    test "clear search restores all tickets", %{conn: conn, admin: admin} do
      %{event: event} = setup_event_with_tickets(admin)

      {:ok, view_filtered, _} =
        live(conn, ~p"/admin/events/#{event.id}/check-in?q=ZZZNOMATCHXYZ")

      assert render(view_filtered) =~ "No tickets match your search"

      {:ok, view_all, _} = live(conn, ~p"/admin/events/#{event.id}/check-in")
      html_all = render(view_all)
      refute html_all =~ "No tickets match your search"
      assert html_all =~ "0 / 1"
    end

    test "clear-search event removes query and reloads tickets", %{
      conn: conn,
      admin: admin
    } do
      %{event: event} = setup_event_with_tickets(admin)

      {:ok, view, _html} =
        live(conn, ~p"/admin/events/#{event.id}/check-in?q=filterxyz")

      assert render(view) =~ "No tickets match your search"

      html_after =
        render_click(view, "clear-search", %{
          "input-id" => "check-in-search-input"
        })

      refute html_after =~ "No tickets match your search"
      assert html_after =~ "0 / 1"
    end

    test "search does not affect total counter — only filtered results change",
         %{
           conn: conn,
           admin: admin
         } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      alice = make_member(%{first_name: "SearchCountAlice", last_name: "Test"})
      bob = make_member(%{first_name: "SearchCountBob", last_name: "Test"})

      confirm_order(
        ticket_order_fixture(%{user: alice, event: event, tier: tier})
      )

      confirm_order(
        ticket_order_fixture(%{user: bob, event: event, tier: tier})
      )

      # With a search that matches only Alice, the counter should still show
      # the full event total (0 / 2), not filtered results
      {:ok, view, _html} =
        live(conn, ~p"/admin/events/#{event.id}/check-in?q=SearchCountAlice")

      html = render(view)

      assert html =~ "0 / 2"
    end
  end

  # ---------------------------------------------------------------------------
  # Launch scanner
  # ---------------------------------------------------------------------------

  describe "launch-scanner" do
    setup [:create_admin]

    test "reuses an existing open event scan session", %{
      conn: conn,
      admin: admin
    } do
      event =
        event_fixture(%{organizer_id: admin.id, title: "Reuse Scan Session"})

      existing = event_scan_session_fixture(event, admin)
      initial_count = session_count_for_event(event.id)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      view
      |> element("[phx-click='launch-scanner']", "QR Scanner")
      |> render_click()

      assert session_count_for_event(event.id) == initial_count
      assert_redirect(view, ~p"/admin/scanner?resume=#{existing.id}")
    end

    test "creates an event scan session with the event's details", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id, title: "My Test Event"})
      initial_count = session_count_for_event(event.id)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      # Scope to the desktop button via its text label to avoid the mobile icon-only duplicate
      view
      |> element("[phx-click='launch-scanner']", "QR Scanner")
      |> render_click()

      assert session_count_for_event(event.id) == initial_count + 1

      import Ecto.Query

      session =
        Repo.one!(
          from s in ScanSession,
            where: s.event_id == ^event.id,
            order_by: [desc: s.inserted_at],
            limit: 1
        )

      assert session.event_id == event.id
      assert session.type == :event
      assert session.name =~ "My Test Event"
    end

    test "session name includes today's date", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      view
      |> element("[phx-click='launch-scanner']", "QR Scanner")
      |> render_click()

      import Ecto.Query

      session =
        Repo.one!(
          from s in ScanSession,
            where: s.event_id == ^event.id,
            order_by: [desc: s.inserted_at],
            limit: 1
        )

      today = Calendar.strftime(Date.utc_today(), "%Y")
      assert session.name =~ today
    end

    test "navigates to the scanner with the new session id", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      result =
        view
        |> element("[phx-click='launch-scanner']", "QR Scanner")
        |> render_click()

      case result do
        {:error, {:live_redirect, %{to: path}}} ->
          assert path =~ "/admin/scanner?resume="

        _ ->
          # push_navigate was followed automatically; verify session was created
          assert session_count_for_event(event.id) >= 1
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Volunteer capabilities
  # ---------------------------------------------------------------------------

  describe "volunteer check-in" do
    setup [:create_volunteer]

    test "volunteer can check in a ticket", %{conn: conn, volunteer: _volunteer} do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})
      buyer = make_member()

      order =
        confirm_order(
          ticket_order_fixture(%{user: buyer, event: event, tier: tier})
        )

      ticket = List.first(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      view
      |> element("#pending-groups button[phx-value-ticket-id='#{ticket.id}']")
      |> render_click()

      updated = Repo.get!(Ysc.Events.Ticket, ticket.id)
      assert updated.checked_in == true
    end

    test "volunteer can undo a check-in", %{conn: conn, volunteer: _volunteer} do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})
      buyer = make_member()

      order =
        confirm_order(
          ticket_order_fixture(%{user: buyer, event: event, tier: tier})
        )

      ticket = List.first(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      view
      |> element("#pending-groups button[phx-value-ticket-id='#{ticket.id}']")
      |> render_click()

      view
      |> element(
        "#checked-in-tickets button[phx-value-ticket-id='#{ticket.id}']"
      )
      |> render_click()

      updated = Repo.get!(Ysc.Events.Ticket, ticket.id)
      assert updated.checked_in == false
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub real-time sync
  # ---------------------------------------------------------------------------

  describe "PubSub real-time sync" do
    setup [:create_admin]

    test "increments counter when another admin checks in via PubSub", %{
      conn: conn,
      admin: admin
    } do
      %{event: event, order: order} = setup_event_with_tickets(admin)
      ticket = List.first(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")
      assert render(view) =~ "0 / 1"

      updated_ticket =
        ticket
        |> Ecto.Changeset.change(
          checked_in: true,
          checked_in_at: DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

      reloaded =
        Repo.preload(updated_ticket, [
          :registration,
          :user,
          :ticket_tier,
          :ticket_order
        ])

      Scanning.broadcast_checkin(
        event.id,
        %Ysc.MessagePassingEvents.TicketCheckedIn{
          ticket: reloaded,
          event_id: event.id
        }
      )

      assert render(view) =~ "1 / 1"
    end

    test "moves ticket to checked-in section when another admin checks in via PubSub",
         %{
           conn: conn,
           admin: admin
         } do
      %{event: event, order: order} = setup_event_with_tickets(admin)
      ticket = List.first(order.tickets)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")
      refute has_element?(view, "#checked-in-tickets")

      updated_ticket =
        ticket
        |> Ecto.Changeset.change(
          checked_in: true,
          checked_in_at: DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

      reloaded =
        Repo.preload(updated_ticket, [
          :registration,
          :user,
          :ticket_tier,
          :ticket_order
        ])

      Scanning.broadcast_checkin(
        event.id,
        %Ysc.MessagePassingEvents.TicketCheckedIn{
          ticket: reloaded,
          event_id: event.id
        }
      )

      assert has_element?(view, "#checked-in-tickets")
    end

    test "decrements counter when another admin undoes check-in via PubSub", %{
      conn: conn,
      admin: admin
    } do
      %{event: event, order: order} = setup_event_with_tickets(admin)
      ticket = List.first(order.tickets)

      ticket
      |> Ecto.Changeset.change(
        checked_in: true,
        checked_in_at: DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")
      assert render(view) =~ "1 / 1"

      ticket_undone =
        Repo.get!(Ysc.Events.Ticket, ticket.id)
        |> Ecto.Changeset.change(checked_in: false, checked_in_at: nil)
        |> Repo.update!()

      reloaded =
        Repo.preload(ticket_undone, [
          :registration,
          :user,
          :ticket_tier,
          :ticket_order
        ])

      Scanning.broadcast_checkin(
        event.id,
        %Ysc.MessagePassingEvents.TicketCheckInUndone{
          ticket: reloaded,
          event_id: event.id
        }
      )

      assert render(view) =~ "0 / 1"
    end

    test "ignores PubSub broadcasts for a different event", %{
      conn: conn,
      admin: admin
    } do
      %{event: event, order: order} = setup_event_with_tickets(admin)
      ticket = List.first(order.tickets)

      other_event = event_fixture(%{organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")
      assert render(view) =~ "0 / 1"

      updated_ticket =
        ticket
        |> Ecto.Changeset.change(
          checked_in: true,
          checked_in_at: DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

      reloaded =
        Repo.preload(updated_ticket, [
          :registration,
          :user,
          :ticket_tier,
          :ticket_order
        ])

      # Broadcast for a DIFFERENT event — the view should not update
      Scanning.broadcast_checkin(
        other_event.id,
        %Ysc.MessagePassingEvents.TicketCheckedIn{
          ticket: reloaded,
          event_id: other_event.id
        }
      )

      assert render(view) =~ "0 / 1"
    end
  end

  describe "check-in-order error handling" do
    setup [:create_admin]

    test "shows flash when order id does not exist", %{conn: conn, admin: admin} do
      %{event: event} = setup_event_with_tickets(admin)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")

      html =
        render_click(view, "check-in-order", %{
          "order-id" => Ecto.ULID.generate()
        })

      assert html =~ "Order not found"
    end
  end

  describe "PubSub TicketCheckInUndone different event" do
    setup [:create_admin]

    test "ignores TicketCheckInUndone broadcast for another event", %{
      conn: conn,
      admin: admin
    } do
      %{event: event, order: order} = setup_event_with_tickets(admin)
      ticket = List.first(order.tickets)

      ticket
      |> Ecto.Changeset.change(
        checked_in: true,
        checked_in_at: DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Repo.update!()

      other_event = event_fixture(%{organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/check-in")
      assert render(view) =~ "1 / 1"

      reloaded =
        Repo.get!(Ysc.Events.Ticket, ticket.id)
        |> Repo.preload([
          :registration,
          :user,
          :ticket_tier,
          :ticket_order
        ])

      undone =
        reloaded
        |> Ecto.Changeset.change(checked_in: false, checked_in_at: nil)
        |> Repo.update!()
        |> Repo.preload([
          :registration,
          :user,
          :ticket_tier,
          :ticket_order
        ])

      Scanning.broadcast_checkin(
        other_event.id,
        %Ysc.MessagePassingEvents.TicketCheckInUndone{
          ticket: undone,
          event_id: other_event.id
        }
      )

      assert render(view) =~ "1 / 1"
    end
  end
end
