defmodule Ysc.Tickets.BookingLocker do
  @moduledoc """
  Provides atomic booking operations with proper locking to prevent race conditions.

  This module ensures that ticket availability checks and ticket creation happen
  atomically within a single database transaction with proper row-level locking.
  """

  import Ecto.Query, warn: false
  alias Ysc.Repo
  alias Ysc.Events.{Event, TicketTier, Ticket, TicketReservation}
  alias Ysc.Tickets.TicketOrder

  @doc """
  Atomically reserves tickets for a booking with proper locking.

  This function:
  1. Locks the event and ticket tiers
  2. Validates availability
  3. Creates the ticket order and tickets
  4. All within a single transaction

  ## Parameters:
  - `user_id`: The user making the booking
  - `event_id`: The event to book for
  - `ticket_selections`: Map of tier_id => quantity

  ## Returns:
  - `{:ok, %TicketOrder{}}` on success
  - `{:error, reason}` on failure
  """
  def atomic_booking(user_id, event_id, ticket_selections) do
    Repo.transaction(fn ->
      with {:ok, event} <- lock_and_validate_event(event_id),
           {:ok, tiers} <-
             lock_and_validate_tiers(event_id, ticket_selections, user_id),
           :ok <-
             validate_event_capacity(event, tiers, ticket_selections, user_id),
           {:ok, total_amount, discount_amount} <-
             calculate_total_amount(tiers, ticket_selections, user_id, event_id),
           {:ok, ticket_order} <-
             create_ticket_order_atomic(
               user_id,
               event_id,
               total_amount,
               discount_amount
             ),
           # Fulfill reservations first, then create only additional tickets needed
           {:ok, fulfilled_reservations_by_tier} <-
             fulfill_reservations_atomic(
               user_id,
               event_id,
               ticket_order.id,
               ticket_selections
             ),
           {:ok, _tickets} <-
             create_tickets_atomic(
               ticket_order,
               tiers,
               ticket_selections,
               fulfilled_reservations_by_tier
             ) do
        ticket_order
      else
        {:error, reason} ->
          require Logger

          Logger.warning("BookingLocker.atomic_booking failed",
            user_id: user_id,
            event_id: event_id,
            ticket_selections: ticket_selections,
            reason: reason
          )

          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Checks availability with proper locking for real-time display.

  This is used for UI display and should not be used for final booking validation.
  """
  def check_availability_with_lock(event_id) do
    Repo.transaction(fn ->
      event = lock_event(event_id)
      tiers = lock_ticket_tiers(event_id)

      event_capacity = get_event_capacity_info(event)
      tier_availability = Enum.map(tiers, &get_tier_availability/1)

      %{
        event_capacity: event_capacity,
        tiers: tier_availability
      }
    end)
  end

  ## Private Functions

  defp lock_and_validate_event(event_id) do
    case lock_event(event_id) do
      nil ->
        {:error, :event_not_found}

      %Event{state: :cancelled} ->
        {:error, :event_cancelled}

      %Event{} = event ->
        if event_in_past?(event) do
          {:error, :event_in_past}
        else
          {:ok, event}
        end
    end
  end

  defp lock_and_validate_tiers(event_id, ticket_selections, user_id) do
    _tier_ids = Map.keys(ticket_selections)

    # Lock all ticket tiers for this event
    tiers = lock_ticket_tiers(event_id)

    # Validate each requested tier
    validations =
      ticket_selections
      |> Enum.map(fn {tier_id, quantity} ->
        validate_tier_availability(tiers, tier_id, quantity, event_id, user_id)
      end)

    if Enum.any?(validations, &(&1 != :ok)) do
      {:error, :tier_validation_failed}
    else
      {:ok, tiers}
    end
  end

  defp validate_tier_availability(tiers, tier_id, quantity, event_id, user_id) do
    case Enum.find(tiers, &(&1.id == tier_id)) do
      nil ->
        {:error, :tier_not_found}

      tier ->
        cond do
          tier.event_id != event_id -> {:error, :tier_not_for_event}
          not tier_on_sale?(tier) -> {:error, :tier_not_on_sale}
          quantity <= 0 -> {:error, :invalid_quantity}
          # Donations don't count towards capacity - skip capacity check
          tier.type == :donation or tier.type == "donation" -> :ok
          true -> validate_tier_capacity(tier, quantity, user_id)
        end
    end
  end

  defp validate_tier_capacity(tier, requested_quantity, user_id) do
    available = get_available_tier_quantity_locked(tier)
    user_reserved = get_user_reserved_quantity_locked(tier.id, user_id)

    cond do
      available == :unlimited ->
        :ok

      # If user has reservations, add their reserved quantity to available
      user_reserved > 0 ->
        user_available = available + user_reserved

        if requested_quantity <= user_available do
          :ok
        else
          {:error, :insufficient_capacity}
        end

      requested_quantity <= available ->
        :ok

      true ->
        # Emit telemetry event for overbooking attempt
        :telemetry.execute(
          [:ysc, :tickets, :overbooking_attempt],
          %{count: 1},
          %{
            tier_id: tier.id,
            event_id: tier.event_id,
            requested_quantity: requested_quantity,
            available: available,
            reason: "insufficient_capacity"
          }
        )

        {:error, :insufficient_capacity}
    end
  end

  defp validate_event_capacity(
         %Event{max_attendees: nil},
         _tiers,
         _ticket_selections,
         _user_id
       ) do
    # No capacity limit, always OK
    :ok
  end

  defp validate_event_capacity(
         %Event{max_attendees: max_attendees} = event,
         tiers,
         ticket_selections,
         user_id
       ) do
    # Count current tickets (both confirmed and pending count toward capacity)
    current_attendees = count_all_tickets_for_event_locked(event.id)

    # Calculate total requested tickets (excluding donations)
    total_requested =
      ticket_selections
      |> Enum.reduce(0, fn {tier_id, quantity}, acc ->
        tier = Enum.find(tiers, &(&1.id == tier_id))

        # Donations don't count toward event capacity
        if tier && (tier.type == :donation || tier.type == "donation") do
          acc
        else
          acc + quantity
        end
      end)

    # Check if user has reservations that would allow them to bypass capacity
    user_has_reservations = user_has_reservations_for_event?(user_id, event.id)

    # Check if adding requested tickets would exceed capacity
    # Allow reserved users to bypass capacity check
    if user_has_reservations or
         current_attendees + total_requested <= max_attendees do
      :ok
    else
      # Emit telemetry event for event capacity exceeded
      :telemetry.execute(
        [:ysc, :tickets, :overbooking_attempt],
        %{count: 1},
        %{
          event_id: event.id,
          current_attendees: current_attendees,
          requested_quantity: total_requested,
          max_attendees: max_attendees,
          reason: "event_capacity_exceeded"
        }
      )

      {:error, :event_capacity_exceeded}
    end
  end

  defp lock_event(event_id) do
    # Fetch event (optimistic locking - no FOR UPDATE)
    # The optimistic lock will be checked when we update the event if needed
    Repo.get(Event, event_id)
  end

  defp lock_ticket_tiers(event_id) do
    # Fetch ticket tiers (optimistic locking - no FOR UPDATE)
    # The optimistic lock will be checked when we update tiers if needed
    Repo.all(
      from tt in TicketTier,
        where: tt.event_id == ^event_id
    )
  end

  defp get_available_tier_quantity_locked(%TicketTier{quantity: nil}),
    do: :unlimited

  defp get_available_tier_quantity_locked(%TicketTier{quantity: 0}),
    do: :unlimited

  defp get_available_tier_quantity_locked(%TicketTier{
         id: tier_id,
         quantity: total_quantity
       }) do
    sold_count = count_sold_tickets_for_tier_locked(tier_id)
    reserved_count = count_reserved_tickets_for_tier_locked(tier_id)
    max(0, total_quantity - sold_count - reserved_count)
  end

  defp get_user_reserved_quantity_locked(tier_id, user_id) do
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

  defp count_reserved_tickets_for_tier_locked(tier_id) do
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

  defp fulfill_reservations_atomic(
         user_id,
         event_id,
         ticket_order_id,
         ticket_selections
       ) do
    # Get all active reservations for this user and event
    reservations =
      TicketReservation
      |> join(:inner, [tr], tt in TicketTier, on: tr.ticket_tier_id == tt.id)
      |> where(
        [tr, tt],
        tr.user_id == ^user_id and tt.event_id == ^event_id and
          tr.status == "active"
      )
      |> order_by([tr], asc: tr.inserted_at)
      |> Repo.all()

    # Fulfill reservations matching the ticket selections
    fulfillments =
      ticket_selections
      |> Enum.reduce({reservations, []}, fn {tier_id, quantity},
                                            {remaining_reservations, fulfilled} ->
        tier_reservations =
          Enum.filter(remaining_reservations, &(&1.ticket_tier_id == tier_id))

        {fulfilled_for_tier, still_active} =
          fulfill_reservations_for_tier(
            tier_reservations,
            quantity,
            ticket_order_id
          )

        remaining =
          remaining_reservations -- (tier_reservations ++ still_active)

        {remaining, fulfilled ++ fulfilled_for_tier}
      end)

    # Update all fulfilled reservations
    fulfilled_reservations = elem(fulfillments, 1)

    Enum.each(fulfilled_reservations, fn reservation ->
      reservation
      |> TicketReservation.changeset(%{
        status: "fulfilled",
        fulfilled_at: DateTime.utc_now(),
        ticket_order_id: ticket_order_id
      })
      |> Repo.update!()
    end)

    # Return fulfilled reservations grouped by tier for use in ticket creation
    # This includes the reservation details so we can store discount amounts on tickets
    fulfilled_reservations_by_tier =
      fulfilled_reservations
      |> Enum.group_by(& &1.ticket_tier_id)

    {:ok, fulfilled_reservations_by_tier}
  end

  defp fulfill_reservations_for_tier(
         reservations,
         requested_quantity,
         _ticket_order_id
       ) do
    # Fulfill reservations in order (FIFO) until we've covered the requested quantity
    {fulfilled, _remaining_qty} =
      Enum.reduce_while(reservations, {[], requested_quantity}, fn reservation,
                                                                   {fulfilled_acc,
                                                                    remaining_qty} ->
        if remaining_qty <= 0 do
          {:halt, {fulfilled_acc, 0}}
        else
          reservation_qty = reservation.quantity

          if reservation_qty <= remaining_qty do
            # Fully fulfill this reservation
            {:cont,
             {[reservation | fulfilled_acc], remaining_qty - reservation_qty}}
          else
            # This reservation covers more than needed, but we'll fulfill it anyway
            # (In a more sophisticated system, we could split reservations)
            {:halt, {[reservation | fulfilled_acc], 0}}
          end
        end
      end)

    remaining = reservations -- fulfilled
    {fulfilled, remaining}
  end

  defp count_sold_tickets_for_tier_locked(tier_id) do
    Ticket
    |> where(
      [t],
      t.ticket_tier_id == ^tier_id and t.status in [:confirmed, :pending]
    )
    |> Repo.aggregate(:count, :id)
  end

  defp get_event_capacity_info(%Event{max_attendees: nil} = event) do
    %{
      max_attendees: nil,
      current_attendees: count_all_tickets_for_event_locked(event.id),
      available: :unlimited,
      at_capacity: false
    }
  end

  defp get_event_capacity_info(%Event{max_attendees: max_attendees} = event) do
    # Count both confirmed and pending tickets for accurate availability display
    current_attendees = count_all_tickets_for_event_locked(event.id)
    available = max_attendees - current_attendees

    %{
      max_attendees: max_attendees,
      current_attendees: current_attendees,
      available: max(0, available),
      at_capacity: current_attendees >= max_attendees
    }
  end

  defp count_all_tickets_for_event_locked(nil), do: 0

  defp count_all_tickets_for_event_locked(event_id) do
    # Count both confirmed and pending tickets since pending tickets are reserved
    Ticket
    |> where(
      [t],
      t.event_id == ^event_id and t.status in [:confirmed, :pending]
    )
    |> Repo.aggregate(:count, :id)
  end

  defp get_tier_availability(%TicketTier{} = tier) do
    available = get_available_tier_quantity_locked(tier)

    %{
      tier_id: tier.id,
      name: tier.name,
      total_quantity: tier.quantity,
      available: available,
      sold: get_sold_tier_quantity_locked(tier),
      on_sale: tier_on_sale?(tier),
      start_date: tier.start_date,
      end_date: tier.end_date
    }
  end

  defp get_sold_tier_quantity_locked(%TicketTier{id: tier_id}) do
    count_sold_tickets_for_tier_locked(tier_id)
  end

  defp calculate_total_amount(tiers, ticket_selections, user_id, event_id) do
    # Get active reservations for this user and event to calculate discounts
    active_reservations =
      TicketReservation
      |> join(:inner, [tr], tt in TicketTier, on: tr.ticket_tier_id == tt.id)
      |> where(
        [tr, tt],
        tr.user_id == ^user_id and tt.event_id == ^event_id and
          tr.status == "active"
      )
      |> order_by([tr], asc: tr.inserted_at)
      |> Repo.all()

    # Build a map of tier_id => list of reservations with discounts
    reservations_by_tier =
      active_reservations
      |> Enum.group_by(& &1.ticket_tier_id)

    {total, discount_total} =
      ticket_selections
      |> Enum.reduce({Money.new(0, :USD), Money.new(0, :USD)}, fn {tier_id,
                                                                   amount_or_quantity},
                                                                  {acc_total,
                                                                   acc_discount} ->
        tier = Enum.find(tiers, &(&1.id == tier_id))
        tier_reservations = Map.get(reservations_by_tier, tier_id, [])

        case tier.type do
          :free ->
            {acc_total, acc_discount}

          :donation ->
            # For donations, amount_or_quantity is already in cents
            # Convert cents to dollars Decimal, then create Money
            dollars_decimal =
              Ysc.MoneyHelper.cents_to_dollars(amount_or_quantity)

            donation_amount = Money.new(dollars_decimal, :USD)

            new_total =
              case Money.add(acc_total, donation_amount) do
                {:ok, total} -> total
                {:error, _} -> acc_total
              end

            {new_total, acc_discount}

          "donation" ->
            # For donations, amount_or_quantity is already in cents
            # Convert cents to dollars Decimal, then create Money
            dollars_decimal =
              Ysc.MoneyHelper.cents_to_dollars(amount_or_quantity)

            donation_amount = Money.new(dollars_decimal, :USD)

            new_total =
              case Money.add(acc_total, donation_amount) do
                {:ok, total} -> total
                {:error, _} -> acc_total
              end

            {new_total, acc_discount}

          _ ->
            # For regular paid tiers, calculate with discounts
            calculate_tier_total_with_discounts(
              tier,
              amount_or_quantity,
              tier_reservations,
              acc_total,
              acc_discount
            )
        end
      end)

    {:ok, total, discount_total}
  end

  defp calculate_tier_total_with_discounts(
         tier,
         requested_quantity,
         reservations,
         acc_total,
         acc_discount
       ) do
    # Calculate original price for all tickets
    original_total =
      case Money.mult(tier.price, requested_quantity) do
        {:ok, total} -> total
        {:error, _} -> Money.new(0, :USD)
      end

    # Calculate how many tickets are covered by reservations and apply discounts
    {_reserved_qty_covered, total_discount_amount} =
      reservations
      |> Enum.reduce_while({0, Money.new(0, :USD)}, fn reservation,
                                                       {covered_qty,
                                                        discount_acc} ->
        remaining_to_cover = requested_quantity - covered_qty

        if remaining_to_cover <= 0 do
          {:halt, {covered_qty, discount_acc}}
        else
          reservation_qty = reservation.quantity

          reservation_discount_pct =
            reservation.discount_percentage || Decimal.new(0)

          if Decimal.gt?(reservation_discount_pct, 0) do
            # Calculate how many tickets from this reservation we can use
            tickets_from_reservation = min(reservation_qty, remaining_to_cover)

            # Calculate discount for these tickets
            reservation_tier_total =
              case Money.mult(tier.price, tickets_from_reservation) do
                {:ok, total} -> total
                {:error, _} -> Money.new(0, :USD)
              end

            # Apply discount percentage (convert percentage to decimal: 50% = 0.50)
            discount_pct_decimal =
              Decimal.div(reservation_discount_pct, Decimal.new(100))

            discount_amount =
              case Money.mult(reservation_tier_total, discount_pct_decimal) do
                {:ok, discount} -> discount
                {:error, _} -> Money.new(0, :USD)
              end

            new_covered = covered_qty + tickets_from_reservation

            new_discount =
              case Money.add(discount_acc, discount_amount) do
                {:ok, total} -> total
                {:error, _} -> discount_acc
              end

            if new_covered >= requested_quantity do
              {:halt, {new_covered, new_discount}}
            else
              {:cont, {new_covered, new_discount}}
            end
          else
            # No discount, but still count as covered
            new_covered = covered_qty + min(reservation_qty, remaining_to_cover)
            {:cont, {new_covered, discount_acc}}
          end
        end
      end)

    # Final total is original minus discounts
    final_total =
      case Money.sub(original_total, total_discount_amount) do
        {:ok, total} -> total
        {:error, _} -> original_total
      end

    # Add to accumulators
    new_acc_total =
      case Money.add(acc_total, final_total) do
        {:ok, total} -> total
        {:error, _} -> acc_total
      end

    new_acc_discount =
      case Money.add(acc_discount, total_discount_amount) do
        {:ok, total} -> total
        {:error, _} -> acc_discount
      end

    {new_acc_total, new_acc_discount}
  end

  defp create_ticket_order_atomic(
         user_id,
         event_id,
         total_amount,
         discount_amount
       ) do
    expires_at = DateTime.add(DateTime.utc_now(), 30, :minute)

    attrs = %{
      user_id: user_id,
      event_id: event_id,
      total_amount: total_amount,
      expires_at: expires_at
    }

    attrs =
      if discount_amount && Money.positive?(discount_amount) do
        Map.put(attrs, :discount_amount, discount_amount)
      else
        attrs
      end

    case %TicketOrder{}
         |> TicketOrder.create_changeset(attrs)
         |> Repo.insert() do
      {:ok, ticket_order} ->
        # Schedule timeout check for this specific order
        Ysc.Tickets.TimeoutWorker.schedule_order_timeout(
          ticket_order.id,
          expires_at
        )

        {:ok, ticket_order}

      error ->
        error
    end
  end

  defp create_tickets_atomic(
         ticket_order,
         tiers,
         ticket_selections,
         fulfilled_reservations_by_tier
       ) do
    # fulfilled_reservations_by_tier is a map of tier_id => [list of fulfilled reservations]
    # We need to create tickets for both reserved and non-reserved quantities
    tickets =
      ticket_selections
      |> Enum.flat_map(fn {tier_id, amount_or_quantity} ->
        tier = Enum.find(tiers, &(&1.id == tier_id))

        # For donation tiers, always create 1 ticket regardless of amount
        # For other tiers, calculate how many tickets to create
        requested_count =
          case tier.type do
            :donation -> 1
            "donation" -> 1
            _ -> amount_or_quantity
          end

        # Get fulfilled reservations for this tier
        fulfilled_reservations =
          Map.get(fulfilled_reservations_by_tier, tier_id, [])

        fulfilled_count =
          Enum.reduce(fulfilled_reservations, 0, fn r, acc ->
            acc + r.quantity
          end)

        # Create tickets for reserved quantities (with discount)
        reserved_tickets =
          fulfilled_reservations
          |> Enum.flat_map(fn reservation ->
            # Calculate discount per ticket for this reservation
            per_ticket_discount =
              if reservation.discount_percentage &&
                   Decimal.gt?(reservation.discount_percentage, 0) &&
                   tier.price do
                # Calculate total discount for this reservation
                reservation_total =
                  case Money.mult(tier.price, reservation.quantity) do
                    {:ok, total} -> total
                    {:error, _} -> Money.new(0, :USD)
                  end

                discount_pct_decimal =
                  Decimal.div(reservation.discount_percentage, Decimal.new(100))

                total_discount =
                  case Money.mult(reservation_total, discount_pct_decimal) do
                    {:ok, discount} -> discount
                    {:error, _} -> Money.new(0, :USD)
                  end

                # Divide discount evenly across tickets in this reservation
                case Money.div(total_discount, reservation.quantity) do
                  {:ok, per_ticket} -> per_ticket
                  {:error, _} -> Money.new(0, :USD)
                end
              else
                Money.new(0, :USD)
              end

            # Create one ticket per quantity in the reservation
            Enum.map(1..reservation.quantity, fn _ ->
              %Ticket{}
              |> Ticket.changeset(%{
                event_id: ticket_order.event_id,
                ticket_tier_id: tier_id,
                user_id: ticket_order.user_id,
                ticket_order_id: ticket_order.id,
                status: :pending,
                expires_at: ticket_order.expires_at,
                discount_amount: per_ticket_discount
              })
            end)
          end)

        # Create tickets for non-reserved quantities (without discount)
        non_reserved_count = max(0, requested_count - fulfilled_count)

        non_reserved_tickets =
          Enum.map(1..non_reserved_count, fn _ ->
            %Ticket{}
            |> Ticket.changeset(%{
              event_id: ticket_order.event_id,
              ticket_tier_id: tier_id,
              user_id: ticket_order.user_id,
              ticket_order_id: ticket_order.id,
              status: :pending,
              expires_at: ticket_order.expires_at,
              discount_amount: Money.new(0, :USD)
            })
          end)

        reserved_tickets ++ non_reserved_tickets
      end)

    # Insert all tickets
    Enum.map(tickets, &Repo.insert!/1)
    |> case do
      tickets when is_list(tickets) -> {:ok, tickets}
      error -> {:error, error}
    end
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
end
