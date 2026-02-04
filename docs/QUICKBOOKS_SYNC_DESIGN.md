# QuickBooks Sync Design Recommendation

## Overview

This document outlines the recommended design for keeping purchases, refunds, and payouts in sync with QuickBooks Online.

## Design Decision: Direct Schema Integration

**Recommendation: Add QuickBooks sync fields directly to `Payment`, `Refund`, and `Payout` schemas.**

### Rationale

1. **Single Source of Truth**: The Payment/Refund/Payout records are the primary entities that need to be synced. They already contain all necessary information.

2. **Simpler Queries**: Easy to find records that need syncing, have failed, or are already synced.

3. **Transaction Integrity**: Keeps sync state with the data it represents, ensuring consistency.

4. **Minimal Schema Changes**: Only requires adding a few fields to existing schemas.

5. **Clear Ownership**: Each Payment/Refund/Payout owns its QuickBooks sync state.

## Schema Changes

### Payment Schema

Add the following fields to `Ysc.Ledgers.Payment`:

```elixir
field :quickbooks_sales_receipt_id, :string
field :quickbooks_sync_status, :string  # :pending, :synced, :failed
field :quickbooks_sync_error, :map  # JSON with error messages, error codes, etc.
field :quickbooks_response, :map  # Full response body from QuickBooks API
field :quickbooks_synced_at, :utc_datetime
field :quickbooks_last_sync_attempt_at, :utc_datetime
```

### Refund Schema

Add the following fields to `Ysc.Ledgers.Refund`:

```elixir
field :quickbooks_sales_receipt_id, :string  # Refunds are also SalesReceipts in QB
field :quickbooks_sync_status, :string
field :quickbooks_sync_error, :map  # JSON with error messages, error codes, etc.
field :quickbooks_response, :map  # Full response body from QuickBooks API
field :quickbooks_synced_at, :utc_datetime
field :quickbooks_last_sync_attempt_at, :utc_datetime
```

### Payout Schema

Add the following fields to `Ysc.Ledgers.Payout`:

```elixir
field :quickbooks_deposit_id, :string
field :quickbooks_sync_status, :string
field :quickbooks_sync_error, :map  # JSON with error messages, error codes, etc.
field :quickbooks_response, :map  # Full response body from QuickBooks API
field :quickbooks_synced_at, :utc_datetime
field :quickbooks_last_sync_attempt_at, :utc_datetime
```

## Sync Architecture

### 1. Async Background Jobs

Use **Oban** (already in your stack) to handle QuickBooks syncing asynchronously.

**Benefits:**

- Non-blocking: Payment processing doesn't wait for QuickBooks API
- Retry logic: Built-in retry for transient failures
- Rate limiting: Can control sync rate to avoid API limits
- Monitoring: Oban provides visibility into job status

### 2. Sync Flow

```
Payment/Refund/Payout Created
    ↓
Mark as :pending sync status
    ↓
Enqueue Oban job (with delay for batching if desired)
    ↓
Job executes → Call QuickBooks API
    ↓
On Success: Update sync status to :synced, store QB ID
On Failure: Update sync status to :failed, store error message
```

### 3. Idempotency

- Check `quickbooks_sync_status` before syncing
- If already `:synced`, skip (idempotent)
- If `:failed`, retry (with backoff)
- Store QuickBooks ID to prevent duplicate creation

## Implementation Plan

### Phase 1: Schema Migration

1. Create migration to add QuickBooks fields to all three schemas
2. Add fields to schema definitions
3. Update changesets to handle new fields

### Phase 2: Sync Functions

Create `Ysc.Quickbooks.Sync` module with:

```elixir
defmodule Ysc.Quickbooks.Sync do
  @moduledoc """
  Handles syncing Payment, Refund, and Payout records to QuickBooks.
  """

  # Sync a payment to QuickBooks as a SalesReceipt
  def sync_payment(payment)

  # Sync a refund to QuickBooks as a SalesReceipt (negative amount)
  def sync_refund(refund)

  # Sync a payout to QuickBooks as a Deposit
  def sync_payout(payout)

  # Batch sync multiple records
  def sync_payments(payments)
  def sync_refunds(refunds)
  def sync_payouts(payouts)
end
```

### Phase 3: Oban Workers

Create workers for async processing:

```elixir
defmodule Ysc.Quickbooks.SyncPaymentWorker do
  use Oban.Worker

  def perform(%{args: %{"payment_id" => payment_id}}) do
    # Fetch payment, sync to QuickBooks, update status
  end
end

defmodule Ysc.Quickbooks.SyncRefundWorker do
  use Oban.Worker

  def perform(%{args: %{"refund_id" => refund_id}}) do
    # Fetch refund, sync to QuickBooks, update status
  end
end

defmodule Ysc.Quickbooks.SyncPayoutWorker do
  use Oban.Worker

  def perform(%{args: %{"payout_id" => payout_id}}) do
    # Fetch payout, sync to QuickBooks, update status
  end
end
```

### Phase 4: Integration Points

#### In `Ysc.Ledgers.process_payment/1`:

```elixir
def process_payment(attrs) do
  Repo.transaction(fn ->
    # ... existing payment creation logic ...

    # After successful payment creation:
    {:ok, payment} = create_payment(...)

    # Mark for QuickBooks sync
    payment
    |> Payment.changeset(%{quickbooks_sync_status: :pending})
    |> Repo.update()

    # Enqueue sync job
    %{payment_id: payment.id}
    |> Ysc.Quickbooks.SyncPaymentWorker.new()
    |> Oban.insert()

    payment
  end)
end
```

#### In `Ysc.Ledgers.process_refund/1`:

Similar pattern - mark as pending and enqueue sync job.

#### In `Ysc.Ledgers.process_stripe_payout/1`:

Similar pattern - mark as pending and enqueue sync job.

### Phase 5: Manual Sync & Retry

Add admin functions for manual syncing and retrying failed syncs:

```elixir
defmodule Ysc.Quickbooks.Sync do
  # Retry failed syncs
  def retry_failed_syncs()

  # Manual sync for a specific record
  def force_sync_payment(payment_id)
  def force_sync_refund(refund_id)
  def force_sync_payout(payout_id)

  # Find records needing sync
  def pending_payments()
  def pending_refunds()
  def pending_payouts()
  def failed_syncs()
end
```

## Data Mapping

### Payment → QuickBooks SalesReceipt

- **Customer**: Map `payment.user` to QuickBooks Customer
- **Item**: Map based on `entity_type` (membership, event, booking, donation)
- **Amount**: Use `payment.amount`
- **Date**: Use `payment.payment_date`
- **Payment Method**: Map `payment.payment_method` to QuickBooks PaymentMethod
- **Reference**: Store `payment.reference_id` in QuickBooks memo/private note

### Refund → QuickBooks SalesReceipt (Negative)

- **Customer**: Map `refund.user` to QuickBooks Customer
- **Item**: Same as original payment
- **Amount**: Negative `refund.amount`
- **Date**: Use `refund.inserted_at`
- **Reference**: Link to original payment's QuickBooks SalesReceipt if available

### Payout → QuickBooks Deposit

- **Bank Account**: Map to QuickBooks bank account
- **Stripe Account**: Map to QuickBooks account representing Stripe
- **Amount**: Use `payout.amount`
- **Date**: Use `payout.arrival_date` or `payout.inserted_at`
- **Memo**: Include payout description and linked payment/refund references

## Error Handling

### Transient Errors (Retry)

- Network timeouts
- Rate limiting (429)
- Temporary API errors (5xx)

### Permanent Errors (Manual Review)

- Invalid customer/item IDs
- Validation errors
- Authentication failures (after refresh attempt)

### Error Storage

- Store error details (messages, codes, etc.) in `quickbooks_sync_error` as a map
- Store full QuickBooks API response in `quickbooks_response` for debugging
- Store last attempt timestamp
- Allow manual retry via admin interface

## Configuration

Add to `config/config.exs`:

```elixir
config :ysc, :quickbooks,
  # ... existing config ...
  sync_enabled: System.get_env("QUICKBOOKS_SYNC_ENABLED", "true") == "true",
  sync_delay_seconds: String.to_integer(System.get_env("QUICKBOOKS_SYNC_DELAY", "5")),
  max_retry_attempts: String.to_integer(System.get_env("QUICKBOOKS_MAX_RETRIES", "3"))
```

## Monitoring & Observability

1. **Metrics**: Track sync success/failure rates
2. **Alerts**: Alert on high failure rates
3. **Dashboard**: Show sync status in admin interface
4. **Logging**: Comprehensive logging of all sync operations

## Alternative Considered: Separate Sync Table

**Why not chosen:**

- Adds complexity with joins
- Risk of sync state getting out of sync with records
- More complex queries to find records needing sync
- Additional table to maintain

**When it might be better:**

- If you need to sync entities that don't have their own schemas
- If you need complex sync relationships (e.g., syncing ledger entries separately)
- If you want to keep QuickBooks concerns completely separate

## Migration Strategy

1. **Backfill Existing Records**: Create Oban jobs to sync existing payments/refunds/payouts
2. **Gradual Rollout**: Enable sync for new records first, then backfill
3. **Validation**: Compare totals between your system and QuickBooks periodically

## Benefits of This Design

1. ✅ **Simple**: Direct schema integration, easy to understand
2. ✅ **Reliable**: Sync state tied to data, can't get out of sync
3. ✅ **Observable**: Easy to query sync status
4. ✅ **Maintainable**: All sync logic in one place
5. ✅ **Scalable**: Async processing via Oban
6. ✅ **Resilient**: Built-in retry and error handling
