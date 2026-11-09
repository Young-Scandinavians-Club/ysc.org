# Financial Reconciliation System

## Overview

The financial reconciliation system ensures data consistency and integrity across all financial entities in the YSC application. It validates that payments, refunds, bookings, ticket reservations, and subscriptions all match their corresponding ledger entries.

## Purpose

Financial reconciliation is critical for:
- **Data Integrity**: Ensuring all financial data is consistent across systems
- **Fraud Detection**: Identifying anomalies or discrepancies
- **Audit Compliance**: Providing audit trails and verification
- **Error Detection**: Catching bugs or data corruption early
- **Confidence**: Knowing your financial data is accurate

## Architecture

### Components

1. **`Ysc.Ledgers.Reconciliation`** - Core reconciliation logic
2. **`Ysc.Ledgers.ReconciliationWorker`** - Scheduled Oban worker
3. **Ledger System** - Double-entry accounting foundation
4. **Entity Tables** - Payments, Refunds, Bookings, Tickets, Subscriptions

### Reconciliation Checks

The system performs the following checks:

#### 1. Payment Reconciliation
- Every payment has a ledger transaction
- Every payment has corresponding ledger entries
- Payment amounts match ledger entry totals
- Total payments in `payments` table = Total debits in ledger

#### 2. Refund Reconciliation
- Every refund has a ledger transaction
- Every refund references a valid payment
- Refund amounts match ledger entry totals
- Total refunds in `refunds` table = Total refund expenses in ledger

#### 3. Ledger Balance Check
- Total debits = Total credits (double-entry rule)
- All accounts sum to zero overall
- No imbalances detected

#### 4. Orphaned Entry Detection
- No ledger entries without valid payments
- No ledger transactions without valid payments/refunds
- All foreign key relationships intact

#### 5. Entity Total Reconciliation
- **Memberships**: Revenue in ledger matches payment totals
- **Bookings**: Revenue in ledger matches booking payment totals
- **Events**: Revenue in ledger matches ticket payment totals

#### 6. Payout Reconciliation
- For each Stripe payout: `sum(linked payments) - sum(linked refunds) - fee_total == payout.amount`
- Catches understated `fee_total` (e.g. missing Billing Usage / `stripe_fee` rows), incomplete linking, and amount drift
- Residual fees (`fee_total` minus fees already booked on linked payments) must be booked on the payout's virtual payment (`Stripe payout fee for …`)

## Usage

### Manual Reconciliation

Run a full reconciliation check:

```elixir
# In IEx
{:ok, report} = Ysc.Ledgers.Reconciliation.run_full_reconciliation()

# View formatted report
IO.puts(Ysc.Ledgers.Reconciliation.format_report(report))
```

### Specific Checks

Run individual reconciliation checks:

```elixir
# Check payments only
{:ok, payment_report} = Ysc.Ledgers.Reconciliation.reconcile_payments()

# Check refunds only
{:ok, refund_report} = Ysc.Ledgers.Reconciliation.reconcile_refunds()

# Check ledger balance
balance_check = Ysc.Ledgers.Reconciliation.check_ledger_balance()

# Check for orphaned entries
orphaned_check = Ysc.Ledgers.Reconciliation.check_orphaned_entries()

# Check entity totals
entity_check = Ysc.Ledgers.Reconciliation.reconcile_entity_totals()
```

### Trigger Worker Manually

```elixir
# Run reconciliation immediately
Ysc.Ledgers.ReconciliationWorker.run_now()

# Schedule for later (runs asynchronously)
Ysc.Ledgers.ReconciliationWorker.schedule_reconciliation()
```

## Scheduling

The reconciliation worker is scheduled to run automatically:

- **Time**: 1:00 AM UTC daily
- **Queue**: `maintenance`
- **Timeout**: 60 seconds
- **Max Attempts**: 3

Configuration in `config/config.exs`:

```elixir
{Oban.Plugins.Cron,
 crontab: [
   {"0 1 * * *", Ysc.Ledgers.ReconciliationWorker}
 ]}
```

## Report Structure

### Full Report Format

```elixir
%{
  timestamp: ~U[2024-11-20 01:00:00Z],
  duration_ms: 1234,
  overall_status: :ok | :error,
  checks: %{
    payments: %{
      status: :ok | :error,
      total_payments: 150,
      discrepancies_count: 0,
      discrepancies: [],
      totals: %{
        payments_table: Money.new(75000, :USD),
        ledger_entries: Money.new(75000, :USD),
        match: true
      }
    },
    refunds: %{
      status: :ok | :error,
      total_refunds: 5,
      discrepancies_count: 0,
      discrepancies: [],
      totals: %{
        refunds_table: Money.new(2500, :USD),
        ledger_entries: Money.new(2500, :USD),
        match: true
      }
    },
    ledger_balance: %{
      status: :ok | :error,
      balanced: true,
      message: "Ledger is balanced"
    },
    orphaned_entries: %{
      status: :ok | :error,
      orphaned_entries_count: 0,
      orphaned_entries: [],
      orphaned_transactions_count: 0,
      orphaned_transactions: []
    },
    entity_totals: %{
      status: :ok | :error,
      memberships: %{
        status: :ok | :error,
        ledger_revenue: Money.new(50000, :USD),
        payment_total: Money.new(50000, :USD),
        match: true
      },
      bookings: %{
        status: :ok | :error,
        ledger_revenue: Money.new(15000, :USD),
        payment_total: Money.new(15000, :USD),
        breakdown: %{
          tahoe: Money.new(10000, :USD),
          clear_lake: Money.new(5000, :USD),
          general: Money.new(0, :USD)
        },
        match: true
      },
      events: %{
        status: :ok | :error,
        ledger_revenue: Money.new(10000, :USD),
        payment_total: Money.new(10000, :USD),
        match: true
      }
    }
  }
}
```

### Formatted Report Example

```
╔══════════════════════════════════════════════════════════════════
║ FINANCIAL RECONCILIATION REPORT
╠══════════════════════════════════════════════════════════════════
║ Status: ✅ PASS
║ Timestamp: 2024-11-20 01:00:00Z
║ Duration: 1234ms
╠══════════════════════════════════════════════════════════════════
║ PAYMENTS
╠══════════════════════════════════════════════════════════════════
║ Total Payments: 150
║ Discrepancies: 0
║ Payments Table Total: $750.00
║ Ledger Entries Total: $750.00
║ Amounts Match: ✅ Yes
╠══════════════════════════════════════════════════════════════════
║ REFUNDS
╠══════════════════════════════════════════════════════════════════
║ Total Refunds: 5
║ Discrepancies: 0
║ Refunds Table Total: $25.00
║ Ledger Entries Total: $25.00
║ Amounts Match: ✅ Yes
╠══════════════════════════════════════════════════════════════════
║ LEDGER BALANCE
╠══════════════════════════════════════════════════════════════════
║ Balanced: ✅ Yes
╠══════════════════════════════════════════════════════════════════
║ ORPHANED ENTRIES
╠══════════════════════════════════════════════════════════════════
║ Orphaned Entries: 0
║ Orphaned Transactions: 0
╠══════════════════════════════════════════════════════════════════
║ ENTITY TOTALS
╠══════════════════════════════════════════════════════════════════
║ Memberships Match: ✅ Yes
║ Bookings Match: ✅ Yes
║ Events Match: ✅ Yes
╚══════════════════════════════════════════════════════════════════
```

## Discrepancy Types

### Payment Discrepancies

Possible issues detected:
- **No ledger transaction found** - Payment exists but no transaction record
- **Transaction amount mismatch** - Transaction amount ≠ payment amount
- **No ledger entries found** - Payment has no accounting entries
- **Entries don't balance** - Ledger entries for payment don't sum to zero

### Refund Discrepancies

Possible issues detected:
- **No ledger transaction found** - Refund exists but no transaction record
- **Transaction amount mismatch** - Transaction amount ≠ refund amount
- **Referenced payment not found** - Refund points to non-existent payment
- **No refund ledger entries found** - Refund has no accounting entries

### Ledger Imbalances

Indicators of problems:
- **Total debits ≠ total credits** - Fundamental accounting violation
- **Account balance anomalies** - Unexpected balances in specific accounts
- **Missing offsetting entries** - Transactions without proper double-entry

### Orphaned Entries

Data integrity issues:
- **Entries without payments** - Ledger entries referencing deleted payments
- **Transactions without entities** - Transactions not linked to payments/refunds
- **Broken foreign keys** - Database relationship violations

### Entity Mismatches

Business logic inconsistencies:
- **Revenue mismatch** - Ledger revenue ≠ sum of entity payments
- **Missing entity records** - Payments without corresponding bookings/tickets
- **Duplicate entries** - Same payment recorded multiple times

## Alerting

When a run finds discrepancies, `ReconciliationWorker`:

1. Logs the discrepancies
2. Posts to Discord: `Discord.send_reconciliation_report/2` for the summary (`:success` / `:error`), plus `send_ledger_imbalance_alert/1` for an imbalance and `send_payment_discrepancy_alert/…` when individual payment discrepancies exist. An aggregate-only payment mismatch shows in the summary without the totals (see [DISCORD_ALERTS.md](DISCORD_ALERTS.md))
3. Emails the Treasurer when a Stripe payout does not reconcile (payout mismatch template)

The Discord summary shows counts and match status, and the payment alert lists IDs and issues for up to three payments. Run `Ysc.Ledgers.Reconciliation.run_full_reconciliation()` and inspect `report.checks.payments.discrepancies` and `report.checks.refunds.discrepancies` for the complete lists.

## Troubleshooting

### Common Discrepancies and Fixes

#### 1. Payment Without Ledger Transaction

**Cause**: Payment creation succeeded but ledger transaction failed

**Investigation**:
```elixir
payment = Ysc.Ledgers.get_payment("payment_id")
entries = Ysc.Ledgers.get_entries_by_payment(payment.id)
```

**Fix**: Manually create ledger transaction:
```elixir
Ysc.Ledgers.process_payment(%{
  user_id: payment.user_id,
  amount: payment.amount,
  # ... other attrs
})
```

#### 2. Ledger Imbalance

**Cause**: Missing credit entry, calculation error, or corrupted data

**Investigation**:
```elixir
{:error, details} = Ysc.Ledgers.get_ledger_imbalance_details()
account_balances = Ysc.Ledgers.get_account_balances()
```

**Fix**: Identify problematic accounts and create correcting entries

#### 3. Orphaned Entries

**Cause**: Payment deleted but ledger entries remained

**Investigation**:
```elixir
orphaned = Ysc.Ledgers.Reconciliation.check_orphaned_entries()
```

**Fix**: Either restore deleted payment or delete orphaned entries

#### 4. Entity Total Mismatch

**Cause**: Payment entity_type incorrect or ledger entry misclassified

**Investigation**:
```elixir
# Check all payments for entity
payments = Ysc.Ledgers.get_payments_by_user(user_id)

# Check ledger entries
entries = Ysc.Ledgers.get_entries_by_payment(payment_id)
```

**Fix**: Update entity_type or correct ledger account classification

## Ledger balance check

`Ysc.Ledgers.BalanceCheckWorker` runs at 00:00 UTC (`maintenance` queue, 3 attempts), an hour before reconciliation, and verifies that total debits equal total credits. On an imbalance it logs a warning with the difference, the account-type breakdown and the top five accounts by absolute balance. It does **not** post to Discord; the 01:00 reconciliation run reports an imbalance to Discord.

```elixir
Ysc.Ledgers.BalanceCheckWorker.check_balance_now()   # run on demand

Ysc.Ledgers.verify_ledger_balance()                  # {:ok, :balanced} | {:error, {:imbalanced, diff}}
Ysc.Ledgers.get_ledger_imbalance_details()           # adds the per-account breakdown
Ysc.Ledgers.get_account_balances()                   # [{account, balance}, ...]
Ysc.Ledgers.calculate_account_balance(account_id)
```

Investigating an imbalance: look at the largest account balances, then at recent payments and ledger transactions that are incomplete or failed. Ledger entries are append-only (see `ledger_entry_append_only_test.exs`), so fix a bad entry with a compensating transaction rather than editing it.

## Practices

- Treat a reconciliation failure as a priority incident; fix and record the root cause.
- Keep every financial write inside a database transaction and idempotent (see [STRIPE_WEBHOOKS.md](STRIPE_WEBHOOKS.md)).
- Run `run_full_reconciliation/0` by hand after migrations or data repairs.

## Tests

`test/ysc/ledgers/reconciliation_test.exs`, `reconciliation_worker_test.exs`, `reconciliation_telemetry_test.exs` and `balance_check_worker_test.exs`. Each discrepancy type in this document has a test that builds the inconsistent data and asserts it is reported; add one when you add a check.

## Related

- [LEDGER_SYSTEM_README.md](LEDGER_SYSTEM_README.md): double-entry model and accounts
- [CURRENCY_HANDLING.md](CURRENCY_HANDLING.md): dollars vs. cents
- [STRIPE_WEBHOOKS.md](STRIPE_WEBHOOKS.md): how payments and refunds reach the ledger
- [REPROCESS_PAYOUTS.md](REPROCESS_PAYOUTS.md): fixing payout links and fees
- [MONITORING.md](MONITORING.md): all nightly checks
