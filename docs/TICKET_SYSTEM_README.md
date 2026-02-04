# Ticket System Implementation

This document describes the comprehensive ticket system implemented for event management, including multi-ticket orders, payment processing, and overbooking prevention.

## Overview

The ticket system provides:

- **Multi-ticket orders**: Users can purchase multiple tickets from different tiers in a single order
- **15-minute payment timeout**: Orders expire after 15 minutes if payment is not completed
- **Stripe integration**: Secure payment processing with proper ledger integration
- **Overbooking prevention**: Comprehensive validation to prevent exceeding event or tier capacity
- **Real-time availability**: Live updates of ticket availability and capacity

## Core Components

### 1. Database Schema

#### Ticket Orders (`ticket_orders`)

- Groups multiple tickets in a single purchase
- Tracks payment status and timeout
- Links to Stripe payment intents

#### Tickets (`tickets`)

- Individual ticket records
- Belongs to a ticket order
- Tracks confirmation status

### 2. Main Modules

#### `Ysc.Tickets`

The main context module providing:

- `create_ticket_order/3` - Creates orders with multiple tickets
- `validate_booking_capacity/2` - Prevents overbooking
- `process_ticket_order_payment/2` - Handles payment completion
- `expire_timed_out_orders/0` - Cleans up expired orders

#### `Ysc.Tickets.BookingValidator`

Comprehensive validation service:

- Event availability checks
- Tier capacity validation
- User membership requirements
- Concurrent booking prevention

#### `Ysc.Tickets.StripeService`

Stripe payment integration:

- Payment intent creation
- Payment processing
- Customer management
- Fee calculation

#### `Ysc.Tickets.TimeoutWorker`

Background job for timeout management:

- Expires orders after 15 minutes
- Releases reserved tickets
- Scheduled cleanup

## Usage Examples

### Creating a Ticket Order

```elixir
# User selects tickets from different tiers
ticket_selections = %{
  "tier_1_id" => 2,  # 2 tickets from tier 1
  "tier_2_id" => 1   # 1 ticket from tier 2
}

case Ysc.Tickets.create_ticket_order(user_id, event_id, ticket_selections) do
  {:ok, ticket_order} ->
    # Create Stripe payment intent
    {:ok, payment_intent} = Ysc.Tickets.StripeService.create_payment_intent(ticket_order)
    # Redirect to Stripe checkout

  {:error, :overbooked} ->
    # Handle capacity exceeded

  {:error, :membership_required} ->
    # Handle membership requirement
end
```

### Validating Booking Capacity

```elixir
# Check if booking is valid before creating order
case Ysc.Tickets.BookingValidator.validate_booking(user_id, event_id, ticket_selections) do
  :ok ->
    # Proceed with order creation

  {:error, :event_at_capacity} ->
    # Event is full

  {:error, :tier_capacity_exceeded} ->
    # Specific tier is sold out
end
```

### Processing Payment Completion

```elixir
# Handle successful payment from Stripe webhook
case Ysc.Tickets.StripeService.process_successful_payment(payment_intent_id) do
  {:ok, completed_order} ->
    # Order completed, tickets confirmed

  {:error, reason} ->
    # Handle payment processing error
end
```

## Key Features

### 1. Overbooking Prevention

The system prevents overbooking through multiple validation layers:

- **Event capacity**: Respects `max_attendees` setting
- **Tier capacity**: Honors individual ticket tier limits
- **Real-time validation**: Checks availability at order creation
- **Concurrent booking prevention**: Prevents multiple pending orders per user

### 2. Payment Timeout Management

- **15-minute timeout**: Orders expire if payment not completed
- **Automatic cleanup**: Background worker releases expired tickets
- **Real-time updates**: UI shows countdown to expiration

### 3. Stripe Integration

- **Payment intents**: Secure payment processing
- **Webhook handling**: Automatic order completion
- **Fee tracking**: Accurate Stripe fee recording in ledger
- **Customer management**: Stripe customer creation and management

### 4. Ledger Integration

All payments are properly recorded in the double-entry ledger system:

- **Revenue tracking**: Event revenue properly categorized
- **Fee recording**: Stripe fees tracked as expenses
- **Audit trail**: Complete transaction history

## API Reference

### Ticket Orders

```elixir
# Create a new ticket order
Ysc.Tickets.create_ticket_order(user_id, event_id, ticket_selections)

# Get ticket order by ID
Ysc.Tickets.get_ticket_order(order_id)

# Get ticket order by reference
Ysc.Tickets.get_ticket_order_by_reference(reference_id)

# List user's ticket orders
Ysc.Tickets.list_user_ticket_orders(user_id)

# Cancel a ticket order
Ysc.Tickets.cancel_ticket_order(ticket_order, reason)

# Complete a ticket order after payment
Ysc.Tickets.complete_ticket_order(ticket_order, payment_id)
```

### Booking Validation

```elixir
# Validate complete booking
Ysc.Tickets.BookingValidator.validate_booking(user_id, event_id, ticket_selections)

# Check tier capacity
Ysc.Tickets.BookingValidator.check_tier_capacity(tier_id, quantity)

# Get event availability
Ysc.Tickets.BookingValidator.get_event_availability(event_id)

# Check if event is at capacity
Ysc.Tickets.BookingValidator.is_event_at_capacity?(event_id)
```

### Stripe Service

```elixir
# Create payment intent
Ysc.Tickets.StripeService.create_payment_intent(ticket_order, opts)

# Process successful payment
Ysc.Tickets.StripeService.process_successful_payment(payment_intent_id)

# Handle failed payment
Ysc.Tickets.StripeService.handle_failed_payment(payment_intent_id, reason)

# Ensure Stripe customer exists
Ysc.Tickets.StripeService.ensure_stripe_customer(user)
```

## Configuration

### Environment Variables

```bash
# Stripe configuration
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...

# Payment timeout (in minutes)
TICKET_PAYMENT_TIMEOUT=15
```

### Oban Configuration

The timeout worker requires Oban to be configured:

```elixir
# config/config.exs
config :ysc, Oban,
  repo: Ysc.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [
    tickets: 10,  # Process ticket timeout jobs
    default: 5
  ]
```

## Webhook Integration

### Stripe Webhooks

The system handles these Stripe webhook events:

- `payment_intent.succeeded` - Complete ticket orders
- `payment_intent.payment_failed` - Cancel orders
- `payment_intent.canceled` - Cancel orders

### Webhook Handler

```elixir
# In your webhook endpoint
def handle_stripe_webhook(event) do
  case event["type"] do
    "payment_intent.succeeded" ->
      Ysc.Tickets.WebhookHandler.handle_webhook_event("payment_intent.succeeded", event["data"]["object"])

    "payment_intent.payment_failed" ->
      Ysc.Tickets.WebhookHandler.handle_webhook_event("payment_intent.payment_failed", event["data"]["object"])

    _ ->
      :ok
  end
end
```

## UI Components

### Event Details Page

The `EventDetailsLive` module has been updated to:

- Show real-time ticket availability
- Handle multi-ticket selection
- Integrate with the new payment flow
- Display capacity warnings

### User Tickets Page

The `UserTicketsLive` module provides:

- List of user's ticket orders
- Order status tracking
- Ticket cancellation
- Payment timeout countdown

## Testing

### Unit Tests

```elixir
# Test ticket order creation
test "creates ticket order with multiple tickets" do
  ticket_selections = %{"tier_1" => 2, "tier_2" => 1}

  assert {:ok, order} = Ysc.Tickets.create_ticket_order(user.id, event.id, ticket_selections)
  assert length(order.tickets) == 3
end

# Test overbooking prevention
test "prevents overbooking when event at capacity" do
  # Set up event at capacity
  # Attempt to book more tickets
  assert {:error, :event_at_capacity} = Ysc.Tickets.create_ticket_order(user.id, event.id, selections)
end
```

### Integration Tests

```elixir
# Test complete payment flow
test "processes ticket order payment successfully" do
  # Create ticket order
  # Simulate Stripe payment success
  # Verify order completion
  # Check ledger entries
end
```

## Monitoring and Observability

### Logging

The system provides comprehensive logging:

```elixir
Logger.info("Ticket order created",
  order_id: order.id,
  user_id: user.id,
  event_id: event.id
)

Logger.error("Payment processing failed",
  payment_intent_id: payment_intent_id,
  error: reason
)
```

### Metrics

Key metrics to monitor:

- Ticket order creation rate
- Payment success rate
- Order timeout rate
- Capacity utilization

## Security Considerations

1. **Payment Security**: All payments processed through Stripe
2. **Capacity Validation**: Server-side validation prevents overbooking
3. **User Authorization**: Membership requirements enforced
4. **Data Integrity**: Database constraints and validations
5. **Audit Trail**: Complete transaction history in ledger

## Performance Considerations

1. **Database Indexes**: Optimized queries for capacity checks
2. **Background Jobs**: Timeout processing doesn't block UI
3. **Caching**: Consider caching availability data for high-traffic events
4. **Connection Pooling**: Proper database connection management

## Future Enhancements

1. **Ticket Transfers**: Allow users to transfer tickets
2. **Wait Lists**: Queue system for sold-out events
3. **Bulk Operations**: Admin tools for managing multiple orders
4. **Analytics**: Detailed reporting on ticket sales
5. **Mobile App**: Native mobile ticket management
