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
  alias Ysc.MoneyHelper

  alias Ysc.Tickets.TicketOrder
  alias Ysc.Tickets.BookingLocker
  alias Ysc.Tickets.AdminGrants
  alias Ysc.Tickets.CheckoutCancel
  alias Ysc.Tickets.DonationDisplay
  alias Ysc.Events.Ticket
  alias Ysc.Events.TicketTier
  alias Ysc.Events.TicketTierHelpers
  alias Ysc.Events.MemberOnlyTickets
  alias Ysc.Events.Event
  alias Ysc.Events.EventDateTime
  alias Ysc.Accounts
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Bookings
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
  - `{:error, :member_only_not_eligible}` if the selection includes member-only tiers the buyer's plan can't purchase
  - `{:error, :member_only_limit_exceeded}` if the selection exceeds the buyer's per-event member-only ticket limit
  - `{:error, :checkout_payment_in_progress}` when another pending checkout has in-flight payment

  ## Options

    * `:bypass_guards` - passed straight through to
      `Ysc.Tickets.BookingLocker.atomic_booking/4` — see its doc for what
      this relaxes and why (the admin/volunteer mobile app's door sales).
      Membership and member-only-tier eligibility are unaffected regardless
      of this option.
  """
  def create_ticket_order(user_id, event_id, ticket_selections, opts \\ []) do
    require Ysc.Logging

    Ysc.Logging.info("Creating ticket order",
      user_id: user_id,
      event_id: event_id,
      ticket_selections: ticket_selections
    )

    case validate_user_membership(user_id) do
      {:ok, user} ->
        with :ok <-
               validate_member_only_selection(user, event_id, ticket_selections),
             :ok <- prepare_new_checkout_session(user_id, event_id),
             {:ok, ticket_order} <-
               BookingLocker.atomic_booking(
                 user_id,
                 event_id,
                 ticket_selections,
                 opts
               ) do
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
        end

      error ->
        require Ysc.Logging

        Ysc.Logging.warning("Failed to create ticket order",
          user_id: user_id,
          event_id: event_id,
          ticket_selections: ticket_selections,
          error: error
        )

        error
    end
  end

  @doc """
  Grants confirmed tickets to a member immediately (admin migration / complimentary).

  Creates a completed $0 ticket order without checkout. See `Ysc.Tickets.AdminGrants` for details.

  ## Options

    * `:skip_capacity` - when true, bypass tier and event capacity checks only
    * `:skip_sale_guards` - when true, bypass publish state, event date, and tier sale window checks (for legacy migration)
    * `:skip_email` - when true, do not send the ticket confirmation email
    * `:admin_grant_notes` - optional audit note (e.g. legacy order reference)
    * `:payment_channel` - optional `"cash"` | `"check"` | `"other"` for an in-person sale recorded outside Stripe
    * `:offline_amount_collected` - optional `Money` the seller physically collected (order total stays $0)

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
      ) do
    skip_email? = Keyword.get(opts, :skip_email, false)

    case AdminGrants.grant_admin_tickets(
           granted_by_id,
           user_id,
           event_id,
           ticket_selections,
           opts
         ) do
      {:ok, ticket_order} ->
        broadcast_ticket_availability_update(event_id)

        if !skip_email? do
          ticket_order.id
          |> get_ticket_order()
          |> send_ticket_confirmation_email()
        end

        {:ok, ticket_order}

      error ->
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
  Gets a ticket order for checkout UI (payment modal, registration).

  Lighter preload than `get_ticket_order/1` — no event agendas or payment.
  """
  def get_ticket_order_for_checkout(id) do
    TicketOrder
    |> where([to], to.id == ^id)
    |> preload([:user, tickets: :ticket_tier])
    |> Repo.one()
  end

  @doc """
  Gets a ticket order for checkout for a specific user (authorization + light preload).
  """
  def get_user_ticket_order_for_checkout(user_id, order_id) do
    from(to in TicketOrder,
      where: to.id == ^order_id and to.user_id == ^user_id,
      preload: [:user, tickets: :ticket_tier]
    )
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
        tickets: [:ticket_tier, :registration]
      ]
    )
    |> Repo.one()
  end

  @doc """
  Gets a ticket order for the QR check-in page.

  Skips agendas, payment, and user preloads that the QR view does not render.
  """
  def get_user_ticket_order_for_qr(user_id, order_id) do
    from(to in TicketOrder,
      where: to.id == ^order_id and to.user_id == ^user_id,
      preload: [
        :event,
        tickets: [:ticket_tier, :registration]
      ]
    )
    |> Repo.one()
  end

  @doc """
  Gets a ticket order for the post-checkout confirmation page.

  Lighter than `get_user_ticket_order/2` — no event agendas; includes cover image,
  payment method, and ticket registrations needed by the confirmation UI.
  """
  def get_user_ticket_order_for_confirmation(user_id, order_id) do
    from(to in TicketOrder,
      where: to.id == ^order_id and to.user_id == ^user_id,
      preload: [
        :user,
        event: :cover_image,
        payment: :payment_method,
        tickets: [:ticket_tier, :registration]
      ]
    )
    |> Repo.one()
  end

  @doc """
  Returns `event_id` when the user owns the ticket order, otherwise `nil`.

  Use for redirect/authorization checks that do not need full order preloads.
  """
  def get_user_ticket_order_event_id(user_id, order_id) do
    from(to in TicketOrder,
      where: to.id == ^order_id and to.user_id == ^user_id,
      select: to.event_id
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
  Ticket orders for the member "Your Tickets" list: not cancelled, linked to an event,
  and the event start is strictly after `now` (same filter semantics as `UserTicketsLive`).

  This avoids loading the full order history and filtering in application code.
  Results are capped at 50 by default; pass `limit:` to override.
  """
  def list_user_upcoming_ticket_orders(user_id, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    limit = Keyword.get(opts, :limit, 50)

    event_query = event_summary_preload_query()

    from(to in TicketOrder,
      where: to.user_id == ^user_id,
      where: to.status != ^:cancelled,
      join: e in Event,
      on: e.id == to.event_id,
      where: e.start_date > ^now,
      order_by: [desc: to.inserted_at],
      limit: ^limit,
      preload: [
        :tickets,
        tickets: :ticket_tier,
        event: ^event_query
      ]
    )
    |> Repo.all()
  end

  @doc """
  Completed orders whose event start is before `now`, for the memory gallery (newest events first).
  """
  def list_user_past_memory_gallery_ticket_orders(user_id, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    limit = Keyword.get(opts, :limit, 12)

    event_query = event_summary_preload_query()

    from(to in TicketOrder,
      where: to.user_id == ^user_id,
      where: to.status == ^:completed,
      join: e in Event,
      on: e.id == to.event_id,
      where: e.start_date < ^now,
      order_by: [desc: e.start_date],
      limit: ^limit,
      preload: [event: ^event_query]
    )
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
    event_query = event_summary_preload_query()

    from(t in Ticket,
      where:
        t.user_id == ^user_id and t.event_id == ^event_id and
          t.status == :confirmed,
      order_by: [desc: t.inserted_at],
      preload: [
        :ticket_tier,
        :ticket_order,
        :registration,
        event: ^event_query
      ]
    )
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

  Only transitions orders in `from_statuses` (default `[:pending]`). Pass
  `from_statuses: [:completed]` when voiding tickets after an admin refund.

  Pending checkout orders with in-flight Stripe payments are not cancelled so a
  concurrent user cancel cannot race a processing or 3DS payment into a charge
  without ticket fulfillment.

  Pass `reconcile_with_stripe: false` (default `true`) to skip the atomic
  Stripe PaymentIntent cancel and just cancel the local order. Stripe-driven
  callers (e.g. `StripeService.handle_failed_payment/2`, reacting to a
  `payment_intent.payment_failed`/`canceled` webhook) must use this: Stripe has
  already decided that PaymentIntent's fate, and a card decline typically
  leaves it in `requires_payment_method` so the customer can retry with a
  different payment method against the same PaymentIntent - actively
  cancelling it here would foreclose that retry.
  """
  def cancel_ticket_order(ticket_order, reason \\ "User cancelled", opts \\ []) do
    from_statuses = Keyword.get(opts, :from_statuses, [:pending])
    context = Keyword.get(opts, :context, "cancel_ticket_order")
    reconcile_with_stripe = Keyword.get(opts, :reconcile_with_stripe, true)

    cond do
      from_statuses != [:pending] ->
        do_cancel_ticket_order(ticket_order, reason, from_statuses)

      Keyword.get(opts, :payment_redirect_in_progress, false) ->
        {:error, :checkout_payment_in_progress}

      not reconcile_with_stripe ->
        do_cancel_ticket_order(ticket_order, reason, from_statuses)

      true ->
        resolve_abandoned_checkout(ticket_order, reason, from_statuses, context)
    end
  end

  # Reconciles a checkout-abandonment cancel with Stripe before touching the
  # local order. See CheckoutCancel.cancel_payment_intent_for_abandoned_checkout/2
  # for why this must cancel (not just read) the PaymentIntent: a status read can
  # go stale between the check and the cancel, letting a client finish confirming
  # payment against an order we're about to throw away. Cancelling atomically closes
  # that gap - and when Stripe reveals the payment already succeeded, we fulfill the
  # order right here instead of orphaning a captured charge with no ticket granted.
  defp resolve_abandoned_checkout(ticket_order, reason, from_statuses, context) do
    require Ysc.Logging

    case CheckoutCancel.cancel_payment_intent_for_abandoned_checkout(
           ticket_order,
           context
         ) do
      {:cancel, _payment_intent} ->
        do_cancel_ticket_order(ticket_order, reason, from_statuses)

      {:already_succeeded, payment_intent} ->
        fulfill_succeeded_checkout_payment(ticket_order, payment_intent)

      {:in_progress, _payment_intent} ->
        Ysc.Logging.info(
          "Skipped ticket order cancellation while checkout payment is in flight",
          ticket_order_id: ticket_order.id,
          payment_intent_id: ticket_order.payment_intent_id
        )

        {:error, :checkout_payment_in_progress}

      {:error, stripe_error} ->
        Ysc.Logging.warning(
          "Could not reconcile checkout payment with Stripe, not cancelling order",
          ticket_order_id: ticket_order.id,
          payment_intent_id: ticket_order.payment_intent_id,
          error: inspect(stripe_error)
        )

        {:error, :checkout_payment_in_progress}
    end
  end

  defp do_cancel_ticket_order(ticket_order, reason, from_statuses) do
    now = DateTime.utc_now()
    ticket_statuses = ticket_cancel_statuses(from_statuses)

    result =
      Repo.transaction(fn ->
        {count, _} =
          from(to in TicketOrder,
            where: to.id == ^ticket_order.id and to.status in ^from_statuses
          )
          |> Repo.update_all(
            set: [
              status: :cancelled,
              cancelled_at: now,
              cancellation_reason: reason,
              updated_at: now
            ]
          )

        if count == 1 do
          from(t in Ticket,
            where:
              t.ticket_order_id == ^ticket_order.id and
                t.status in ^ticket_statuses
          )
          |> Repo.update_all(set: [status: :cancelled, updated_at: now])

          case get_ticket_order(ticket_order.id) do
            nil -> Repo.rollback({:error, :not_found})
            updated_order -> {:cancelled, updated_order}
          end
        else
          case get_ticket_order(ticket_order.id) do
            nil -> Repo.rollback({:error, :not_found})
            order -> {:skipped, order}
          end
        end
      end)

    case result do
      {:ok, {:cancelled, updated_order}} ->
        event = %Ysc.MessagePassingEvents.CheckoutSessionCancelled{
          ticket_order: updated_order,
          user_id: updated_order.user_id,
          event_id: updated_order.event_id,
          reason: reason
        }

        require Ysc.Logging

        Ysc.Logging.info("Broadcasting CheckoutSessionCancelled event",
          user_id: updated_order.user_id,
          event_id: updated_order.event_id,
          reason: reason
        )

        broadcast_to_user(updated_order.user_id, event)
        broadcast_ticket_availability_update(updated_order.event_id)
        {:ok, updated_order}

      {:ok, {:skipped, order}} ->
        {:ok, order}

      error ->
        error
    end
  end

  defp ticket_cancel_statuses(from_statuses) do
    if :completed in from_statuses do
      [:confirmed]
    else
      [:pending]
    end
  end

  @doc """
  Calculates the refund amount for the given tickets without mutating anything.

  Lets a caller (e.g. an admin refund flow) get the amount to send to the
  payment provider *before* committing to cancelling any tickets, so a
  provider-side failure doesn't leave tickets cancelled with no refund
  actually issued.

  ## Returns:
  - `{:ok, Money.t()}` on success
  - `{:error, :no_valid_tickets}` if none of `ticket_ids` are refundable
  """
  def calculate_refund_amount(ticket_order, ticket_ids) do
    case fetch_refundable_tickets(ticket_order, ticket_ids) do
      {:ok, %{refund_amount: refund_amount}} -> {:ok, refund_amount}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Refunds individual tickets from a ticket order.

  This function:
  - Cancels the specified tickets (returns them to stock)
  - Calculates the refund amount based on ticket prices
  - Updates the ticket order if all tickets are refunded

  Call `calculate_refund_amount/2` first if you need the amount before
  deciding whether to cancel the tickets at all (e.g. to issue a payment
  provider refund only after which this should run).

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
        {tickets_to_refund, refund_amount} =
          case fetch_refundable_tickets(ticket_order, ticket_ids) do
            {:ok, %{tickets_to_refund: tickets, refund_amount: amount}} ->
              {tickets, amount}

            {:error, error_reason} ->
              Repo.rollback(error_reason)
          end

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
        require Ysc.Logging

        Ysc.Logging.info("Refunded individual tickets",
          ticket_order_id: ticket_order.id,
          ticket_ids: ticket_ids,
          refund_amount: Money.to_string!(refund_info.refund_amount),
          reason: reason
        )

        broadcast_ticket_availability_update(ticket_order.event_id)
        {:ok, refund_info}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Issues a refund for `amount` against `payment` via Stripe and records it in
  the ledger.

  Shared by the admin Payments refund flow and per-ticket refunds. Issues the
  refund in Stripe first, then records it in the ledger using the
  Stripe-issued refund id (mirrors AdminBookingsLive's process-booking-refund).
  `Ledgers.process_refund/1`'s idempotency check only matches on
  `external_refund_id`, so a ledger-only refund recorded before Stripe
  confirms the money moved would get a synthetic id that a later webhook for
  the real Stripe refund can't match against -- producing a second Refund, a
  second ledger transaction, and a second "your refund has been processed"
  email for the same payment.

  Stripe idempotency is scoped per refund, not per `(payment, amount)`. Two
  tickets of the same price on one order are two intentional refunds; a key
  of only payment+amount would return the first Stripe refund on the second
  ticket, cancel the ticket, and never move the second share of money.
  Pass `:ticket_ids` so a retry of the *same* tickets reuses the Stripe
  refund after a post-refund failure (e.g. `Ledgers.process_refund/1`
  erroring), while a later refund of different tickets issues a new one.
  Amount-only refunds (no ticket ids) include the existing refund count so
  two sequential $50 partials on the same payment also stay distinct.

  ## Options
  - `:ticket_ids` — ids of the tickets this refund covers (per-ticket flows)

  ## Returns
  - `{:ok, {:skipped_zero_amount, nil, nil}}` if `amount` is zero or negative
  - `{:ok, {refund, transaction, entries}}` on success
  - `{:error, {:stripe_error, reason}}` if Stripe declines the refund
  - `{:error, :no_stripe_payment}` if `payment` has no Stripe payment to refund
  """
  def refund_via_stripe(payment, amount, reason, opts \\ []) do
    amount_cents = MoneyHelper.money_to_cents(amount)

    cond do
      # Free tickets (and $0 donation leftovers) have nothing to refund in
      # Stripe. Sending amount=0 is rejected by Stripe and would block ticket
      # cancellation after #1077's Stripe-first ordering.
      amount_cents <= 0 ->
        {:ok, {:skipped_zero_amount, nil, nil}}

      payment.external_payment_id && payment.external_provider == :stripe ->
        idempotency_key =
          stripe_refund_idempotency_key(payment, amount_cents, opts)

        case Bookings.create_stripe_refund_for_admin(
               payment.external_payment_id,
               amount_cents,
               reason,
               idempotency_key: idempotency_key
             ) do
          {:ok, stripe_refund} ->
            Ledgers.process_refund(%{
              payment_id: payment.id,
              refund_amount: amount,
              reason: reason,
              external_refund_id: stripe_refund.id
            })

          {:error, stripe_reason} ->
            require Ysc.Logging

            Ysc.Logging.error("Admin Stripe refund failed",
              payment_id: payment.id,
              amount_cents: amount_cents,
              error: inspect(stripe_reason)
            )

            {:error, {:stripe_error, stripe_reason}}
        end

      true ->
        {:error, :no_stripe_payment}
    end
  end

  # Stripe idempotency key for an admin refund. Same tickets + amount (or the
  # same amount-only sequence number) retries the original Stripe refund;
  # a different ticket set or a later partial of the same amount does not.
  defp stripe_refund_idempotency_key(payment, amount_cents, opts) do
    ticket_ids =
      opts
      |> Keyword.get(:ticket_ids, [])
      |> List.wrap()
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)
      |> Enum.sort()

    scope =
      case ticket_ids do
        [] -> "n#{payment_refunds_count(payment.id)}"
        ids -> "t" <> Enum.join(ids, "-")
      end

    Ysc.Stripe.Idempotency.key(
      "admin_refund_#{payment.id}_#{scope}_#{amount_cents}"
    )
  end

  defp payment_refunds_count(payment_id) do
    payment_id
    |> payment_refunds_count_query()
    |> Repo.aggregate(:count, :id)
  end

  defp payment_refunds_count_query(payment_id) do
    from(r in Ysc.Ledgers.Refund, where: r.payment_id == ^payment_id)
  end

  @doc """
  Reassigns a ticket to a different user (the ticket holder, not the ticket
  order's purchaser). Skips purchase-time validations since this is an
  administrative correction.
  """
  def reassign_ticket(%Ticket{} = ticket, new_user_id) do
    ticket
    |> Ticket.reassign_changeset(%{user_id: new_user_id})
    |> Repo.update()
  end

  @doc """
  Lists confirmed tickets for an event for admin display, newest first,
  preloading ticket tier, ticket holder, attendee registration info, and the
  order (with purchaser, for grouping tickets by order). Payment is loaded
  only when refunding — it is not needed to render the list.
  Pending/cancelled/expired tickets aren't actionable from this list, so
  they're excluded.
  """
  def list_tickets_for_admin(event_id) do
    event_id
    |> list_tickets_for_admin_query()
    |> Repo.all()
  end

  # Display fields for purchaser / ticket-holder cards. Omits hashed_password,
  # board_bio, and other columns the admin ticket list never renders.
  @admin_ticket_user_fields [
    :id,
    :email,
    :first_name,
    :last_name,
    :most_connected_country,
    :current_avatar_id
  ]

  defp list_tickets_for_admin_query(event_id) do
    user_query =
      from(u in Ysc.Accounts.User,
        select: struct(u, ^@admin_ticket_user_fields)
      )

    from(t in Ticket,
      where: t.event_id == ^event_id and t.status == :confirmed,
      order_by: [desc: t.inserted_at],
      preload: [
        :ticket_tier,
        :registration,
        user: ^user_query,
        ticket_order: [user: ^user_query]
      ]
    )
  end

  @doc """
  Loads the Stripe payment row for a ticket order, or `nil` when the order
  never collected a payment (admin grants, free tickets).
  """
  def get_payment_for_order(%TicketOrder{payment_id: nil}), do: nil

  def get_payment_for_order(%TicketOrder{payment_id: payment_id}) do
    Repo.get(Ysc.Ledgers.Payment, payment_id)
  end

  # Read-only: finds the refundable tickets and computes the refund amount,
  # without cancelling anything. Shared by calculate_refund_amount/2 (no
  # mutation) and refund_tickets/3 (calculates then mutates in one transaction).
  #
  # Paid tickets refund `price - discount_amount`. Donation tickets refund
  # their share of `total_amount` after non-donation nets — never the full
  # order total. Splitting against every donation ticket on the order (any
  # status) keeps a later refund of a remaining donation at the original
  # per-ticket amount.
  defp fetch_refundable_tickets(ticket_order, ticket_ids) do
    ticket_id_set =
      ticket_ids
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    order_tickets =
      ticket_order.id
      |> order_tickets_for_refund_query()
      |> Repo.all()

    tickets_to_refund =
      Enum.filter(order_tickets, fn ticket ->
        ticket.status in [:confirmed, :pending] and
          MapSet.member?(ticket_id_set, to_string(ticket.id))
      end)

    if tickets_to_refund == [] do
      {:error, :no_valid_tickets}
    else
      amounts =
        DonationDisplay.money_amounts_by_ticket_id(%{
          tickets: order_tickets,
          total_amount: ticket_order.total_amount
        })

      refund_amount =
        Enum.reduce(tickets_to_refund, Money.new(0, :USD), fn ticket, acc ->
          case Money.add(
                 acc,
                 Map.get(amounts, ticket.id, Money.new(0, :USD))
               ) do
            {:ok, new_total} -> new_total
            {:error, _} -> acc
          end
        end)

      {:ok,
       %{tickets_to_refund: tickets_to_refund, refund_amount: refund_amount}}
    end
  end

  defp order_tickets_for_refund_query(ticket_order_id) do
    from(t in Ticket,
      where: t.ticket_order_id == ^ticket_order_id,
      preload: [:ticket_tier]
    )
  end

  @doc """
  Expires a ticket order that has exceeded the payment timeout.

  Skips expiration when checkout payment is in flight (same guard as
  `CheckoutCancel`), so a late capture is not raced against released tickets.

  When a PaymentIntent is present, Stripe cancel runs *before* inventory is
  released — the same atomic reconcile as `cancel_ticket_order/3`.
  `StripeService.cancel_payment_intent/1` treats a succeeded PaymentIntent as
  `:ok`, so the previous expire-then-cancel path could release tickets after a
  captured charge. Late fulfillment then re-checked capacity against seats
  that were already given away, and `maybe_refund_unfulfilled_ticket_payment/3`
  only auto-refunds `:amount_mismatch`.
  """
  def expire_ticket_order(ticket_order) do
    if CheckoutCancel.pending_order_safe_to_cancel?(ticket_order,
         context: "expire_ticket_order"
       ) do
      expire_after_stripe_reconcile(ticket_order)
    else
      require Ysc.Logging

      Ysc.Logging.info(
        "Skipped ticket order expiration while checkout payment is in flight",
        ticket_order_id: ticket_order.id,
        payment_intent_id: ticket_order.payment_intent_id
      )

      {:ok, ticket_order}
    end
  end

  defp expire_after_stripe_reconcile(ticket_order) do
    require Ysc.Logging

    case CheckoutCancel.cancel_payment_intent_for_abandoned_checkout(
           ticket_order,
           "expire_ticket_order"
         ) do
      {:cancel, _payment_intent} ->
        do_expire_ticket_order(ticket_order)

      {:already_succeeded, payment_intent} ->
        fulfill_succeeded_checkout_payment(ticket_order, payment_intent)

      {:in_progress, _payment_intent} ->
        Ysc.Logging.info(
          "Skipped ticket order expiration while checkout payment is in flight",
          ticket_order_id: ticket_order.id,
          payment_intent_id: ticket_order.payment_intent_id
        )

        {:ok, ticket_order}

      {:error, stripe_error} ->
        Ysc.Logging.warning(
          "Could not reconcile checkout payment with Stripe, not expiring order",
          ticket_order_id: ticket_order.id,
          payment_intent_id: ticket_order.payment_intent_id,
          error: inspect(stripe_error)
        )

        {:ok, ticket_order}
    end
  end

  # Shared by checkout-abandonment cancel and payment-timeout expiry: Stripe
  # already captured the charge, so fulfill while tickets are still pending
  # rather than releasing inventory first.
  defp fulfill_succeeded_checkout_payment(ticket_order, payment_intent) do
    require Ysc.Logging

    case Ysc.Tickets.StripeService.process_successful_payment(payment_intent) do
      {:ok, completed_order} = ok ->
        Ysc.Logging.info(
          "Fulfilled ticket order after payment succeeded during checkout reconcile",
          ticket_order_id: completed_order.id,
          payment_intent_id: payment_intent.id
        )

        ok

      {:error, fulfillment_error} ->
        Ysc.Logging.error(
          "Payment succeeded during checkout reconcile but order could not be fulfilled",
          ticket_order_id: ticket_order.id,
          payment_intent_id: payment_intent.id,
          error: inspect(fulfillment_error)
        )

        # Tagged distinctly from a plain cancel/expire failure: the customer's
        # card was already charged, so callers must not treat this like an
        # ordinary timeout.
        {:error, {:payment_succeeded_fulfillment_failed, fulfillment_error}}
    end
  end

  defp do_expire_ticket_order(ticket_order) do
    now = DateTime.utc_now()

    result =
      Repo.transaction(fn ->
        {count, _} =
          from(to in TicketOrder,
            where: to.id == ^ticket_order.id and to.status == :pending
          )
          |> Repo.update_all(
            set: [
              status: :expired,
              cancelled_at: now,
              cancellation_reason: "Payment timeout",
              updated_at: now
            ]
          )

        if count == 1 do
          from(t in Ticket,
            where:
              t.ticket_order_id == ^ticket_order.id and t.status == :pending
          )
          |> Repo.update_all(set: [status: :expired, updated_at: now])

          case get_ticket_order(ticket_order.id) do
            nil -> Repo.rollback({:error, :not_found})
            updated_order -> {:expired, updated_order}
          end
        else
          case get_ticket_order(ticket_order.id) do
            nil -> Repo.rollback({:error, :not_found})
            order -> {:skipped, order}
          end
        end
      end)

    case result do
      {:ok, {:expired, updated_order}} ->
        event = %Ysc.MessagePassingEvents.CheckoutSessionExpired{
          ticket_order: updated_order,
          user_id: updated_order.user_id,
          event_id: updated_order.event_id
        }

        broadcast_to_user(updated_order.user_id, event)
        broadcast_ticket_availability_update(updated_order.event_id)
        {:ok, updated_order}

      {:ok, {:skipped, order}} ->
        {:ok, order}

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
    tier_ids = Map.keys(ticket_selections)
    tiers_by_id = batch_load_tiers_for_capacity(tier_ids)
    sold_counts = batch_count_sold_tickets_for_tiers(tier_ids)

    non_donation_qty =
      non_donation_ticket_quantity(ticket_selections, tiers_by_id)

    # Check if event is at capacity (donation-only purchases are still allowed)
    if non_donation_qty > 0 and event_at_capacity?(event) do
      {:error, :event_at_capacity}
    else
      # Check each ticket tier capacity (donation tiers skip tier/event capacity)
      tier_validations =
        Enum.map(ticket_selections, fn {tier_id, quantity} ->
          validate_tier_capacity(tier_id, quantity, tiers_by_id, sold_counts)
        end)

      if Enum.any?(tier_validations, &(&1 == :error)) do
        {:error, :tier_capacity_exceeded}
      else
        if within_event_capacity?(event, non_donation_qty) do
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
  Counts confirmed attendee tickets for an event (donation tiers excluded).
  """
  def count_confirmed_tickets_for_event(event_id) do
    Ysc.Events.count_tickets_sold_excluding_donations(event_id)
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
  def process_ticket_order_payment(ticket_order, payment_intent_id)
      when is_binary(payment_intent_id) do
    ticket_order = ensure_ticket_order_for_payment(ticket_order)

    cond do
      ticket_order_fully_finalized?(ticket_order) ->
        {:ok, completed_ticket_order_for_return(ticket_order)}

      ticket_order_completed?(ticket_order) ->
        with {:ok, payment_intent} <-
               Ysc.Stripe.RetryHelper.stripe_retry(fn ->
                 stripe_client().retrieve_payment_intent(payment_intent_id, %{})
               end) do
          finalize_already_completed_ticket_order(ticket_order, payment_intent)
        end

      true ->
        with {:ok, payment_intent} <-
               Ysc.Stripe.RetryHelper.stripe_retry(fn ->
                 stripe_client().retrieve_payment_intent(payment_intent_id, %{})
               end) do
          process_ticket_order_payment(ticket_order, payment_intent)
        end
    end
  end

  def process_ticket_order_payment(
        ticket_order,
        %Stripe.PaymentIntent{} = payment_intent
      ) do
    start_time = System.monotonic_time()

    ticket_order =
      ticket_order.id
      |> get_ticket_order()
      |> ensure_ticket_order_for_payment()

    result =
      cond do
        ticket_order_fully_finalized?(ticket_order) ->
          {:ok, completed_ticket_order_for_return(ticket_order)}

        ticket_order_completed?(ticket_order) ->
          finalize_already_completed_ticket_order(ticket_order, payment_intent)

        true ->
          do_process_ticket_order_payment(ticket_order, payment_intent)
      end

    emit_payment_processed_telemetry(
      start_time,
      ticket_order,
      payment_intent.id,
      result
    )

    result
  end

  defp do_process_ticket_order_payment(ticket_order, payment_intent) do
    # Complete the order before recording ledger payment so a concurrent cancel
    # cannot leave a Stripe charge recorded without tickets (see booking checkout).
    with {:ok, ticket_order} <-
           sync_pending_order_pricing_for_fulfillment(ticket_order),
         :ok <- validate_fulfillable_order_status(ticket_order),
         :ok <- validate_payment_intent(payment_intent, ticket_order),
         :ok <- validate_expired_order_fulfillment_capacity(ticket_order),
         {:ok, completed_order, completion_status} <-
           complete_ticket_order_if_pending(ticket_order, nil),
         :ok <- confirm_tickets(completed_order),
         {:ok, {payment, _transaction, _entries}} <-
           process_ledger_payment(ticket_order, payment_intent),
         :ok <- attach_ledger_payment_to_order(completed_order.id, payment.id) do
      reloaded_order =
        if completion_status == :newly_completed do
          get_ticket_order(completed_order.id)
        else
          completed_order
        end

      if completion_status == :newly_completed do
        send_ticket_confirmation_email(reloaded_order)
        broadcast_ticket_availability_update(ticket_order.event_id)
      end

      {:ok, reloaded_order}
    else
      {:error, reason} = error ->
        maybe_refund_unfulfilled_ticket_payment(
          ticket_order,
          payment_intent,
          reason
        )

        error
    end
  end

  defp complete_ticket_order_if_pending(ticket_order, payment_id, opts \\ []) do
    from_statuses = Keyword.get(opts, :from_statuses, [:pending, :expired])
    now = DateTime.utc_now()

    # Allow :expired so a succeeded Stripe payment can still fulfill tickets when
    # TimeoutWorker wins the race against payment_intent.succeeded / redirect return.
    {count, _} =
      from(to in TicketOrder,
        where: to.id == ^ticket_order.id and to.status in ^from_statuses
      )
      |> Repo.update_all(
        set: [
          status: :completed,
          payment_id: payment_id,
          completed_at: now,
          updated_at: now
        ]
      )

    cond do
      count == 1 ->
        {:ok,
         %{
           ticket_order
           | status: :completed,
             payment_id: payment_id,
             completed_at: now,
             updated_at: now
         }, :newly_completed}

      ticket_order.status == :completed ->
        {:ok, ticket_order, :already_completed}

      true ->
        case get_ticket_order(ticket_order.id) do
          %{status: :completed} = order ->
            {:ok, order, :already_completed}

          _ ->
            {:error, :cannot_complete_order}
        end
    end
  end

  defp ensure_ticket_order_for_payment(%TicketOrder{} = ticket_order) do
    if ticket_order_ready_for_payment?(ticket_order) do
      ticket_order
    else
      get_ticket_order_for_checkout(ticket_order.id)
    end
  end

  defp ticket_order_completed?(%TicketOrder{status: :completed}), do: true

  defp ticket_order_completed?(%TicketOrder{id: id}) do
    TicketOrder
    |> where([t], t.id == ^id and t.status == :completed)
    |> Repo.exists?()
  end

  defp ticket_order_expired?(%{expires_at: expires_at})
       when not is_nil(expires_at) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  defp ticket_order_expired?(_), do: false

  defp ticket_order_fully_finalized?(%TicketOrder{} = ticket_order) do
    ticket_order.status == :completed and not is_nil(ticket_order.payment_id) and
      tickets_all_confirmed?(ticket_order)
  end

  defp tickets_all_confirmed?(%TicketOrder{tickets: tickets})
       when is_list(tickets) and tickets != [] do
    Enum.all?(tickets, &(&1.status == :confirmed))
  end

  defp tickets_all_confirmed?(%TicketOrder{id: id}) do
    total =
      from(t in Ysc.Events.Ticket, where: t.ticket_order_id == ^id)
      |> Repo.aggregate(:count)

    unconfirmed =
      from(t in Ysc.Events.Ticket,
        where: t.ticket_order_id == ^id and t.status != :confirmed
      )
      |> Repo.aggregate(:count)

    total > 0 and unconfirmed == 0
  end

  defp completed_ticket_order_for_return(
         %TicketOrder{status: :completed} = ticket_order
       ) do
    ticket_order
  end

  defp completed_ticket_order_for_return(%TicketOrder{id: id}) do
    get_ticket_order(id)
  end

  # Idempotent recovery when the order row is already :completed but ticket
  # confirmation and/or ledger recording did not finish.
  defp finalize_already_completed_ticket_order(ticket_order, payment_intent) do
    with :ok <- confirm_tickets(ticket_order),
         {:ok, {payment, _transaction, _entries}} <-
           process_ledger_payment(ticket_order, payment_intent),
         :ok <- attach_ledger_payment_to_order(ticket_order.id, payment.id) do
      {:ok, completed_ticket_order_for_return(ticket_order)}
    end
  end

  defp attach_ledger_payment_to_order(ticket_order_id, payment_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(to in TicketOrder,
      where: to.id == ^ticket_order_id and is_nil(to.payment_id)
    )
    |> Repo.update_all(set: [payment_id: payment_id, updated_at: now])

    :ok
  end

  defp ticket_order_ready_for_payment?(%TicketOrder{} = ticket_order) do
    Ecto.assoc_loaded?(ticket_order.user) and
      Ecto.assoc_loaded?(ticket_order.tickets) and
      Enum.all?(ticket_order.tickets, &Ecto.assoc_loaded?(&1.ticket_tier))
  end

  defp emit_payment_processed_telemetry(
         start_time,
         ticket_order,
         payment_intent_id,
         result
       ) do
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
  end

  @doc """
  Builds tier selection counts/amounts from a ticket order for pricing lookups.
  """
  def ticket_selections_from_order(%TicketOrder{} = ticket_order) do
    ticket_order
    |> ensure_ticket_order_for_payment()
    |> Map.update!(:tickets, fn tickets ->
      Enum.filter(tickets, &(&1.status == :pending))
    end)
    |> do_ticket_selections_from_order()
  end

  @doc """
  Recalculates a pending order total using current tier prices and reservations.
  """
  def recalculate_pending_order_total(%TicketOrder{} = ticket_order) do
    {:ok, total, _discount} = recalculate_pending_order_pricing(ticket_order)
    {:ok, total}
  end

  @doc """
  Recalculates pending order pricing using current tier prices and reservations.

  Returns `{:ok, total, discount}`.
  """
  def recalculate_pending_order_pricing(
        %TicketOrder{status: :expired} = ticket_order
      ) do
    selections = expired_ticket_selections(ticket_order.id)

    if map_size(selections) == 0 do
      {:ok, ticket_order.total_amount,
       ticket_order.discount_amount || Money.new(0, :USD)}
    else
      BookingLocker.estimate_order_total(
        ticket_order.user_id,
        ticket_order.event_id,
        selections,
        include_fulfilled_for_order_id: ticket_order.id
      )
    end
  end

  def recalculate_pending_order_pricing(%TicketOrder{} = ticket_order) do
    selections = ticket_selections_from_order(ticket_order)

    BookingLocker.estimate_order_total(
      ticket_order.user_id,
      ticket_order.event_id,
      selections,
      include_fulfilled_for_order_id: ticket_order.id
    )
  end

  @doc """
  Persists recalculated pricing for a pending or expired ticket order.

  Mirrors booking hold checkout pricing sync so Stripe PaymentIntents and
  payment verification use current tier prices instead of the snapshot taken
  when the order was created.
  """
  def sync_pending_order_pricing(%TicketOrder{status: status} = ticket_order)
      when status in [:pending, :expired] do
    ticket_order = ensure_ticket_order_for_payment(ticket_order)

    if CheckoutCancel.checkout_payment_in_flight?(ticket_order,
         context: "sync_pending_order_pricing"
       ) do
      {:ok, ticket_order}
    else
      do_sync_pending_order_pricing(ticket_order)
    end
  end

  def sync_pending_order_pricing(%TicketOrder{} = ticket_order) do
    {:ok, ensure_ticket_order_for_payment(ticket_order)}
  end

  @doc """
  Persists recalculated pricing immediately before ticket fulfillment.

  Unlike `sync_pending_order_pricing/1`, this always reprices even when a
  payment intent is in flight. Checkout UI uses the guarded variant so 3DS
  is not interrupted; fulfillment must verify against current tier prices.
  """
  def sync_pending_order_pricing_for_fulfillment(
        %TicketOrder{status: status} = ticket_order
      )
      when status in [:pending, :expired] do
    ticket_order
    |> ensure_ticket_order_for_payment()
    |> do_sync_pending_order_pricing()
  end

  def sync_pending_order_pricing_for_fulfillment(%TicketOrder{} = ticket_order) do
    {:ok, ensure_ticket_order_for_payment(ticket_order)}
  end

  defp do_sync_pending_order_pricing(ticket_order) do
    with {:ok, total, discount} <-
           recalculate_pending_order_pricing(ticket_order) do
      attrs = pending_order_pricing_attrs(total, discount)

      if pending_order_pricing_unchanged?(ticket_order, attrs) do
        {:ok, ticket_order}
      else
        ticket_order
        |> Ecto.Changeset.change(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, ensure_ticket_order_for_payment(updated)}
          {:error, _} = error -> error
        end
      end
    end
  end

  @doc """
  Returns true when a pending order is still complimentary at current tier prices.
  """
  def pending_order_still_complimentary?(%TicketOrder{} = ticket_order) do
    {:ok, total} = recalculate_pending_order_total(ticket_order)
    Money.zero?(total)
  end

  @doc """
  Processes a free ticket order (no payment required).
  """
  def process_free_ticket_order(%TicketOrder{} = ticket_order) do
    cond do
      ticket_order.status != :pending ->
        {:error, :order_not_pending}

      ticket_order_expired?(ticket_order) ->
        {:error, :order_expired}

      not pending_order_still_complimentary?(ticket_order) ->
        {:error, :payment_required}

      true ->
        case complete_ticket_order_if_pending(ticket_order, nil,
               from_statuses: [:pending]
             ) do
          {:ok, completed_order, :newly_completed} ->
            with :ok <- confirm_tickets(completed_order) do
              reloaded_order = get_ticket_order(completed_order.id)
              send_ticket_confirmation_email(reloaded_order)
              broadcast_ticket_availability_update(ticket_order.event_id)
              {:ok, reloaded_order}
            end

          {:ok, completed_order, :already_completed} ->
            {:ok, completed_order}

          {:error, _} = error ->
            error
        end
    end
  end

  def process_free_ticket_order(_ticket_order), do: {:error, :order_not_pending}

  defp do_ticket_selections_from_order(%TicketOrder{tickets: []}), do: %{}

  defp do_ticket_selections_from_order(%TicketOrder{} = ticket_order) do
    tickets = ticket_order.tickets

    tickets
    |> Enum.group_by(& &1.ticket_tier_id)
    |> Enum.reduce(%{}, fn {tier_id, tier_tickets}, acc ->
      first_ticket = List.first(tier_tickets)
      tier = first_ticket.ticket_tier
      quantity = length(tier_tickets)

      if TicketTierHelpers.donation_tier?(tier) do
        {_gross_event_amount, donation_amount, _discount_amount} =
          calculate_event_and_donation_amounts(ticket_order)

        donation_tickets_count =
          Enum.count(tickets, fn t ->
            TicketTierHelpers.donation_tier?(t.ticket_tier)
          end)

        if donation_tickets_count > 0 do
          case Money.div(donation_amount, donation_tickets_count) do
            {:ok, amount_per_ticket} ->
              {:ok, tier_donation_total} =
                Money.mult(amount_per_ticket, quantity)

              Map.put(
                acc,
                tier_id,
                MoneyHelper.money_to_cents(tier_donation_total)
              )

            _ ->
              acc
          end
        else
          acc
        end
      else
        Map.put(acc, tier_id, quantity)
      end
    end)
  end

  defp pending_order_pricing_attrs(total, discount) do
    zero = Money.new(0, :USD)

    %{
      total_amount: total,
      discount_amount:
        if(discount && Money.positive?(discount), do: discount, else: zero)
    }
  end

  defp pending_order_pricing_unchanged?(ticket_order, attrs) do
    money_equal?(ticket_order.total_amount, attrs.total_amount) and
      money_equal?(ticket_order.discount_amount, attrs.discount_amount)
  end

  defp money_equal?(%Money{} = left, %Money{} = right),
    do: Money.equal?(left, right)

  defp money_equal?(nil, %Money{} = right), do: Money.zero?(right)
  defp money_equal?(%Money{} = left, nil), do: Money.zero?(left)
  defp money_equal?(nil, nil), do: true

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
    require Ysc.Logging

    try do
      pending_orders =
        TicketOrder
        |> where([to], to.status == :pending)
        |> preload(:tickets)
        |> Repo.all()

      count = length(pending_orders)

      if count > 0 do
        Ysc.Logging.info("Manually expiring all pending checkout sessions",
          total_sessions: count
        )

        Enum.each(pending_orders, fn ticket_order ->
          expire_ticket_order(ticket_order)
        end)

        Ysc.Logging.info("Successfully expired all pending checkout sessions",
          expired_count: count
        )
      else
        Ysc.Logging.info("No pending checkout sessions found to expire")
      end

      {:ok, count}
    rescue
      error ->
        require Ysc.Logging

        Ysc.Logging.error("Failed to expire pending checkout sessions",
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
    require Ysc.Logging

    try do
      pending_orders =
        TicketOrder
        |> where([to], to.user_id == ^user_id and to.status == :pending)
        |> preload(:tickets)
        |> Repo.all()

      count = length(pending_orders)

      if count > 0 do
        Ysc.Logging.info("Manually expiring pending checkout sessions for user",
          user_id: user_id,
          total_sessions: count
        )

        Enum.each(pending_orders, fn ticket_order ->
          expire_ticket_order(ticket_order)
        end)

        Ysc.Logging.info(
          "Successfully expired user's pending checkout sessions",
          user_id: user_id,
          expired_count: count
        )
      else
        Ysc.Logging.info("No pending checkout sessions found for user",
          user_id: user_id
        )
      end

      {:ok, count}
    rescue
      error ->
        require Ysc.Logging

        Ysc.Logging.error("Failed to expire user's pending checkout sessions",
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
    require Ysc.Logging

    try do
      pending_orders =
        TicketOrder
        |> where([to], to.event_id == ^event_id and to.status == :pending)
        |> preload(:tickets)
        |> Repo.all()

      count = length(pending_orders)

      if count > 0 do
        Ysc.Logging.info(
          "Manually expiring pending checkout sessions for event",
          event_id: event_id,
          total_sessions: count
        )

        Enum.each(pending_orders, fn ticket_order ->
          expire_ticket_order(ticket_order)
        end)

        Ysc.Logging.info(
          "Successfully expired event's pending checkout sessions",
          event_id: event_id,
          expired_count: count
        )
      else
        Ysc.Logging.info("No pending checkout sessions found for event",
          event_id: event_id
        )
      end

      {:ok, count}
    rescue
      error ->
        require Ysc.Logging

        Ysc.Logging.error("Failed to expire event's pending checkout sessions",
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

  defp prepare_new_checkout_session(user_id, event_id) do
    require Ysc.Logging

    # Same cheap pre-check EventDetailsLive uses before teardown cancel: skip
    # orders whose PaymentIntent is already in 3DS / processing / succeeded.
    # Stripe accepts cancelling a requires_action PaymentIntent instead of
    # refusing it, so without this, starting a second checkout could cancel
    # a payment the user is actively completing elsewhere. Orders that look
    # safe here still go through cancel_ticket_order/3's atomic cancel below,
    # which can still discover the payment succeeded moments later (the same
    # TOCTOU race the atomic cancel closes) - that's what
    # fulfilled_during_cleanup? catches. Orders filtered out here are left
    # pending, caught below by blocking_pending_orders/2.
    fulfilled_during_cleanup? =
      from(to in TicketOrder,
        where:
          to.user_id == ^user_id and to.event_id == ^event_id and
            to.status == :pending
      )
      |> Repo.all()
      |> Enum.filter(
        &CheckoutCancel.pending_order_safe_to_cancel?(&1,
          context: "create_ticket_order"
        )
      )
      |> Enum.map(fn order ->
        cancel_ticket_order(order, "Superseded by new checkout",
          context: "create_ticket_order"
        )
      end)
      |> Enum.any?(fn
        {:ok, %TicketOrder{status: :completed}} -> true
        _ -> false
      end)

    cond do
      fulfilled_during_cleanup? ->
        # A stale pending order's payment turned out to have already
        # succeeded with Stripe, and cancel_ticket_order/3 just fulfilled it
        # instead of orphaning that charge. Block starting a brand-new
        # checkout for this event so the user doesn't pay twice - they
        # already have tickets from the order we just completed.
        Ysc.Logging.info(
          "Blocked new ticket checkout: an abandoned order for this event was fulfilled during cleanup",
          user_id: user_id,
          event_id: event_id
        )

        {:error, :checkout_payment_in_progress}

      true ->
        case CheckoutCancel.blocking_pending_orders(user_id, event_id) do
          [] ->
            :ok

          orders ->
            Ysc.Logging.info(
              "Blocked new ticket checkout while another payment is in flight",
              user_id: user_id,
              event_id: event_id,
              pending_order_ids: Enum.map(orders, & &1.id)
            )

            {:error, :checkout_payment_in_progress}
        end
    end
  end

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

  # Enforces the "member only" ticket-tier rules for this checkout.
  #
  # Loads only `id` / `member_only` / `type` for the selected tiers (PK lookup,
  # no sold-count aggregation). The owned-ticket COUNT runs only when a
  # finite per-event limit applies — Single members buying a member-only
  # tier. Family/lifetime (unlimited) and regular-tier checkouts skip it.
  # See `Ysc.Events.MemberOnlyTickets` for the per-plan rules.
  defp validate_member_only_selection(user, event_id, ticket_selections) do
    ticket_tiers =
      ticket_selections
      |> Map.keys()
      |> Ysc.Events.list_ticket_tier_member_only_attrs()

    if MemberOnlyTickets.any_member_only?(ticket_tiers) do
      plan_type = MembershipCache.get_membership_plan_type(user)
      limit = MemberOnlyTickets.event_limit(plan_type)

      already_owned =
        if needs_owned_member_only_count?(limit) do
          count_owned_member_only_tickets(user.id, event_id)
        else
          0
        end

      MemberOnlyTickets.validate_selection(
        ticket_selections,
        ticket_tiers,
        limit,
        already_owned
      )
    else
      :ok
    end
  end

  # Only Single (limit 1) needs to know how many member-only tickets the buyer
  # already holds. Unlimited plans and ineligible buyers don't.
  defp needs_owned_member_only_count?(limit)
       when is_integer(limit) and limit > 0,
       do: true

  defp needs_owned_member_only_count?(_), do: false

  defp count_owned_member_only_tickets(user_id, event_id) do
    user_id
    |> owned_member_only_tickets_count_query(event_id)
    |> Repo.one()
  end

  defp owned_member_only_tickets_count_query(user_id, event_id) do
    from(t in Ticket,
      join: tt in TicketTier,
      on: tt.id == t.ticket_tier_id,
      where:
        t.user_id == ^user_id and t.event_id == ^event_id and
          t.status == :confirmed and tt.member_only == true and
          tt.type != :donation,
      select: count(t.id)
    )
  end

  defp validate_tier_capacity(
         tier_id,
         requested_quantity,
         tiers_by_id,
         sold_counts
       ) do
    case Map.get(tiers_by_id, tier_id) do
      nil ->
        :error

      tier ->
        if TicketTierHelpers.donation_tier?(tier) do
          :ok
        else
          available = get_available_tier_quantity(tier, sold_counts)

          if available == :unlimited or requested_quantity <= available do
            :ok
          else
            :error
          end
        end
    end
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

  defp get_available_tier_quantity(%TicketTier{quantity: nil}, _sold_counts),
    do: :unlimited

  defp get_available_tier_quantity(%TicketTier{quantity: 0}, _sold_counts),
    do: :unlimited

  defp get_available_tier_quantity(
         %TicketTier{id: tier_id, quantity: total_quantity},
         sold_counts
       ) do
    sold_count = Map.get(sold_counts, tier_id, 0)
    max(0, total_quantity - sold_count)
  end

  defp batch_load_tiers_for_capacity([]), do: %{}

  defp batch_load_tiers_for_capacity(tier_ids) do
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

  defp within_event_capacity?(%Event{max_attendees: nil}, _), do: true

  defp within_event_capacity?(
         %Event{max_attendees: max_attendees} = event,
         requested_quantity
       ) do
    current_attendees = count_confirmed_tickets_for_event(event.id)
    current_attendees + requested_quantity <= max_attendees
  end

  defp validate_fulfillable_order_status(ticket_order) do
    case Repo.get(TicketOrder, ticket_order.id) do
      %{status: status} when status in [:pending, :expired] ->
        :ok

      _ ->
        {:error, :cannot_complete_order}
    end
  end

  defp validate_expired_order_fulfillment_capacity(ticket_order) do
    case Repo.get(TicketOrder, ticket_order.id) do
      %{status: :expired, user_id: user_id, event_id: event_id} = expired_order ->
        ticket_selections = expired_ticket_selections(expired_order.id)

        if map_size(ticket_selections) == 0 do
          :ok
        else
          BookingLocker.validate_fulfillment_capacity(
            user_id,
            event_id,
            ticket_selections,
            expired_fulfillment_capacity_opts(event_id)
          )
        end

      _ ->
        :ok
    end
  end

  # Door sales (#1186) create pending tickets *after* the event has started
  # (`bypass_guards: true`). If TimeoutWorker expires that cart and Stripe
  # later reports a succeeded PaymentIntent, late-payment recovery must not
  # re-apply the web-checkout "event in past" / capacity guards — those
  # reject a charge that already went through, and
  # `maybe_refund_unfulfilled_ticket_payment/3` only auto-refunds
  # `:amount_mismatch`. Web checkout cannot create pending tickets for an
  # in-progress event, and the public UI closes sales at start, so skipping
  # here does not reopen self-service overbooking.
  defp expired_fulfillment_capacity_opts(event_id) do
    case Repo.get(Event, event_id) do
      %Event{} = event ->
        if EventDateTime.in_past?(event) do
          [skip_sale_guards: true, skip_capacity: true]
        else
          []
        end

      _ ->
        []
    end
  end

  defp expired_ticket_selections(ticket_order_id) do
    from(t in Ticket,
      where: t.ticket_order_id == ^ticket_order_id and t.status == :expired,
      select: {t.ticket_tier_id, count(t.id)},
      group_by: t.ticket_tier_id
    )
    |> Repo.all()
    |> Map.new()
  end

  defp validate_payment_intent(payment_intent, ticket_order) do
    metadata = payment_intent.metadata || %{}

    metadata_order_id =
      Map.get(metadata, "ticket_order_id") ||
        Map.get(metadata, :ticket_order_id)

    metadata_user_id =
      Map.get(metadata, "user_id") || Map.get(metadata, :user_id)

    expected_amount = fulfillment_expected_amount_cents(ticket_order)

    cond do
      payment_intent.status != "succeeded" ->
        {:error, :payment_not_succeeded}

      to_string(metadata_order_id || "") != to_string(ticket_order.id) ->
        {:error, :payment_metadata_mismatch}

      to_string(metadata_user_id || "") != to_string(ticket_order.user_id) ->
        {:error, :payment_metadata_mismatch}

      payment_intent.amount != expected_amount ->
        {:error, :amount_mismatch}

      true ->
        :ok
    end
  end

  defp fulfillment_expected_amount_cents(ticket_order) do
    {:ok, total, _} = recalculate_pending_order_pricing(ticket_order)
    MoneyHelper.money_to_cents(total)
  end

  @refundable_unfulfilled_ticket_errors ~w(amount_mismatch)a

  @doc """
  Refunds a captured Stripe payment when ticket fulfillment fails and the
  order remains uncompleted (for example, tier prices changed during checkout).
  """
  def maybe_refund_unfulfilled_ticket_payment(
        %TicketOrder{} = ticket_order,
        %Stripe.PaymentIntent{} = payment_intent,
        reason
      ) do
    require Ysc.Logging

    normalized_reason = normalize_ticket_fulfillment_failure_reason(reason)

    if refund_unfulfilled_ticket_payment?(
         ticket_order,
         payment_intent,
         normalized_reason
       ) do
      refund_reason = "unfulfilled_ticket:#{normalized_reason}"

      case Ysc.Bookings.create_stripe_refund_for_admin(
             payment_intent.id,
             payment_intent.amount,
             refund_reason
           ) do
        {:ok, refund} ->
          Ysc.Logging.info(
            "Refunded captured ticket payment after fulfillment failure",
            ticket_order_id: ticket_order.id,
            payment_intent_id: payment_intent.id,
            refund_id: refund.id,
            reason: normalized_reason
          )

          {:ok, refund}

        {:error, refund_error} ->
          Ysc.Logging.error(
            "Failed to refund captured ticket payment after fulfillment failure",
            ticket_order_id: ticket_order.id,
            payment_intent_id: payment_intent.id,
            reason: normalized_reason,
            refund_error: inspect(refund_error)
          )

          {:error, refund_error}
      end
    else
      :skipped
    end
  end

  defp refund_unfulfilled_ticket_payment?(
         %TicketOrder{} = ticket_order,
         %Stripe.PaymentIntent{} = payment_intent,
         reason
       ) do
    payment_intent.status == "succeeded" and
      ticket_order.status in [:pending, :expired] and
      reason in @refundable_unfulfilled_ticket_errors
  end

  defp normalize_ticket_fulfillment_failure_reason({:error, reason}),
    do: normalize_ticket_fulfillment_failure_reason(reason)

  defp normalize_ticket_fulfillment_failure_reason(reason) when is_atom(reason),
    do: reason

  defp normalize_ticket_fulfillment_failure_reason(_), do: :unknown

  defp process_ledger_payment(ticket_order, payment_intent) do
    # Use consolidated fee extraction from Stripe.WebhookHandler
    stripe_fee =
      Ysc.Stripe.WebhookHandler.extract_stripe_fee_from_payment_intent(
        payment_intent
      )

    ticket_order = ensure_ticket_order_for_payment(ticket_order)

    # Calculate donation vs regular ticket amounts (returns gross amount, donation, discount)
    {gross_event_amount, donation_amount, discount_amount} =
      calculate_event_and_donation_amounts(ticket_order)

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
    require Ysc.Logging

    case payment_intent.payment_method do
      nil ->
        Ysc.Logging.info("No payment method found in payment intent",
          payment_intent_id: payment_intent.id
        )

        nil

      payment_method_id when is_binary(payment_method_id) ->
        # Retrieve the full payment method from Stripe
        case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
               stripe_payment_method_module().retrieve(payment_method_id)
             end) do
          {:ok, stripe_payment_method} ->
            user = Ysc.Accounts.get_user!(user_id)

            # Sync the payment method to our database
            case Ysc.Payments.sync_payment_method_from_stripe(
                   user,
                   stripe_payment_method
                 ) do
              {:ok, payment_method} ->
                Ysc.Logging.info(
                  "Successfully synced payment method for ticket payment",
                  payment_method_id: payment_method.id,
                  stripe_payment_method_id: payment_method_id,
                  user_id: user_id
                )

                payment_method.id

              {:error, reason} ->
                Ysc.Logging.warning(
                  "Failed to sync payment method for ticket payment",
                  stripe_payment_method_id: payment_method_id,
                  user_id: user_id,
                  error: inspect(reason)
                )

                nil
            end

          {:error, error} ->
            Ysc.Logging.warning("Failed to retrieve payment method from Stripe",
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

  defp confirm_tickets(ticket_order) do
    now = DateTime.utc_now()

    from(t in Ticket,
      where:
        t.ticket_order_id == ^ticket_order.id and
          t.status in [:pending, :expired]
    )
    |> Repo.update_all(set: [status: :confirmed, updated_at: now])

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
    require Ysc.Logging

    Ysc.Logging.info("Broadcasting to user topic",
      user_id: user_id,
      topic: topic_name,
      event_type: event.__struct__,
      event_data: inspect(event, limit: :infinity)
    )

    result =
      Phoenix.PubSub.broadcast(Ysc.PubSub, topic_name, {__MODULE__, event})

    Ysc.Logging.info("PubSub broadcast result",
      user_id: user_id,
      topic: topic_name,
      result: result
    )

    result
  end

  defp broadcast_to_event(event_id, event) do
    topic_name = topic_event(event_id)
    require Ysc.Logging

    Ysc.Logging.info("Broadcasting to event topic",
      event_id: event_id,
      topic: topic_name,
      event_type: event.__struct__
    )

    Phoenix.PubSub.broadcast(Ysc.PubSub, topic_name, {__MODULE__, event})
  end

  defp broadcast_ticket_availability_update(event_id) do
    Ysc.Events.invalidate_event_caches()

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
    require Ysc.Logging

    Ysc.Logging.info(
      "TEST: Manually broadcasting CheckoutSessionCancelled event",
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

    Ysc.Logging.info("TEST: Broadcast completed")
    :ok
  end

  @doc """
  Sends a ticket purchase confirmation email for a completed ticket order.
  """
  def send_ticket_confirmation_email(ticket_order) do
    require Ysc.Logging

    Ysc.Logging.info("Starting ticket confirmation email process",
      ticket_order_id: ticket_order.id,
      user_id: ticket_order.user_id,
      user_email: ticket_order.user.email,
      completed_at: ticket_order.completed_at
    )

    try do
      # Prepare email data
      Ysc.Logging.info(
        "Preparing email data for ticket order #{ticket_order.id}"
      )

      email_data =
        YscWeb.Emails.TicketPurchaseConfirmation.prepare_email_data(
          ticket_order
        )

      Ysc.Logging.info("Email data prepared successfully",
        email_data_keys: Map.keys(email_data)
      )

      # Generate idempotency key
      idempotency_key = "ticket_confirmation_#{ticket_order.id}"

      Ysc.Logging.info("Generated idempotency key: #{idempotency_key}")

      # Schedule the email
      Ysc.Logging.info("Scheduling email with Oban")

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
          Ysc.Logging.info("Ticket confirmation email scheduled successfully",
            ticket_order_id: ticket_order.id,
            user_id: ticket_order.user_id,
            user_email: ticket_order.user.email,
            job_id: job.id,
            idempotency_key: idempotency_key
          )

          :ok

        {:error, reason} ->
          Ysc.Logging.error("Failed to schedule email",
            ticket_order_id: ticket_order.id,
            user_id: ticket_order.user_id,
            error: reason
          )

          :error
      end
    rescue
      error ->
        Ysc.Logging.error("Failed to send ticket confirmation email",
          ticket_order_id: ticket_order.id,
          user_id: ticket_order.user_id,
          user_email: ticket_order.user.email,
          error: error,
          stacktrace: __STACKTRACE__
        )

        :error
    end
  end

  defp stripe_payment_method_module do
    Application.get_env(
      :ysc,
      :stripe_payment_method_module,
      Stripe.PaymentMethod
    )
  end

  defp event_summary_preload_query do
    from(e in Event, select: struct(e, ^Event.summary_fields()))
  end

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    user_id = Fixtures.ulid()
    now = Fixtures.now()

    event_query = event_summary_preload_query()

    from(to in TicketOrder,
      where: to.user_id == ^user_id,
      where: to.status != ^:cancelled,
      join: e in Event,
      on: e.id == to.event_id,
      where: e.start_date > ^now,
      order_by: [desc: to.inserted_at],
      preload: [
        :tickets,
        tickets: :ticket_tier,
        event: ^event_query
      ]
    )
  end

  @doc false
  def ci_query_explain_list_tickets_for_admin_query do
    list_tickets_for_admin_query(Ysc.Ci.QueryExplain.Fixtures.ulid())
  end

  @doc false
  def ci_query_explain_order_tickets_for_refund_query do
    order_tickets_for_refund_query(Ysc.Ci.QueryExplain.Fixtures.ulid())
  end

  @doc false
  def ci_query_explain_payment_refunds_count_query do
    payment_refunds_count_query(Ysc.Ci.QueryExplain.Fixtures.ulid())
  end

  @doc false
  def ci_query_explain_owned_member_only_tickets_count_query do
    ulid = Ysc.Ci.QueryExplain.Fixtures.ulid()
    owned_member_only_tickets_count_query(ulid, ulid)
  end

  defp stripe_client do
    Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)
  end
end
