defmodule Ysc.Tickets do
  @moduledoc """
  The Tickets context for managing ticket orders and individual tickets.

  This module provides utilities for:
  - Creating ticket orders with multiple tickets
  - Validating booking capacity and preventing overbooking
  - Processing payments with Stripe integration
  - Managing 15-minute payment timeouts
  - Handling ticket order lifecycle
  """

  import Ecto.Query, warn: false
  alias Ysc.Repo

  alias Ysc.Tickets.TicketOrder
  alias Ysc.Tickets.BookingLocker
  alias Ysc.Events.Ticket
  alias Ysc.Events.TicketTier
  alias Ysc.Events.Event
  alias Ysc.Accounts
  alias Ysc.Ledgers

  @payment_timeout_minutes 15

  ## Ticket Order Management

  @doc """
  Creates a new ticket order with multiple tickets.

  This function:
  - Validates user membership
  - Cancels older pending orders for the user (keeps newest session)
  - Uses atomic booking to prevent overbooking
  - Creates tickets with pending status
  - Schedules timeout cleanup

  ## Parameters:
  - `user_id`: The user purchasing tickets
  - `event_id`: The event being purchased for
  - `ticket_selections`: Map of ticket_tier_id => quantity

  ## Returns:
  - `{:ok, %TicketOrder{}}` on success
  - `{:error, changeset}` on validation failure
  - `{:error, :overbooked}` if event or tier capacity exceeded
  - `{:error, :event_capacity_exceeded}` if event's global max_attendees limit would be exceeded
  - `{:error, :event_not_available}` if event is not available for purchase
  - `{:error, :membership_required}` if user doesn't have active membership
  """
  def create_ticket_order(user_id, event_id, ticket_selections) do
    require Logger

    Logger.info("Creating ticket order",
      user_id: user_id,
      event_id: event_id,
      ticket_selections: ticket_selections
    )

    case validate_user_membership(user_id) do
      {:ok, _} ->
        # Note: Ticket bookings don't update tiers/events, so optimistic locking isn't used here
        # Capacity is checked by counting existing tickets within the transaction
        case BookingLocker.atomic_booking(user_id, event_id, ticket_selections) do
          {:ok, ticket_order} ->
            # Emit telemetry event for ticket order creation
            ticket_count =
              if Ecto.assoc_loaded?(ticket_order.tickets) do
                length(ticket_order.tickets)
              else
                0
              end

            :telemetry.execute(
              [:ysc, :tickets, :order_created],
              %{count: 1},
              %{
                ticket_order_id: ticket_order.id,
                event_id: event_id,
                user_id: user_id,
                total_amount: Money.to_decimal(ticket_order.total_amount),
                ticket_count: ticket_count
              }
            )

            # Broadcast ticket availability update to all users viewing this event
            broadcast_ticket_availability_update(event_id)
            {:ok, ticket_order}

          error ->
            error
        end

      error ->
        require Logger

        Logger.warning("Failed to create ticket order",
          user_id: user_id,
          event_id: event_id,
          ticket_selections: ticket_selections,
          error: error
        )

        error
    end
  end

  @doc """
  Gets a ticket order by ID with preloaded tickets.
  """
  def get_ticket_order(id) do
    TicketOrder
    |> where([to], to.id == ^id)
    |> preload([
      :user,
      event: [agendas: :agenda_items],
      payment: :payment_method,
      tickets: :ticket_tier
    ])
    |> Repo.one()
  end

  @doc """
  Gets a ticket order by payment ID with preloaded associations.
  """
  def get_ticket_order_by_payment_id(payment_id) do
    from(to in TicketOrder,
      where: to.payment_id == ^payment_id,
      limit: 1,
      preload: [:user, event: [], tickets: :ticket_tier]
    )
    |> Repo.one()
  end

  def get_ticket_order_by_reference(reference_id) do
    TicketOrder
    |> where([to], to.reference_id == ^reference_id)
    |> preload([
      :user,
      :event,
      payment: :payment_method,
      tickets: :ticket_tier
    ])
    |> Repo.one()
  end

  @doc """
  Gets a ticket order by ID for a specific user with preloaded tickets.

  This function filters by user_id to ensure users can only access their own ticket orders.
  Use this instead of `get_ticket_order/1` for user-facing operations.
  """
  def get_user_ticket_order(user_id, order_id) do
    from(to in TicketOrder,
      where: to.id == ^order_id and to.user_id == ^user_id,
      preload: [
        :user,
        event: [agendas: :agenda_items],
        payment: :payment_method,
        tickets: :ticket_tier
      ]
    )
    |> Repo.one()
  end

  @doc """
  Gets a ticket order by payment ID for a specific user with preloaded associations.

  This function filters by user_id to ensure users can only access their own ticket orders.
  Use this instead of `get_ticket_order_by_payment_id/1` for user-facing operations.
  """
  def get_user_ticket_order_by_payment_id(user_id, payment_id) do
    from(to in TicketOrder,
      where: to.payment_id == ^payment_id and to.user_id == ^user_id,
      limit: 1,
      preload: [:user, event: [], tickets: :ticket_tier]
    )
    |> Repo.one()
  end

  @doc """
  Gets a ticket order by reference ID for a specific user with preloaded associations.

  This function filters by user_id to ensure users can only access their own ticket orders.
  Use this instead of `get_ticket_order_by_reference/1` for user-facing operations.
  """
  def get_user_ticket_order_by_reference(user_id, reference_id) do
    from(to in TicketOrder,
      where: to.reference_id == ^reference_id and to.user_id == ^user_id,
      preload: [
        :user,
        :event,
        payment: :payment_method,
        tickets: :ticket_tier
      ]
    )
    |> Repo.one()
  end

  @doc """
  Gets all ticket orders for a user.
  """
  def list_user_ticket_orders(user_id) do
    TicketOrder
    |> where([to], to.user_id == ^user_id)
    |> order_by([to], desc: to.inserted_at)
    |> preload([:tickets, :event, tickets: :ticket_tier])
    |> Repo.all()
  end

  @doc """
  Gets paginated ticket orders for a user with Flop.
  """
  def list_user_ticket_orders_paginated(user_id, params) do
    base_query =
      from(to in TicketOrder,
        where: to.user_id == ^user_id,
        preload: [:tickets, :event, :payment, tickets: :ticket_tier]
      )

    case Flop.validate_and_run(base_query, params, for: TicketOrder) do
      {:ok, {orders, meta}} ->
        {:ok, {orders, meta}}

      error ->
        error
    end
  end

  @doc """
  Gets all confirmed tickets for a user for a specific event.
  """
  def list_user_tickets_for_event(user_id, event_id) do
    Ticket
    |> where(
      [t],
      t.user_id == ^user_id and t.event_id == ^event_id and
        t.status == :confirmed
    )
    |> order_by([t], desc: t.inserted_at)
    |> preload([:ticket_tier, :ticket_order])
    |> Repo.all()
  end

  @doc """
  Updates a ticket order's payment intent ID.
  """
  def update_payment_intent(ticket_order, payment_intent_id) do
    ticket_order
    |> TicketOrder.payment_changeset(%{payment_intent_id: payment_intent_id})
    |> Repo.update()
  end

  @doc """
  Marks a ticket order as completed after successful payment.
  """
  def complete_ticket_order(ticket_order, payment_id) do
    ticket_order
    |> TicketOrder.status_changeset(%{
      status: :completed,
      payment_id: payment_id,
      completed_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Cancels a ticket order and releases the reserved tickets.
  """
  def cancel_ticket_order(ticket_order, reason \\ "User cancelled") do
    result =
      Repo.transaction(fn ->
        # Update ticket order status
        {:ok, updated_order} =
          ticket_order
          |> TicketOrder.status_changeset(%{
            status: :cancelled,
            cancelled_at: DateTime.utc_now(),
            cancellation_reason: reason
          })
          |> Repo.update()

        # Cancel all associated tickets
        tickets =
          Repo.all(
            from t in Ticket, where: t.ticket_order_id == ^ticket_order.id
          )

        Enum.each(tickets, fn ticket ->
          ticket
          |> Ticket.changeset(%{status: :cancelled})
          |> Repo.update()
        end)

        updated_order
      end)

    # Broadcast the cancellation event
    case result do
      {:ok, updated_order} ->
        event = %Ysc.MessagePassingEvents.CheckoutSessionCancelled{
          ticket_order: updated_order,
          user_id: updated_order.user_id,
          event_id: updated_order.event_id,
          reason: reason
        }

        require Logger

        Logger.info("Broadcasting CheckoutSessionCancelled event",
          user_id: updated_order.user_id,
          event_id: updated_order.event_id,
          reason: reason
        )

        broadcast_to_user(updated_order.user_id, event)
        # Also broadcast to event-level topic for availability updates
        broadcast_ticket_availability_update(updated_order.event_id)
        result

      error ->
        error
    end
  end

  @doc """
  Refunds individual tickets from a ticket order.

  This function:
  - Cancels the specified tickets (returns them to stock)
  - Calculates the refund amount based on ticket prices
  - Updates the ticket order if all tickets are refunded

  ## Parameters:
  - `ticket_order`: The ticket order to refund from
  - `ticket_ids`: List of ticket IDs to refund
  - `reason`: Reason for the refund

  ## Returns:
  - `{:ok, %{refund_amount: Money.t(), refunded_tickets: list(), ticket_order: TicketOrder.t()}}` on success
  - `{:error, reason}` on failure
  """
  def refund_tickets(ticket_order, ticket_ids, reason \\ "Admin refund") do
    result =
      Repo.transaction(fn ->
        # Get the tickets to refund
        tickets_to_refund =
          from(t in Ticket,
            where: t.id in ^ticket_ids,
            where: t.ticket_order_id == ^ticket_order.id,
            where: t.status in [:confirmed, :pending],
            preload: [:ticket_tier]
          )
          |> Repo.all()

        if Enum.empty?(tickets_to_refund) do
          Repo.rollback({:error, :no_valid_tickets})
        end

        # Calculate refund amount
        refund_amount =
          tickets_to_refund
          |> Enum.reduce(Money.new(0, :USD), fn ticket, acc ->
            case ticket.ticket_tier.type do
              :free ->
                acc

              :donation ->
                # For donation tickets, we need to get the actual donation amount
                # Since donation tickets store the amount in the payment, we'll use a proportional split
                # This is a simplification - ideally we'd store the donation amount per ticket
                if ticket_order.total_amount && ticket_order.payment_id do
                  # Count total donation tickets in the order
                  donation_tickets_count =
                    from(t in Ticket,
                      join: tt in TicketTier,
                      on: t.ticket_tier_id == tt.id,
                      where: t.ticket_order_id == ^ticket_order.id,
                      where: tt.type == :donation
                    )
                    |> Repo.aggregate(:count, :id)

                  if donation_tickets_count > 0 do
                    case Money.div(
                           ticket_order.total_amount,
                           donation_tickets_count
                         ) do
                      {:ok, ticket_amount} ->
                        case Money.add(acc, ticket_amount) do
                          {:ok, new_total} -> new_total
                          {:error, _} -> acc
                        end

                      {:error, _} ->
                        acc
                    end
                  else
                    acc
                  end
                else
                  acc
                end

              _ ->
                # For paid tickets, use the tier price
                if ticket.ticket_tier.price do
                  case Money.add(acc, ticket.ticket_tier.price) do
                    {:ok, new_total} -> new_total
                    {:error, _} -> acc
                  end
                else
                  acc
                end
            end
          end)

        # Cancel the tickets (this returns them to stock)
        Enum.each(tickets_to_refund, fn ticket ->
          ticket
          |> Ticket.changeset(%{status: :cancelled})
          |> Repo.update()
        end)

        # Check if all tickets in the order are now cancelled
        remaining_tickets =
          from(t in Ticket,
            where: t.ticket_order_id == ^ticket_order.id,
            where: t.status in [:confirmed, :pending]
          )
          |> Repo.aggregate(:count, :id)

        # Update ticket order status if all tickets are refunded
        updated_order =
          if remaining_tickets == 0 do
            case ticket_order
                 |> TicketOrder.status_changeset(%{
                   status: :cancelled,
                   cancelled_at: DateTime.utc_now(),
                   cancellation_reason: reason
                 })
                 |> Repo.update() do
              {:ok, order} -> order
              {:error, _} -> ticket_order
            end
          else
            ticket_order
          end

        %{
          refund_amount: refund_amount,
          refunded_tickets: tickets_to_refund,
          ticket_order: updated_order
        }
      end)

    case result do
      {:ok, refund_info} ->
        require Logger

        Logger.info("Refunded individual tickets",
          ticket_order_id: ticket_order.id,
          ticket_ids: ticket_ids,
          refund_amount: Money.to_string!(refund_info.refund_amount),
          reason: reason
        )

        {:ok, refund_info}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Expires a ticket order that has exceeded the payment timeout.
  """
  def expire_ticket_order(ticket_order) do
    require Logger

    result =
      Repo.transaction(fn ->
        # Cancel PaymentIntent in Stripe if it exists
        if ticket_order.payment_intent_id do
          case Ysc.Tickets.StripeService.cancel_payment_intent(
                 ticket_order.payment_intent_id
               ) do
            :ok ->
              Logger.info("Canceled PaymentIntent for expired ticket order",
                ticket_order_id: ticket_order.id,
                payment_intent_id: ticket_order.payment_intent_id
              )

            {:error, reason} ->
              Logger.warning(
                "Failed to cancel PaymentIntent for expired ticket order (continuing anyway)",
                ticket_order_id: ticket_order.id,
                payment_intent_id: ticket_order.payment_intent_id,
                error: reason
              )
          end
        end

        # Update ticket order status
        updated_order =
          case ticket_order
               |> TicketOrder.status_changeset(%{
                 status: :expired,
                 cancelled_at: DateTime.utc_now(),
                 cancellation_reason: "Payment timeout"
               })
               |> Repo.update() do
            {:ok, order} ->
              order

            {:error, changeset} ->
              Logger.error("Failed to update ticket order status",
                ticket_order_id: ticket_order.id,
                errors: inspect(changeset.errors)
              )

              # Raise to rollback transaction
              Repo.rollback({:error, :failed_to_update_order})
          end

        # Cancel all associated tickets
        tickets =
          Repo.all(
            from t in Ticket, where: t.ticket_order_id == ^ticket_order.id
          )

        # Update each ticket and collect any errors
        ticket_update_results =
          Enum.map(tickets, fn ticket ->
            case ticket
                 |> Ticket.status_changeset(%{status: :expired})
                 |> Repo.update() do
              {:ok, updated_ticket} ->
                {:ok, updated_ticket}

              {:error, changeset} ->
                Logger.error("Failed to expire ticket",
                  ticket_id: ticket.id,
                  ticket_order_id: ticket_order.id,
                  errors: inspect(changeset.errors)
                )

                {:error, ticket.id, changeset}
            end
          end)

        # Check if any ticket updates failed
        failed_updates =
          Enum.filter(ticket_update_results, &match?({:error, _, _}, &1))

        if Enum.any?(failed_updates) do
          Logger.error("Failed to expire some tickets",
            ticket_order_id: ticket_order.id,
            failed_count: length(failed_updates),
            total_count: length(tickets)
          )

          # Rollback transaction if any ticket update failed
          Repo.rollback({:error, :failed_to_expire_tickets})
        end

        updated_order
      end)

    # Broadcast the expiration event
    case result do
      {:ok, updated_order} ->
        event = %Ysc.MessagePassingEvents.CheckoutSessionExpired{
          ticket_order: updated_order,
          user_id: updated_order.user_id,
          event_id: updated_order.event_id
        }

        broadcast_to_user(updated_order.user_id, event)
        # Also broadcast to event-level topic for availability updates
        broadcast_ticket_availability_update(updated_order.event_id)
        result

      error ->
        error
    end
  end

  ## Booking Validation

  @doc """
  Validates that the requested ticket quantities don't exceed available capacity.
  """
  def validate_booking_capacity(event_id, ticket_selections) do
    event = Ysc.Events.get_event!(event_id)

    # Check if event is at capacity
    if event_at_capacity?(event) do
      {:error, :event_at_capacity}
    else
      # Check each ticket tier capacity
      tier_validations =
        ticket_selections
        |> Enum.map(fn {tier_id, quantity} ->
          validate_tier_capacity(tier_id, quantity, event)
        end)

      if Enum.any?(tier_validations, &(&1 == :error)) do
        {:error, :tier_capacity_exceeded}
      else
        # Check total event capacity
        total_requested = Enum.sum(Map.values(ticket_selections))

        if within_event_capacity?(event, total_requested) do
          :ok
        else
          {:error, :event_capacity_exceeded}
        end
      end
    end
  end

  @doc """
  Checks if an event is at its maximum capacity.
  """
  def event_at_capacity?(%Event{max_attendees: nil}), do: false

  def event_at_capacity?(%Event{max_attendees: max_attendees} = event) do
    current_attendees = count_confirmed_tickets_for_event(event.id)
    current_attendees >= max_attendees
  end

  # Handle maps (from our custom query)
  def event_at_capacity?(%{max_attendees: nil}), do: false

  def event_at_capacity?(%{max_attendees: max_attendees, id: event_id}) do
    current_attendees = count_confirmed_tickets_for_event(event_id)
    current_attendees >= max_attendees
  end

  @doc """
  Counts the total number of confirmed tickets for an event.
  """
  def count_confirmed_tickets_for_event(event_id) do
    Ticket
    |> where([t], t.event_id == ^event_id and t.status == :confirmed)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Counts the total number of pending tickets for an event (including expired ones that haven't been cleaned up).
  """
  def count_pending_tickets_for_event(event_id) do
    Ticket
    |> where([t], t.event_id == ^event_id and t.status == :pending)
    |> Repo.aggregate(:count, :id)
  end

  ## Payment Processing

  @doc """
  Processes payment for a ticket order using Stripe.
  """
  def process_ticket_order_payment(ticket_order, payment_intent_id) do
    start_time = System.monotonic_time()

    result =
      with {:ok, payment_intent} <-
             Stripe.PaymentIntent.retrieve(payment_intent_id, %{}),
           :ok <- validate_payment_intent(payment_intent, ticket_order),
           {:ok, {payment, _transaction, _entries}} <-
             process_ledger_payment(ticket_order, payment_intent),
           {:ok, completed_order} <-
             complete_ticket_order(ticket_order, payment.id),
           :ok <- confirm_tickets(completed_order) do
        # Reload the completed order with all necessary associations for email
        reloaded_order = get_ticket_order(completed_order.id)
        # Send confirmation email
        send_ticket_confirmation_email(reloaded_order)
        # Broadcast ticket availability update
        broadcast_ticket_availability_update(ticket_order.event_id)
        {:ok, reloaded_order}
      end

    # Emit telemetry event for payment processing
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    :telemetry.execute(
      [:ysc, :tickets, :payment_processed],
      %{duration: duration_ms, count: 1},
      %{
        ticket_order_id: ticket_order.id,
        event_id: ticket_order.event_id,
        user_id: ticket_order.user_id,
        status: if(match?({:ok, _}, result), do: "success", else: "failure"),
        payment_intent_id: payment_intent_id
      }
    )

    result
  end

  @doc """
  Processes a free ticket order (no payment required).
  """
  def process_free_ticket_order(ticket_order) do
    with {:ok, completed_order} <- complete_ticket_order(ticket_order, nil),
         :ok <- confirm_tickets(completed_order) do
      # Reload the completed order with all necessary associations for email
      reloaded_order = get_ticket_order(completed_order.id)
      # Send confirmation email
      send_ticket_confirmation_email(reloaded_order)
      # Broadcast ticket availability update
      broadcast_ticket_availability_update(ticket_order.event_id)
      {:ok, reloaded_order}
    end
  end

  ## Timeout Management

  @doc """
  Finds and expires ticket orders that have exceeded the payment timeout.

  Note: expires_at is already set to (now + timeout) when the order is created,
  so we just need to check if expires_at < now (not now - timeout).
  """
  def expire_timed_out_orders do
    now = DateTime.utc_now()

    expired_orders =
      TicketOrder
      |> where([to], to.status == :pending and to.expires_at < ^now)
      |> preload(:tickets)
      |> Repo.all()

    count = length(expired_orders)

    Enum.each(expired_orders, &expire_ticket_order/1)

    # Emit telemetry event for expired orders
    if count > 0 do
      :telemetry.execute(
        [:ysc, :tickets, :timeout_expired],
        %{count: count},
        %{}
      )
    end
  end

  @doc """
  Utility function to expire all current pending checkout sessions.

  This is useful for:
  - Admin operations
  - Testing scenarios
  - Maintenance tasks
  - Emergency situations

  ## Returns:
  - `{:ok, count}` where count is the number of expired sessions
  - `{:error, reason}` if there was an error
  """
  def expire_all_pending_checkout_sessions do
    require Logger

    try do
      pending_orders =
        TicketOrder
        |> where([to], to.status == :pending)
        |> preload(:tickets)
        |> Repo.all()

      count = length(pending_orders)

      if count > 0 do
        Logger.info("Manually expiring all pending checkout sessions",
          total_sessions: count
        )

        Enum.each(pending_orders, fn ticket_order ->
          expire_ticket_order(ticket_order)
        end)

        Logger.info("Successfully expired all pending checkout sessions",
          expired_count: count
        )
      else
        Logger.info("No pending checkout sessions found to expire")
      end

      {:ok, count}
    rescue
      error ->
        require Logger

        Logger.error("Failed to expire pending checkout sessions",
          error: error
        )

        {:error, error}
    end
  end

  @doc """
  Utility function to expire pending checkout sessions for a specific user.

  ## Parameters:
  - `user_id`: The user ID to expire sessions for

  ## Returns:
  - `{:ok, count}` where count is the number of expired sessions
  - `{:error, reason}` if there was an error
  """
  def expire_user_pending_checkout_sessions(user_id) do
    require Logger

    try do
      pending_orders =
        TicketOrder
        |> where([to], to.user_id == ^user_id and to.status == :pending)
        |> preload(:tickets)
        |> Repo.all()

      count = length(pending_orders)

      if count > 0 do
        Logger.info("Manually expiring pending checkout sessions for user",
          user_id: user_id,
          total_sessions: count
        )

        Enum.each(pending_orders, fn ticket_order ->
          expire_ticket_order(ticket_order)
        end)

        Logger.info("Successfully expired user's pending checkout sessions",
          user_id: user_id,
          expired_count: count
        )
      else
        Logger.info("No pending checkout sessions found for user",
          user_id: user_id
        )
      end

      {:ok, count}
    rescue
      error ->
        require Logger

        Logger.error("Failed to expire user's pending checkout sessions",
          user_id: user_id,
          error: error
        )

        {:error, error}
    end
  end

  @doc """
  Utility function to expire pending checkout sessions for a specific event.

  ## Parameters:
  - `event_id`: The event ID to expire sessions for

  ## Returns:
  - `{:ok, count}` where count is the number of expired sessions
  - `{:error, reason}` if there was an error
  """
  def expire_event_pending_checkout_sessions(event_id) do
    require Logger

    try do
      pending_orders =
        TicketOrder
        |> where([to], to.event_id == ^event_id and to.status == :pending)
        |> preload(:tickets)
        |> Repo.all()

      count = length(pending_orders)

      if count > 0 do
        Logger.info("Manually expiring pending checkout sessions for event",
          event_id: event_id,
          total_sessions: count
        )

        Enum.each(pending_orders, fn ticket_order ->
          expire_ticket_order(ticket_order)
        end)

        Logger.info("Successfully expired event's pending checkout sessions",
          event_id: event_id,
          expired_count: count
        )
      else
        Logger.info("No pending checkout sessions found for event",
          event_id: event_id
        )
      end

      {:ok, count}
    rescue
      error ->
        require Logger

        Logger.error("Failed to expire event's pending checkout sessions",
          event_id: event_id,
          error: error
        )

        {:error, error}
    end
  end

  @doc """
  Gets the expiration time for a new ticket order.
  """
  def get_order_expiration_time do
    DateTime.add(DateTime.utc_now(), @payment_timeout_minutes, :minute)
  end

  @doc """
  Gets statistics about pending checkout sessions.

  ## Returns:
  - Map with statistics about pending sessions
  """
  def get_pending_checkout_statistics do
    pending_orders =
      TicketOrder
      |> where([to], to.status == :pending)
      |> preload([:tickets, :user, :event])
      |> Repo.all()

    total_sessions = length(pending_orders)

    total_tickets =
      Enum.reduce(pending_orders, 0, fn order, acc ->
        acc + length(order.tickets)
      end)

    # Group by event
    event_stats =
      pending_orders
      |> Enum.group_by(& &1.event_id)
      |> Enum.map(fn {event_id, orders} ->
        event = hd(orders).event

        %{
          event_id: event_id,
          event_title: event.title,
          pending_sessions: length(orders),
          pending_tickets:
            Enum.reduce(orders, 0, fn order, acc ->
              acc + length(order.tickets)
            end)
        }
      end)

    # Group by user
    user_stats =
      pending_orders
      |> Enum.group_by(& &1.user_id)
      |> Enum.map(fn {user_id, orders} ->
        user = hd(orders).user

        %{
          user_id: user_id,
          user_email: user.email,
          pending_sessions: length(orders),
          pending_tickets:
            Enum.reduce(orders, 0, fn order, acc ->
              acc + length(order.tickets)
            end)
        }
      end)

    %{
      total_pending_sessions: total_sessions,
      total_pending_tickets: total_tickets,
      by_event: event_stats,
      by_user: user_stats,
      generated_at: DateTime.utc_now()
    }
  end

  ## Private Functions

  defp validate_user_membership(user_id) do
    case Accounts.get_user!(user_id, [:subscriptions]) do
      nil ->
        {:error, :user_not_found}

      user ->
        if has_active_membership?(user) do
          {:ok, user}
        else
          {:error, :membership_required}
        end
    end
  end

  defp has_active_membership?(user) do
    Accounts.has_active_membership?(user)
  end

  defp validate_tier_capacity(tier_id, requested_quantity, _event) do
    case Ysc.Events.get_ticket_tier(tier_id) do
      nil ->
        :error

      tier ->
        available = get_available_tier_quantity(tier)

        if available == :unlimited or requested_quantity <= available do
          :ok
        else
          :error
        end
    end
  end

  defp get_available_tier_quantity(%TicketTier{quantity: nil}), do: :unlimited
  defp get_available_tier_quantity(%TicketTier{quantity: 0}), do: :unlimited

  defp get_available_tier_quantity(%TicketTier{
         id: tier_id,
         quantity: total_quantity
       }) do
    sold_count = count_sold_tickets_for_tier(tier_id)
    max(0, total_quantity - sold_count)
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

  defp validate_payment_intent(payment_intent, ticket_order) do
    expected_amount = money_to_cents(ticket_order.total_amount)

    cond do
      payment_intent.amount != expected_amount ->
        {:error, :amount_mismatch}

      payment_intent.status != "succeeded" ->
        {:error, :payment_not_succeeded}

      true ->
        :ok
    end
  end

  defp process_ledger_payment(ticket_order, payment_intent) do
    # Use consolidated fee extraction from Stripe.WebhookHandler
    stripe_fee =
      Ysc.Stripe.WebhookHandler.extract_stripe_fee_from_payment_intent(
        payment_intent
      )

    # Load ticket order with tickets and ticket tiers to check for donations
    ticket_order_with_tickets =
      get_ticket_order(ticket_order.id)

    # Calculate donation vs regular ticket amounts (returns gross amount, donation, discount)
    {gross_event_amount, donation_amount, discount_amount} =
      calculate_event_and_donation_amounts(ticket_order_with_tickets)

    # If there are donations or discounts, use the mixed payment processor
    if Money.positive?(donation_amount) || Money.positive?(discount_amount) do
      Ledgers.process_event_payment_with_donations_and_discounts(%{
        user_id: ticket_order.user_id,
        total_amount: ticket_order.total_amount,
        gross_event_amount: gross_event_amount,
        event_amount: gross_event_amount,
        donation_amount: donation_amount,
        discount_amount: discount_amount,
        event_id: ticket_order.event_id,
        external_payment_id: payment_intent.id,
        stripe_fee: stripe_fee,
        description: "Event tickets - Order #{ticket_order.reference_id}",
        payment_method_id:
          extract_payment_method_id(payment_intent, ticket_order.user_id),
        ticket_order_id: ticket_order.id
      })
    else
      # No donations or discounts, use regular event payment processing
      Ledgers.process_payment(%{
        user_id: ticket_order.user_id,
        amount: ticket_order.total_amount,
        entity_type: :event,
        entity_id: ticket_order.event_id,
        external_payment_id: payment_intent.id,
        stripe_fee: stripe_fee,
        description: "Event tickets - Order #{ticket_order.reference_id}",
        property: nil,
        payment_method_id:
          extract_payment_method_id(payment_intent, ticket_order.user_id)
      })
    end
  end

  # Calculate event revenue amount and donation amount from ticket order
  # Returns {gross_event_amount, donation_amount, discount_amount}
  # gross_event_amount is the amount before discounts (for ledger tracking)
  def calculate_event_and_donation_amounts(ticket_order) do
    if ticket_order && Ecto.assoc_loaded?(ticket_order.tickets) &&
         ticket_order.tickets do
      # Calculate non-donation ticket costs (regular event revenue) - gross amount before discounts
      gross_event_amount =
        ticket_order.tickets
        |> Enum.filter(fn t ->
          tier_type = t.ticket_tier.type

          tier_type != "donation" && tier_type != :donation &&
            tier_type != "free" &&
            tier_type != :free
        end)
        |> Enum.reduce(Money.new(0, :USD), fn ticket, acc ->
          case ticket.ticket_tier.price do
            nil ->
              acc

            price when is_struct(price, Money) ->
              case Money.add(acc, price) do
                {:ok, new_total} -> new_total
                _ -> acc
              end

            _ ->
              acc
          end
        end)

      # Calculate discount amount from fulfilled reservations
      discount_amount = calculate_discount_from_reservations(ticket_order)

      # Calculate donation amount (total - event amount after discounts)
      net_event_amount =
        case Money.sub(gross_event_amount, discount_amount) do
          {:ok, amount} -> amount
          _ -> gross_event_amount
        end

      donation_amount =
        case Money.sub(ticket_order.total_amount, net_event_amount) do
          {:ok, amount} -> amount
          _ -> Money.new(0, :USD)
        end

      {gross_event_amount, donation_amount, discount_amount}
    else
      # If we can't load tickets, assume all is event revenue
      {ticket_order.total_amount, Money.new(0, :USD), Money.new(0, :USD)}
    end
  end

  # Calculate total discount amount from fulfilled reservations for a ticket order
  defp calculate_discount_from_reservations(ticket_order) do
    import Ecto.Query
    alias Ysc.Events.TicketReservation

    # Get all fulfilled reservations for this ticket order
    fulfilled_reservations =
      TicketReservation
      |> where(
        [tr],
        tr.ticket_order_id == ^ticket_order.id and tr.status == "fulfilled"
      )
      |> preload([:ticket_tier])
      |> Repo.all()

    # Calculate total discount amount
    fulfilled_reservations
    |> Enum.reduce(Money.new(0, :USD), fn reservation, acc ->
      if reservation.discount_percentage &&
           Decimal.gt?(reservation.discount_percentage, 0) do
        # Calculate original price for reserved tickets
        tier_price = reservation.ticket_tier.price

        if tier_price do
          original_total =
            case Money.mult(tier_price, reservation.quantity) do
              {:ok, total} -> total
              {:error, _} -> Money.new(0, :USD)
            end

          # Apply discount percentage
          discount_pct_decimal =
            Decimal.div(reservation.discount_percentage, Decimal.new(100))

          discount_amount =
            case Money.mult(original_total, discount_pct_decimal) do
              {:ok, discount} -> discount
              {:error, _} -> Money.new(0, :USD)
            end

          case Money.add(acc, discount_amount) do
            {:ok, new_total} -> new_total
            {:error, _} -> acc
          end
        else
          acc
        end
      else
        acc
      end
    end)
  end

  defp extract_payment_method_id(payment_intent, user_id) do
    require Logger

    case payment_intent.payment_method do
      nil ->
        Logger.info("No payment method found in payment intent",
          payment_intent_id: payment_intent.id
        )

        nil

      payment_method_id when is_binary(payment_method_id) ->
        # Retrieve the full payment method from Stripe
        case Stripe.PaymentMethod.retrieve(payment_method_id) do
          {:ok, stripe_payment_method} ->
            user = Ysc.Accounts.get_user!(user_id)

            # Sync the payment method to our database
            case Ysc.Payments.sync_payment_method_from_stripe(
                   user,
                   stripe_payment_method
                 ) do
              {:ok, payment_method} ->
                Logger.info(
                  "Successfully synced payment method for ticket payment",
                  payment_method_id: payment_method.id,
                  stripe_payment_method_id: payment_method_id,
                  user_id: user_id
                )

                payment_method.id

              {:error, reason} ->
                Logger.warning(
                  "Failed to sync payment method for ticket payment",
                  stripe_payment_method_id: payment_method_id,
                  user_id: user_id,
                  error: inspect(reason)
                )

                nil
            end

          {:error, error} ->
            Logger.warning("Failed to retrieve payment method from Stripe",
              payment_method_id: payment_method_id,
              payment_intent_id: payment_intent.id,
              error: error.message
            )

            nil
        end

      _ ->
        nil
    end
  end

  # Helper function to safely convert Money to cents
  defp money_to_cents(%Money{amount: amount, currency: :USD}) do
    # Use Decimal for precise conversion to avoid floating-point errors
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(%Money{amount: amount, currency: _currency}) do
    # For other currencies, use same conversion
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(_) do
    # Fallback for invalid money values
    0
  end

  defp confirm_tickets(ticket_order) do
    # Query for tickets directly to avoid association loading issues
    # Only update tickets that are not already confirmed (idempotency)
    tickets =
      Repo.all(
        from t in Ticket,
          where:
            t.ticket_order_id == ^ticket_order.id and t.status != :confirmed
      )

    tickets
    |> Enum.each(fn ticket ->
      ticket
      |> Ticket.changeset(%{status: :confirmed})
      |> Repo.update()
    end)

    :ok
  end

  ## PubSub Functions

  @doc """
  Subscribe to ticket-related events.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Ysc.PubSub, topic())
  end

  @doc """
  Subscribe to ticket events for a specific user.
  """
  def subscribe(user_id) do
    Phoenix.PubSub.subscribe(Ysc.PubSub, topic(user_id))
  end

  @doc """
  Subscribe to ticket events for a specific event.
  """
  def subscribe_event(event_id) do
    Phoenix.PubSub.subscribe(Ysc.PubSub, topic_event(event_id))
  end

  defp topic do
    "tickets"
  end

  defp topic(user_id) do
    "tickets:user:#{user_id}"
  end

  defp topic_event(event_id) do
    "tickets:event:#{event_id}"
  end

  defp broadcast_to_user(user_id, event) do
    topic_name = topic(user_id)
    require Logger

    Logger.info("Broadcasting to user topic",
      user_id: user_id,
      topic: topic_name,
      event_type: event.__struct__,
      event_data: inspect(event, limit: :infinity)
    )

    result =
      Phoenix.PubSub.broadcast(Ysc.PubSub, topic_name, {__MODULE__, event})

    Logger.info("PubSub broadcast result",
      user_id: user_id,
      topic: topic_name,
      result: result
    )

    result
  end

  defp broadcast_to_event(event_id, event) do
    topic_name = topic_event(event_id)
    require Logger

    Logger.info("Broadcasting to event topic",
      event_id: event_id,
      topic: topic_name,
      event_type: event.__struct__
    )

    Phoenix.PubSub.broadcast(Ysc.PubSub, topic_name, {__MODULE__, event})
  end

  defp broadcast_ticket_availability_update(event_id) do
    # Broadcast a simple event to notify all viewers that ticket availability has changed
    event = %Ysc.MessagePassingEvents.TicketAvailabilityUpdated{
      event_id: event_id
    }

    broadcast_to_event(event_id, event)
  end

  @doc """
  Test function to manually broadcast a CheckoutSessionCancelled event.
  This is useful for debugging PubSub connectivity.
  """
  def test_broadcast_checkout_cancelled(user_id) do
    require Logger

    Logger.info("TEST: Manually broadcasting CheckoutSessionCancelled event",
      user_id: user_id,
      topic: topic(user_id)
    )

    event = %Ysc.MessagePassingEvents.CheckoutSessionCancelled{
      ticket_order: nil,
      user_id: user_id,
      event_id: nil,
      reason: "Manual test broadcast"
    }

    broadcast_to_user(user_id, event)

    Logger.info("TEST: Broadcast completed")
    :ok
  end

  @doc """
  Sends a ticket purchase confirmation email for a completed ticket order.
  """
  def send_ticket_confirmation_email(ticket_order) do
    require Logger

    Logger.info("Starting ticket confirmation email process",
      ticket_order_id: ticket_order.id,
      user_id: ticket_order.user_id,
      user_email: ticket_order.user.email,
      completed_at: ticket_order.completed_at
    )

    try do
      # Prepare email data
      Logger.info("Preparing email data for ticket order #{ticket_order.id}")

      email_data =
        YscWeb.Emails.TicketPurchaseConfirmation.prepare_email_data(
          ticket_order
        )

      Logger.info("Email data prepared successfully",
        email_data_keys: Map.keys(email_data)
      )

      # Generate idempotency key
      idempotency_key = "ticket_confirmation_#{ticket_order.id}"

      Logger.info("Generated idempotency key: #{idempotency_key}")

      # Schedule the email
      Logger.info("Scheduling email with Oban")

      result =
        YscWeb.Emails.Notifier.schedule_email(
          ticket_order.user.email,
          idempotency_key,
          YscWeb.Emails.TicketPurchaseConfirmation.get_subject(),
          "ticket_purchase_confirmation",
          email_data,
          "",
          ticket_order.user_id
        )

      case result do
        %Oban.Job{} = job ->
          Logger.info("Ticket confirmation email scheduled successfully",
            ticket_order_id: ticket_order.id,
            user_id: ticket_order.user_id,
            user_email: ticket_order.user.email,
            job_id: job.id,
            idempotency_key: idempotency_key
          )

          :ok

        {:error, reason} ->
          Logger.error("Failed to schedule email",
            ticket_order_id: ticket_order.id,
            user_id: ticket_order.user_id,
            error: reason
          )

          :error
      end
    rescue
      error ->
        Logger.error("Failed to send ticket confirmation email",
          ticket_order_id: ticket_order.id,
          user_id: ticket_order.user_id,
          user_email: ticket_order.user.email,
          error: error,
          stacktrace: __STACKTRACE__
        )

        :error
    end
  end
end
