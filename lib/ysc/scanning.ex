defmodule Ysc.Scanning do
  @moduledoc """
  Context for QR code scanning sessions and records.

  Handles two scanning modes:
  - **Membership**: Validates a user's active membership status
  - **Event**: Validates ticket ownership and performs check-in
  """

  import Ecto.Query

  require Ysc.Logging

  alias Ysc.Repo
  alias Ysc.Accounts
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Events.Ticket
  alias Ysc.Tickets.TicketOrder
  alias Ysc.Scanning.{QrToken, ScanSession, ScanRecord}

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

    session
    |> ScanSession.close_changeset()
    |> Repo.update()
  end

  def get_session!(id) do
    ScanSession
    |> Repo.get!(id)
    |> Repo.preload([:event, :created_by])
  end

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

  defp process_membership_scan(%ScanSession{} = session, user_id) do
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
      nil -> {:error, :invalid, "Ticket not found."}
      ticket -> do_check_in_ticket(session, ticket, :individual)
    end
  end

  @doc """
  Check in all unchecked tickets in an order.
  """
  def check_in_order(%ScanSession{} = session, order_id) do
    case Repo.get(TicketOrder, order_id) do
      nil ->
        {:error, :invalid, "Order not found."}

      order ->
        order = Repo.preload(order, tickets: [:registration])

        unchecked =
          Enum.filter(order.tickets, fn t ->
            t.status == :confirmed && !t.checked_in
          end)

        results =
          Enum.map(unchecked, fn ticket ->
            do_check_in_ticket(session, ticket, :group)
          end)

        successes = Enum.filter(results, &match?({:ok, _}, &1))
        {:ok, :group_checked_in, Enum.count(successes)}
    end
  end

  defp do_check_in_ticket(session, ticket, checkin_type) do
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
    |> order_by([r], desc: r.inserted_at)
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
        :membership ->
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
          :membership ->
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
end
