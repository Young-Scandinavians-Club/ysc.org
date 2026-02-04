# Reprocessing Payouts

This guide explains how to reprocess Stripe payouts that were created with the old method and failed to properly link all payments, refunds, and fee amounts.

## Problem

Payouts created before the BalanceTransaction API implementation may have:
- Missing linked payments
- Missing linked refunds
- Missing or incorrect `fee_total` values

## Solution

Use the `relink_payout_transactions` function to reprocess a payout using the new BalanceTransaction API method.

## Methods

### Method 1: Using the Script (Recommended)

The easiest way is to use the provided script:

```bash
# From the project root
mix run reprocess_payout.exs po_1SYFlzREiftrEncLDHTuRysd
```

The script will:
1. Find the payout in the database
2. Show current linked transactions
3. Relink all transactions using BalanceTransaction API
4. Update fee_total
5. Check if QuickBooks sync should be triggered
6. Display updated results

### Method 2: Using IEx (Interactive)

For more control, use IEx:

```elixir
# Start IEx with the app
iex -S mix

# Or in a remote console (production/staging)
# fly ssh console --pty -C "/app/bin/ysc remote"

# Load the script
Code.load_file("reprocess_payout.exs")

# Reprocess a specific payout
payout = Ysc.Ledgers.get_payout_by_stripe_id("po_1SYFlzREiftrEncLDHTuRysd")
updated_payout = Ysc.Stripe.WebhookHandler.relink_payout_transactions(payout)

# Check the results
updated_payout = Ysc.Repo.preload(updated_payout, [:payments, :refunds])
IO.inspect(length(updated_payout.payments), label: "Linked payments")
IO.inspect(length(updated_payout.refunds), label: "Linked refunds")
IO.inspect(updated_payout.fee_total, label: "Fee total")
```

### Method 3: Direct Function Call

You can also call the function directly:

```elixir
alias Ysc.Ledgers
alias Ysc.Stripe.WebhookHandler

# Get the payout
payout = Ledgers.get_payout_by_stripe_id("po_1SYFlzREiftrEncLDHTuRysd")

# Relink all transactions
updated_payout = WebhookHandler.relink_payout_transactions(payout)

# The function will:
# - Fetch all balance transactions from Stripe (with pagination)
# - Link all payments and refunds to the payout
# - Update fee_total from balance transactions
# - Check if QuickBooks sync should be triggered
```

## What Happens During Reprocessing

1. **Fetches Balance Transactions**: Uses `Stripe.BalanceTransaction.all` with pagination to get ALL transactions for the payout
2. **Expands Source Objects**: Uses `expand: ["data.source"]` to get Charge/Refund objects directly
3. **Skips Payout Transaction**: Automatically skips the payout balance transaction itself (type: "payout")
4. **Links Payments**: Finds payments by payment_intent_id and links them to the payout
5. **Links Refunds**: Finds refunds by external_refund_id and links them to the payout
6. **Updates Fee Total**: Calculates and updates fee_total from balance transactions
7. **Checks QuickBooks Sync**: If all conditions are met, enqueues QuickBooks sync

## Finding Payouts That Need Reprocessing

To find payouts that might need reprocessing:

```elixir
import Ecto.Query
alias Ysc.Ledgers
alias Ysc.Repo

# Find payouts without fee_total
payouts_without_fee =
  from(p in Ledgers.Payout,
    where: is_nil(p.fee_total),
    where: not is_nil(p.stripe_payout_id),
    order_by: [desc: p.inserted_at]
  )
  |> Repo.all()

# Find payouts with no linked transactions
payouts_without_transactions =
  from(p in Ledgers.Payout,
    left_join: pp in "payout_payments", on: pp.payout_id == p.id,
    left_join: pr in "payout_refunds", on: pr.payout_id == p.id,
    where: is_nil(pp.id) and is_nil(pr.id),
    where: not is_nil(p.stripe_payout_id),
    order_by: [desc: p.inserted_at]
  )
  |> Repo.all()
```

## Batch Reprocessing

To reprocess multiple payouts:

```elixir
Code.load_file("reprocess_payout.exs")

# Reprocess all payouts (limited to 100)
ReprocessPayout.reprocess_all()
```

Or process specific payouts:

```elixir
stripe_payout_ids = [
  "po_1SYFlzREiftrEncLDHTuRysd",
  "po_1ABC123...",
  # ... more payout IDs
]

Enum.each(stripe_payout_ids, fn stripe_payout_id ->
  case ReprocessPayout.reprocess(stripe_payout_id) do
    {:ok, _payout} -> IO.puts("✅ Processed: #{stripe_payout_id}")
    {:error, reason} -> IO.puts("❌ Failed: #{stripe_payout_id} - #{inspect(reason)}")
  end
end)
```

## Verification

After reprocessing, verify the results:

```elixir
payout = Ysc.Ledgers.get_payout_by_stripe_id("po_1SYFlzREiftrEncLDHTuRysd")
payout = Ysc.Repo.preload(payout, [:payments, :refunds])

# Check counts
IO.puts("Payments: #{length(payout.payments)}")
IO.puts("Refunds: #{length(payout.refunds)}")
IO.puts("Fee Total: #{if payout.fee_total, do: Money.to_string!(payout.fee_total), else: "not set"}")

# Check QuickBooks sync status
IO.puts("QuickBooks Sync Status: #{payout.quickbooks_sync_status || "not set"}")

# List payment IDs
Enum.each(payout.payments, fn payment ->
  IO.puts("  Payment: #{payment.id} - #{payment.reference_id} - #{Money.to_string!(payment.amount)}")
end)

# List refund IDs
Enum.each(payout.refunds, fn refund ->
  IO.puts("  Refund: #{refund.id} - #{refund.reference_id} - #{Money.to_string!(refund.amount)}")
end)
```

## Troubleshooting

### Payout Not Found
If the payout is not found in the database, check:
- The Stripe payout ID is correct
- The payout was actually created in the database (check webhook logs)

### No Payments/Refunds Linked
If no payments or refunds are linked after reprocessing:
- Check if the payments/refunds exist in the database
- Verify the payment_intent_id matches between Stripe and the database
- Check logs for any errors during linking

### Fee Total Not Updated
If fee_total is still not set:
- Check if the payout balance transaction has a fee
- Verify balance transactions were fetched successfully
- Check logs for fee calculation errors

## Related Functions

- `Ysc.Stripe.WebhookHandler.relink_payout_transactions/1` - Main function to relink transactions
- `Ysc.Ledgers.get_payout_by_stripe_id/1` - Get payout by Stripe ID
- `Ysc.Ledgers.get_payout!/1` - Get payout by ID with preloaded relations

