# Reconciliation Testing Requirements

## Overview

The reconciliation module is critical financial infrastructure that requires comprehensive testing. Due to the complexity of the ledger system and the specific API requirements of `process_payment` and `process_refund`, tests need to be carefully structured.

## Current Test File Status

**Location**: `test/ysc/ledgers/reconciliation_test.exs`

**Status**: Partially implemented - requires updates to match actual `Ledgers.process_payment/1` API

## API Signatures to Match

### process_payment/1

Expected parameters:
```elixir
%{
  user_id: user_id,
  amount: amount,
  entity_type: entity_type,          # Not related_entity_type
  entity_id: entity_id,              # Not related_entity_id
  external_payment_id: external_payment_id,
  stripe_fee: stripe_fee,             # Required
  description: description,            # Required
  property: property,                  # Required
  payment_method_id: payment_method_id # Required
}
```

Returns: `{:ok, {payment, transaction, entries}}` (wrapped in transaction)

### process_refund/1

Expected parameters:
```elixir
%{
  user_id: user_id,
  payment_id: payment_id,
  amount: amount,
  external_provider: :stripe,
  external_refund_id: external_refund_id,
  reason: reason
}
```

Returns: `{:ok, {refund, refund_transaction, entries}}`

## Critical Test Scenarios

### 1. Payment Reconciliation Tests
- ✅ All payments have ledger transactions
- ✅ All payments have ledger entries
- ✅ Payment amounts match ledger totals
- ✅ Unbalanced ledger entries detected
- ✅ Missing transactions detected
- ✅ Amount mismatches detected

### 2. Refund Reconciliation Tests
- ✅ All refunds have ledger transactions
- ✅ Refunds reference valid payments
- ✅ Refund amounts match ledger totals
- ✅ Orphaned refunds detected
- ✅ Partial refunds handled correctly

### 3. Ledger Balance Tests
- ✅ Balanced ledger returns :ok
- ✅ Imbalanced ledger detected with details
- ✅ Account-level balance tracking

### 4. Orphaned Entry Tests
- ✅ Entries with invalid payment_id
- ✅ Transactions with invalid payment_id
- ✅ Transactions with invalid refund_id

### 5. Entity Total Tests
- ✅ Membership payment totals match ledger
- ✅ Booking payment totals match ledger (Tahoe, Clear Lake, General)
- ✅ Event payment totals match ledger
- ✅ Mismatches detected and reported

### 6. Full Reconciliation Tests
- ✅ All checks passing returns :ok status
- ✅ Multiple simultaneous issues detected
- ✅ Performance with large datasets
- ✅ Report formatting

### 7. Edge Cases
- ✅ Empty system (no transactions)
- ✅ High volume (50+ payments)
- ✅ Mixed success/failure states
- ✅ Concurrent payments and refunds
- ✅ Partial refunds
- ✅ Rounding edge cases

## Implementation Notes

### DateTime Handling
When creating records directly via `Repo.insert!`, datetime values must be truncated:
```elixir
payment_date: DateTime.utc_now() |> DateTime.truncate(:second)
```

### Status Values
Payment and refund status must be one of:
- `:pending`
- `:completed`
- `:failed`
- `:refunded`

NOT `:paid` (invalid enum value)

### Account Retrieval
Use `Ledgers.get_account_by_name/1` (returns account or nil), not `get_account_by_name!/1` (doesn't exist)

### Foreign Key Constraints
Cannot create refunds with non-existent payment_ids due to database constraints. To test orphaned refund scenarios:
1. Create valid payment and refund
2. Delete the payment to orphan the refund
3. Run reconciliation to detect orphan

## Test Data Setup Pattern

```elixir
# Correct pattern for creating test payment
{:ok, {payment, transaction, entries}} = Ledgers.process_payment(%{
  user_id: user.id,
  amount: Money.new(10000, :USD),
  entity_type: :membership,
  entity_id: Ecto.ULID.generate(),
  external_payment_id: "pi_test_#{unique_id}",
  stripe_fee: Money.new(300, :USD),
  description: "Test payment",
  property: :tahoe,
  payment_method_id: "pm_test"
})

# Correct pattern for creating test refund
{:ok, {refund, refund_transaction, refund_entries}} = Ledgers.process_refund(%{
  user_id: user.id,
  payment_id: payment.id,
  amount: Money.new(5000, :USD),
  external_provider: :stripe,
  external_refund_id: "re_test_#{unique_id}",
  reason: "customer_request"
})
```

## Current Test File Issues

1. **API Mismatch**: Tests use `related_entity_type/id` instead of `entity_type/id`
2. **Missing Required Fields**: Tests don't provide `stripe_fee`, `description`, `property`, `payment_method_id`
3. **DateTime Format**: Direct `Repo.insert!` calls need truncated dates
4. **Invalid Status Values**: Using `:paid` instead of `:completed`

## Recommended Approach

### Option 1: Full Test Suite (Recommended)
Update the test file to match the actual API:
1. Add helper function to create valid payment attrs
2. Add helper function to create valid refund attrs
3. Update all test cases to use correct parameters
4. Add missing required fields

### Option 2: Integration Tests
Create higher-level integration tests that exercise the reconciliation through real workflows:
1. Stripe webhook processing tests
2. End-to-end payment flow tests
3. End-to-end refund flow tests
4. Daily reconciliation job tests

### Option 3: Hybrid Approach (Best)
1. Core unit tests for reconciliation logic
2. Integration tests for full workflows
3. Property-based tests for edge cases
4. Performance benchmarks for large datasets

## Success Criteria

A comprehensive reconciliation test suite should:
1. **Cover all reconciliation functions** - payments, refunds, balance, orphans, entities
2. **Test both success and failure paths** - balanced and imbalanced states
3. **Handle edge cases** - empty system, high volume, concurrent operations
4. **Verify error detection** - all types of discrepancies caught
5. **Validate reporting** - human-readable output generated correctly
6. **Run efficiently** - complete in < 2 seconds for normal test suite
7. **Be maintainable** - clear test names, good organization, helper functions

## Next Steps

1. **Define Test Data Factories**: Create factory functions for valid payments/refunds
2. **Update Existing Tests**: Fix API mismatches in current test file
3. **Add Missing Scenarios**: Implement tests for uncovered edge cases
4. **Performance Tests**: Add benchmarks for large dataset handling
5. **Documentation**: Document expected reconciliation behavior
6. **CI Integration**: Ensure tests run on every commit

## Related Documentation

- [Reconciliation System](RECONCILIATION_SYSTEM.md)
- [Currency Handling](CURRENCY_HANDLING.md)
- [Ledger Balance Monitoring](LEDGER_BALANCE_MONITORING.md)

---

**Last Updated**: November 20, 2024
**Status**: In Progress
**Priority**: High - Critical Financial Infrastructure

