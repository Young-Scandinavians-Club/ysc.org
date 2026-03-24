defmodule Ysc.ScanningTest do
  @moduledoc """
  Tests for the Ysc.Scanning context.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures
  import Ysc.ScanningFixtures

  alias Ysc.Scanning
  alias Ysc.Scanning.QrToken

  # ──────────────────────────────────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────────────────────────────────

  defp make_active_member do
    user = user_fixture()

    user =
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()

    Ysc.Repo.reload!(user)
  end

  defp confirm_tickets(ticket_order) do
    order = Ysc.Repo.get!(Ysc.Tickets.TicketOrder, ticket_order.id)
    order = Ysc.Repo.preload(order, [:tickets])

    Enum.each(order.tickets, fn ticket ->
      ticket
      |> Ecto.Changeset.change(status: :confirmed)
      |> Ysc.Repo.update!()
    end)

    fresh = Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
    Ysc.Repo.preload(fresh, tickets: [:ticket_tier, :registration])
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Session management
  # ──────────────────────────────────────────────────────────────────────────

  describe "create_session/1" do
    test "creates a membership scan session" do
      admin = user_fixture(%{role: "admin"})

      assert {:ok, session} =
               Scanning.create_session(%{
                 name: "Morning Scan",
                 type: :membership,
                 created_by_id: admin.id
               })

      assert session.type == :membership
      assert session.name == "Morning Scan"
      assert is_nil(session.closed_at)
    end

    test "creates an event scan session" do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})

      assert {:ok, session} =
               Scanning.create_session(%{
                 name: "Door Check",
                 type: :event,
                 event_id: event.id,
                 created_by_id: admin.id
               })

      assert session.type == :event
      assert session.event_id == event.id
    end

    test "fails without required fields" do
      assert {:error, changeset} = Scanning.create_session(%{})
      assert %{name: _, type: _, created_by_id: _} = errors_on(changeset)
    end

    test "fails for event type without event_id" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, changeset} =
               Scanning.create_session(%{
                 name: "Missing Event",
                 type: :event,
                 created_by_id: admin.id
               })

      assert %{event_id: [_ | _]} = errors_on(changeset)
    end
  end

  describe "close_session/1" do
    test "sets closed_at on the session" do
      session = scan_session_fixture()
      assert is_nil(session.closed_at)

      assert {:ok, closed} = Scanning.close_session(session.id)
      refute is_nil(closed.closed_at)
    end
  end

  describe "list_sessions/0" do
    test "returns sessions and includes created sessions" do
      admin = user_fixture(%{role: "admin"})

      {:ok, s1} =
        Scanning.create_session(%{
          name: "First",
          type: :membership,
          created_by_id: admin.id
        })

      {:ok, s2} =
        Scanning.create_session(%{
          name: "Second",
          type: :membership,
          created_by_id: admin.id
        })

      sessions = Scanning.list_sessions()
      ids = Enum.map(sessions, & &1.id)

      assert s1.id in ids
      assert s2.id in ids
    end
  end

  describe "get_open_sessions/1" do
    test "returns only open sessions for the given user" do
      admin = user_fixture(%{role: "admin"})
      other_admin = user_fixture(%{role: "admin"})

      {:ok, open_session} =
        Scanning.create_session(%{
          name: "Open",
          type: :membership,
          created_by_id: admin.id
        })

      {:ok, closed_session} =
        Scanning.create_session(%{
          name: "Closed",
          type: :membership,
          created_by_id: admin.id
        })

      Scanning.close_session(closed_session.id)

      {:ok, _other_session} =
        Scanning.create_session(%{
          name: "Other Admin",
          type: :membership,
          created_by_id: other_admin.id
        })

      sessions = Scanning.get_open_sessions(admin.id)
      ids = Enum.map(sessions, & &1.id)

      assert open_session.id in ids
      refute closed_session.id in ids
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # process_scan — membership mode
  # ──────────────────────────────────────────────────────────────────────────

  describe "process_scan/2 membership mode" do
    test "returns :active for a user with lifetime membership" do
      session = scan_session_fixture()
      user = make_active_member()
      token = QrToken.sign_membership(user.id)

      assert {:ok, result} = Scanning.process_scan(session, token)
      assert result.status == :active
      assert result.user.id == user.id
      assert result.membership_type == :lifetime
    end

    test "returns :inactive for a user without membership" do
      session = scan_session_fixture()
      user = user_fixture()
      token = QrToken.sign_membership(user.id)

      assert {:ok, result} = Scanning.process_scan(session, token)
      assert result.status == :inactive
    end

    test "records a scan record for membership scan" do
      session = scan_session_fixture()
      user = make_active_member()
      token = QrToken.sign_membership(user.id)

      assert {:ok, result} = Scanning.process_scan(session, token)
      assert result.scan_record.scan_session_id == session.id
      assert result.scan_record.user_id == user.id
      assert result.scan_record.result == :success
      assert result.scan_record.membership_status == "active"
    end

    test "returns cross_mode error when scanning membership token in event session" do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_scan_session_fixture(event, admin)
      user = make_active_member()
      token = QrToken.sign_membership(user.id)

      assert {:error, :cross_mode, _message} =
               Scanning.process_scan(session, token)
    end

    test "returns error for unknown user id in token" do
      session = scan_session_fixture()
      token = QrToken.sign_membership("00000000000000000000000000")

      assert {:error, :invalid, _message} =
               Scanning.process_scan(session, token)
    end

    test "returns error for invalid token data" do
      session = scan_session_fixture()

      assert {:error, :invalid, _message} =
               Scanning.process_scan(session, "garbage-data")
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # process_scan — event mode
  # ──────────────────────────────────────────────────────────────────────────

  describe "process_scan/2 event mode" do
    setup do
      Ysc.Ledgers.ensure_basic_accounts()
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_scan_session_fixture(event, admin)
      member = make_active_member()
      order = ticket_order_fixture(%{user: member, event: event})
      order = confirm_tickets(order)

      %{
        session: session,
        event: event,
        admin: admin,
        member: member,
        order: order
      }
    end

    test "checks in a single confirmed ticket successfully", %{
      session: session,
      order: order
    } do
      ticket = hd(order.tickets)
      token = QrToken.sign_ticket(ticket.id)

      result = Scanning.process_scan(session, token)

      assert {:ok, {updated_ticket, _record}} = result
      assert updated_ticket.checked_in == true
      assert updated_ticket.checked_in_at != nil
    end

    test "records a scan_record with :success on check-in", %{
      session: session,
      order: order
    } do
      ticket = hd(order.tickets)
      token = QrToken.sign_ticket(ticket.id)

      {:ok, {_ticket, record}} = Scanning.process_scan(session, token)

      assert record.result == :success
      assert record.ticket_id == ticket.id
      assert record.scan_session_id == session.id
    end

    test "returns :already_scanned when ticket has already been checked in", %{
      session: session,
      order: order
    } do
      ticket = hd(order.tickets)

      ticket
      |> Ysc.Events.Ticket.check_in_changeset()
      |> Ysc.Repo.update!()

      token = QrToken.sign_ticket(ticket.id)

      assert {:error, :already_scanned, info} =
               Scanning.process_scan(session, token)

      assert info.ticket_id == ticket.id
    end

    test "returns cross_mode error when scanning ticket token in membership session" do
      session = scan_session_fixture()
      order = ticket_order_fixture()
      order = confirm_tickets(order)
      ticket = hd(order.tickets)
      token = QrToken.sign_ticket(ticket.id)

      assert {:error, :cross_mode, _message} =
               Scanning.process_scan(session, token)
    end

    test "returns error when ticket belongs to a different event", %{
      session: session,
      member: member
    } do
      other_event = event_fixture()
      other_order = ticket_order_fixture(%{user: member, event: other_event})
      other_order = confirm_tickets(other_order)
      ticket = hd(other_order.tickets)
      token = QrToken.sign_ticket(ticket.id)

      assert {:error, :invalid, msg} = Scanning.process_scan(session, token)
      assert msg =~ "different event"
    end

    test "returns error when ticket is not confirmed", %{
      session: session,
      order: order
    } do
      ticket = hd(order.tickets)

      ticket
      |> Ecto.Changeset.change(status: :pending)
      |> Ysc.Repo.update!()

      token = QrToken.sign_ticket(ticket.id)

      assert {:error, :invalid, _msg} = Scanning.process_scan(session, token)
    end

    test "returns error for unknown ticket id" do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_scan_session_fixture(event, admin)
      token = QrToken.sign_ticket("00000000000000000000000000")

      assert {:error, :invalid, _msg} = Scanning.process_scan(session, token)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Group check-in
  # ──────────────────────────────────────────────────────────────────────────

  describe "process_scan/2 group check-in prompt" do
    setup do
      Ysc.Ledgers.ensure_basic_accounts()
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_scan_session_fixture(event, admin)
      member = make_active_member()

      tier = ticket_tier_fixture(%{event_id: event.id})

      order =
        ticket_order_fixture(%{
          user: member,
          event: event,
          ticket_selections: %{tier.id => 3}
        })

      order = confirm_tickets(order)

      %{
        session: session,
        event: event,
        admin: admin,
        member: member,
        order: order
      }
    end

    test "shows group prompt when order has multiple unchecked tickets", %{
      session: session,
      order: order
    } do
      ticket = hd(order.tickets)
      token = QrToken.sign_ticket(ticket.id)

      assert {:ok, :group_prompt, info} = Scanning.process_scan(session, token)
      assert length(info.unchecked_tickets) == 3
      assert info.partially_scanned == false
    end

    test "shows group prompt with partially_scanned=true when some tickets already checked in",
         %{session: session, order: order} do
      [first | rest] = order.tickets

      first
      |> Ysc.Events.Ticket.check_in_changeset()
      |> Ysc.Repo.update!()

      token = QrToken.sign_ticket(hd(rest).id)

      assert {:ok, :group_prompt, info} = Scanning.process_scan(session, token)
      assert info.partially_scanned == true
      assert length(info.unchecked_tickets) == 2
      assert length(info.checked_tickets) == 1
    end
  end

  describe "check_in_single/2" do
    setup do
      Ysc.Ledgers.ensure_basic_accounts()
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_scan_session_fixture(event, admin)
      member = make_active_member()
      order = ticket_order_fixture(%{user: member, event: event})
      order = confirm_tickets(order)

      %{session: session, order: order}
    end

    test "marks ticket as checked in and returns the record", %{
      session: session,
      order: order
    } do
      ticket = hd(order.tickets)

      assert {:ok, {updated, record}} =
               Scanning.check_in_single(session, ticket.id)

      assert updated.checked_in
      assert record.result == :success
      assert record.checkin_type == :individual
    end

    test "returns error for unknown ticket id", %{session: session} do
      nonexistent_id = Ecto.ULID.generate()

      assert {:error, :invalid, _} =
               Scanning.check_in_single(session, nonexistent_id)
    end
  end

  describe "check_in_order/2" do
    setup do
      Ysc.Ledgers.ensure_basic_accounts()
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_scan_session_fixture(event, admin)
      member = make_active_member()

      tier = ticket_tier_fixture(%{event_id: event.id})

      order =
        ticket_order_fixture(%{
          user: member,
          event: event,
          ticket_selections: %{tier.id => 2}
        })

      order = confirm_tickets(order)

      %{session: session, order: order}
    end

    test "checks in all tickets in an order and returns the count", %{
      session: session,
      order: order
    } do
      assert {:ok, :group_checked_in, count} =
               Scanning.check_in_order(session, order.id)

      assert count == 2
    end

    test "skips already checked-in tickets", %{session: session, order: order} do
      [first | _] = order.tickets

      first
      |> Ysc.Events.Ticket.check_in_changeset()
      |> Ysc.Repo.update!()

      assert {:ok, :group_checked_in, count} =
               Scanning.check_in_order(session, order.id)

      assert count == 1
    end

    test "returns error for unknown order id", %{session: session} do
      nonexistent_id = Ecto.ULID.generate()

      assert {:error, :invalid, _} =
               Scanning.check_in_order(session, nonexistent_id)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Manual lookup
  # ──────────────────────────────────────────────────────────────────────────

  describe "manual_membership_lookup/1" do
    test "returns the user for a known email" do
      user = user_fixture()
      assert {:ok, found} = Scanning.manual_membership_lookup(user.email)
      assert found.id == user.id
    end

    test "returns error for unknown email" do
      assert {:error, :not_found, _} =
               Scanning.manual_membership_lookup("nobody@example.com")
    end
  end

  describe "manual_ticket_lookup/2" do
    setup do
      Ysc.Ledgers.ensure_basic_accounts()
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      member = make_active_member()
      order = ticket_order_fixture(%{user: member, event: event})

      %{event: event, order: order}
    end

    test "returns the order when reference and event match", %{
      event: event,
      order: order
    } do
      assert {:ok, found} =
               Scanning.manual_ticket_lookup(order.reference_id, event.id)

      assert found.id == order.id
    end

    test "returns error for wrong event" do
      Ysc.Ledgers.ensure_basic_accounts()
      another_event = event_fixture()
      member = make_active_member()
      order = ticket_order_fixture(%{user: member, event: another_event})

      wrong_event = event_fixture()

      assert {:error, :not_found, _} =
               Scanning.manual_ticket_lookup(order.reference_id, wrong_event.id)
    end

    test "returns error for unknown reference" do
      event = event_fixture()

      assert {:error, :not_found, _} =
               Scanning.manual_ticket_lookup("ORD-DOESNOTEXIST", event.id)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Scan counts
  # ──────────────────────────────────────────────────────────────────────────

  describe "get_session_scan_count/1 and count_scan_records/1" do
    test "counts only successful records" do
      session = scan_session_fixture()
      user = make_active_member()

      token_active = QrToken.sign_membership(user.id)
      inactive_user = user_fixture()
      token_inactive = QrToken.sign_membership(inactive_user.id)

      Scanning.process_scan(session, token_active)
      Scanning.process_scan(session, token_inactive)
      Scanning.process_scan(session, "bad-token")

      assert Scanning.get_session_scan_count(session.id) == 2
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # CSV export
  # ──────────────────────────────────────────────────────────────────────────

  describe "export_session_csv/1" do
    test "returns a valid CSV string for a membership session" do
      session = scan_session_fixture()
      user = make_active_member()
      token = QrToken.sign_membership(user.id)
      Scanning.process_scan(session, token)

      csv = Scanning.export_session_csv(session.id)

      assert is_binary(csv)
      assert csv =~ "Name"
      assert csv =~ "Email"
      assert csv =~ "Membership Status"
      assert csv =~ user.email
    end

    test "includes correct headers for an event session" do
      Ysc.Ledgers.ensure_basic_accounts()
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_scan_session_fixture(event, admin)

      csv = Scanning.export_session_csv(session.id)

      assert csv =~ "Ticket Reference"
      assert csv =~ "Check-in Type"
      refute csv =~ "Membership Status"
    end

    test "exports empty session as headers only" do
      session = scan_session_fixture()
      csv = Scanning.export_session_csv(session.id)

      lines = String.split(String.trim(csv), "\n")
      assert length(lines) == 1
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # list_scan_records/1
  # ──────────────────────────────────────────────────────────────────────────

  describe "list_scan_records/1" do
    test "returns records for the session ordered newest first" do
      session = scan_session_fixture()
      user = make_active_member()
      user2 = make_active_member()

      {:ok, _} =
        Scanning.process_scan(session, QrToken.sign_membership(user.id))

      {:ok, _} =
        Scanning.process_scan(session, QrToken.sign_membership(user2.id))

      [first, second] = Scanning.list_scan_records(session.id)

      assert MapSet.equal?(
               MapSet.new([first.user_id, second.user_id]),
               MapSet.new([user.id, user2.id])
             )

      assert first.user_id == user2.id,
             "user2 (second scan) should appear first"
    end

    test "does not include records from other sessions" do
      session1 = scan_session_fixture()
      session2 = scan_session_fixture()
      user = make_active_member()

      Scanning.process_scan(session1, QrToken.sign_membership(user.id))

      assert Scanning.list_scan_records(session2.id) == []
    end
  end
end
