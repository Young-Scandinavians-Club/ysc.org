# Currency Handling Guide

## Overview

This document explains how monetary values are handled throughout the YSC application, particularly in the interaction between Stripe (which uses cents) and our ledger system (which uses dollars).

## Core Principles

### 1. Database Storage: **Dollars**
- All amounts in the database are stored as **dollar values** using the `Money` Ecto type
- Example: $50.00 is stored as `Money.new(50, :USD)` or `Money.new(Decimal.new("50.00"), :USD)`

### 2. Stripe API: **Cents**
- Stripe sends all amounts as **integers in cents**
- Example: $50.00 is received as `5000` (cents)

### 3. Conversion Function
The `Ysc.MoneyHelper.cents_to_dollars/1` function handles conversion:

```elixir
def cents_to_dollars(cents) when is_integer(cents) do
  cents
  |> Decimal.new()
  |> Decimal.div(Decimal.new(100))
end
```

**Important**: This returns a `Decimal`, not a `Money` struct!

## Money Type Construction

### Correct Usage

When converting from Stripe cents to Money:

```elixir
# ✅ CORRECT: Decimal first, currency second
amount_cents = 5000  # From Stripe
amount_dollars = Money.new(MoneyHelper.cents_to_dollars(amount_cents), :USD)
# Result: Money.new(Decimal.new("50.00"), :USD)
```

### Common Pitfall

```elixir
# ❌ WRONG: Currency first with Decimal
amount_cents = 5000
amount_dollars = Money.new(:USD, MoneyHelper.cents_to_dollars(amount_cents))
# This will fail or produce unexpected results!
```

### Money.new() Signatures

The Money library has two different signatures:

1. **`Money.new(amount, currency)`** - When `amount` is a number or Decimal
   - Returns: `Money.t()`
   - Example: `Money.new(50, :USD)` or `Money.new(Decimal.new("50.00"), :USD)`

2. **`Money.new(currency, string_amount)`** - When amount is a string
   - Returns: `{:ok, Money.t()}` or `{:error, reason}`
   - Example: `Money.new(:USD, "50.00")`

## Double-Entry Accounting Rules

### Debit vs Credit in Our System

In double-entry accounting:
- **Debits** = Positive amounts (increase assets/expenses, decrease liabilities/revenue)
- **Credits** = Negative amounts (decrease assets/expenses, increase liabilities/revenue)

### Account Types and Normal Balances

| Account Type | Normal Balance | Example Accounts |
|-------------|---------------|------------------|
| **Asset** | Debit (positive) | `cash`, `stripe_account`, `accounts_receivable` |
| **Liability** | Credit (negative) | `accounts_payable`, `deferred_revenue`, `refund_liability` |
| **Revenue** | Credit (negative) | `membership_revenue`, `event_revenue`, `booking_revenue` |
| **Expense** | Debit (positive) | `stripe_fees`, `operating_expenses`, `refund_expense` |

### Example: Processing a $100 Payment

```elixir
# Entry 1: Debit Stripe Account (Asset) +$100
create_entry(%{
  account_id: stripe_account.id,
  amount: Money.new(100, :USD),  # Positive = Debit
  description: "Payment receivable from Stripe"
})

# Entry 2: Credit Revenue -$100
{:ok, negative_amount} = Money.mult(Money.new(100, :USD), -1)
create_entry(%{
  account_id: revenue_account.id,
  amount: negative_amount,  # Negative = Credit
  description: "Revenue from membership"
})
```

### Example: Processing a $50 Refund

```elixir
# Entry 1: Debit Refund Expense +$50
create_entry(%{
  account_id: refund_expense_account.id,
  amount: Money.new(50, :USD),  # Positive = Debit
  description: "Refund issued"
})

# Entry 2: Credit Stripe Account -$50
{:ok, negative_amount} = Money.mult(Money.new(50, :USD), -1)
create_entry(%{
  account_id: stripe_account.id,
  amount: negative_amount,  # Negative = Credit
  description: "Refund processed through Stripe"
})

# Entry 3: Debit Revenue +$50 (reversal)
create_entry(%{
  account_id: revenue_account.id,
  amount: Money.new(50, :USD),  # Positive = Debit (reverses the credit)
  description: "Revenue reversal for refund"
})
```

## Stripe Webhook Integration

### Invoice Payment Succeeded

```elixir
# Stripe sends amount_paid in cents
invoice_data = %{
  "amount_paid" => 5000  # $50.00 in cents
}

# Convert to dollars for our system
payment_attrs = %{
  user_id: user.id,
  amount: Money.new(MoneyHelper.cents_to_dollars(5000), :USD),
  # ... other attrs
}

Ledgers.process_payment(payment_attrs)
```

### Refund Processing

```elixir
# Stripe sends refund amount in cents
refund_data = %Stripe.Refund{
  amount: 2500  # $25.00 in cents
}

# Convert to dollars
refund_amount = Money.new(MoneyHelper.cents_to_dollars(2500), :USD)

Ledgers.process_refund(%{
  payment_id: payment.id,
  refund_amount: refund_amount,
  reason: "Customer request",
  external_refund_id: refund_data.id
})
```

### Stripe Fees

```elixir
# Stripe fee from balance transaction (in cents)
balance_transaction = %{fee: 175}  # $1.75 in cents

# Convert to dollars
stripe_fee = Money.new(MoneyHelper.cents_to_dollars(175), :USD)
```

## Ledger Balance Verification

The `verify_ledger_balance/0` function ensures all debits and credits balance:

```elixir
# Get all debits (positive amounts)
total_debits = sum_of_all_positive_entries()

# Get all credits (negative amounts)
total_credits = sum_of_all_negative_entries()

# In a balanced ledger: total_debits + total_credits = 0
{:ok, balance} = Money.add(total_debits, total_credits)

Money.equal?(balance, Money.new(0, :USD))  # Should be true
```

## Common Patterns

### Creating Payments

```elixir
# From Stripe webhook (cents)
def handle_stripe_payment(stripe_data) do
  amount_cents = stripe_data["amount_paid"]

  Ledgers.process_payment(%{
    amount: Money.new(MoneyHelper.cents_to_dollars(amount_cents), :USD),
    # ... other attrs
  })
end

# From user input (already in dollars)
def handle_manual_payment(params) do
  amount_dollars = Decimal.new(params["amount"])

  Ledgers.process_payment(%{
    amount: Money.new(amount_dollars, :USD),
    # ... other attrs
  })
end
```

### Money Arithmetic

```elixir
# Addition
amount1 = Money.new(50, :USD)
amount2 = Money.new(25, :USD)
{:ok, total} = Money.add(amount1, amount2)  # Returns {:ok, Money.new(75, :USD)}

# Multiplication (for negation)
amount = Money.new(100, :USD)
{:ok, negative} = Money.mult(amount, -1)  # Returns {:ok, Money.new(-100, :USD)}

# Comparison
Money.equal?(amount1, amount2)  # Returns boolean
Money.positive?(amount)         # Returns boolean
```

## Checklist for New Payment Features

When adding new payment-related features:

1. ✅ **Convert Stripe amounts**: Use `MoneyHelper.cents_to_dollars()` for all Stripe amounts
2. ✅ **Correct Money.new()**: Use `Money.new(decimal, :USD)` not `Money.new(:USD, decimal)`
3. ✅ **Handle Money.add() tuples**: Unwrap `{:ok, money}` tuples from arithmetic operations
4. ✅ **Follow debit/credit rules**:
   - Assets/Expenses: Positive values (debits)
   - Liabilities/Revenue: Negative values (credits)
5. ✅ **Test ledger balance**: Ensure `verify_ledger_balance()` passes after transactions
6. ✅ **Idempotency**: Check for duplicate processing using `external_payment_id` or `external_refund_id`

## Testing Currency Handling

```elixir
test "converts Stripe cents to dollars correctly" do
  # Simulate Stripe data
  stripe_amount_cents = 5000  # $50.00

  # Process payment
  {:ok, {payment, _transaction, _entries}} =
    Ledgers.process_payment(%{
      amount: Money.new(MoneyHelper.cents_to_dollars(stripe_amount_cents), :USD),
      # ... other attrs
    })

  # Verify stored amount is in dollars
  assert Money.equal?(payment.amount, Money.new(50, :USD))

  # Verify ledger is balanced
  assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
end
```

## Summary

- **Database**: Stores dollar amounts as `Money` type
- **Stripe**: Sends/receives cent amounts as integers
- **Conversion**: Always use `MoneyHelper.cents_to_dollars()` when receiving from Stripe
- **Money Construction**: Use `Money.new(decimal, :USD)` for decimal amounts
- **Double-Entry**: Follow debit (positive) / credit (negative) conventions
- **Verification**: Use `verify_ledger_balance()` to ensure accounting integrity

---

**Last Updated**: November 20, 2024
**Maintained By**: Engineering Team

