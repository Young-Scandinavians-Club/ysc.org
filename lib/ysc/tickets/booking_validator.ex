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
  alias Ysc.Events.{
    Event,
    EventDateTime,
    TicketTier,
    Ticket,
    TicketReservation,
    TicketTierHelpers
  }
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
    tiers_by_id = batch_load_tiers(Map.keys(ticket_selections))

    with :ok <- validate_user(user_id),
         :ok <- validate_event(event_id),
         :ok <-
           validate_ticket_selections(event_id, ticket_selections, tiers_by_id),
         :ok <-
           validate_capacity(event_id, ticket_selections, user_id, tiers_by_id) do
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

      %Event{state: state} when state != :published ->
        {:error, :event_not_available}

      %Event{} = event ->
        if EventDateTime.in_past?(event) do
          {:error, :event_in_past}
        else
          :ok
        end
    end
  end

  defp validate_ticket_selections(_event_id, ticket_selections, _tiers_by_id)
       when ticket_selections == %{} do
    {:error, :no_tickets_selected}
  end

  defp validate_ticket_selections(event_id, ticket_selections, tiers_by_id) do
    tier_validations =
      Enum.map(ticket_selections, fn {tier_id, quantity} ->
        validate_tier_selection(event_id, tier_id, quantity, tiers_by_id)
      end)

    if Enum.any?(tier_validations, &(&1 != :ok)) do
      {:error, :invalid_tier_selection}
    else
      :ok
    end
  end

  defp validate_tier_selection(event_id, tier_id, quantity, tiers_by_id) do
    case Map.get(tiers_by_id, tier_id) do
      nil ->
        {:error, :tier_not_found}

      tier ->
        cond do
          tier.event_id != event_id ->
            {:error, :tier_not_for_event}

          not TicketTierHelpers.tier_sale_started?(tier) ->
            {:error, :tier_not_on_sale}

          quantity <= 0 ->
            {:error, :invalid_quantity}

          true ->
            :ok
        end
    end
  end

  defp validate_capacity(event_id, ticket_selections, user_id, tiers_by_id) do
    event = Events.get_event!(event_id)

    # Check if user has reservations that would allow bypassing capacity
    user_has_reservations = user_has_reservations_for_event?(user_id, event_id)

    non_donation_tier_ids =
      non_donation_tier_ids(ticket_selections, tiers_by_id)

    sold_counts = batch_count_sold_tickets_for_tiers(non_donation_tier_ids)

    reserved_counts =
      batch_count_reserved_tickets_for_tiers(non_donation_tier_ids)

    user_reserved_counts =
      if user_id do
        batch_user_reserved_quantities(non_donation_tier_ids, user_id)
      else
        %{}
      end

    non_donation_qty =
      non_donation_ticket_quantity(ticket_selections, tiers_by_id)

    # Check if event is already at capacity (unless user has reservations or only donations)
    if not user_has_reservations and non_donation_qty > 0 and
         event_at_capacity?(event) do
      {:error, :event_at_capacity}
    else
      # Check each tier capacity (donation tiers skip tier/event capacity)
      tier_capacity_validations =
        Enum.map(ticket_selections, fn {tier_id, quantity} ->
          case Map.get(tiers_by_id, tier_id) do
            tier ->
              if TicketTierHelpers.donation_tier?(tier) do
                :ok
              else
                check_tier_capacity_with_context(
                  tier,
                  quantity,
                  user_id,
                  sold_counts,
                  reserved_counts,
                  user_reserved_counts
                )
              end
          end
        end)

      if Enum.any?(
           tier_capacity_validations,
           &(&1 == {:error, :insufficient_capacity})
         ) do
        {:error, :tier_capacity_exceeded}
      else
        if user_has_reservations or
             within_event_capacity?(event, non_donation_qty) do
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
      on_sale: TicketTierHelpers.tier_sale_started?(tier_map),
      start_date:
        Map.get(tier_map, :start_date) || Map.get(tier_map, "start_date"),
      end_date: Map.get(tier_map, :end_date) || Map.get(tier_map, "end_date")
    }
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
    |> where([tr], tr.ticket_tier_id == ^tier_id and tr.user_id == ^user_id)
    |> Events.where_ticket_reservation_hold_active()
    |> select([tr], sum(tr.quantity))
    |> Repo.one()
    |> case do
      nil -> 0
      count -> count
    end
  end

  defp count_reserved_tickets_for_tier(tier_id) do
    TicketReservation
    |> where([tr], tr.ticket_tier_id == ^tier_id)
    |> Events.where_ticket_reservation_hold_active()
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
    |> where([tr, tt], tr.user_id == ^user_id and tt.event_id == ^event_id)
    |> Events.where_ticket_reservation_hold_active()
    |> Repo.exists?()
  end

  defp count_confirmed_tickets_for_event(nil), do: 0

  defp count_confirmed_tickets_for_event(event_id) do
    Events.count_tickets_sold_excluding_donations(event_id)
  end

  defp non_donation_ticket_quantity(ticket_selections, tiers_by_id) do
    Enum.reduce(ticket_selections, 0, fn {tier_id, quantity}, acc ->
      tier = Map.get(tiers_by_id, tier_id)

      if TicketTierHelpers.donation_tier?(tier) do
        acc
      else
        acc + quantity
      end
    end)
  end

  defp non_donation_tier_ids(ticket_selections, tiers_by_id) do
    ticket_selections
    |> Enum.flat_map(fn {tier_id, _quantity} ->
      tier = Map.get(tiers_by_id, tier_id)

      if TicketTierHelpers.donation_tier?(tier) do
        []
      else
        [tier_id]
      end
    end)
  end

  defp check_tier_capacity_with_context(
         tier,
         requested_quantity,
         user_id,
         sold_counts,
         reserved_counts,
         user_reserved_counts
       ) do
    available =
      get_available_tier_quantity_with_counts(
        tier,
        user_id,
        sold_counts,
        reserved_counts,
        user_reserved_counts
      )

    cond do
      available == :unlimited ->
        :ok

      requested_quantity <= available ->
        :ok

      true ->
        {:error, :insufficient_capacity}
    end
  end

  defp get_available_tier_quantity_with_counts(
         %TicketTier{quantity: nil},
         _user_id,
         _sold_counts,
         _reserved_counts,
         _user_reserved_counts
       ),
       do: :unlimited

  defp get_available_tier_quantity_with_counts(
         %TicketTier{quantity: 0},
         _user_id,
         _sold_counts,
         _reserved_counts,
         _user_reserved_counts
       ),
       do: :unlimited

  defp get_available_tier_quantity_with_counts(
         %TicketTier{id: tier_id, quantity: total_quantity},
         user_id,
         sold_counts,
         reserved_counts,
         user_reserved_counts
       ) do
    sold_count = Map.get(sold_counts, tier_id, 0)
    reserved_count = Map.get(reserved_counts, tier_id, 0)
    available = max(0, total_quantity - sold_count - reserved_count)

    if user_id do
      available + Map.get(user_reserved_counts, tier_id, 0)
    else
      available
    end
  end

  defp batch_load_tiers([]), do: %{}

  defp batch_load_tiers(tier_ids) do
    from(tt in TicketTier, where: tt.id in ^tier_ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp batch_count_sold_tickets_for_tiers([]), do: %{}

  defp batch_count_sold_tickets_for_tiers(tier_ids) do
    from(t in Ticket,
      where:
        t.ticket_tier_id in ^tier_ids and t.status in [:confirmed, :pending],
      group_by: t.ticket_tier_id,
      select: {t.ticket_tier_id, count(t.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp batch_count_reserved_tickets_for_tiers([]), do: %{}

  defp batch_count_reserved_tickets_for_tiers(tier_ids) do
    from(tr in TicketReservation, where: tr.ticket_tier_id in ^tier_ids)
    |> Events.where_ticket_reservation_hold_active()
    |> group_by([tr], tr.ticket_tier_id)
    |> select([tr], {tr.ticket_tier_id, sum(tr.quantity)})
    |> Repo.all()
    |> Map.new(fn {tier_id, count} -> {tier_id, count || 0} end)
  end

  defp batch_user_reserved_quantities([], _user_id), do: %{}

  defp batch_user_reserved_quantities(tier_ids, user_id) do
    from(tr in TicketReservation,
      where: tr.ticket_tier_id in ^tier_ids and tr.user_id == ^user_id
    )
    |> Events.where_ticket_reservation_hold_active()
    |> group_by([tr], tr.ticket_tier_id)
    |> select([tr], {tr.ticket_tier_id, sum(tr.quantity)})
    |> Repo.all()
    |> Map.new(fn {tier_id, count} -> {tier_id, count || 0} end)
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

  defp get_ticket_tier(tier_id) do
    Events.get_ticket_tier(tier_id)
  end

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    user_id = Fixtures.ulid()
    event_id = Fixtures.ulid()

    TicketReservation
    |> join(:inner, [tr], tt in TicketTier, on: tr.ticket_tier_id == tt.id)
    |> where([tr, tt], tr.user_id == ^user_id and tt.event_id == ^event_id)
    |> Events.where_ticket_reservation_hold_active()
  end
end
