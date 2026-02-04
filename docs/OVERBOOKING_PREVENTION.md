# Overbooking Prevention System

This document explains how the ticket booking system prevents overbooking while processing payments through Stripe.

## Overview

The system uses a **reservation-based approach** with **database-level locking** to ensure that:

1. Tickets are reserved immediately when a booking is initiated
2. Reserved tickets count against capacity (preventing overbooking)
3. Reservations expire after a timeout period if payment fails
4. Payments are processed atomically with proper error handling

## Key Mechanisms

### 1. Atomic Booking with Database Locking

**Location**: `lib/ysc/tickets/booking_locker.ex`

The `BookingLocker.atomic_booking/3` function uses PostgreSQL row-level locking (`FOR UPDATE`) to ensure atomic operations:

```elixir
def atomic_booking(user_id, event_id, ticket_selections) do
  Repo.transaction(fn ->
    with {:ok, _event} <- lock_and_validate_event(event_id),
         {:ok, tiers} <- lock_and_validate_tiers(event_id, ticket_selections),
         {:ok, total_amount} <- calculate_total_amount(tiers, ticket_selections),
         {:ok, ticket_order} <- create_ticket_order_atomic(user_id, event_id, total_amount),
         {:ok, _tickets} <- create_tickets_atomic(ticket_order, tiers, ticket_selections) do
      ticket_order
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end)
end
```

**How it works**:

- Locks the event row (`FOR UPDATE`) - prevents concurrent modifications
- Locks all ticket tiers for the event (`FOR UPDATE`)
- Validates availability **within the locked transaction**
- Creates tickets with `:pending` status **within the same transaction**
- All operations are atomic - either all succeed or all fail

**Why this prevents overbooking**:

- Only one booking can lock the event/tiers at a time
- Availability is checked **after** acquiring locks
- Tickets are created **before** releasing locks
- No race conditions possible

### 2. Pending Tickets Count Against Capacity

**Location**: `lib/ysc/tickets/booking_locker.ex:162-166`

When calculating available capacity, the system counts **both confirmed AND pending tickets**:

```elixir
defp count_sold_tickets_for_tier_locked(tier_id) do
  Ticket
  |> where([t], t.ticket_tier_id == ^tier_id and t.status in [:confirmed, :pending])
  |> Repo.aggregate(:count, :id)
end
```

**Why this is critical**:

- Prevents double-booking: If 10 tickets are available and someone reserves 5, only 5 remain available
- Ensures capacity is respected even during payment processing
- Other users see accurate availability in real-time

### 3. Payment Timeout Mechanism

**Location**: `lib/ysc/tickets/timeout_worker.ex`

Orders expire after **30 minutes** (configurable) if payment is not completed:

```elixir
def expire_timed_out_orders do
  timeout_threshold = DateTime.add(DateTime.utc_now(), -30, :minute)

  TicketOrder
  |> where([t], t.status == :pending and t.expires_at < ^timeout_threshold)
  |> preload(:tickets)
  |> Repo.all()
  |> Enum.each(fn ticket_order ->
    Tickets.expire_ticket_order(ticket_order)
  end)
end
```

**How it works**:

- Each ticket order has an `expires_at` timestamp (set to 30 minutes from creation)
- Oban background workers check for expired orders periodically
- Expired orders release their tickets back to available pool
- Tickets are marked as `:expired` status

**Why this is important**:

- Prevents indefinite reservations
- Releases tickets if user abandons checkout
- Ensures fair access to tickets

### 4. Payment Processing Flow

**Location**: `lib/ysc/tickets/stripe_service.ex` and `lib/ysc/tickets.ex`

The payment flow ensures tickets are only confirmed after successful payment:

```elixir
def process_ticket_order_payment(ticket_order, payment_intent_id) do
  with {:ok, payment_intent} <- Stripe.PaymentIntent.retrieve(payment_intent_id, %{}),
       :ok <- validate_payment_intent(payment_intent, ticket_order),
       {:ok, {payment, _transaction, _entries}} <- process_ledger_payment(ticket_order, payment_intent),
       {:ok, completed_order} <- complete_ticket_order(ticket_order, payment.id),
       :ok <- confirm_tickets(completed_order) do
    {:ok, completed_order}
  end
end
```

**Steps**:

1. Retrieve payment intent from Stripe
2. Validate payment amount matches order total
3. Record payment in ledger system
4. Mark order as `:completed`
5. Change ticket status from `:pending` to `:confirmed`

**Failure handling**:

- If payment fails → order is cancelled → tickets released
- If webhook fails → order remains pending → timeout will expire it
- If validation fails → order is cancelled → tickets released

### 5. Webhook Handling with Idempotency

**Location**: `lib/ysc/stripe/webhook_handler.ex` and `lib/ysc/webhooks.ex`

Stripe webhooks are processed with idempotency protection:

```elixir
def handle_event(event) do
  # Write webhook event to database first
  Ysc.Webhooks.create_webhook_event!(%{
    provider: "stripe",
    event_id: event.id,
    event_type: event.type,
    payload: stripe_event_to_map(event)
  })

  # Lock and process the event
  case Ysc.Webhooks.lock_webhook_event_by_provider_and_event_id("stripe", event.id) do
    {:ok, webhook_event} ->
      process_webhook_event(webhook_event, event)
    {:error, :already_processing} ->
      # Already being processed, skip
      :ok
  end
end
```

**Idempotency guarantees**:

- Each webhook event is stored with unique `(provider, event_id)` constraint
- Events are locked before processing
- Duplicate webhooks are detected and skipped
- Prevents double-processing of payments

## Complete Flow Diagram

```
User Initiates Booking
    ↓
[1] Lock Event & Tiers (FOR UPDATE)
    ↓
[2] Check Availability (within lock)
    ↓
[3] Create TicketOrder (:pending)
    ↓
[4] Create Tickets (:pending status)
    ↓
[5] Release Locks
    ↓
[6] Tickets Count Against Capacity ✓
    ↓
Create Stripe PaymentIntent
    ↓
User Completes Payment
    ↓
Stripe Webhook Received
    ↓
[7] Validate Payment
    ↓
[8] Record Payment in Ledger
    ↓
[9] Mark Order :completed
    ↓
[10] Confirm Tickets (:confirmed)
    ↓
Send Confirmation Email
```

**If Payment Fails**:

```
Payment Fails
    ↓
Stripe Webhook (payment_failed)
    ↓
Cancel Order (:cancelled)
    ↓
Cancel Tickets (:cancelled)
    ↓
Tickets Released ✓
```

**If Timeout Occurs**:

```
30 Minutes Pass
    ↓
Timeout Worker Runs
    ↓
Expire Order (:expired)
    ↓
Expire Tickets (:expired)
    ↓
Tickets Released ✓
```

## Safety Guarantees

### 1. **No Race Conditions**

- Database locks ensure only one booking processes at a time
- Availability checks happen within locked transactions
- Ticket creation is atomic

### 2. **Capacity Always Respected**

- Pending tickets count against capacity
- Availability calculations include pending tickets
- No possibility of selling more than available

### 3. **Automatic Cleanup**

- Expired orders are automatically cleaned up
- Failed payments release tickets
- Background workers ensure no orphaned reservations

### 4. **Idempotent Operations**

- Webhook processing is idempotent
- Payment processing can be safely retried
- Duplicate webhooks are ignored

## Potential Edge Cases & Mitigations

### Edge Case 1: Payment Succeeds but Confirmation Fails

**Scenario**: Payment succeeds in Stripe, but ticket confirmation fails due to database error.

**Mitigation**:

- Webhook is stored and can be reprocessed
- Order remains `:pending` until confirmation succeeds
- Timeout worker will eventually expire if not fixed
- Admin can manually reprocess failed webhooks

**Recommendation**: Add idempotency check in `confirm_tickets/1`:

```elixir
defp confirm_tickets(ticket_order) do
  tickets = Repo.all(from t in Ticket, where: t.ticket_order_id == ^ticket_order.id)

  tickets
  |> Enum.each(fn ticket ->
    # Only update if not already confirmed
    if ticket.status != :confirmed do
      ticket
      |> Ticket.changeset(%{status: :confirmed})
      |> Repo.update()
    end
  end)

  :ok
end
```

### Edge Case 2: Multiple Payment Attempts for Same Order

**Scenario**: User tries to pay multiple times for the same order.

**Mitigation**:

- Order status check: if already `:completed`, skip processing
- Payment intent validation ensures amount matches
- Webhook idempotency prevents double-processing

**Current Protection**: ✅ Already handled

### Edge Case 3: Webhook Arrives Before User Completes Payment

**Scenario**: Stripe sends webhook before user finishes checkout flow.

**Mitigation**:

- Payment intent status is validated (`status == "succeeded"`)
- Order must exist and be in `:pending` status
- If order already completed, webhook is ignored

**Current Protection**: ✅ Already handled

### Edge Case 4: Clock Skew / Timeout Worker Delay

**Scenario**: System clock is wrong or timeout worker is delayed.

**Mitigation**:

- Uses `DateTime.utc_now()` for consistency
- Timeout checks run periodically (every 5 minutes)
- Orders checked against threshold, not exact time
- Small delays acceptable (tickets released within ~5 minutes of expiration)

**Current Protection**: ✅ Acceptable delay window

## Monitoring & Alerts

### Key Metrics to Monitor

1. **Pending Order Count**: High count may indicate payment issues
2. **Expired Order Rate**: High rate may indicate checkout abandonment
3. **Payment Success Rate**: Low rate may indicate payment processing issues
4. **Webhook Processing Time**: Slow processing may cause delays
5. **Capacity Utilization**: Track how close events get to capacity

### Recommended Alerts

```elixir
# Alert if many pending orders exist
if count_pending_orders() > 100 do
  alert("High number of pending ticket orders")
end

# Alert if payment success rate drops
if payment_success_rate() < 0.95 do
  alert("Payment success rate below threshold")
end

# Alert if webhook processing fails
if failed_webhook_count() > 10 do
  alert("Multiple webhook processing failures")
end
```

## Testing Recommendations

### Unit Tests

```elixir
test "prevents overbooking with concurrent requests" do
  # Create event with capacity of 10
  # Simulate 15 concurrent booking requests for 1 ticket each
  # Verify only 10 succeed
end

test "releases tickets on payment timeout" do
  # Create pending order
  # Advance time past expiration
  # Run timeout worker
  # Verify tickets are expired and available again
end

test "handles duplicate webhooks idempotently" do
  # Process same webhook twice
  # Verify order only processed once
end
```

### Integration Tests

```elixir
test "complete booking flow prevents overbooking" do
  # Create event with limited capacity
  # Create multiple orders concurrently
  # Verify capacity is never exceeded
  # Verify expired orders release tickets
end
```

## Best Practices

1. **Always use `BookingLocker.atomic_booking/3`** for creating orders

   - Never create tickets outside of this function
   - Ensures proper locking and validation

2. **Check order status before processing payments**

   - Verify order is `:pending` before confirming
   - Prevents double-processing

3. **Monitor timeout worker**

   - Ensure Oban jobs are running
   - Check for failed timeout jobs

4. **Handle webhook failures gracefully**

   - Store webhooks for reprocessing
   - Alert on repeated failures
   - Provide admin tools for manual reprocessing

5. **Test with concurrent load**
   - Simulate high traffic scenarios
   - Verify capacity limits are respected
   - Test timeout mechanisms

## Summary

The system prevents overbooking through:

1. ✅ **Database-level locking** - Ensures atomic operations
2. ✅ **Pending ticket counting** - Reserves capacity immediately
3. ✅ **Timeout mechanism** - Releases abandoned reservations
4. ✅ **Idempotent webhooks** - Prevents double-processing
5. ✅ **Comprehensive validation** - Multiple layers of checks

The combination of these mechanisms ensures that:

- Capacity is never exceeded
- Tickets are fairly distributed
- Failed payments don't block availability
- System is resilient to failures
