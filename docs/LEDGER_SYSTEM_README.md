# Double-Entry Ledger System

This document describes the comprehensive double-entry accounting system implemented for managing payments, subscriptions, events, and bookings.

## Overview

The ledger system provides:

- **Double-entry bookkeeping** for all financial transactions
- **Automatic Stripe fee tracking** via webhooks
- **Admin refund and credit management** through the admin interface
- **Comprehensive account structure** for different revenue streams
- **Audit trail** for all financial transactions

## Core Components

### 1. Ledger Accounts

The system includes these basic account types:

**Asset Accounts:**

- `cash` - Cash account for holding funds
- `stripe_account` - Stripe account balance
- `accounts_receivable` - Outstanding payments from customers

**Liability Accounts:**

- `accounts_payable` - Outstanding payments to vendors
- `deferred_revenue` - Prepaid subscriptions and bookings
- `refund_liability` - Pending refunds

**Revenue Accounts:**

- `membership_revenue` - Revenue from membership subscriptions
- `event_revenue` - Revenue from event registrations
- `booking_revenue` - Revenue from cabin bookings
- `donation_revenue` - Revenue from donations

**Expense Accounts:**

- `stripe_fees` - Stripe processing fees
- `operating_expenses` - General operating expenses
- `refund_expense` - Refunds issued to customers

### 2. Main Functions

#### Processing Payments

```elixir
# Process a membership payment
Ysc.Ledgers.process_payment(%{
  user_id: user.id,
  amount: Money.new(5000, :USD), # $50.00
  entity_type: :membership,
  entity_id: membership.id,
  external_payment_id: "pi_1234567890",
  stripe_fee: Money.new(175, :USD), # $1.75 (2.9% + 30¢)
  description: "Annual membership fee",
  property: nil,
  payment_method_id: payment_method.id # Optional: reference to payment method
})
```

#### Processing Refunds

```elixir
# Process a refund
Ysc.Ledgers.process_refund(%{
  payment_id: payment.id,
  refund_amount: Money.new(2500, :USD), # $25.00
  reason: "Customer requested partial refund",
  external_refund_id: "re_1234567890"
})
```

#### Adding Credits

```elixir
# Add credit to user account
Ysc.Ledgers.add_credit(%{
  user_id: user.id,
  amount: Money.new(1000, :USD), # $10.00
  reason: "Compensation for service issue",
  entity_type: :administration,
  entity_id: nil
})
```

### 3. Admin Interface

The admin money management interface (`/admin/money`) provides:

- **Account Balance Dashboard** - View all account balances
- **Recent Payments Table** - List of recent payments with refund options
- **Refund Modal** - Process refunds with reason tracking
- **Credit Modal** - Add credits to user accounts

### 4. Stripe Integration

The system automatically processes Stripe webhooks:

- **`payment_intent.succeeded`** - Creates ledger entries for successful payments
- **`charge.dispute.created`** - Logs chargebacks and disputes
- **Automatic fee tracking** - Calculates and records Stripe processing fees

## Database Schema

### Ledger Accounts

```sql
CREATE TABLE ledger_accounts (
  id UUID PRIMARY KEY,
  account_type VARCHAR NOT NULL, -- asset, liability, revenue, expense, equity
  name VARCHAR NOT NULL,
  description TEXT,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  UNIQUE(account_type, name)
);
```

### Payments

```sql
CREATE TABLE payments (
  id UUID PRIMARY KEY,
  reference_id VARCHAR UNIQUE NOT NULL,
  external_provider VARCHAR NOT NULL,
  external_payment_id VARCHAR UNIQUE NOT NULL,
  amount MONEY NOT NULL,
  status VARCHAR NOT NULL,
  payment_date TIMESTAMP,
  user_id UUID REFERENCES users(id),
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
```

### Ledger Transactions

```sql
CREATE TABLE ledger_transactions (
  id UUID PRIMARY KEY,
  type VARCHAR NOT NULL, -- payment, refund, fee, adjustment
  payment_id UUID REFERENCES payments(id),
  total_amount MONEY NOT NULL,
  status VARCHAR NOT NULL DEFAULT 'pending',
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
```

### Ledger Entries

```sql
CREATE TABLE ledger_entries (
  id UUID PRIMARY KEY,
  account_id UUID REFERENCES ledger_accounts(id) NOT NULL,
  related_entity_type VARCHAR,
  related_entity_id UUID,
  payment_id UUID REFERENCES payments(id),
  description TEXT,
  amount MONEY NOT NULL,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
```

## Usage Examples

### 1. Event Registration Payment

```elixir
# When a user registers for an event
Ysc.Ledgers.process_payment(%{
  user_id: user.id,
  amount: Money.new(7500, :USD), # $75.00
  entity_type: :event,
  entity_id: event.id,
  external_payment_id: "pi_event_123",
  stripe_fee: Money.new(247, :USD), # $2.47
  description: "Event registration: #{event.name}",
  property: nil,
  payment_method_id: payment_method.id # Optional: reference to payment method
})
```

This creates:

- **Debit Cash**: $75.00
- **Credit Event Revenue**: $75.00
- **Debit Stripe Fees**: $2.47
- **Credit Cash**: $2.47

### 2. Cabin Booking Payment

```elixir
# When a user books a cabin
Ysc.Ledgers.process_payment(%{
  user_id: user.id,
  amount: Money.new(20000, :USD), # $200.00
  entity_type: :booking,
  entity_id: booking.id,
  external_payment_id: "pi_booking_456",
  stripe_fee: Money.new(610, :USD), # $6.10
  description: "Cabin booking: #{booking.cabin_name}",
  property: :tahoe, # or :clear_lake
  payment_method_id: payment_method.id # Optional: reference to payment method
})
```

### 3. Partial Refund

```elixir
# Refund half of an event registration
Ysc.Ledgers.process_refund(%{
  payment_id: payment.id,
  refund_amount: Money.new(3750, :USD), # $37.50
  reason: "Event cancelled, partial refund issued",
  external_refund_id: "re_partial_789"
})
```

This creates:

- **Debit Refund Expense**: $37.50
- **Credit Cash**: $37.50

### 4. Admin Credit

```elixir
# Admin adds credit for customer service
Ysc.Ledgers.add_credit(%{
  user_id: user.id,
  amount: Money.new(500, :USD), # $5.00
  reason: "Compensation for booking issue",
  entity_type: :booking,
  entity_id: booking.id
})
```

This creates:

- **Debit Accounts Receivable**: $5.00
- **Credit Cash**: $5.00

## Running Migrations

To set up the ledger system:

```bash
# Run the ledger table migrations
mix ecto.migrate

# Seed the basic accounts
mix ecto.migrate
```

## Admin Access

Admins can access the money management interface at `/admin/money` to:

- View account balances
- Process refunds
- Add credits
- Monitor recent payments

## Security Considerations

- All financial operations are wrapped in database transactions
- Admin actions require proper authentication and authorization
- All ledger entries are immutable (no updates, only new entries)
- Comprehensive audit trail for all transactions

## Future Enhancements

- **Reporting Dashboard** - Financial reports and analytics
- **Automated Reconciliation** - Match Stripe data with ledger entries
- **Multi-currency Support** - Handle different currencies
- **Tax Tracking** - Separate tax accounts and calculations
- **Budget Management** - Track against budgets and forecasts
