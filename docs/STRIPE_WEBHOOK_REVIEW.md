# Stripe Webhook Handler - Comprehensive Review

**Date:** November 20, 2024
**Reviewer:** AI Assistant
**Status:** Critical Issues Found

## Executive Summary

The Stripe webhook handler has good idempotency protection at the webhook event level, but there are **critical issues** with duplicate refund processing and race conditions between subscription creation and invoice payment webhooks that could lead to data inconsistency.

---

## ✅ What's Working Well

### 1. Webhook Event Deduplication

- ✅ Excellent webhook-level idempotency using database locking
- ✅ Proper handling of duplicate webhook deliveries from Stripe
- ✅ State tracking (pending → processing → processed/failed)
- ✅ Retry mechanism via `Ysc.Webhooks.Reprocessor`

### 2. Payment Idempotency

- ✅ Unique constraint on `payments.external_payment_id`
- ✅ Check for existing payment in `invoice.payment_succeeded` handler (lines 327-335)
- ✅ Prevents duplicate payment recording

### 3. Subscription Management

- ✅ `create_subscription_from_stripe` checks for existing subscription (lines 725-734)
- ✅ Proper subscription item updates with `on_conflict: :replace_all`
- ✅ Handles subscription cancellation properly

### 4. Payout Tracking

- ✅ Idempotency check for payouts (lines 441-454)
- ✅ Unique constraint on `payouts.stripe_payout_id`
- ✅ Proper linking of balance transactions to payouts

---

## 🚨 Critical Issues

### Issue #1: Duplicate Refund Processing (CRITICAL)

**Location:** Lines 470-515 (both `charge.refunded` and `refund.created` handlers)

**Problem:**
Both webhook events process refunds for the same Stripe refund, potentially creating duplicate refund transactions in the ledger.

**Evidence:**

```elixir
# Both handlers call process_refund without checking if refund already exists
defp handle("charge.refunded", %Stripe.Charge{} = charge) do
  process_refund_from_charge(charge)  # Creates refund transaction
  :ok
end

defp handle("refund.created", %Stripe.Refund{} = refund) do
  process_refund_from_refund_object(refund)  # Creates ANOTHER refund transaction
  :ok
end
```

**Root Cause:**

1. No tracking of `external_refund_id` in database (not stored in `ledger_transactions`)
2. The `external_refund_id` parameter is passed but **never used** in `create_refund_entries` (line 352-356)
3. No unique constraint to prevent duplicate refunds

**Impact:**

- 💰 **Double refunds in ledger** (same refund processed twice)
- 📊 **Incorrect financial reporting** (revenue/expenses doubled)
- 🏦 **Ledger imbalance** (books won't balance)

**Frequency:** Every time both webhooks arrive (which Stripe guarantees they will)

---

### Issue #2: Race Condition - Invoice vs Subscription (HIGH)

**Location:** Lines 306-382 (`invoice.payment_succeeded`)

**Problem:**
If `invoice.payment_succeeded` arrives before `customer.subscription.created`, the payment is recorded with `entity_id: nil` because the subscription doesn't exist yet in our database.

**Evidence:**

```elixir
# Line 346: entity_id may be nil
entity_id: find_subscription_id_from_stripe_id(subscription_id, user),

# find_subscription_id_from_stripe_id returns nil if subscription not found
defp find_subscription_id_from_stripe_id(stripe_subscription_id, _user) do
  case Ysc.Subscriptions.get_subscription_by_stripe_id(stripe_subscription_id) do
    nil -> nil  # ❌ Payment gets created with entity_id: nil
    subscription -> subscription.id
  end
end
```

**Workaround Present:** The `resolve_subscription_id` function (lines 762-819) tries to find the subscription by querying the most recent subscription for the user, but this is:

- Unreliable (what if multiple subscriptions?)
- Hacky (sorting by inserted_at and hoping)
- Doesn't fix the entity_id problem

**Impact:**

- 💸 Payments not linked to subscriptions
- 📊 Cannot properly track subscription revenue
- 🔍 Difficult to reconcile payments to memberships

---

### Issue #3: Missing Refund Idempotency in Ledger (CRITICAL)

**Location:** `lib/ysc/ledgers.ex` lines 307-347

**Problem:**
The `process_refund` function accepts `external_refund_id` but never stores or uses it for idempotency checks.

**Evidence:**

```elixir
# process_refund receives external_refund_id
def process_refund(attrs) do
  %{
    payment_id: payment_id,
    refund_amount: refund_amount,
    reason: reason,
    external_refund_id: external_refund_id  # ✅ Received
  } = attrs

  # ... but never checks if this external_refund_id already processed

  # create_refund_entries doesn't even extract it:
  %{
    payment: payment,
    refund_amount: refund_amount,
    reason: reason
  } = attrs  # ❌ external_refund_id ignored!
```

**Impact:**

- No protection against duplicate refunds at the ledger level
- Relies entirely on webhook-level deduplication (insufficient given multiple webhook types for same refund)

---

### Issue #4: Partial Refund Handling (MEDIUM)

**Location:** Lines 934-1025 (`process_refund_from_charge`)

**Problem:**
When multiple partial refunds exist on a charge, the handler sums all refunds and processes them as one. If a new partial refund is added, it would process the entire total again.

**Evidence:**

```elixir
# Line 950-957: Sums ALL refunds
total_cents =
  Enum.reduce(refunds, 0, fn refund, acc ->
    case refund do
      %Stripe.Refund{amount: amount} -> acc + amount
      %{amount: amount} when is_integer(amount) -> acc + amount
      _ -> acc
    end
  end)
```

**Impact:**

- Each `charge.refunded` event would process the cumulative total
- Partial refunds get re-processed

---

### Issue #5: Payment Method Race Condition (LOW)

**Location:** Lines 128-143 (`customer.updated` handler)

**Problem:**
The handler explicitly skips syncing to prevent race conditions, but there's no documentation of what the race condition is or how it's properly resolved.

**Evidence:**

```elixir
defp handle("customer.updated", %Stripe.Customer{} = event) do
  user = Ysc.Accounts.get_user_from_stripe_id(event.id)

  if user do
    # Temporarily disable automatic syncing to prevent race conditions
    # The user-initiated payment method selection should handle this
    Logger.info("Customer updated webhook received, skipping automatic sync...")
  end

  :ok  # ❌ Does nothing
end
```

**Impact:**

- Unclear if customer updates are properly synchronized
- Potential for stale payment method data

---

## 🔧 Recommended Fixes

### Fix #1: Add External Refund ID Tracking (CRITICAL - Must Fix)

**Changes Required:**

1. **Database Migration**: Add `external_refund_id` to `ledger_transactions`

```elixir
# priv/repo/migrations/TIMESTAMP_add_external_refund_id_to_ledger_transactions.exs
defmodule Ysc.Repo.Migrations.AddExternalRefundIdToLedgerTransactions do
  use Ecto.Migration

  def change do
    alter table(:ledger_transactions) do
      add :external_refund_id, :string
    end

    # Unique constraint to prevent duplicate refund processing
    create unique_index(:ledger_transactions, [:external_refund_id],
      where: "external_refund_id IS NOT NULL",
      name: :ledger_transactions_external_refund_id_index
    )

    create index(:ledger_transactions, [:external_refund_id])
  end
end
```

2. **Update Schema**: Add field to `LedgerTransaction`

```elixir
# lib/ysc/ledgers/ledger_transaction.ex
schema "ledger_transactions" do
  field :type, LedgerTransactionType
  belongs_to :payment, Ysc.Ledgers.Payment
  field :total_amount, Money.Ecto.Composite.Type, default_currency: :USD
  field :status, LedgerTransactionStatus
  field :external_refund_id, :string  # ADD THIS

  timestamps()
end

def changeset(transaction, attrs) do
  transaction
  |> cast(attrs, [:type, :payment_id, :total_amount, :status, :external_refund_id])  # ADD HERE
  |> validate_required([:type, :total_amount, :status])
  |> validate_length(:external_refund_id, max: 255)
  |> unique_constraint(:external_refund_id)  # ADD THIS
  |> foreign_key_constraint(:payment_id)
end
```

3. **Update Ledgers Module**: Store and check external_refund_id

```elixir
# lib/ysc/ledgers.ex - Update process_refund
def process_refund(attrs) do
  %{
    payment_id: payment_id,
    refund_amount: refund_amount,
    reason: reason,
    external_refund_id: external_refund_id
  } = attrs

  ensure_basic_accounts()

  Repo.transaction(fn ->
    # Get original payment
    payment = Repo.get!(Payment, payment_id)

    # ✅ CHECK if refund already exists
    if external_refund_id do
      existing_refund =
        from(t in LedgerTransaction,
          where: t.external_refund_id == ^external_refund_id,
          where: t.type == "refund"
        )
        |> Repo.one()

      if existing_refund do
        # Refund already processed, return existing transaction
        Repo.rollback({:already_processed, existing_refund})
      end
    end

    # Create refund transaction with external_refund_id
    {:ok, refund_transaction} =
      create_transaction(%{
        type: :refund,
        payment_id: payment_id,
        total_amount: refund_amount,
        status: :completed,
        external_refund_id: external_refund_id  # ✅ STORE IT
      })

    # Create double-entry entries for refund
    entries =
      create_refund_entries(%{
        payment: payment,
        transaction: refund_transaction,
        refund_amount: refund_amount,
        reason: reason,
        external_refund_id: external_refund_id
      })

    # Update original payment status if fully refunded
    if Money.equal?(refund_amount, payment.amount) do
      update_payment(payment, %{status: :refunded})
    end

    {refund_transaction, entries}
  end)
end
```

4. **Update Webhook Handler**: Handle idempotency properly

```elixir
# lib/ysc/stripe/webhook_handler.ex

defp handle("charge.refunded", %Stripe.Charge{} = charge) do
  require Logger

  Logger.info("Charge refunded",
    charge_id: charge.id,
    payment_intent_id: charge.payment_intent
  )

  # Process refund in ledger
  result = process_refund_from_charge(charge)

  # ✅ Handle already processed case
  case result do
    {:error, {:already_processed, _refund_transaction}} ->
      Logger.info("Refund already processed, skipping (idempotency)",
        charge_id: charge.id,
        payment_intent_id: charge.payment_intent
      )
      :ok

    _ ->
      result
  end

  :ok
end

defp handle("refund.created", %Stripe.Refund{} = refund) do
  require Logger

  Logger.info("Refund created",
    refund_id: refund.id,
    charge_id: refund.charge,
    amount: refund.amount
  )

  # Process refund in ledger
  result = process_refund_from_refund_object(refund)

  # ✅ Handle already processed case
  case result do
    {:error, {:already_processed, _refund_transaction}} ->
      Logger.info("Refund already processed, skipping (idempotency)",
        refund_id: refund.id,
        charge_id: refund.charge
      )
      :ok

    _ ->
      result
  end

  :ok
end

# Update both process_refund functions to handle rollback
defp process_refund_from_charge(%Stripe.Charge{} = charge) do
  require Logger

  payment_intent_id = charge.payment_intent

  if payment_intent_id do
    payment = Ledgers.get_payment_by_external_id(payment_intent_id)

    if payment do
      # Get refund amount and ID
      {refund_amount, refund_id} = extract_refund_info_from_charge(charge)

      reason = extract_refund_reason(charge.metadata)

      # Process refund in ledger
      case Ledgers.process_refund(%{
             payment_id: payment.id,
             refund_amount: refund_amount,
             reason: reason,
             external_refund_id: refund_id
           }) do
        {:ok, {_refund_transaction, _entries}} ->
          Logger.info("Refund processed successfully in ledger",
            payment_id: payment.id,
            refund_id: refund_id,
            amount: Money.to_string!(refund_amount)
          )
          :ok

        {:error, {:already_processed, refund_transaction}} ->
          # Return the error tuple so it can be handled by caller
          {:error, {:already_processed, refund_transaction}}

        {:error, reason} ->
          Logger.error("Failed to process refund in ledger",
            payment_id: payment.id,
            refund_id: refund_id,
            error: inspect(reason)
          )
          :ok
      end
    else
      Logger.warning("Payment not found for refund",
        payment_intent_id: payment_intent_id,
        charge_id: charge.id
      )
      :ok
    end
  else
    Logger.warning("No payment intent ID found in charge", charge_id: charge.id)
    :ok
  end
end

# Helper to extract refund info more reliably
defp extract_refund_info_from_charge(%Stripe.Charge{} = charge) do
  case charge.refunds do
    %Stripe.List{data: [refund | _]} ->
      amount = Money.new(:USD, MoneyHelper.cents_to_dollars(refund.amount))
      refund_id = refund.id
      {amount, refund_id}

    %Stripe.List{data: refunds} when is_list(refunds) and length(refunds) > 0 ->
      # Take the most recent refund
      refund = List.last(refunds)
      amount = Money.new(:USD, MoneyHelper.cents_to_dollars(refund.amount))
      refund_id = refund.id
      {amount, refund_id}

    _ ->
      # Fallback
      amount = Money.new(:USD, MoneyHelper.cents_to_dollars(charge.amount))
      {amount, nil}
  end
end

defp extract_refund_reason(metadata) do
  case metadata do
    %{"reason" => reason} when is_binary(reason) -> reason
    %{reason: reason} when is_binary(reason) -> reason
    _ -> "Booking cancellation refund"
  end
end
```

---

### Fix #2: Resolve Subscription Race Condition (HIGH)

**Option A: Store Subscription ID from Invoice (Recommended)**

The invoice contains the subscription ID. Store it even if the subscription doesn't exist locally yet, then backfill when subscription.created arrives.

```elixir
# lib/ysc/stripe/webhook_handler.ex

defp handle("invoice.payment_succeeded", invoice) when is_map(invoice) do
  require Logger

  subscription_id = resolve_subscription_id(invoice)

  case subscription_id do
    nil ->
      :ok

    subscription_id ->
      customer_id = invoice[:customer] || invoice["customer"]
      invoice_id = invoice[:id] || invoice["id"]
      user = Ysc.Accounts.get_user_from_stripe_id(customer_id)

      if user do
        existing_payment = Ledgers.get_payment_by_external_id(invoice_id)

        if existing_payment do
          Logger.info("Payment already exists for invoice",
            invoice_id: invoice_id,
            payment_id: existing_payment.id
          )
          :ok
        else
          # ✅ Find or wait for subscription
          entity_id = find_or_create_subscription_reference(subscription_id, user)

          amount_paid = invoice[:amount_paid] || invoice["amount_paid"]
          description = invoice[:description] || invoice["description"]
          number = invoice[:number] || invoice["number"]

          payment_attrs = %{
            user_id: user.id,
            amount: Money.new(:USD, MoneyHelper.cents_to_dollars(amount_paid)),
            entity_type: :membership,
            entity_id: entity_id,  # ✅ Will be set properly
            external_payment_id: invoice_id,
            stripe_fee: extract_stripe_fee_from_invoice(invoice),
            description: "Membership payment - #{description || "Invoice #{number}"}",
            property: nil,
            payment_method_id: extract_payment_method_from_invoice(invoice)
          }

          case Ledgers.process_payment(payment_attrs) do
            {:ok, {_payment, _transaction, _entries}} ->
              Logger.info("Subscription payment processed successfully in ledger",
                invoice_id: invoice_id,
                user_id: user.id,
                subscription_id: subscription_id
              )
              :ok

            {:error, reason} ->
              Logger.error("Failed to process subscription payment in ledger",
                invoice_id: invoice_id,
                user_id: user.id,
                error: reason
              )
              :ok
          end
        end
      else
        Logger.warning("No user found for invoice payment",
          invoice_id: invoice_id,
          customer_id: customer_id
        )
        :ok
      end
  end
end

# New helper function
defp find_or_create_subscription_reference(stripe_subscription_id, user) do
  # Try to find existing subscription
  case Ysc.Subscriptions.get_subscription_by_stripe_id(stripe_subscription_id) do
    nil ->
      # Subscription doesn't exist locally yet
      # Fetch from Stripe and create it
      require Logger

      Logger.info("Subscription not found locally, fetching from Stripe",
        stripe_subscription_id: stripe_subscription_id,
        user_id: user.id
      )

      case Stripe.Subscription.retrieve(stripe_subscription_id) do
        {:ok, stripe_subscription} ->
          case Ysc.Subscriptions.create_subscription_from_stripe(user, stripe_subscription) do
            {:ok, subscription} ->
              Logger.info("Created subscription from Stripe before processing payment",
                subscription_id: subscription.id,
                stripe_subscription_id: stripe_subscription_id
              )
              subscription.id

            {:error, reason} ->
              Logger.error("Failed to create subscription from Stripe",
                stripe_subscription_id: stripe_subscription_id,
                error: inspect(reason)
              )
              nil
          end

        {:error, reason} ->
          Logger.error("Failed to fetch subscription from Stripe",
            stripe_subscription_id: stripe_subscription_id,
            error: inspect(reason)
          )
          nil
      end

    subscription ->
      subscription.id
  end
end
```

**Option B: Defer Payment Processing**

Create the payment but mark it as pending, then update it when subscription is confirmed.

---

### Fix #3: Handle Partial Refunds Correctly (MEDIUM)

**Change the `charge.refunded` handler to only use `refund.created`:**

```elixir
# Option 1: Ignore charge.refunded entirely
defp handle("charge.refunded", %Stripe.Charge{} = charge) do
  require Logger

  Logger.info("Charge refunded event received, relying on refund.created events",
    charge_id: charge.id,
    payment_intent_id: charge.payment_intent
  )

  # Don't process - let refund.created handle each individual refund
  :ok
end

# Option 2: Make charge.refunded fetch individual refunds
defp handle("charge.refunded", %Stripe.Charge{} = charge) do
  require Logger

  Logger.info("Charge refunded",
    charge_id: charge.id,
    payment_intent_id: charge.payment_intent
  )

  # Process each refund individually to match refund.created behavior
  case charge.refunds do
    %Stripe.List{data: refunds} when is_list(refunds) ->
      Enum.each(refunds, fn refund ->
        process_refund_from_refund_object(refund)
      end)

    _ ->
      Logger.warning("No refunds data in charge.refunded event",
        charge_id: charge.id
      )
  end

  :ok
end
```

---

### Fix #4: Document Payment Method Race Condition (LOW)

Add proper documentation and consider re-enabling sync with proper locking:

```elixir
defp handle("customer.updated", %Stripe.Customer{} = event) do
  user = Ysc.Accounts.get_user_from_stripe_id(event.id)

  if user do
    # Skip automatic syncing because:
    # 1. User-initiated payment method changes update default immediately
    # 2. Stripe may send customer.updated before payment_method.attached
    # 3. We rely on payment_method.* webhooks for payment method sync
    # 4. Customer.updated can fire for many reasons (address, email, etc.)
    #    and we don't want to overwrite user's payment method selection
    require Logger

    Logger.info(
      "Customer updated webhook received, skipping automatic sync",
      user_id: user.id,
      customer_id: event.id,
      reason: "Payment method changes handled by payment_method.* webhooks"
    )
  end

  :ok
end
```

---

## 🧪 Testing Recommendations

### Test Case 1: Duplicate Refund Webhooks

```elixir
# test/ysc/stripe/webhook_handler_test.exs
test "handles duplicate refund webhooks (charge.refunded + refund.created)" do
  # Setup: Create payment
  # Send charge.refunded webhook
  # Send refund.created webhook with same refund_id
  # Assert: Only ONE refund transaction created
  # Assert: Payment status updated correctly
  # Assert: Ledger entries are correct (not doubled)
end
```

### Test Case 2: Invoice Before Subscription

```elixir
test "handles invoice.payment_succeeded before customer.subscription.created" do
  # Setup: Create user
  # Send invoice.payment_succeeded (subscription doesn't exist yet)
  # Assert: Payment created with correct entity_id
  # Send customer.subscription.created
  # Assert: Subscription created
  # Assert: Payment properly linked to subscription
end
```

### Test Case 3: Partial Refunds

```elixir
test "handles multiple partial refunds correctly" do
  # Setup: Create payment for $100
  # Send refund.created for $30
  # Send refund.created for $40
  # Send charge.refunded with both refunds
  # Assert: Only 2 refund transactions (not 3)
  # Assert: Total refunded = $70
  # Assert: Payment status = partially_refunded (if you add this status)
end
```

---

## 📊 Impact Assessment

### Critical (Must Fix Before Production)

1. ✅ **Duplicate Refund Processing** - Fix #1 required
2. ✅ **Subscription Race Condition** - Fix #2 required

### High Priority (Should Fix Soon)

3. **Partial Refund Handling** - Fix #3 recommended

### Medium Priority (Technical Debt)

4. **Payment Method Race Condition** - Fix #4 (documentation)

---

## 🎯 Implementation Plan

### Phase 1: Critical Fixes (Week 1)

1. Implement Fix #1 (Refund Idempotency)
   - Create migration
   - Update schema
   - Update Ledgers module
   - Update webhook handler
   - Add tests
2. Implement Fix #2 (Subscription Race Condition)
   - Add helper function
   - Update webhook handler
   - Add tests

### Phase 2: High Priority (Week 2)

3. Implement Fix #3 (Partial Refunds)
   - Update charge.refunded handler
   - Add tests

### Phase 3: Documentation (Week 3)

4. Implement Fix #4 (Documentation)
   - Add comments
   - Update README

---

## 📝 Additional Recommendations

### 1. Add Ledger Balance Checks

Consider adding a periodic job to verify ledger balance:

```elixir
# Verify that debits = credits
def verify_ledger_balance do
  total_debits =
    from(e in LedgerEntry, where: e.amount > 0, select: sum(e.amount))
    |> Repo.one()

  total_credits =
    from(e in LedgerEntry, where: e.amount < 0, select: sum(e.amount))
    |> Repo.one()

  if Money.add(total_debits, total_credits) != Money.new(0, :USD) do
    Logger.error("LEDGER IMBALANCE DETECTED!")
  end
end
```

### 2. Add Webhook Replay Protection

Consider adding a timestamp check to prevent replay attacks:

```elixir
# Reject webhooks older than 5 minutes
if DateTime.diff(DateTime.utc_now(), event_timestamp) > 300 do
  {:error, :webhook_too_old}
end
```

### 3. Add Monitoring

- Set up alerts for failed webhooks
- Monitor ledger balance
- Track webhook processing time
- Alert on duplicate payment/refund attempts

### 4. Add Reconciliation Reports

- Daily report comparing Stripe payments/refunds to local ledger
- Alert on discrepancies

---

## ✅ Sign-Off

This review has identified critical issues that **must be fixed** before the system can be considered production-ready for financial transactions.

**Priority:** 🔴 HIGH
**Recommended Action:** Implement Phase 1 fixes immediately

**Next Steps:**

1. Review this document with team
2. Prioritize fixes
3. Assign implementation
4. Test thoroughly
5. Deploy to staging
6. Monitor carefully

---

## Appendix: Related Files

- `lib/ysc/stripe/webhook_handler.ex` - Main webhook handler
- `lib/ysc/ledgers.ex` - Ledger processing logic
- `lib/ysc/ledgers/payment.ex` - Payment schema
- `lib/ysc/ledgers/ledger_transaction.ex` - Transaction schema
- `lib/ysc/subscriptions.ex` - Subscription management
- `lib/ysc/webhooks.ex` - Webhook event storage
- `lib/ysc/webhooks/reprocessor.ex` - Failed webhook retry
- `priv/repo/migrations/20241204201154_add_ledger.exs` - Ledger schema
