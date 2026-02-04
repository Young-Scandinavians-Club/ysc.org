# Currency Handling Fixes - Summary

## Date
November 20, 2024

## Problem Statement

The ledger system was storing amounts in **dollars** in the database, but there were inconsistencies in how Stripe amounts (which are sent in **cents**) were being converted and how `Money` types were being constructed.

## Critical Issues Fixed

### 1. Incorrect Money.new() Parameter Order

**Problem**: Throughout the Stripe webhook handler, `Money.new()` was being called with incorrect parameter order.

**Wrong Pattern**:
```elixir
# ❌ INCORRECT
Money.new(:USD, MoneyHelper.cents_to_dollars(amount))
```

**Fixed Pattern**:
```elixir
# ✅ CORRECT
Money.new(MoneyHelper.cents_to_dollars(amount), :USD)
```

**Locations Fixed**:
- `lib/ysc/stripe/webhook_handler.ex` line 398 - Invoice payment processing
- `lib/ysc/stripe/webhook_handler.ex` line 684 - Payout processing
- `lib/ysc/stripe/webhook_handler.ex` line 773 - Stripe fee from charge
- `lib/ysc/stripe/webhook_handler.ex` line 977 - Stripe fee from metadata
- `lib/ysc/stripe/webhook_handler.ex` line 1116 - Refund amount processing

**Why This Matters**:
- `Money.new(decimal, :USD)` returns `Money.t()` directly
- `Money.new(:USD, string)` returns `{:ok, Money.t()}` and expects a string
- Using the wrong signature caused type mismatches and potential runtime errors

### 2. Revenue Entry Lookup Logic

**Problem**: The `get_revenue_entry_for_payment/1` function was looking for revenue entries with **positive** amounts, but revenue entries are **credits** (negative amounts).

**Location**: `lib/ysc/ledgers.ex` line 1220

**Before**:
```elixir
# Filter for positive amounts in Elixir since we can't do it in the query
if entry.amount.amount > 0, do: entry, else: nil
```

**After**:
```elixir
# Filter for negative amounts (credits) in Elixir since we can't do it in the query
# Revenue entries are credits (negative values)
if Decimal.negative?(entry.amount.amount), do: entry, else: nil
```

**Impact**: This was causing revenue tracking and payment classification to fail for detailed payment listings.

## Double-Entry Accounting Corrections

All changes align with proper double-entry accounting principles:

### Normal Balances
| Account Type | Normal Balance | Sign in DB |
|-------------|---------------|------------|
| Assets | Debit | Positive |
| Liabilities | Credit | Negative |
| Revenue | Credit | Negative |
| Expenses | Debit | Positive |

### Payment Flow (Example: $100 payment)
1. **Debit** Stripe Account (Asset): `+$100`
2. **Credit** Revenue: `-$100`
3. *(Optional)* **Debit** Stripe Fees (Expense): `+$2.90`
4. *(Optional)* **Credit** Stripe Account: `-$2.90`

**Total**: Debits = Credits (Balanced)

### Refund Flow (Example: $50 refund)
1. **Debit** Refund Expense: `+$50`
2. **Credit** Stripe Account: `-$50`
3. **Debit** Revenue (reversal): `+$50`

## Conversion Logic

### MoneyHelper.cents_to_dollars()

This utility function is the **single source of truth** for converting Stripe cents to database dollars:

```elixir
def cents_to_dollars(cents) when is_integer(cents) do
  cents
  |> Decimal.new()
  |> Decimal.div(Decimal.new(100))
end
```

**Examples**:
- `cents_to_dollars(5000)` → `Decimal.new("50.00")`
- `cents_to_dollars(175)` → `Decimal.new("1.75")`
- `cents_to_dollars(33)` → `Decimal.new("0.33")`

### Usage Pattern

**Always** use this pattern when receiving amounts from Stripe:

```elixir
# Stripe sends cents
stripe_amount = 5000  # $50.00

# Convert and store as Money
amount = Money.new(MoneyHelper.cents_to_dollars(stripe_amount), :USD)

# Result: Money.new(Decimal.new("50.00"), :USD)
```

## Files Modified

### Core Changes
1. **`lib/ysc/stripe/webhook_handler.ex`**
   - Fixed 5 instances of `Money.new()` with incorrect parameter order
   - All conversions from Stripe cents now use correct pattern

2. **`lib/ysc/ledgers.ex`**
   - Fixed revenue entry lookup to check for negative amounts (credits)
   - Previously fixed: Revenue entry creation to use negative amounts
   - Previously fixed: Refund entry creation to properly reverse credits

### Documentation
3. **`docs/CURRENCY_HANDLING.md`** (NEW)
   - Comprehensive guide to currency handling
   - Double-entry accounting rules
   - Stripe integration patterns
   - Common pitfalls and solutions

4. **`docs/CURRENCY_FIXES_SUMMARY.md`** (NEW)
   - This summary document

## Testing Results

All 27 tests in `test/ysc/stripe/webhook_handler_test.exs` pass:
- ✅ Webhook deduplication
- ✅ Webhook replay protection
- ✅ Refund idempotency
- ✅ Partial refunds
- ✅ Subscription race conditions
- ✅ **Ledger balance integrity** (Critical!)
- ✅ Payment processing
- ✅ Error handling

## Validation Checklist

✅ **All Stripe amounts converted correctly** - Using `cents_to_dollars()` everywhere
✅ **Money.new() parameter order** - Decimal first, currency second
✅ **Double-entry accounting** - Debits and credits properly signed
✅ **Revenue entries** - Stored as negative (credit) amounts
✅ **Refund processing** - Properly reverses original entries
✅ **Ledger balance** - `verify_ledger_balance()` passes
✅ **Tests passing** - All 27 webhook tests green
✅ **Documentation** - Comprehensive currency handling guide created

## Future Considerations

### Prevention
1. **Type Safety**: Consider creating a custom Ecto type that enforces dollar amounts
2. **Validation**: Add schema-level checks for proper debit/credit signs
3. **Testing**: Add property-based tests for currency conversions

### Monitoring
1. **Ledger Balance Checks**: Already implemented via `BalanceCheckWorker` (runs daily at midnight)
2. **Alerting**: Monitor for imbalances and alert immediately
3. **Audit Trail**: All ledger transactions are immutable and traceable

### Improvements
1. **Multi-Currency Support**: System currently only supports USD
2. **Exchange Rates**: Would need to be added for international support
3. **Decimal Precision**: Currently using default precision (might need adjustment for micro-transactions)

## Key Takeaways

1. **Stripe sends cents, we store dollars** - Always convert at the boundary
2. **Money.new() has two signatures** - Know which one you need
3. **Revenue is a credit** - It's negative in double-entry accounting
4. **Test your assumptions** - The ledger balance check catches errors
5. **Document your conventions** - Future developers need to understand the system

## Related Documentation

- `docs/CURRENCY_HANDLING.md` - Comprehensive currency handling guide
- `docs/LEDGER_SYSTEM_README.md` - Double-entry accounting system overview
- `docs/STRIPE_WEBHOOK_REVIEW.md` - Initial webhook handling review
- `docs/STRIPE_WEBHOOK_FIXES_IMPLEMENTED_V2.md` - Refund refactoring details
- `docs/WEBHOOK_SECURITY_IMPROVEMENTS.md` - Security enhancements
- `docs/LEDGER_BALANCE_MONITORING.md` - Balance monitoring system

---

**Changes Reviewed By**: Engineering Team
**Status**: ✅ Complete
**All Tests**: ✅ Passing
**Compilation**: ✅ Success
**Documentation**: ✅ Created

