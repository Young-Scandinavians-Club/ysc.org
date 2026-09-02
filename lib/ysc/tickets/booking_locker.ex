defmodule Ysc.Tickets.BookingLocker do
  @moduledoc """
  Provides atomic booking operations within a single database transaction.

  Capacity checks and ticket creation run in the same transaction so validation
  and inserts share one snapshot. Event/tier rows are loaded without
  `FOR UPDATE` today (see `lock_event/1` and `lock_ticket_tiers/1`), so
  concurrent transactions can still race on inventory counts under heavy load.
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

  alias Ysc.Tickets.TicketOrder
  alias Ysc.Accounts.User

  @doc """
  Atomically reserves tickets for a booking.

  This function:
  1. Loads the event and selected ticket tiers (no `FOR UPDATE` row locks yet),
     or reuses `%Event{}` / tier structs passed in `:event` / `:tiers`
  2. Validates availability
  3. Creates the ticket order and tickets
  4. All within a single transaction

  ## Parameters:
  - `user_id`: The user making the booking
  - `event_id`: The event to book for
  - `ticket_selections`: Map of tier_id => quantity

  ## Options

    * `:bypass_guards` - when `true`, skips the "event already started" check
      and each tier's sale-start window, and allows exceeding tier/event
      capacity instead of rejecting the order. For the admin/volunteer
      mobile app's in-person door sales: selling at the door is precisely
      what you do *while* an event is happening and to fix on-the-spot
      problems (a tier that was capped too low, a walk-in after the posted
      start time), so these guards — all written for the self-service web
      checkout — don't apply there. Capacity is intentionally a soft limit
      here, not skipped silently: pair this with `capacity_warnings/2` / `capacity_warnings/3`
      (call it *before* placing the order) so the admin app can show what
      it would exceed and let the seller decide. Membership/member-only-tier
      eligibility are unaffected — bypassing those is a different,
      unrequested policy change from "let the door seller override sale
      timing and capacity".
    * `:user` - `%Ysc.Accounts.User{}` already loaded for `user_id`. Ticket
      inserts reuse it for the membership check instead of selecting the
      buyer once per ticket.
    * `:event` - `%Event{}` already loaded for `event_id`. Skips the event
      SELECT; published/cancelled/in-past checks still run on the struct.
    * `:tiers` - ticket tier structs already loaded for the selection. Skips
      the tier SELECT when every selected id is present and belongs to the
      event. Pass rows loaded in the same request (door sale); do not pass
      LiveView assigns that may have gone stale while the page was open.

  ## Returns:
  - `{:ok, %TicketOrder{}}` on success
  - `{:error, reason}` on failure
  """
  def atomic_booking(user_id, event_id, ticket_selections, opts \\ []) do
    bypass_guards? = Keyword.get(opts, :bypass_guards, false)
    buyer = buyer_for_ticket_inserts(user_id, opts)

    Repo.transaction(fn ->
      with {:ok, event} <-
             lock_and_validate_event(event_id, bypass_guards?, opts),
           {:ok, tiers} <-
             lock_and_validate_tiers(
               event_id,
               ticket_selections,
               user_id,
               bypass_guards?,
               opts
             ),
           :ok <-
             (if bypass_guards? do
                :ok
              else
                validate_event_capacity(
                  event,
                  tiers,
                  ticket_selections,
                  user_id
                )
              end),
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
               event,
               tiers,
               ticket_selections,
               fulfilled_reservations_by_tier,
               bypass_guards?,
               buyer
             ) do
        ticket_order
      else
        {:error, reason} ->
          require Ysc.Logging

          Ysc.Logging.warning("BookingLocker.atomic_booking failed",
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
  Validates that ticket selections can still be fulfilled after inventory was released.

  Used when completing an expired order after a late Stripe success so we do not
  confirm tickets that would exceed tier or event capacity.
  """
  def validate_fulfillment_capacity(
        user_id,
        event_id,
        ticket_selections,
        opts \\ []
      ) do
    Repo.transaction(fn ->
      case validate_fulfillment_capacity_in_transaction(
             user_id,
             event_id,
             ticket_selections,
             opts
           ) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates fulfillment capacity inside an existing transaction.

  Keeps validation and subsequent inserts on the same snapshot, but does **not**
  acquire `FOR UPDATE` locks on event or tier rows. Callers that need to prevent
  concurrent overbooking under load should add row locks or use stricter isolation.
  """
  def validate_fulfillment_capacity_in_transaction(
        user_id,
        event_id,
        ticket_selections,
        opts \\ []
      ) do
    skip_capacity? = Keyword.get(opts, :skip_capacity, false)
    skip_sale_guards? = Keyword.get(opts, :skip_sale_guards, false)

    # Door sales / admin override already loaded and validated the event and
    # selected tiers. Reloading every tier on the event (twice — once in a
    # pre-check transaction and once inside the insert) is wasted work when
    # both sale-window and capacity checks are skipped.
    if skip_capacity? and skip_sale_guards? do
      :ok
    else
      with {:ok, event} <-
             validate_event_for_fulfillment(event_id, skip_sale_guards?),
           {:ok, tiers} <-
             validate_tiers_for_fulfillment(
               event_id,
               ticket_selections,
               user_id,
               skip_sale_guards: skip_sale_guards?,
               skip_capacity: skip_capacity?
             ) do
        if skip_capacity? do
          :ok
        else
          validate_event_capacity(event, tiers, ticket_selections, user_id)
        end
      end
    end
  end

  @doc """
  Fulfills active ticket reservations for the given selections inside a transaction.

  Links holds to `ticket_order_id` FIFO per tier, matching `atomic_booking/3`.
  Must be called within the same `Repo.transaction/1` that creates the order/tickets.
  """
  def fulfill_reservations_for_selections(
        user_id,
        event_id,
        ticket_order_id,
        ticket_selections
      ) do
    fulfill_reservations_atomic(
      user_id,
      event_id,
      ticket_order_id,
      ticket_selections
    )
  end

  @doc """
  Checks availability with proper locking for real-time display.

  This is used for UI display and should not be used for final booking validation.
  """
  def check_availability_with_lock(event_id) do
    Repo.transaction(fn ->
      event = lock_event(event_id)
      tiers = lock_ticket_tiers(event_id)

      counts = load_capacity_counts(Enum.map(tiers, & &1.id))

      %{
        event_capacity: get_event_capacity_info(event),
        tiers: Enum.map(tiers, &get_tier_availability(&1, counts))
      }
    end)
  end

  @doc """
  Best-effort, read-only check of whether `ticket_selections` would exceed
  tier or event capacity — for warning the seller *before* placing an order
  with `atomic_booking/4`'s `bypass_guards: true`, which allows exceeding
  capacity rather than rejecting it. Returns a list of human-readable
  warning strings (empty when nothing would be exceeded).

  Not authoritative and not locked: existing capacity can still change
  between this call and the actual order (another sale, a reservation
  expiring), same caveat as the rest of this module's unlocked reads. That's
  fine for a "heads up, you're about to oversell" prompt — it doesn't need
  to be race-free the way actually placing the order does.

  ## Options

    * `:event` - `%Event{}` already loaded for `event_id` (skips the event SELECT)
    * `:tiers` - ticket tier structs already loaded (skips the tier SELECT)
  """
  def capacity_warnings(event_id, ticket_selections, opts \\ []) do
    case event_for_capacity_warnings(event_id, opts) do
      nil ->
        []

      event ->
        tiers = tiers_for_capacity_warnings(event_id, opts)

        counts =
          load_capacity_counts(
            capped_inventory_tier_ids(tiers, Map.keys(ticket_selections))
          )

        tier_warnings =
          Enum.flat_map(
            ticket_selections,
            &tier_capacity_warning(tiers, counts, &1)
          )

        event_warnings = event_capacity_warning(event, tiers, ticket_selections)
        tier_warnings ++ event_warnings
    end
  end

  defp event_for_capacity_warnings(event_id, opts) do
    case Keyword.get(opts, :event) do
      %Event{id: id} = event when id == event_id -> event
      _ -> lock_event(event_id)
    end
  end

  defp tiers_for_capacity_warnings(event_id, opts) do
    case Keyword.get(opts, :tiers) do
      tiers when is_list(tiers) -> tiers
      _ -> lock_ticket_tiers(event_id)
    end
  end

  defp tier_capacity_warning(tiers, counts, {tier_id, quantity}) do
    with %TicketTier{} = tier <- Enum.find(tiers, &(&1.id == tier_id)),
         false <- TicketTierHelpers.donation_tier?(tier),
         available when available != :unlimited <-
           available_tier_quantity(tier, counts),
         true <- quantity > available do
      over = quantity - available

      [
        "#{tier.name}: selling #{quantity} exceeds the #{available} remaining by #{over}"
      ]
    else
      _ -> []
    end
  end

  defp event_capacity_warning(
         %Event{max_attendees: nil},
         _tiers,
         _ticket_selections
       ),
       do: []

  defp event_capacity_warning(
         %Event{max_attendees: max_attendees} = event,
         tiers,
         ticket_selections
       ) do
    current_attendees = count_all_tickets_for_event_locked(event.id)

    total_requested =
      Enum.reduce(ticket_selections, 0, fn {tier_id, quantity}, acc ->
        tier = Enum.find(tiers, &(&1.id == tier_id))

        if tier && TicketTierHelpers.donation_tier?(tier),
          do: acc,
          else: acc + quantity
      end)

    projected = current_attendees + total_requested

    if projected > max_attendees do
      [
        "Event capacity: selling this would bring attendance to #{projected} of #{max_attendees} max, exceeding it by #{projected - max_attendees}"
      ]
    else
      []
    end
  end

  ## Private Functions

  defp lock_and_validate_event(event_id, bypass_guards? \\ false, opts \\ []) do
    case event_for_booking(event_id, opts) do
      nil ->
        {:error, :event_not_found}

      %Event{state: :cancelled} ->
        {:error, :event_cancelled}

      %Event{state: state} when state != :published ->
        {:error, :event_not_available}

      %Event{} = event ->
        if not bypass_guards? and EventDateTime.in_past?(event) do
          {:error, :event_in_past}
        else
          {:ok, event}
        end
    end
  end

  defp lock_and_validate_tiers(
         event_id,
         ticket_selections,
         user_id,
         bypass_guards?,
         opts
       ) do
    validate_tiers_for_fulfillment(
      event_id,
      ticket_selections,
      user_id,
      skip_sale_guards: bypass_guards?,
      skip_capacity: bypass_guards?,
      tiers: Keyword.get(opts, :tiers)
    )
  end

  defp validate_event_for_fulfillment(event_id, true) do
    case lock_event(event_id) do
      nil -> {:error, :event_not_found}
      event -> {:ok, event}
    end
  end

  defp validate_event_for_fulfillment(event_id, false) do
    lock_and_validate_event(event_id)
  end

  defp validate_tiers_for_fulfillment(
         event_id,
         ticket_selections,
         user_id,
         opts
       ) do
    skip_sale_guards? = Keyword.get(opts, :skip_sale_guards, false)
    skip_capacity? = Keyword.get(opts, :skip_capacity, false)
    tiers = tiers_for_booking(event_id, ticket_selections, opts)

    counts =
      if skip_capacity? do
        empty_capacity_counts()
      else
        load_capacity_counts(
          capped_inventory_tier_ids(tiers, Map.keys(ticket_selections)),
          user_id: user_id
        )
      end

    validations =
      ticket_selections
      |> Enum.map(fn {tier_id, quantity} ->
        validate_tier_availability(
          tiers,
          tier_id,
          quantity,
          event_id,
          counts,
          skip_sale_guards: skip_sale_guards?,
          skip_capacity: skip_capacity?
        )
      end)

    if Enum.any?(validations, &(&1 != :ok)) do
      {:error, :tier_validation_failed}
    else
      {:ok, tiers}
    end
  end

  defp validate_tier_availability(
         tiers,
         tier_id,
         quantity,
         event_id,
         counts,
         opts
       ) do
    skip_sale_guards? = Keyword.get(opts, :skip_sale_guards, false)
    skip_capacity? = Keyword.get(opts, :skip_capacity, false)

    case Enum.find(tiers, &(&1.id == tier_id)) do
      nil ->
        {:error, :tier_not_found}

      tier ->
        cond do
          tier.event_id != event_id ->
            {:error, :tier_not_for_event}

          not skip_sale_guards? and
              not TicketTierHelpers.tier_sale_started?(tier) ->
            {:error, :tier_not_on_sale}

          quantity <= 0 ->
            {:error, :invalid_quantity}

          TicketTierHelpers.donation_tier?(tier) ->
            :ok

          skip_capacity? ->
            :ok

          true ->
            validate_tier_capacity(tier, quantity, counts)
        end
    end
  end

  defp validate_tier_capacity(tier, requested_quantity, counts) do
    available = available_tier_quantity(tier, counts)
    user_reserved = Map.get(counts.user_reserved, tier.id, 0)

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
        if tier && TicketTierHelpers.donation_tier?(tier) do
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

  defp event_for_booking(event_id, opts) do
    case Keyword.get(opts, :event) do
      %Event{id: id} = event when id == event_id -> event
      _ -> lock_event(event_id)
    end
  end

  defp tiers_for_booking(event_id, ticket_selections, opts) do
    selected_ids = Map.keys(ticket_selections)

    case Keyword.get(opts, :tiers) do
      tiers when is_list(tiers) ->
        if selected_tiers_complete?(tiers, selected_ids, event_id) do
          tiers
        else
          lock_selected_ticket_tiers(event_id, selected_ids)
        end

      _ ->
        lock_selected_ticket_tiers(event_id, selected_ids)
    end
  end

  defp selected_tiers_complete?(tiers, selected_ids, event_id) do
    selected = MapSet.new(selected_ids)

    loaded =
      Enum.reduce(tiers, MapSet.new(), fn
        %TicketTier{id: id, event_id: ^event_id}, acc -> MapSet.put(acc, id)
        _, acc -> acc
      end)

    MapSet.subset?(selected, loaded)
  end

  defp lock_event(event_id) do
    # Plain read — no FOR UPDATE. Concurrent transactions can observe the same counts.
    Repo.get(Event, event_id)
  end

  defp lock_ticket_tiers(event_id) do
    # Plain read — no FOR UPDATE. See module doc for concurrency caveats.
    Repo.all(ticket_tiers_for_event_query(event_id))
  end

  defp lock_selected_ticket_tiers(_event_id, []), do: []

  defp lock_selected_ticket_tiers(event_id, selected_ids) do
    # Plain read — no FOR UPDATE. See module doc for concurrency caveats.
    Repo.all(selected_ticket_tiers_query(event_id, selected_ids))
  end

  defp ticket_tiers_for_event_query(event_id) do
    from tt in TicketTier,
      where: tt.event_id == ^event_id
  end

  defp selected_ticket_tiers_query(event_id, selected_ids) do
    from tt in TicketTier,
      where: tt.event_id == ^event_id and tt.id in ^selected_ids
  end

  defp empty_capacity_counts do
    %{sold: %{}, reserved: %{}, user_reserved: %{}}
  end

  defp load_capacity_counts(tier_ids, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)

    %{
      sold: batch_count_sold_tickets_for_tiers(tier_ids),
      reserved: Events.batch_count_reserved_tickets_for_tiers(tier_ids),
      user_reserved:
        if user_id do
          batch_user_reserved_quantities(tier_ids, user_id)
        else
          %{}
        end
    }
  end

  defp capped_inventory_tier_ids(tiers, selected_ids) do
    selected = MapSet.new(selected_ids)

    Enum.flat_map(tiers, fn tier ->
      if MapSet.member?(selected, tier.id) and capped_inventory_tier?(tier) do
        [tier.id]
      else
        []
      end
    end)
  end

  defp capped_inventory_tier?(%TicketTier{} = tier) do
    not TicketTierHelpers.donation_tier?(tier) and
      is_integer(tier.quantity) and tier.quantity > 0
  end

  defp available_tier_quantity(%TicketTier{quantity: nil}, _counts),
    do: :unlimited

  defp available_tier_quantity(%TicketTier{quantity: 0}, _counts),
    do: :unlimited

  defp available_tier_quantity(
         %TicketTier{id: tier_id, quantity: total_quantity},
         counts
       ) do
    sold_count = Map.get(counts.sold, tier_id, 0)
    reserved_count = Map.get(counts.reserved, tier_id, 0)
    max(0, total_quantity - sold_count - reserved_count)
  end

  defp batch_count_sold_tickets_for_tiers([]), do: %{}

  defp batch_count_sold_tickets_for_tiers(tier_ids) do
    tier_ids
    |> batch_count_sold_tickets_for_tiers_query()
    |> Repo.all()
    |> Map.new()
  end

  defp batch_count_sold_tickets_for_tiers_query(tier_ids) do
    from(t in Ticket,
      where:
        t.ticket_tier_id in ^tier_ids and t.status in [:confirmed, :pending],
      group_by: t.ticket_tier_id,
      select: {t.ticket_tier_id, count(t.id)}
    )
  end

  defp batch_user_reserved_quantities([], _user_id), do: %{}

  defp batch_user_reserved_quantities(tier_ids, user_id) do
    tier_ids
    |> batch_user_reserved_quantities_query(user_id)
    |> Repo.all()
    |> Map.new(fn {tier_id, count} -> {tier_id, count || 0} end)
  end

  defp batch_user_reserved_quantities_query(tier_ids, user_id) do
    from(tr in TicketReservation,
      where: tr.ticket_tier_id in ^tier_ids and tr.user_id == ^user_id
    )
    |> Events.where_ticket_reservation_hold_active()
    |> group_by([tr], tr.ticket_tier_id)
    |> select([tr], {tr.ticket_tier_id, sum(tr.quantity)})
  end

  defp user_has_reservations_for_event?(user_id, event_id) do
    TicketReservation
    |> join(:inner, [tr], tt in TicketTier, on: tr.ticket_tier_id == tt.id)
    |> where([tr, tt], tr.user_id == ^user_id and tt.event_id == ^event_id)
    |> Events.where_ticket_reservation_hold_active()
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
      |> where([tr, tt], tr.user_id == ^user_id and tt.event_id == ^event_id)
      |> Events.where_ticket_reservation_hold_active()
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

    # Fulfill each hold with a conditional UPDATE so a concurrent expiry job cannot
    # be overwritten from cancelled back to fulfilled (and vice versa).
    fulfilled_reservations = elem(fulfillments, 1)

    case fulfill_reservations_in_transaction(
           fulfilled_reservations,
           ticket_order_id
         ) do
      {:ok, fulfilled} ->
        {:ok,
         Enum.group_by(fulfilled, fn {reservation, _qty} ->
           reservation.ticket_tier_id
         end)}

      {:error, _} = error ->
        error
    end
  end

  defp fulfill_reservations_in_transaction(fulfillment_plans, ticket_order_id) do
    Enum.reduce_while(fulfillment_plans, {:ok, []}, fn {reservation,
                                                        fulfill_qty},
                                                       {:ok, acc} ->
      with {:ok, reservation_to_fulfill} <-
             maybe_split_reservation_for_fulfillment(reservation, fulfill_qty),
           {:ok, updated} <-
             Events.fulfill_ticket_reservation(
               reservation_to_fulfill,
               ticket_order_id
             ) do
        {:cont, {:ok, [{updated, fulfill_qty} | acc]}}
      else
        {:error, _} ->
          {:halt, {:error, :reservation_lapsed}}
      end
    end)
  end

  defp maybe_split_reservation_for_fulfillment(reservation, fulfill_qty)
       when fulfill_qty >= reservation.quantity do
    {:ok, reservation}
  end

  defp maybe_split_reservation_for_fulfillment(reservation, fulfill_qty) do
    remainder = reservation.quantity - fulfill_qty

    with {:ok, updated} <-
           reservation
           |> Ecto.Changeset.change(quantity: fulfill_qty)
           |> Repo.update(),
         {:ok, _remainder} <-
           %TicketReservation{}
           |> TicketReservation.changeset(%{
             ticket_tier_id: reservation.ticket_tier_id,
             user_id: reservation.user_id,
             quantity: remainder,
             discount_percentage: reservation.discount_percentage,
             expires_at: reservation.expires_at,
             notes: reservation.notes,
             created_by_id: reservation.created_by_id,
             status: "active"
           })
           |> Repo.insert() do
      {:ok, updated}
    end
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
             {[{reservation, reservation_qty} | fulfilled_acc],
              remaining_qty - reservation_qty}}
          else
            # Partially fulfill: only consume the tickets the user selected
            {:halt, {[{reservation, remaining_qty} | fulfilled_acc], 0}}
          end
        end
      end)

    fulfilled_ids =
      MapSet.new(fulfilled, fn {reservation, _} -> reservation.id end)

    still_active =
      Enum.reject(reservations, fn reservation ->
        MapSet.member?(fulfilled_ids, reservation.id)
      end)

    {fulfilled, still_active}
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
    # Count both confirmed and pending tickets since pending tickets are reserved.
    # Donation tiers do not count toward event max_attendees (see validate_event_capacity/4).
    Ticket
    |> join(:inner, [t], tt in TicketTier, on: t.ticket_tier_id == tt.id)
    |> where(
      [t, tt],
      t.event_id == ^event_id and t.status in [:confirmed, :pending] and
        tt.type != :donation
    )
    |> Repo.aggregate(:count, :id)
  end

  defp get_tier_availability(%TicketTier{} = tier, counts) do
    available = available_tier_quantity(tier, counts)

    %{
      tier_id: tier.id,
      name: tier.name,
      total_quantity: tier.quantity,
      available: available,
      sold: Map.get(counts.sold, tier.id, 0),
      on_sale: TicketTierHelpers.tier_sale_started?(tier),
      start_date: tier.start_date,
      end_date: tier.end_date
    }
  end

  defp calculate_total_amount(
         tiers,
         ticket_selections,
         user_id,
         event_id,
         opts \\ []
       ) do
    # Get reservations for this user and event to calculate discounts.
    #
    # When repricing an existing order (`:include_fulfilled_for_order_id`), also
    # count reservations this order already fulfilled. Fulfillment flips a hold
    # from "active" to "fulfilled", so without this a 100%-off hold would drop
    # its discount the moment checkout fulfills it and the order would reprice to
    # full fare (both when picking the free-vs-paid path and when creating the
    # Stripe PaymentIntent).
    fulfilled_order_id = Keyword.get(opts, :include_fulfilled_for_order_id)

    reservation_scope =
      TicketReservation
      |> join(:inner, [tr], tt in TicketTier, on: tr.ticket_tier_id == tt.id)
      |> where([tr, tt], tr.user_id == ^user_id and tt.event_id == ^event_id)

    reservation_scope =
      if fulfilled_order_id do
        now = DateTime.utc_now()

        where(
          reservation_scope,
          [tr],
          (tr.status == "active" and
             (is_nil(tr.expires_at) or tr.expires_at > ^now)) or
            tr.ticket_order_id == ^fulfilled_order_id
        )
      else
        Events.where_ticket_reservation_hold_active(reservation_scope)
      end

    active_reservations =
      reservation_scope
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

  defp buyer_for_ticket_inserts(user_id, opts) do
    case Keyword.get(opts, :user) do
      %User{id: id} = user when id == user_id -> user
      _ -> Repo.get(User, user_id)
    end
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
         |> Repo.insert_with_reference_retry(TicketOrder) do
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
         event,
         tiers,
         ticket_selections,
         fulfilled_reservations_by_tier,
         bypass_guards?,
         buyer
       ) do
    buyer = Ticket.ensure_membership_preloads(buyer)

    ticket_changeset_fn = fn attrs ->
      if bypass_guards? do
        Ticket.door_sale_changeset(%Ticket{}, attrs, user: buyer)
      else
        Ticket.changeset(%Ticket{}, attrs, user: buyer, event: event)
      end
    end

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

        # Get fulfilled reservations for this tier (each entry is {reservation, fulfill_qty})
        fulfilled_reservations =
          Map.get(fulfilled_reservations_by_tier, tier_id, [])

        fulfilled_count =
          Enum.reduce(fulfilled_reservations, 0, fn {_reservation, qty}, acc ->
            acc + qty
          end)

        # Create tickets for reserved quantities (with discount)
        reserved_tickets =
          fulfilled_reservations
          |> Enum.flat_map(fn {reservation, fulfill_qty} ->
            # Calculate discount per ticket for this reservation
            per_ticket_discount =
              if reservation.discount_percentage &&
                   Decimal.gt?(reservation.discount_percentage, 0) &&
                   tier.price do
                # Calculate total discount for this reservation
                reservation_total =
                  case Money.mult(tier.price, fulfill_qty) do
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
                case Money.div(total_discount, fulfill_qty) do
                  {:ok, per_ticket} -> per_ticket
                  {:error, _} -> Money.new(0, :USD)
                end
              else
                Money.new(0, :USD)
              end

            # Create one ticket per fulfilled quantity (may be less than the original hold)
            Enum.map(1..fulfill_qty, fn _ ->
              ticket_changeset_fn.(%{
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
          if non_reserved_count <= 0 do
            []
          else
            Enum.map(1..non_reserved_count, fn _ ->
              ticket_changeset_fn.(%{
                event_id: ticket_order.event_id,
                ticket_tier_id: tier_id,
                user_id: ticket_order.user_id,
                ticket_order_id: ticket_order.id,
                status: :pending,
                expires_at: ticket_order.expires_at,
                discount_amount: Money.new(0, :USD)
              })
            end)
          end

        reserved_tickets ++ non_reserved_tickets
      end)

    # Insert all tickets (with reference_id retry on collision)
    tickets_result =
      Enum.reduce_while(tickets, {:ok, []}, fn ticket_cs, {:ok, acc} ->
        case Repo.insert_with_reference_retry(ticket_cs, Ticket) do
          {:ok, t} -> {:cont, {:ok, [t | acc]}}
          {:error, cs} -> {:halt, {:error, cs}}
        end
      end)

    case tickets_result do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      {:error, _} = err -> err
    end
  end

  defp active_reservations_for_event_ordered_query(user_id, event_id) do
    TicketReservation
    |> join(:inner, [tr], tt in TicketTier, on: tr.ticket_tier_id == tt.id)
    |> where([tr, tt], tr.user_id == ^user_id and tt.event_id == ^event_id)
    |> Events.where_ticket_reservation_hold_active()
    |> order_by([tr], asc: tr.inserted_at)
  end

  @doc """
  Estimates an order total from current tier prices and reservations.

  Used before checkout to detect stale pending orders when tier pricing changed
  after the order was created.

  ## Options

    * `:include_fulfilled_for_order_id` - also apply discounts from reservations
      already fulfilled by this order, not just active holds. Pass this when
      repricing an existing order so a fulfilled 100%-off hold keeps its
      discount.
  """
  def estimate_order_total(user_id, event_id, ticket_selections, opts \\ [])
      when is_map(ticket_selections) do
    tier_ids = Map.keys(ticket_selections)

    if tier_ids == [] do
      {:ok, Money.new(0, :USD), Money.new(0, :USD)}
    else
      tiers =
        from(t in TicketTier, where: t.id in ^tier_ids)
        |> Repo.all()

      calculate_total_amount(tiers, ticket_selections, user_id, event_id, opts)
    end
  end

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    active_reservations_for_event_ordered_query(
      Fixtures.ulid(),
      Fixtures.ulid()
    )
  end

  @doc false
  def ci_query_explain_sold_counts_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    batch_count_sold_tickets_for_tiers_query([Fixtures.ulid()])
  end

  @doc false
  def ci_query_explain_selected_tiers_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    selected_ticket_tiers_query(Fixtures.ulid(), [Fixtures.ulid()])
  end

  @doc false
  def ci_query_explain_user_reserved_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    batch_user_reserved_quantities_query([Fixtures.ulid()], Fixtures.ulid())
  end
end
