# Stripe Webhook Handler - Quick Reference

## What Was Fixed

### 🔴 CRITICAL: Duplicate Refund Processing
- **Problem:** Every refund was processed twice (charge.refunded + refund.created)
- **Fix:** Added `external_refund_id` tracking with unique database constraint
- **Result:** Each refund now processed exactly once

### 🟡 HIGH: Subscription Race Condition
- **Problem:** Payment recorded with `entity_id: nil` when invoice arrives before subscription
- **Fix:** Automatically fetch subscription from Stripe if not found locally
- **Result:** All subscription payments now properly linked

### 🟡 HIGH: Partial Refund Issues
- **Problem:** charge.refunded summed all refunds, causing re-processing
- **Fix:** Process each refund individually with idempotency
- **Result:** Partial refunds handled correctly

---

## Key Changes

### Database
```sql
-- New column for refund idempotency
ALTER TABLE ledger_transactions ADD COLUMN external_refund_id VARCHAR(255);

-- Unique index prevents duplicates
CREATE UNIQUE INDEX ledger_transactions_external_refund_id_index
ON ledger_transactions(external_refund_id)
WHERE external_refund_id IS NOT NULL;
```

### Code Files Modified
1. `lib/ysc/stripe/webhook_handler.ex` - Updated webhook handlers
2. `lib/ysc/ledgers.ex` - Added idempotency check
3. `lib/ysc/ledgers/ledger_transaction.ex` - Added external_refund_id field
4. `priv/repo/migrations/20251120061547_*.exs` - Database migration

---

## What to Monitor

### Log Messages to Watch For
```elixir
# Good - Idempotency working
"Refund already processed, skipping (idempotency)"

# Good - Race condition handled
"Subscription not found locally, fetching from Stripe..."
"Created subscription from Stripe before processing payment"

# Bad - Needs investigation
"Failed to create subscription from Stripe"
"Failed to fetch subscription from Stripe"
"Failed to process refund in ledger"
```

### Key Metrics
- Duplicate webhook attempts (should increase, good!)
- Failed subscription fetches (should be near 0)
- Payments with null entity_id (should be 0)
- Failed refund processing (should be near 0)

---

## Testing Commands

```bash
# Run migration
mix ecto.migrate

# Compile and check for warnings
mix compile --force

# Run tests (when created)
mix test test/ysc/stripe/webhook_handler_test.exs
```

---

## Rollback (If Needed)

```bash
# Rollback migration
mix ecto.rollback --step 1

# Remove external_refund_id column
# ALTER TABLE ledger_transactions DROP COLUMN external_refund_id;
```

---

## Common Scenarios

### Scenario 1: Duplicate Refund Webhooks
**What happens:** Stripe sends both charge.refunded and refund.created
**Before fix:** 2 ledger transactions created
**After fix:** 1 ledger transaction created, 2nd attempt logged and skipped

### Scenario 2: Invoice Before Subscription
**What happens:** invoice.payment_succeeded arrives first
**Before fix:** Payment created with entity_id: nil
**After fix:** Subscription fetched from Stripe, payment properly linked

### Scenario 3: Multiple Partial Refunds
**What happens:** Customer refunded in 2 separate amounts
**Before fix:** Each charge.refunded webhook summed all refunds
**After fix:** Each refund processed individually with proper tracking

---

## Quick Troubleshooting

### Issue: Duplicate refunds in ledger
- **Check:** Do transactions have the same external_refund_id?
- **Likely cause:** Migration not run or constraint not created
- **Fix:** Run `mix ecto.migrate`

### Issue: Payments missing entity_id
- **Check:** Are subscription fetch logs present?
- **Likely cause:** Stripe API error or subscription doesn't exist
- **Fix:** Check Stripe API connectivity and subscription status

### Issue: Refund processing failures
- **Check:** Is external_refund_id being passed correctly?
- **Likely cause:** Webhook payload missing refund ID
- **Fix:** Review webhook payload structure

---

## Documentation

- **Detailed Review:** `docs/STRIPE_WEBHOOK_REVIEW.md`
- **Implementation Details:** `docs/STRIPE_WEBHOOK_FIXES_IMPLEMENTED.md`
- **Source Code:** `lib/ysc/stripe/webhook_handler.ex`

---

## Contact

For issues or questions about these fixes, refer to the implementation documentation or check the git history for commit messages and context.

**Last Updated:** November 20, 2024

