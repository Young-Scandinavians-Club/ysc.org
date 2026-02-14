# QuickBooks Sync Test Fixes

## Summary

Fixed two flaky tests in `test/ysc/quickbooks/sync_test.exs` that were failing due to race conditions with Oban's inline testing mode.

## Tests Fixed

1. `sync_payment/1 with mixed event/donation payments handles missing QuickBooks item IDs gracefully` (line 1204)
2. `booking refund class assignment booking refund inherits property from original payment through ledger entries` (line 3272)

## Root Cause

Both tests were failing due to the same underlying issue:

### Oban Inline Testing Mode

The test environment is configured with `config :ysc, Oban, testing: :inline` in `config/test.exs`. This means:

- When `Ledgers.process_payment()` or `Ledgers.process_refund()` is called, it immediately enqueues and executes QuickBooks sync jobs
- These async jobs run with whatever mocks are set up at that moment (typically the default stubs from `setup_default_mocks()`)
- Later in the test, when specific mocks are set up and `Sync.sync_payment()` is called explicitly, the payment/refund is already synced

### Test 1 Failure

```
assert match?({:error, _}, result)
left:  {:error, _}
right: {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
```

- The test expected an error when `get_or_create_item` was stubbed to fail
- However, the payment creation triggered an async sync that succeeded with the default stub
- The explicit `Sync.sync_payment()` call returned early with `{:ok, ...}` because the payment was already synced

### Test 2 Failure

```
assert item_ref.value == "tahoe_item_123"
left:  "qb_item_default"
right: "tahoe_item_123"
```

- The config was set to `tahoe_booking_item_id: "tahoe_item_123"`
- However, the async refund sync job ran with the default stub that returns `"qb_item_default"`
- The explicit `Sync.sync_refund()` call used the already-synced refund, which had the wrong item ID

## Solution

Wrap payment/refund creation in `Oban.Testing.with_testing_mode(:manual, fn -> ... end)` to prevent inline execution:

```elixir
# Before (flaky)
{:ok, {payment, _, _}} = Ledgers.process_payment(%{...})
# Async sync job runs immediately with default mocks

# After (stable)
payment = Oban.Testing.with_testing_mode(:manual, fn ->
  {:ok, {payment, _, _}} = Ledgers.process_payment(%{...})
  payment
end)
# No async sync job runs
```

Then set up specific mocks and call the sync function explicitly.

## Changes Made

### Test 1: Line 1204

- Wrapped `Ledgers.process_event_payment_with_donations()` in `Oban.Testing.with_testing_mode(:manual, fn -> ... end)`
- Removed `setup_default_mocks()` call at the beginning
- Removed the "Clear sync status" block that was trying to reset already-synced payments
- Simplified the test to focus on the core functionality: item creation failure should cause sync to fail

### Test 2: Line 3272

- Wrapped both `Ledgers.process_payment()` and `Ledgers.process_refund()` in `Oban.Testing.with_testing_mode(:manual, fn -> ... end)`
- Removed `setup_default_mocks()` calls
- Removed the `Process.sleep(100)` and "Clear sync status" block
- Config is now set before the explicit sync, ensuring it's used correctly

## Testing

All 52 tests in `test/ysc/quickbooks/sync_test.exs` now pass consistently:

```bash
mix test test/ysc/quickbooks/sync_test.exs
# 52 tests, 0 failures
```

## Key Takeaways

1. **Oban inline mode** can cause race conditions in tests when async jobs run before test mocks are set up
2. Use `Oban.Testing.with_testing_mode(:manual, fn -> ... end)` to prevent inline execution when you need precise control over when jobs run
3. The pattern is:
   - Create entities with `:manual` mode
   - Set up specific mocks
   - Call sync functions explicitly
   - Assert on the results
