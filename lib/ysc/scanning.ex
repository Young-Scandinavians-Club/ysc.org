defmodule Ysc.Scanning do
  @moduledoc """
  Context for QR code scanning sessions and records.

  Handles two scanning modes:
  - **Membership**: Validates a user's active membership status
  - **Event**: Validates ticket ownership and performs check-in
  - **Event Membership**: Verifies membership status and tracks attendance for an event without pre-sold tickets
  """

  import Ecto.Query

  alias Ysc.Repo
  alias Ysc.Accounts
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Events.Ticket
  alias Ysc.Events.TicketDetail
  alias Ysc.Tickets.TicketOrder
  alias Ysc.Scanning.{QrToken, ScanSession, ScanRecord, SessionCheckIn}
  alias Ysc.MessagePassingEvents

  # --- Session Management ---

  def create_session(attrs) do
    created_by_id = attrs[:created_by_id] || attrs["created_by_id"]

    %ScanSession{}
    |> ScanSession.changeset(attrs)
    |> Ecto.Changeset.put_change(:created_by_id, created_by_id)
    |> Ecto.Changeset.validate_required([:created_by_id])
    |> Repo.insert()
  end

  def close_session(session_id) do
    session = get_session!(session_id)

    case session |> ScanSession.close_changeset() |> Repo.update() do
      {:ok, _updated} = result ->
        broadcast_membership_checkin(
          session_id,
          %MessagePassingEvents.MembershipSessionCompleted{
            session_id: session_id
          }
        )

        result

      error ->
        error
    end
  end

  def get_session!(id) do
    ScanSession
    |> Repo.get!(id)
    |> Repo.preload([:event, :created_by])
  end

  @doc """
  Returns `:ok` when `user_id` created the scan session, else `{:error, :unauthorized}`.
  """
  def authorize_session_owner!(session_id, user_id) do
    case Repo.get(ScanSession, session_id) do
      %{created_by_id: ^user_id} -> :ok
      %ScanSession{} -> {:error, :unauthorized}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Authorizes access to an `event_membership` check-in desk.

  Open sessions are collaborative: any admin or volunteer may join the desk.
  Closed sessions are restricted to the operator who created them so other
  volunteers cannot browse or export historical member PII.
  """
  def authorize_membership_checkin_access!(session_id, user_id) do
    case Repo.get(ScanSession, session_id) do
      %ScanSession{} = session ->
        authorize_membership_checkin_session(session, user_id)

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Loads an `event_membership` check-in session with associations when access is allowed.

  Combines authorization and preload in a single database round-trip.
  """
  def fetch_membership_checkin_session(session_id, user_id) do
    case Repo.get(ScanSession, session_id)
         |> Repo.preload([:event, :created_by]) do
      %ScanSession{} = session ->
        case authorize_membership_checkin_session(session, user_id) do
          :ok -> {:ok, session}
          error -> error
        end

      nil ->
        {:error, :not_found}
    end
  end

  defp authorize_membership_checkin_session(
         %{type: :event_membership, created_by_id: creator_id} = session,
         user_id
       ) do
    cond do
      creator_id == user_id -> :ok
      is_nil(session.closed_at) -> :ok
      true -> {:error, :unauthorized}
    end
  end

  defp authorize_membership_checkin_session(_session, _user_id),
    do: {:error, :unauthorized}

  def list_sessions(opts \\ []) do
    type_filter = Keyword.get(opts, :type)

    ScanSession
    |> maybe_filter_session_type(type_filter)
    |> order_by([s], desc: s.inserted_at)
    |> preload([:event, :created_by])
    |> Repo.all()
  end

  @doc """
  Returns all open (not yet closed) sessions created by a given user.
  """
  def get_open_sessions(user_id) do
    ScanSession
    |> where([s], s.created_by_id == ^user_id and is_nil(s.closed_at))
    |> order_by([s], desc: s.inserted_at)
    |> preload([:event, :created_by])
    |> Repo.all()
  end

  @doc """
  Returns all open event_membership sessions across all admins.
  Used for the "join session" feature so any admin can participate in an
  active membership check-in desk.
  """
  def get_open_membership_sessions do
    ScanSession
    |> where([s], s.type == :event_membership and is_nil(s.closed_at))
    |> order_by([s], desc: s.inserted_at)
    |> preload([:event, :created_by])
    |> Repo.all()
  end

  @event_check_in_session_types [:event, :event_membership]

  @doc """
  Returns the most relevant open scan session for an event, if any.

  By default prefers `:event_membership` over `:event` when both are open.
  Pass `types:` to limit which session types are considered, and `prefer:` to
  change which type wins when multiple are open.
  """
  def get_open_session_for_event(event_id, opts \\ []) do
    types = Keyword.get(opts, :types, @event_check_in_session_types)
    prefer = Keyword.get(opts, :prefer, :event_membership)

    ScanSession
    |> where(
      [s],
      s.event_id == ^event_id and is_nil(s.closed_at) and s.type in ^types
    )
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
    |> pick_open_session(prefer)
  end

  @doc """
  Returns a map of `event_id => open session` for the given event ids.

  Uses the same preference rules as `get_open_session_for_event/2`.
  """
  def get_open_check_in_sessions_by_event_id(event_ids, opts \\ []) do
    types = Keyword.get(opts, :types, @event_check_in_session_types)
    prefer = Keyword.get(opts, :prefer, :event_membership)

    if event_ids == [] do
      %{}
    else
      ScanSession
      |> where(
        [s],
        s.event_id in ^event_ids and is_nil(s.closed_at) and s.type in ^types
      )
      |> order_by([s], desc: s.inserted_at)
      |> Repo.all()
      |> Enum.group_by(& &1.event_id, & &1)
      |> Map.new(fn {event_id, sessions} ->
        {event_id, pick_open_session(sessions, prefer)}
      end)
      |> Map.reject(fn {_id, session} -> is_nil(session) end)
    end
  end

  defp pick_open_session([], _prefer), do: nil

  defp pick_open_session(sessions, prefer) do
    Enum.find(sessions, &(&1.type == prefer)) || List.first(sessions)
  end

  @doc """
  Returns an open session for the event and type, creating one if none exists.

  Uses a per-event advisory lock so concurrent callers do not create duplicates.
  """
  def get_or_create_open_session_for_event(event_id, type, attrs)
      when type in [:event, :event_membership] do
    lock_key = advisory_lock_key(event_id, type)

    result =
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])

        case get_open_session_for_event(event_id, types: [type], prefer: type) do
          %ScanSession{} = session ->
            session

          nil ->
            case create_session(attrs) do
              {:ok, session} ->
                session

              {:error, changeset} ->
                Repo.rollback(changeset)
            end
        end
      end)

    case result do
      {:ok, session} -> {:ok, session}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  defp advisory_lock_key(event_id, type) do
    :erlang.phash2({event_id, type})
  end

  @doc """
  Returns the number of successful scan records for a session.
  """
  def get_session_scan_count(session_id) do
    ScanRecord
    |> where([r], r.scan_session_id == ^session_id and r.result == :success)
    |> Repo.aggregate(:count)
  end

  defp maybe_filter_session_type(query, nil), do: query

  defp maybe_filter_session_type(query, type) do
    where(query, [s], s.type == ^type)
  end

  # --- Scan Processing ---

  @doc """
  Process a QR scan. Verifies the token and applies business rules
  based on the session type (membership or event).
  """
  def process_scan(%ScanSession{} = session, qr_data) when is_binary(qr_data) do
    case QrToken.verify(qr_data) do
      {:ok, {:membership, user_id}} ->
        process_membership_scan(session, user_id)

      {:ok, {:ticket, ticket_id}} ->
        process_ticket_scan(session, ticket_id)

      {:error, :invalid} ->
        {:error, :invalid,
         "Invalid QR code. This does not appear to be a valid membership or ticket QR."}
    end
  end

  def process_scan(_session, _qr_data),
    do: {:error, :invalid, "Invalid scan data."}

  defp process_membership_scan(%ScanSession{type: :event} = _session, _user_id) do
    {:error, :cross_mode,
     "Invalid Ticket: This is a Membership QR. Please scan an Event Ticket."}
  end

  defp process_membership_scan(
         %ScanSession{type: :event_membership} = session,
         user_id
       ) do
    case process_membership_scan_for_user(session, user_id) do
      {:ok, result} ->
        if result.status == :active do
          user = result.user
          checked_in_by = Repo.get!(Ysc.Accounts.User, session.created_by_id)
          check_in_member(session, user, checked_in_by)
        end

        {:ok, result}

      error ->
        error
    end
  end

  defp process_membership_scan(%ScanSession{} = session, user_id) do
    process_membership_scan_for_user(session, user_id)
  end

  defp process_membership_scan_for_user(%ScanSession{} = session, user_id) do
    case Accounts.get_user(user_id) do
      nil ->
        record_scan(session, %{
          result: :invalid,
          metadata: %{reason: "user_not_found"}
        })

        {:error, :invalid, "User not found."}

      user ->
        membership = MembershipCache.get_active_membership(user)
        active? = YscWeb.UserAuth.membership_active?(membership)
        plan_type = YscWeb.UserAuth.get_membership_plan_type(membership)
        renewal_date = YscWeb.UserAuth.get_membership_renewal_date(membership)
        member_since = get_member_since(user, membership)

        is_sub_account = Accounts.sub_account?(user)

        primary_user =
          if is_sub_account, do: Accounts.get_primary_user(user), else: nil

        status = if active?, do: "active", else: "inactive"
        type_str = if plan_type, do: Atom.to_string(plan_type), else: nil

        {:ok, record} =
          record_scan(session, %{
            user_id: user.id,
            result: :success,
            membership_status: status,
            membership_type: type_str
          })

        {:ok,
         %{
           scan_record: record,
           status: if(active?, do: :active, else: :inactive),
           user: user,
           membership_type: plan_type,
           member_since: member_since,
           renewal_date: renewal_date,
           is_sub_account: is_sub_account,
           primary_user: primary_user
         }}
    end
  end

  defp process_ticket_scan(
         %ScanSession{type: :membership} = _session,
         _ticket_id
       ) do
    {:error, :cross_mode,
     "Invalid QR: This is a Ticket QR. Please scan a Membership QR code."}
  end

  defp process_ticket_scan(
         %ScanSession{type: :event_membership} = _session,
         _ticket_id
       ) do
    {:error, :cross_mode,
     "Invalid QR: This session checks membership, not tickets. Please scan a Membership QR code."}
  end

  defp process_ticket_scan(%ScanSession{} = session, ticket_id) do
    case get_ticket_for_scan(ticket_id) do
      nil ->
        record_scan(session, %{
          result: :invalid,
          metadata: %{reason: "ticket_not_found"}
        })

        {:error, :invalid, "Ticket not found."}

      ticket ->
        validate_ticket_scan(session, ticket)
    end
  end

  defp validate_ticket_scan(session, ticket) do
    cond do
      ticket.event_id != session.event_id ->
        record_scan(session, %{
          ticket_id: ticket.id,
          user_id: ticket.user_id,
          result: :invalid,
          metadata: %{reason: "wrong_event"}
        })

        {:error, :invalid, "This ticket is for a different event."}

      ticket.status != :confirmed ->
        record_scan(session, %{
          ticket_id: ticket.id,
          user_id: ticket.user_id,
          result: :invalid,
          metadata: %{reason: "not_confirmed", status: ticket.status}
        })

        {:error, :invalid, "This ticket is #{ticket.status}, not confirmed."}

      ticket.checked_in ->
        check_partially_checked_in_order(session, ticket)

      true ->
        check_group_tickets(session, ticket)
    end
  end

  # When the scanned ticket is already checked in, look at the rest of the order.
  # If unchecked confirmed tickets remain, surface the group-prompt modal so the
  # admin can check them in without needing to hunt for another ticket to scan.
  # If every ticket in the order is already checked in, show the regular
  # "ALREADY SCANNED" result.
  defp check_partially_checked_in_order(session, ticket) do
    record_scan(session, %{
      ticket_id: ticket.id,
      user_id: ticket.user_id,
      result: :already_scanned,
      metadata: %{original_checkin_at: ticket.checked_in_at}
    })

    order = ticket.ticket_order

    if order do
      loaded_order = Repo.preload(order, tickets: [:registration])
      all_tickets = loaded_order.tickets

      unchecked =
        Enum.filter(all_tickets, fn t ->
          t.status == :confirmed && !t.checked_in
        end)

      checked = Enum.filter(all_tickets, & &1.checked_in)

      if unchecked != [] do
        {:ok, :group_prompt,
         %{
           ticket: ticket,
           order: loaded_order,
           unchecked_tickets: unchecked,
           checked_tickets: checked,
           partially_scanned: true
         }}
      else
        {:error, :already_scanned,
         %{
           checked_in_at: ticket.checked_in_at,
           ticket_id: ticket.id,
           order_id: ticket.ticket_order_id,
           user_id: ticket.user_id
         }}
      end
    else
      {:error, :already_scanned,
       %{
         checked_in_at: ticket.checked_in_at,
         ticket_id: ticket.id,
         order_id: ticket.ticket_order_id,
         user_id: ticket.user_id
       }}
    end
  end

  defp check_group_tickets(session, ticket) do
    order = ticket.ticket_order

    if order do
      order_tickets =
        order
        |> Repo.preload(tickets: [:registration])
        |> Map.get(:tickets, [])

      unchecked =
        Enum.filter(order_tickets, fn t ->
          t.status == :confirmed && !t.checked_in
        end)

      checked =
        Enum.filter(order_tickets, fn t ->
          t.checked_in
        end)

      case unchecked do
        [_, _ | _] ->
          {:ok, :group_prompt,
           %{
             ticket: ticket,
             order: order,
             unchecked_tickets: unchecked,
             checked_tickets: checked,
             partially_scanned: checked != []
           }}

        _ ->
          do_check_in_ticket(session, ticket, :individual)
      end
    else
      do_check_in_ticket(session, ticket, :individual)
    end
  end

  @doc """
  Check in a single ticket by ID.
  """
  def check_in_single(%ScanSession{} = session, ticket_id) do
    case get_ticket_for_scan(ticket_id) do
      nil ->
        {:error, :invalid, "Ticket not found."}

      ticket ->
        validate_manual_check_in(session, ticket)
    end
  end

  @doc """
  Check in all unchecked tickets in an order.
  """
  def check_in_order(%ScanSession{} = session, order_id) do
    case Repo.get(TicketOrder, order_id) do
      nil ->
        {:error, :invalid, "Order not found."}

      %{event_id: event_id} when event_id != session.event_id ->
        {:error, :invalid, "This order is for a different event."}

      order ->
        order = Repo.preload(order, tickets: [:registration])

        unchecked =
          Enum.filter(order.tickets, fn t ->
            t.status == :confirmed && !t.checked_in
          end)

        case unchecked do
          [] ->
            {:ok, :group_checked_in, 0}

          tickets ->
            check_in_order_tickets(session, tickets)
        end
    end
  end

  defp check_in_order_tickets(session, tickets) do
    result =
      Repo.transaction(fn ->
        updated_tickets =
          Enum.map(tickets, fn ticket ->
            case Repo.update(Ticket.check_in_changeset(ticket)) do
              {:ok, updated} -> updated
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end)

        Enum.each(updated_tickets, fn ticket ->
          case record_scan(session, %{
                 user_id: ticket.user_id,
                 ticket_id: ticket.id,
                 ticket_order_id: ticket.ticket_order_id,
                 checkin_type: :individual,
                 result: :success
               }) do
            {:ok, _record} -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

        updated_tickets
      end)

    case result do
      {:ok, updated_tickets} ->
        event_id = session.event_id

        updated_tickets
        |> Repo.preload([:registration, :user, :ticket_tier, :ticket_order])
        |> Enum.each(fn loaded_ticket ->
          broadcast_checkin(
            event_id,
            %MessagePassingEvents.TicketCheckedIn{
              ticket: loaded_ticket,
              event_id: event_id
            }
          )
        end)

        {:ok, :group_checked_in, length(updated_tickets)}

      {:error, _reason} ->
        {:error, :check_in_failed,
         "Failed to check in tickets. Please try again."}
    end
  end

  defp validate_manual_check_in(session, ticket) do
    cond do
      ticket.event_id != session.event_id ->
        record_scan(session, %{
          ticket_id: ticket.id,
          user_id: ticket.user_id,
          result: :invalid,
          metadata: %{reason: "wrong_event"}
        })

        {:error, :invalid, "This ticket is for a different event."}

      ticket.status != :confirmed ->
        record_scan(session, %{
          ticket_id: ticket.id,
          user_id: ticket.user_id,
          result: :invalid,
          metadata: %{reason: "not_confirmed", status: ticket.status}
        })

        {:error, :invalid, "This ticket is #{ticket.status}, not confirmed."}

      ticket.checked_in ->
        {:error, :already_scanned,
         %{
           checked_in_at: ticket.checked_in_at,
           ticket_id: ticket.id,
           order_id: ticket.ticket_order_id,
           user_id: ticket.user_id
         }}

      true ->
        do_check_in_ticket(session, ticket, :individual)
    end
  end

  defp do_check_in_ticket(session, ticket, checkin_type) do
    result =
      Repo.transaction(fn ->
        changeset = Ticket.check_in_changeset(ticket)

        case Repo.update(changeset) do
          {:ok, updated_ticket} ->
            case record_scan(session, %{
                   user_id: ticket.user_id,
                   ticket_id: ticket.id,
                   ticket_order_id: ticket.ticket_order_id,
                   checkin_type: checkin_type,
                   result: :success
                 }) do
              {:ok, record} -> {updated_ticket, record}
              {:error, reason} -> Repo.rollback(reason)
            end

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, {updated_ticket, _record}} ->
        loaded_ticket =
          Repo.preload(updated_ticket, [
            :registration,
            :user,
            :ticket_tier,
            :ticket_order
          ])

        broadcast_checkin(
          ticket.event_id,
          %MessagePassingEvents.TicketCheckedIn{
            ticket: loaded_ticket,
            event_id: ticket.event_id
          }
        )

        result

      _ ->
        result
    end
  end

  # --- Manual Lookup ---

  @doc """
  Look up a user by email for manual membership verification.
  """
  def manual_membership_lookup(email) when is_binary(email) do
    case Accounts.get_user_by_email(email) do
      nil -> {:error, :not_found, "No user found with that email."}
      user -> {:ok, user}
    end
  end

  @doc """
  Look up a ticket order by reference ID for manual event check-in.
  """
  def manual_ticket_lookup(reference_id, event_id)
      when is_binary(reference_id) do
    order =
      TicketOrder
      |> where([o], o.reference_id == ^reference_id and o.event_id == ^event_id)
      |> preload(tickets: [:registration])
      |> Repo.one()

    case order do
      nil ->
        {:error, :not_found,
         "No order found with that reference ID for this event."}

      order ->
        {:ok, order}
    end
  end

  # --- Record Keeping ---

  defp record_scan(session, attrs) do
    programmatic_fields =
      Map.take(attrs, [
        :user_id,
        :ticket_id,
        :ticket_order_id,
        :membership_status,
        :membership_type
      ])

    cast_attrs =
      attrs
      |> Map.drop([
        :user_id,
        :ticket_id,
        :ticket_order_id,
        :membership_status,
        :membership_type
      ])
      |> Map.put(:scan_session_id, session.id)

    %ScanRecord{}
    |> ScanRecord.changeset(cast_attrs)
    |> Ecto.Changeset.change(programmatic_fields)
    |> Repo.insert()
  end

  def list_scan_records(session_id) do
    ScanRecord
    |> where([r], r.scan_session_id == ^session_id)
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> preload([:user, :ticket])
    |> Repo.all()
  end

  def count_scan_records(session_id) do
    ScanRecord
    |> where([r], r.scan_session_id == ^session_id)
    |> where([r], r.result == :success)
    |> Repo.aggregate(:count)
  end

  # --- CSV Export ---

  def export_session_csv(session_id) do
    records =
      ScanRecord
      |> where([r], r.scan_session_id == ^session_id)
      |> order_by([r], asc: r.inserted_at)
      |> preload([:user, :ticket])
      |> Repo.all()

    session = get_session!(session_id)

    headers =
      case session.type do
        t when t in [:membership, :event_membership] ->
          [
            "Name",
            "Email",
            "Timestamp",
            "Membership Status",
            "Membership Type",
            "Result"
          ]

        :event ->
          [
            "Name",
            "Email",
            "Timestamp",
            "Ticket Reference",
            "Check-in Type",
            "Result"
          ]
      end

    rows =
      Enum.map(records, fn record ->
        user = record.user

        name =
          if user, do: "#{user.first_name} #{user.last_name}", else: "Unknown"

        email = if user, do: user.email, else: ""

        timestamp =
          Calendar.strftime(record.inserted_at, "%Y-%m-%d %H:%M:%S UTC")

        case session.type do
          t when t in [:membership, :event_membership] ->
            [
              name,
              email,
              timestamp,
              record.membership_status || "",
              record.membership_type || "",
              to_string(record.result)
            ]

          :event ->
            ticket_ref =
              if record.ticket,
                do: record.ticket.reference_id || "",
                else: ""

            [
              name,
              email,
              timestamp,
              ticket_ref,
              to_string(record.checkin_type || ""),
              to_string(record.result)
            ]
        end
      end)

    [headers | rows]
    |> CSV.encode()
    |> Enum.to_list()
    |> IO.iodata_to_binary()
  end

  @doc """
  Exports a membership check-in session's SessionCheckIn records as a CSV string.
  Each row contains the checked-in member's name, email, membership status,
  membership type, check-in time, and the name of the admin who checked them in.
  """
  def export_membership_checkins_csv(session_id) do
    check_ins =
      SessionCheckIn
      |> where([sc], sc.scan_session_id == ^session_id)
      |> order_by([sc], asc: sc.inserted_at)
      |> preload([:user, :checked_in_by])
      |> Repo.all()

    headers = [
      "Name",
      "Email",
      "Membership Status",
      "Membership Type",
      "Checked-in At",
      "Checked-in By"
    ]

    rows =
      Enum.map(check_ins, fn sc ->
        user = sc.user
        checked_in_by = sc.checked_in_by

        name =
          if user, do: "#{user.first_name} #{user.last_name}", else: "Unknown"

        email = if user, do: user.email, else: ""

        by_name =
          if checked_in_by,
            do: "#{checked_in_by.first_name} #{checked_in_by.last_name}",
            else: ""

        timestamp = Calendar.strftime(sc.inserted_at, "%Y-%m-%d %H:%M:%S UTC")

        [
          name,
          email,
          sc.membership_status || "",
          sc.membership_type || "",
          timestamp,
          by_name
        ]
      end)

    [headers | rows]
    |> CSV.encode()
    |> Enum.to_list()
    |> IO.iodata_to_binary()
  end

  # --- Manual Check-in View ---

  @doc """
  Lists all confirmed tickets for an event for the check-in management view.
  Optionally filters by a search query matching attendee name, purchaser name,
  purchaser email, order reference (ORD-xxx), or ticket reference (TKT-xxx).
  Returns tickets preloaded with registration, user, ticket_tier, and ticket_order.
  Sorted: pending (not checked in) alphabetically by attendee/purchaser name, then checked-in.
  """
  def list_event_checkin_tickets(event_id, search \\ nil) do
    base_query =
      Ticket
      |> where([t], t.event_id == ^event_id and t.status == :confirmed)
      |> join(:left, [t], td in TicketDetail,
        on: td.ticket_id == t.id,
        as: :registration
      )
      |> join(:left, [t], u in assoc(t, :user), as: :user)
      |> join(:left, [t], tt in assoc(t, :ticket_tier), as: :ticket_tier)
      |> join(:left, [t], o in assoc(t, :ticket_order), as: :ticket_order)
      |> preload([registration: td, user: u, ticket_tier: tt, ticket_order: o],
        registration: td,
        user: u,
        ticket_tier: tt,
        ticket_order: o
      )

    query =
      if search && search != "" do
        search_term = "%#{search}%"

        base_query
        |> where(
          [t, registration: td, user: u, ticket_order: o],
          ilike(
            fragment("concat(?, ' ', ?)", td.first_name, td.last_name),
            ^search_term
          ) or
            ilike(
              fragment("concat(?, ' ', ?)", u.first_name, u.last_name),
              ^search_term
            ) or
            ilike(u.email, ^search_term) or
            ilike(o.reference_id, ^search_term) or
            ilike(t.reference_id, ^search_term)
        )
      else
        base_query
      end

    query
    |> order_by([t, registration: td, user: u],
      asc: t.checked_in,
      asc:
        fragment(
          "coalesce(?, concat(?, ' ', ?))",
          fragment("concat(?, ' ', ?)", td.first_name, td.last_name),
          u.first_name,
          u.last_name
        )
    )
    |> Repo.all()
  end

  @doc """
  Returns the check-in counts for an event: {checked_in_count, total_confirmed_count}.
  """
  def event_checkin_counts(event_id) do
    %{checked_in: checked_in, total: total} =
      Ticket
      |> where([t], t.event_id == ^event_id and t.status == :confirmed)
      |> select([t], %{
        total: count(t.id),
        checked_in: count(t.id) |> filter(t.checked_in == true)
      })
      |> Repo.one!()

    {checked_in, total}
  end

  @doc """
  Undoes a check-in for a single ticket by ID, setting checked_in to false and
  clearing checked_in_at. Broadcasts TicketCheckInUndone via PubSub.

  When `expected_event_id` is provided, tickets for other events are rejected.
  """
  def undo_check_in(ticket_id, expected_event_id \\ nil)

  def undo_check_in(ticket_id, expected_event_id) do
    case Repo.get(Ticket, ticket_id) do
      nil ->
        {:error, :not_found, "Ticket not found."}

      %{event_id: event_id}
      when not is_nil(expected_event_id) and event_id != expected_event_id ->
        {:error, :invalid, "This ticket is for a different event."}

      ticket ->
        changeset = Ticket.undo_check_in_changeset(ticket)

        case Repo.update(changeset) do
          {:ok, updated_ticket} ->
            updated_ticket =
              Repo.preload(updated_ticket, [
                :registration,
                :user,
                :ticket_tier,
                :ticket_order
              ])

            broadcast_checkin(
              ticket.event_id,
              %MessagePassingEvents.TicketCheckInUndone{
                ticket: updated_ticket,
                event_id: ticket.event_id
              }
            )

            {:ok, updated_ticket}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Subscribe to check-in events for a specific event.
  """
  def subscribe_checkin(event_id) do
    Phoenix.PubSub.subscribe(Ysc.PubSub, checkin_topic(event_id))
  end

  @doc """
  Broadcast a check-in event to all subscribers for the given event.
  """
  def broadcast_checkin(event_id, event) do
    Phoenix.PubSub.broadcast(
      Ysc.PubSub,
      checkin_topic(event_id),
      {__MODULE__, event}
    )
  end

  defp checkin_topic(event_id), do: "checkin:event:#{event_id}"

  # --- Membership Check-in (event_membership sessions) ---

  @doc """
  Checks in a user to a membership scan session.

  Verifies membership status, creates a SessionCheckIn record, and broadcasts
  via PubSub. Returns `{:ok, check_in}` on success.

  Returns `{:error, :already_checked_in, message}` if the user was already
  checked in. Unlike ticket check-in, there is NO restriction on inactive
  membership — the user is always checked in; the status is merely recorded.
  """
  def check_in_member(%ScanSession{closed_at: closed_at}, _user, _checked_in_by)
      when not is_nil(closed_at) do
    {:error, :session_closed,
     "This session has been completed and is no longer accepting check-ins."}
  end

  def check_in_member(%ScanSession{} = session, user, checked_in_by) do
    membership = MembershipCache.get_active_membership(user)
    active? = YscWeb.UserAuth.membership_active?(membership)

    plan_type = YscWeb.UserAuth.get_membership_plan_type(membership)

    membership_status = if(active?, do: "active", else: "inactive")

    membership_type =
      case plan_type do
        nil -> nil
        atom when is_atom(atom) -> Atom.to_string(atom)
        other -> to_string(other)
      end

    attrs = %{
      membership_status: membership_status,
      membership_type: membership_type
    }

    changeset =
      %SessionCheckIn{}
      |> Ecto.Changeset.change(%{
        scan_session_id: session.id,
        user_id: user.id,
        checked_in_by_id: checked_in_by.id
      })
      |> SessionCheckIn.changeset(attrs)
      |> SessionCheckIn.validate_required_keys()

    case Repo.insert(changeset) do
      {:ok, check_in} ->
        check_in =
          Repo.preload(check_in, [:user, :checked_in_by, :scan_session])

        broadcast_membership_checkin(
          session.id,
          %MessagePassingEvents.MemberCheckedIn{
            session_check_in: check_in,
            session_id: session.id
          }
        )

        {:ok, check_in}

      {:error, %Ecto.Changeset{} = cs} when cs.errors != [] ->
        if Enum.any?(cs.errors, fn {_field, {_msg, opts}} ->
             Keyword.get(opts, :constraint_name) ==
               "session_check_ins_scan_session_id_user_id_index"
           end) do
          {:error, :already_checked_in,
           "This member has already been checked in."}
        else
          {:error, :db_error, inspect(cs.errors)}
        end

      {:error, changeset} ->
        {:error, :db_error, inspect(changeset.errors)}
    end
  end

  @doc """
  Undoes (removes) a membership check-in for a user in a session.
  Broadcasts MemberCheckInUndone via PubSub.
  """
  def undo_member_check_in(session_id, user_id) do
    session = get_session!(session_id)

    if session.closed_at do
      {:error, :session_closed,
       "This session has been completed and is no longer accepting changes."}
    else
      do_undo_member_check_in(session_id, user_id)
    end
  end

  defp do_undo_member_check_in(session_id, user_id) do
    case Repo.get_by(SessionCheckIn,
           scan_session_id: session_id,
           user_id: user_id
         ) do
      nil ->
        {:error, :not_found, "Check-in not found."}

      check_in ->
        case Repo.delete(check_in) do
          {:ok, _deleted} ->
            broadcast_membership_checkin(
              session_id,
              %MessagePassingEvents.MemberCheckInUndone{
                user_id: user_id,
                session_id: session_id
              }
            )

            {:ok, :removed}

          {:error, changeset} ->
            {:error, :db_error, inspect(changeset.errors)}
        end
    end
  end

  @doc """
  Lists all users checked in to a membership session, with optional search.
  Results are ordered by check-in time (most recent first).
  """
  def list_membership_check_ins(session_id, search \\ nil) do
    alias Ysc.Accounts.User

    base =
      from(sc in SessionCheckIn,
        where: sc.scan_session_id == ^session_id,
        join: u in User,
        on: u.id == sc.user_id,
        preload: [:user, :checked_in_by],
        order_by: [desc: sc.inserted_at]
      )

    query =
      if search && String.trim(search) != "" do
        term = "%#{String.trim(search)}%"

        from([sc, u] in base,
          where:
            ilike(u.first_name, ^term) or
              ilike(u.last_name, ^term) or
              ilike(u.email, ^term) or
              ilike(fragment("? || ' ' || ?", u.first_name, u.last_name), ^term)
        )
      else
        base
      end

    Repo.all(query)
  end

  @doc """
  Returns the count of members checked in to a session.
  """
  def membership_check_in_count(session_id) do
    SessionCheckIn
    |> where([sc], sc.scan_session_id == ^session_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns true if the given user is already checked in to the session.
  """
  def member_checked_in?(session_id, user_id) do
    SessionCheckIn
    |> where([sc], sc.scan_session_id == ^session_id and sc.user_id == ^user_id)
    |> Repo.exists?()
  end

  @doc """
  Searches active users and enriches each result with:
  - `membership_status`: :active | :inactive
  - `membership_type`: plan atom or nil
  - `checked_in?`: whether the user is already checked in to this session
  """
  def search_users_for_checkin(_session_id, query)
      when is_binary(query) and byte_size(query) == 0,
      do: []

  def search_users_for_checkin(session_id, query) when is_binary(query) do
    trimmed = String.trim(query)

    if trimmed == "" do
      []
    else
      users = Accounts.search_users(trimmed, limit: 20)
      user_ids = Enum.map(users, & &1.id)
      checked_in_ids = checked_in_user_ids(session_id, user_ids)
      membership_data = MembershipCache.batch_membership_data_for_users(users)

      Enum.map(users, fn user ->
        {membership, plan_type} = Map.get(membership_data, user.id, {nil, nil})
        active? = YscWeb.UserAuth.membership_active?(membership)

        %{
          user: user,
          membership_status: if(active?, do: :active, else: :inactive),
          membership_type: plan_type,
          checked_in?: user.id in checked_in_ids
        }
      end)
    end
  end

  defp checked_in_user_ids(_session_id, []), do: []

  defp checked_in_user_ids(session_id, user_ids) do
    SessionCheckIn
    |> where(
      [sc],
      sc.scan_session_id == ^session_id and sc.user_id in ^user_ids
    )
    |> select([sc], sc.user_id)
    |> Repo.all()
  end

  @doc """
  Subscribe to membership check-in events for a specific session.
  """
  def subscribe_membership_checkin(session_id) do
    Phoenix.PubSub.subscribe(Ysc.PubSub, membership_checkin_topic(session_id))
  end

  @doc """
  Broadcast a membership check-in event to all subscribers for the session.
  """
  def broadcast_membership_checkin(session_id, event) do
    Phoenix.PubSub.broadcast(
      Ysc.PubSub,
      membership_checkin_topic(session_id),
      {__MODULE__, event}
    )
  end

  defp membership_checkin_topic(session_id),
    do: "membership_checkin:session:#{session_id}"

  # --- Helpers ---

  defp get_ticket_for_scan(ticket_id) do
    Ticket
    |> Repo.get(ticket_id)
    |> case do
      nil ->
        nil

      ticket ->
        Repo.preload(ticket, [
          :event,
          :user,
          :registration,
          ticket_order: :tickets
        ])
    end
  end

  defp get_member_since(user, membership) do
    cond do
      membership != nil && is_map(membership) &&
          Map.get(membership, :type) == :lifetime ->
        membership.awarded_at

      membership != nil && is_map(membership) &&
          Map.get(membership, :start_date) != nil ->
        membership.start_date

      user.lifetime_membership_awarded_at != nil ->
        user.lifetime_membership_awarded_at

      true ->
        user.inserted_at
    end
  end

  @doc false
  def ci_query_explain_query do
    alias Ysc.Accounts.User
    alias Ysc.Ci.QueryExplain.Fixtures

    session_id = Fixtures.ulid()

    from(sc in SessionCheckIn,
      where: sc.scan_session_id == ^session_id,
      join: u in User,
      on: u.id == sc.user_id,
      preload: [:user, :checked_in_by],
      order_by: [desc: sc.inserted_at]
    )
  end
end
