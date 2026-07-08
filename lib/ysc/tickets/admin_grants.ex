defmodule Ysc.Tickets.AdminGrants do
  @moduledoc """
  Admin-granted complimentary tickets for members (e.g. migration from legacy systems).

  Creates completed $0 ticket orders with confirmed tickets immediately, without checkout.
  """

  import Ecto.Query, warn: false

  require Ysc.Logging

  alias Ysc.Accounts
  alias Ysc.Events
  alias Ysc.Events.Event
  alias Ysc.Events.EventDateTime
  alias Ysc.Events.Ticket
  alias Ysc.Events.TicketTier
  alias Ysc.Repo
  alias Ysc.Tickets.BookingLocker
  alias Ysc.Tickets.TicketOrder

  @doc """
  Grants confirmed tickets to a member for an event.

  ## Parameters

    * `granted_by_id` - admin user performing the grant
    * `user_id` - member receiving tickets
    * `event_id` - event id
    * `ticket_selections` - map of `ticket_tier_id => quantity`
    * `opts` - `:skip_capacity`, `:skip_email`, `:admin_grant_notes`

  ## Returns

    * `{:ok, %TicketOrder{}}` with tickets preloaded
    * `{:error, reason}` or `{:error, %Ecto.Changeset{}}`
  """
  def grant_admin_tickets(
        granted_by_id,
        user_id,
        event_id,
        ticket_selections,
        opts \\ []
      )
      when is_map(ticket_selections) do
    skip_capacity? = Keyword.get(opts, :skip_capacity, false)
    admin_grant_notes = Keyword.get(opts, :admin_grant_notes)

    Ysc.Logging.info("Admin ticket grant started",
      granted_by_id: granted_by_id,
      user_id: user_id,
      event_id: event_id,
      ticket_selections: ticket_selections,
      skip_capacity: skip_capacity?
    )

    result =
      with {:ok, user} <- fetch_user(user_id),
           {:ok, event} <- fetch_grantable_event(event_id),
           {:ok, tiers} <- load_and_validate_tiers(event_id, ticket_selections),
           :ok <-
             maybe_validate_capacity(
               user_id,
               event_id,
               ticket_selections,
               skip_capacity?
             ) do
        insert_grant_transaction(
          granted_by_id,
          user,
          event,
          tiers,
          ticket_selections,
          admin_grant_notes
        )
      end

    case result do
      {:ok, ticket_order} ->
        Ysc.Logging.info("Admin ticket grant succeeded",
          granted_by_id: granted_by_id,
          user_id: user_id,
          event_id: event_id,
          ticket_order_id: ticket_order.id,
          ticket_count: length(ticket_order.tickets || [])
        )

        {:ok, ticket_order}

      {:error, reason} = error ->
        Ysc.Logging.info("Admin ticket grant failed",
          granted_by_id: granted_by_id,
          user_id: user_id,
          event_id: event_id,
          reason: inspect(reason)
        )

        error
    end
  end

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    event_id = Fixtures.ulid()
    tier_ids = [Fixtures.ulid()]

    from(tt in TicketTier,
      where: tt.id in ^tier_ids and tt.event_id == ^event_id
    )
  end

  defp fetch_user(user_id) do
    case Accounts.get_user(user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp fetch_grantable_event(event_id) do
    case Repo.get(Event, event_id) do
      nil ->
        {:error, :event_not_found}

      %Event{partiful_link: link} when link not in [nil, ""] ->
        {:error, :partiful_event}

      %Event{} = event ->
        {:ok, event}
    end
  end

  defp load_and_validate_tiers(event_id, ticket_selections) do
    if ticket_selections == %{} do
      {:error, :empty_selection}
    else
      tier_ids = Map.keys(ticket_selections)

      tiers =
        TicketTier
        |> where([tt], tt.id in ^tier_ids and tt.event_id == ^event_id)
        |> Repo.all()

      if length(tiers) != length(tier_ids) do
        {:error, :invalid_ticket_tier}
      else
        case Enum.find(tiers, &donation_tier?/1) do
          nil ->
            case invalid_quantity?(ticket_selections) do
              true -> {:error, :invalid_quantity}
              false -> {:ok, tiers}
            end

          _ ->
            {:error, :donation_tier_not_grantable}
        end
      end
    end
  end

  defp donation_tier?(%TicketTier{type: type}),
    do: type in [:donation, "donation"]

  defp invalid_quantity?(ticket_selections) do
    Enum.any?(ticket_selections, fn {_tier_id, quantity} ->
      not is_integer(quantity) or quantity < 1
    end)
  end

  defp maybe_validate_capacity(_user_id, _event_id, _ticket_selections, true),
    do: :ok

  defp maybe_validate_capacity(user_id, event_id, ticket_selections, false) do
    case BookingLocker.validate_fulfillment_capacity(
           user_id,
           event_id,
           ticket_selections
         ) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_grant_transaction(
         granted_by_id,
         user,
         event,
         tiers,
         ticket_selections,
         admin_grant_notes
       ) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = grant_expires_at(event, now)
    tiers_by_id = Map.new(tiers, &{&1.id, &1})

    Repo.transaction(fn ->
      order_attrs = %{
        user_id: user.id,
        event_id: event.id,
        total_amount: Money.new(0, :USD),
        discount_amount: Money.new(0, :USD),
        expires_at: expires_at,
        completed_at: now,
        granted_by_id: granted_by_id,
        admin_grant_notes: admin_grant_notes
      }

      with {:ok, ticket_order} <- insert_ticket_order(order_attrs),
           {:ok, tickets} <-
             insert_tickets_for_selections(
               ticket_order,
               user,
               tiers_by_id,
               ticket_selections,
               expires_at
             ),
           :ok <- maybe_insert_registration_details(tickets, tiers_by_id, user) do
        ticket_order
        |> Repo.preload(tickets: :ticket_tier)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, ticket_order} -> {:ok, ticket_order}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_ticket_order(%{granted_by_id: granted_by_id} = attrs) do
    order_attrs = Map.delete(attrs, :granted_by_id)

    %TicketOrder{}
    |> TicketOrder.admin_grant_changeset(order_attrs, granted_by_id)
    |> Repo.insert_with_reference_retry(TicketOrder)
  end

  defp insert_tickets_for_selections(
         ticket_order,
         user,
         tiers_by_id,
         ticket_selections,
         expires_at
       ) do
    ticket_selections
    |> Enum.flat_map(fn {tier_id, quantity} ->
      tier = Map.fetch!(tiers_by_id, tier_id)

      Enum.map(1..quantity, fn _ ->
        %Ticket{}
        |> Ticket.admin_grant_changeset(%{
          event_id: ticket_order.event_id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          ticket_order_id: ticket_order.id,
          status: :confirmed,
          expires_at: expires_at,
          discount_amount: Money.new(0, :USD)
        })
      end)
    end)
    |> Enum.reduce_while({:ok, []}, fn changeset, {:ok, acc} ->
      case Repo.insert_with_reference_retry(changeset, Ticket) do
        {:ok, ticket} ->
          {:cont, {:ok, [ticket | acc]}}

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, inserted} -> {:ok, Enum.reverse(inserted)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp maybe_insert_registration_details(tickets, tiers_by_id, user) do
    details =
      Enum.flat_map(tickets, fn ticket ->
        tier = Map.fetch!(tiers_by_id, ticket.ticket_tier_id)

        if tier.requires_registration do
          [
            %{
              ticket_id: ticket.id,
              first_name: user.first_name,
              last_name: user.last_name,
              email: user.email
            }
          ]
        else
          []
        end
      end)

    if details == [] do
      :ok
    else
      case Events.create_ticket_details(details) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp grant_expires_at(%Event{} = event, now) do
    end_date = event.end_date || event.start_date
    end_time = event.end_time || event.start_time

    case EventDateTime.combine(end_date, end_time) do
      %DateTime{} = end_dt -> end_dt
      _ -> DateTime.add(now, 365, :day)
    end
  end
end
