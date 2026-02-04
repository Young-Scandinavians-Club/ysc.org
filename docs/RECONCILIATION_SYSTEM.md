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

When discrepancies are found, the system:

1. **Logs Critical Errors** - All discrepancies logged at CRITICAL level
2. **Sends Alerts** - Integrates with alerting system (Slack, email, PagerDuty)
3. **Provides Details** - Specific payment IDs, amounts, and issues
4. **Suggests Actions** - Guidance on investigating and resolving issues

### Alert Example

```
🚨 CRITICAL: Financial Reconciliation Discrepancies Detected

**Timestamp:** 2024-11-20 01:00:00Z
**Duration:** 1234ms

**PAYMENT DISCREPANCIES**
- Total Discrepancies: 2
- Payments Total: $750.00
- Ledger Total: $740.00
- Match: false

Issues:
  - Payment 01ABC123:
    No ledger transaction found
  - Payment 01DEF456:
    Transaction amount ($15.00) doesn't match payment amount ($25.00)

**Action Required:**
Investigate these discrepancies immediately. Run detailed checks:
```
Ysc.Ledgers.Reconciliation.run_full_reconciliation()
```
```

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

## Best Practices

### 1. Run Regularly
- Automated daily checks at off-peak hours
- Manual checks after major migrations or data changes
- Spot checks when suspicious activity detected

### 2. Monitor Trends
- Track discrepancy counts over time
- Alert on increasing error rates
- Investigate patterns in failures

### 3. Immediate Response
- Treat reconciliation failures as P0 incidents
- Investigate and resolve within 24 hours
- Document root causes and fixes

### 4. Preventive Measures
- Use database transactions for all financial operations
- Implement idempotency for webhook handlers
- Add validation at multiple layers
- Test edge cases thoroughly

### 5. Audit Trail
- Log all reconciliation results
- Store reports for historical analysis
- Maintain records of discrepancies and resolutions

## Integration

### Slack Notifications

```elixir
defp send_slack_notification(alert_message) do
  # Configure in your alerting module
  Ysc.Alerts.send_slack_message(
    channel: "#finance-alerts",
    message: alert_message,
    priority: :critical
  )
end
```

### Email Alerts

```elixir
defp send_email_alert(alert_message) do
  Ysc.Mailer.deliver(
    Ysc.Emails.reconciliation_alert(
      to: "finance@yourcompany.com",
      subject: "🚨 Financial Reconciliation Alert",
      body: alert_message
    )
  )
end
```

### PagerDuty Integration

```elixir
defp trigger_pagerduty(report) do
  Ysc.PagerDuty.create_incident(
    service: "financial-system",
    severity: "critical",
    summary: "Financial reconciliation discrepancies detected",
    details: report
  )
end
```

## Performance Considerations

### Large Datasets

For systems with millions of transactions:

1. **Pagination**: Process payments/refunds in batches
2. **Sampling**: Run full checks periodically, sample daily
3. **Indexes**: Ensure proper database indexes on foreign keys
4. **Caching**: Cache account lookups and calculations
5. **Parallelization**: Use concurrent queries where safe

### Optimization Example

```elixir
# Process payments in batches
def reconcile_payments_batched(batch_size \\ 1000) do
  Payment
  |> Repo.stream()
  |> Stream.chunk_every(batch_size)
  |> Enum.reduce([], fn batch, acc ->
    batch_discrepancies = check_batch(batch)
    acc ++ batch_discrepancies
  end)
end
```

## Testing

Comprehensive tests should cover:

```elixir
# Test successful reconciliation
test "reconciliation passes with consistent data"

# Test payment discrepancies
test "detects payment without ledger transaction"
test "detects payment amount mismatch"

# Test refund discrepancies
test "detects refund without ledger transaction"
test "detects orphaned refund"

# Test ledger imbalances
test "detects ledger imbalance"

# Test orphaned entries
test "detects entries without valid payments"

# Test entity mismatches
test "detects membership revenue mismatch"
```

## Related Documentation

- [Ledger System](LEDGER_SYSTEM_README.md) - Double-entry accounting overview
- [Currency Handling](CURRENCY_HANDLING.md) - Dollars vs cents conversion
- [Stripe Webhooks](STRIPE_WEBHOOK_FIXES_IMPLEMENTED_V2.md) - Payment processing
- [Balance Monitoring](LEDGER_BALANCE_MONITORING.md) - Daily balance checks

---

**Last Updated**: November 20, 2024
**Maintained By**: Engineering Team
**Review Frequency**: Quarterly

