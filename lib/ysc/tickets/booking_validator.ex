defmodule Ysc.Tickets.BookingValidator do
  @moduledoc """
  Service for validating ticket bookings and preventing overbooking.

  This module provides comprehensive validation for:
  - Event capacity limits
  - Ticket tier availability
  - User membership requirements
  - Event availability (not cancelled, not in past)
  - Concurrent booking prevention
  """

  import Ecto.Query, warn: false
  alias Ysc.Repo
  alias Ysc.Events
  alias Ysc.Events.{Event, TicketTier, Ticket, TicketReservation}
  alias Ysc.Accounts

  @doc """
  Validates a complete ticket booking request.

  ## Parameters:
  - `user_id`: The user requesting tickets
  - `event_id`: The event to book tickets for
  - `ticket_selections`: Map of ticket_tier_id => quantity

  ## Returns:
  - `:ok` if booking is valid
  - `{:error, reason}` if booking is invalid
  """
  def validate_booking(user_id, event_id, ticket_selections) do
    with :ok <- validate_user(user_id),
         :ok <- validate_event(event_id),
         :ok <- validate_ticket_selections(event_id, ticket_selections),
         :ok <- validate_capacity(event_id, ticket_selections, user_id) do
      validate_concurrent_booking(user_id, event_id)
    end
  end

  @doc """
  Gets real-time availability information for an event.

  ## Parameters:
  - `event_id`: The event to check

  ## Returns:
  - `%{event_capacity: info, tiers: [tier_info]}` with availability details
  """
  def get_event_availability(event_id) do
    event = Events.get_event!(event_id)
    ticket_tiers = Events.list_ticket_tiers_for_event(event_id)

    event_capacity = get_event_capacity_info(event)

    tier_availability =
      Enum.map(ticket_tiers, &get_tier_availability_from_map/1)

    %{
      event_capacity: event_capacity,
      tiers: tier_availability
    }
  end

  @doc """
  Checks if a specific ticket tier has available capacity.

  ## Parameters:
  - `tier_id`: The ticket tier to check
  - `requested_quantity`: Number of tickets requested

  ## Returns:
  - `{:ok, available_quantity}` if tier has capacity
  - `{:error, :insufficient_capacity}` if tier is sold out
  - `{:error, :tier_not_found}` if tier doesn't exist
  """
  def check_tier_capacity(tier_id, requested_quantity, user_id \\ nil) do
    case get_ticket_tier(tier_id) do
      nil ->
        {:error, :tier_not_found}

      tier ->
        available = get_available_tier_quantity(tier, user_id)

        cond do
          available == :unlimited ->
            {:ok, :unlimited}

          requested_quantity <= available ->
            {:ok, available}

          true ->
            {:error, :insufficient_capacity}
        end
    end
  end

  @doc """
  Checks if an event is at capacity.

  ## Parameters:
  - `event_id`: The event to check

  ## Returns:
  - `true` if event is at capacity
  - `false` if event has available capacity
  """
  def event_at_capacity?(event_id) when is_binary(event_id) do
    event = Events.get_event!(event_id)
    event_at_capacity?(event)
  end

  def event_at_capacity?(%Event{max_attendees: nil}), do: false

  def event_at_capacity?(%Event{max_attendees: max_attendees} = event) do
    current_attendees = count_confirmed_tickets_for_event(event.id)
    current_attendees >= max_attendees
  end

  ## Private Functions

  defp validate_user(user_id) do
    case Accounts.get_user(user_id) do
      nil ->
        {:error, :user_not_found}

      user ->
        if Accounts.has_active_membership?(user) do
          :ok
        else
          {:error, :membership_required}
        end
    end
  end

  defp validate_event(event_id) do
    case Events.get_event(event_id) do
      nil ->
        {:error, :event_not_found}

      %Event{state: :cancelled} ->
        {:error, :event_cancelled}

      %Event{} = event ->
        if event_in_past?(event) do
          {:error, :event_in_past}
        else
          :ok
        end
    end
  end

  defp validate_ticket_selections(event_id, ticket_selections) do
    if Enum.empty?(ticket_selections) do
      {:error, :no_tickets_selected}
    else
      # Validate each tier exists and is available for sale
      tier_validations =
        ticket_selections
        |> Enum.map(fn {tier_id, quantity} ->
          validate_tier_selection(event_id, tier_id, quantity)
        end)

      if Enum.any?(tier_validations, &(&1 != :ok)) do
        {:error, :invalid_tier_selection}
      else
        :ok
      end
    end
  end

  defp validate_tier_selection(event_id, tier_id, quantity) do
    case get_ticket_tier(tier_id) do
      nil ->
        {:error, :tier_not_found}

      tier ->
        cond do
          tier.event_id != event_id ->
            {:error, :tier_not_for_event}

          not tier_on_sale?(tier) ->
            {:error, :tier_not_on_sale}

          quantity <= 0 ->
            {:error, :invalid_quantity}

          true ->
            :ok
        end
    end
  end

  defp validate_capacity(event_id, ticket_selections, user_id) do
    event = Events.get_event!(event_id)

    # Check if user has reservations that would allow bypassing capacity
    user_has_reservations = user_has_reservations_for_event?(user_id, event_id)

    # Check if event is already at capacity (unless user has reservations)
    if not user_has_reservations and event_at_capacity?(event) do
      {:error, :event_at_capacity}
    else
      # Check each tier capacity
      tier_capacity_validations =
        ticket_selections
        |> Enum.map(fn {tier_id, quantity} ->
          check_tier_capacity(tier_id, quantity, user_id)
        end)

      if Enum.any?(
           tier_capacity_validations,
           &(&1 == {:error, :insufficient_capacity})
         ) do
        {:error, :tier_capacity_exceeded}
      else
        # Check total event capacity (unless user has reservations)
        total_requested = Enum.sum(Map.values(ticket_selections))

        if user_has_reservations or
             within_event_capacity?(event, total_requested) do
          :ok
        else
          {:error, :event_capacity_exceeded}
        end
      end
    end
  end

  defp validate_concurrent_booking(user_id, event_id) do
    # Check if user already has a pending order for this event
    pending_orders =
      Ysc.Tickets.TicketOrder
      |> where(
        [to],
        to.user_id == ^user_id and to.event_id == ^event_id and
          to.status == :pending
      )
      |> Repo.all()

    if Enum.empty?(pending_orders) do
      :ok
    else
      {:error, :concurrent_booking_not_allowed}
    end
  end

  defp get_event_capacity_info(%Event{max_attendees: nil}) do
    %{
      max_attendees: nil,
      current_attendees: count_confirmed_tickets_for_event(nil),
      available: :unlimited,
      at_capacity: false
    }
  end

  defp get_event_capacity_info(%Event{max_attendees: max_attendees} = event) do
    current_attendees = count_confirmed_tickets_for_event(event.id)
    available = max_attendees - current_attendees

    %{
      max_attendees: max_attendees,
      current_attendees: current_attendees,
      available: max(0, available),
      at_capacity: current_attendees >= max_attendees
    }
  end

  defp get_tier_availability_from_map(tier_map) when is_map(tier_map) do
    # Convert map to struct-like access for compatibility
    tier_id = Map.get(tier_map, :id) || Map.get(tier_map, "id")
    quantity = Map.get(tier_map, :quantity) || Map.get(tier_map, "quantity")

    sold_count =
      Map.get(tier_map, :sold_tickets_count, 0) ||
        Map.get(tier_map, "sold_tickets_count", 0)

    available =
      case quantity do
        nil -> :unlimited
        0 -> :unlimited
        qty -> max(0, qty - sold_count)
      end

    %{
      tier_id: tier_id,
      name: Map.get(tier_map, :name) || Map.get(tier_map, "name"),
      total_quantity: quantity,
      available: available,
      sold: sold_count,
      on_sale: tier_on_sale_from_map?(tier_map),
      start_date:
        Map.get(tier_map, :start_date) || Map.get(tier_map, "start_date"),
      end_date: Map.get(tier_map, :end_date) || Map.get(tier_map, "end_date")
    }
  end

  defp tier_on_sale_from_map?(tier_map) do
    start_date =
      Map.get(tier_map, :start_date) || Map.get(tier_map, "start_date")

    if is_nil(start_date) do
      true
    else
      now = DateTime.utc_now()
      DateTime.compare(now, start_date) != :lt
    end
  end

  defp get_available_tier_quantity(%TicketTier{quantity: nil}, _user_id),
    do: :unlimited

  defp get_available_tier_quantity(%TicketTier{quantity: 0}, _user_id),
    do: :unlimited

  defp get_available_tier_quantity(
         %TicketTier{id: tier_id, quantity: total_quantity},
         user_id
       ) do
    sold_count = count_sold_tickets_for_tier(tier_id)
    reserved_count = count_reserved_tickets_for_tier(tier_id)
    available = max(0, total_quantity - sold_count - reserved_count)

    # If user has reservations, add their reserved quantity to available
    if user_id do
      user_reserved = get_user_reserved_quantity(tier_id, user_id)
      available + user_reserved
    else
      available
    end
  end

  defp get_user_reserved_quantity(tier_id, user_id) do
    TicketReservation
    |> where(
      [tr],
      tr.ticket_tier_id == ^tier_id and tr.user_id == ^user_id and
        tr.status == "active"
    )
    |> select([tr], sum(tr.quantity))
    |> Repo.one()
    |> case do
      nil -> 0
      count -> count
    end
  end

  defp count_reserved_tickets_for_tier(tier_id) do
    TicketReservation
    |> where([tr], tr.ticket_tier_id == ^tier_id and tr.status == "active")
    |> select([tr], sum(tr.quantity))
    |> Repo.one()
    |> case do
      nil -> 0
      count -> count
    end
  end

  defp user_has_reservations_for_event?(user_id, event_id) do
    TicketReservation
    |> join(:inner, [tr], tt in TicketTier, on: tr.ticket_tier_id == tt.id)
    |> where(
      [tr, tt],
      tr.user_id == ^user_id and tt.event_id == ^event_id and
        tr.status == "active"
    )
    |> Repo.exists?()
  end

  defp count_confirmed_tickets_for_event(event_id) do
    Ticket
    |> where([t], t.event_id == ^event_id and t.status == :confirmed)
    |> Repo.aggregate(:count, :id)
  end

  defp count_sold_tickets_for_tier(tier_id) do
    Ticket
    |> where(
      [t],
      t.ticket_tier_id == ^tier_id and t.status in [:confirmed, :pending]
    )
    |> Repo.aggregate(:count, :id)
  end

  defp within_event_capacity?(%Event{max_attendees: nil}, _), do: true

  defp within_event_capacity?(
         %Event{max_attendees: max_attendees} = event,
         requested_quantity
       ) do
    current_attendees = count_confirmed_tickets_for_event(event.id)
    current_attendees + requested_quantity <= max_attendees
  end

  defp tier_on_sale?(%TicketTier{start_date: nil}), do: true

  defp tier_on_sale?(%TicketTier{start_date: start_date}) do
    now = DateTime.utc_now()
    DateTime.compare(now, start_date) != :lt
  end

  defp event_in_past?(%Event{start_date: nil}), do: false

  defp event_in_past?(%Event{start_date: start_date, start_time: nil}) do
    DateTime.compare(DateTime.utc_now(), start_date) == :gt
  end

  defp event_in_past?(%Event{start_date: start_date, start_time: start_time}) do
    event_datetime = combine_date_time(start_date, start_time)
    DateTime.compare(DateTime.utc_now(), event_datetime) == :gt
  end

  defp combine_date_time(date, time) do
    case {date, time} do
      {%DateTime{} = dt, %Time{} = t} ->
        naive_date = DateTime.to_naive(dt)
        date_part = NaiveDateTime.to_date(naive_date)
        naive_datetime = NaiveDateTime.new!(date_part, t)
        DateTime.from_naive!(naive_datetime, "Etc/UTC")

      {date, time} when not is_nil(date) and not is_nil(time) ->
        NaiveDateTime.new!(date, time)
        |> DateTime.from_naive!("Etc/UTC")
    end
  end

  defp get_ticket_tier(tier_id) do
    Events.get_ticket_tier(tier_id)
  end
end
