# Ledger Balance Monitoring System

**Date:** November 20, 2024
**Status:** ✅ Implemented and Scheduled

## Overview

Automated nightly ledger balance checks ensure the integrity of the double-entry accounting system. The system verifies that debits equal credits and identifies specific accounts causing any imbalances.

---

## Features

### 1. Automated Daily Checks ✅
- **Schedule:** Midnight UTC (00:00) every night
- **Queue:** `maintenance` (dedicated queue for system health tasks)
- **Duration:** ~30 seconds max (typically <5 seconds)
- **Retry:** 3 attempts on failure

### 2. Detailed Imbalance Detection ✅
- Total difference calculation
- Account-by-account breakdown
- Grouping by account type (asset, liability, revenue, expense)
- Top 5 accounts by absolute value
- Comprehensive logging for investigation

### 3. Alert System ✅
- Critical error logging
- Detailed breakdown in alerts
- Investigation commands included
- Ready for integration with external alerting (Slack, PagerDuty, email)

---

## Components

### 1. Ledger Module Functions

**File:** `lib/ysc/ledgers.ex`

#### `verify_ledger_balance/0`
Basic balance check returning `:ok` or `:error`.

```elixir
Ysc.Ledgers.verify_ledger_balance()
# => {:ok, :balanced}
# or
# => {:error, {:imbalanced, %Money{amount: 100, currency: :USD}}}
```

#### `get_ledger_imbalance_details/0`
Enhanced check with account-level details.

```elixir
Ysc.Ledgers.get_ledger_imbalance_details()
# => {:ok, :balanced}
# or
# => {:error, {:imbalanced, difference, [
#      {%LedgerAccount{name: "stripe_account"}, %Money{amount: 1000}},
#      {%LedgerAccount{name: "revenue"}, %Money{amount: -900}}
#    ]}}
```

#### `get_account_balances/0`
Returns all accounts with non-zero balances, sorted by amount.

```elixir
Ysc.Ledgers.get_account_balances()
# => [
#   {%LedgerAccount{name: "stripe_account"}, %Money{amount: 5000}},
#   {%LedgerAccount{name: "membership_revenue"}, %Money{amount: -4500}},
#   ...
# ]
```

#### `calculate_account_balance/1`
Calculates balance for a specific account ID.

```elixir
Ysc.Ledgers.calculate_account_balance(account_id)
# => %Money{amount: 1234, currency: :USD}
```

### 2. Balance Check Worker

**File:** `lib/ysc/ledgers/balance_check_worker.ex`

#### Scheduled Job
Runs automatically at midnight UTC via Oban cron.

```elixir
# Configured in config/config.exs
{"0 0 * * *", Ysc.Ledgers.BalanceCheckWorker}
```

#### Manual Execution
Can be triggered manually for testing or investigation:

```elixir
# Via IEx or scripts
Ysc.Ledgers.BalanceCheckWorker.check_balance_now()
```

#### On-Demand via Oban
```elixir
# Queue a job immediately
%{}
|> Ysc.Ledgers.BalanceCheckWorker.new()
|> Oban.insert()
```

---

## Alert Details

When an imbalance is detected, the system generates a comprehensive alert:

### Alert Contents

1. **Summary Information**
   - Total difference amount
   - Number of accounts affected
   - Timestamp of detection

2. **Breakdown by Account Type**
   - Asset accounts: count and total
   - Liability accounts: count and total
   - Revenue accounts: count and total
   - Expense accounts: count and total

3. **Top 5 Imbalanced Accounts**
   - Sorted by absolute value
   - Account name and balance shown

4. **Investigation Commands**
   - Ready-to-run Elixir commands
   - Helpful for immediate troubleshooting

### Example Alert

```
🚨 CRITICAL: Ledger Imbalance Detected

**Total Difference:** $100.00 USD
**Total Accounts Affected:** 12
**Timestamp:** 2024-11-20T00:00:05Z

**Breakdown by Account Type:**
asset: 3 accounts, total: $1,500.00 USD
liability: 2 accounts, total: -$800.00 USD
revenue: 5 accounts, total: -$12,000.00 USD
expense: 2 accounts, total: $11,200.00 USD

**Top 5 Accounts by Value:**
  stripe_account: $1,200.00 USD
  membership_revenue: -$10,500.00 USD
  stripe_fees: $8,900.00 USD
  refund_expense: $2,300.00 USD
  cash: $300.00 USD

**Action Required:**
1. Review recent transactions in the ledger
2. Check for failed payment/refund processing
3. Investigate any manual ledger entries
4. Run: `Ysc.Ledgers.get_account_balances()` for full details

**Investigation Commands:**
```elixir
# Get full account breakdown
Ysc.Ledgers.get_account_balances()

# Check specific account
Ysc.Ledgers.calculate_account_balance(account_id)

# Get recent ledger entries
Ysc.Ledgers.get_recent_payments(start_date, end_date)
```
```

---

## Configuration

### Cron Schedule

**File:** `config/config.exs`

```elixir
config :ysc, Oban,
  repo: Ysc.Repo,
  notifier: Oban.Notifiers.PG,
  queues: [
    default: 10,
    media: 5,
    exports: 3,
    mailers: 20,
    maintenance: 2  # New queue for system health tasks
  ],
  log: false,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 5},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", YscWeb.Workers.FileExportCleanUp},
       {"*/30 * * * *", Ysc.PropertyOutages.OutageScraperWorker},
       {"*/5 * * * *", Ysc.Bookings.HoldExpiryWorker},
       {"*/5 * * * *", Ysc.Tickets.TimeoutWorker},
       {"0 2 * * *", YscWeb.Workers.ImageReprocessor},
       {"0 0 * * *", Ysc.Ledgers.BalanceCheckWorker}  # Midnight UTC
     ]}
  ]
```

### Changing the Schedule

Cron syntax: `minute hour day month weekday`

**Examples:**
```elixir
# Every 6 hours
{"0 */6 * * *", Ysc.Ledgers.BalanceCheckWorker}

# Twice daily (midnight and noon UTC)
{"0 0,12 * * *", Ysc.Ledgers.BalanceCheckWorker}

# Every hour
{"0 * * * *", Ysc.Ledgers.BalanceCheckWorker}

# Weekly on Sundays at 1 AM
{"0 1 * * 0", Ysc.Ledgers.BalanceCheckWorker}
```

---

## Integration with Alerting Systems

The worker includes a placeholder for integrating with external alerting systems. Update the `send_imbalance_alert/1` function in `balance_check_worker.ex`:

### Slack Integration

```elixir
defp send_imbalance_alert(details) do
  # ... existing code ...

  # Send to Slack
  webhook_url = System.get_env("SLACK_WEBHOOK_URL")

  HTTPoison.post(webhook_url, Jason.encode!(%{
    text: "🚨 Ledger Imbalance Detected",
    blocks: [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: alert_message
        }
      }
    ]
  }), [{"Content-Type", "application/json"}])
end
```

### PagerDuty Integration

```elixir
defp send_imbalance_alert(details) do
  # ... existing code ...

  # Send to PagerDuty
  PagerDuty.create_incident(%{
    title: "Ledger Imbalance Detected",
    severity: "critical",
    description: alert_message,
    details: %{
      difference: Money.to_string!(details.difference),
      account_count: details.total_accounts
    }
  })
end
```

### Email Integration

```elixir
defp send_imbalance_alert(details) do
  # ... existing code ...

  # Send email to finance team
  YscWeb.Emails.send_ledger_imbalance_alert(
    to: "finance@example.com",
    subject: "🚨 CRITICAL: Ledger Imbalance Detected",
    body: alert_message
  )
end
```

### Sentry Integration

```elixir
defp send_imbalance_alert(details) do
  # ... existing code ...

  # Capture in Sentry
  Sentry.capture_message(
    "Ledger imbalance detected",
    level: :error,
    extra: %{
      difference: Money.to_string!(details.difference),
      account_count: details.total_accounts,
      accounts_by_type: details.accounts_by_type
    }
  )
end
```

---

## Investigation Workflow

When an alert is triggered, follow this workflow:

### 1. Assess the Situation

```elixir
# Get overall status
Ysc.Ledgers.get_ledger_imbalance_details()

# Get all account balances
balances = Ysc.Ledgers.get_account_balances()

# Check total imbalance
{:error, {:imbalanced, difference, _}} = Ysc.Ledgers.verify_ledger_balance()
Money.to_string!(difference)  # How much is off?
```

### 2. Identify Problem Accounts

```elixir
# Look at accounts with largest balances
Ysc.Ledgers.get_account_balances()
|> Enum.take(10)

# Check specific account
account_id = "..."
Ysc.Ledgers.calculate_account_balance(account_id)

# Get entries for that account
entries = from(e in Ysc.Ledgers.LedgerEntry,
  where: e.account_id == ^account_id,
  order_by: [desc: e.inserted_at],
  limit: 50,
  preload: [:payment]
) |> Ysc.Repo.all()
```

### 3. Check Recent Activity

```elixir
# Get recent payments
today = DateTime.utc_now()
yesterday = DateTime.add(today, -1, :day)
Ysc.Ledgers.get_recent_payments(yesterday, today)

# Check for failed transactions
failed = from(t in Ysc.Ledgers.LedgerTransaction,
  where: t.status == "failed",
  where: t.inserted_at > ^yesterday
) |> Ysc.Repo.all()

# Check for incomplete transactions
incomplete = from(t in Ysc.Ledgers.LedgerTransaction,
  where: t.status == "pending",
  where: t.inserted_at < ^yesterday
) |> Ysc.Repo.all()
```

### 4. Common Causes

- **Failed webhook processing** - Payment recorded but entries not created
- **Incomplete refunds** - Refund initiated but not completed
- **Manual ledger entries** - Direct database modifications
- **Race conditions** - Concurrent transaction processing
- **Migration issues** - Data migration errors

### 5. Resolution

Once the cause is identified:

1. **Document the issue** in your incident tracking system
2. **Fix the root cause** (code bug, data issue, etc.)
3. **Create correcting entries** if needed (with approval)
4. **Verify the fix** by running balance check again
5. **Update procedures** to prevent recurrence

---

## Monitoring & Metrics

### Key Metrics to Track

1. **Balance Check Status**
   - Daily success/failure rate
   - Time to complete checks
   - Imbalance frequency

2. **Imbalance Severity**
   - Total difference amount
   - Number of accounts affected
   - Duration of imbalance

3. **Resolution Time**
   - Time from detection to resolution
   - Number of iterations to fix

### Recommended Dashboards

**Daily Health Dashboard:**
```
- Last balance check: [timestamp]
- Status: ✓ Balanced / ❌ Imbalanced
- Accounts monitored: [count]
- Last issue: [timestamp] ([resolved/pending])
```

**Investigation Dashboard:**
```
- Current imbalance: [$amount]
- Affected accounts: [count]
- Top imbalanced accounts: [list]
- Recent transactions: [chart]
```

---

## Testing

### Test in Development

```elixir
# Create a test imbalance (don't do this in production!)
account = Ysc.Repo.get_by!(Ysc.Ledgers.LedgerAccount, name: "cash")

# Create orphan entry (will cause imbalance)
%Ysc.Ledgers.LedgerEntry{}
|> Ysc.Ledgers.LedgerEntry.changeset(%{
  account_id: account.id,
  amount: Money.new(100, :USD),
  description: "Test imbalance"
})
|> Ysc.Repo.insert!()

# Run the check
Ysc.Ledgers.BalanceCheckWorker.check_balance_now()
# Should detect the $100 imbalance

# Clean up
Ysc.Repo.delete_all(Ysc.Ledgers.LedgerEntry,
  where: [description: "Test imbalance"])
```

### Test Scheduling

```elixir
# Check if job is scheduled
Oban.check_queue(:maintenance)

# See scheduled jobs
from(j in Oban.Job,
  where: j.worker == "Ysc.Ledgers.BalanceCheckWorker",
  where: j.state in ["scheduled", "available"],
  order_by: [desc: j.scheduled_at],
  limit: 5
) |> Ysc.Repo.all()
```

---

## Maintenance

### Regular Tasks

**Daily:**
- Review balance check results
- Investigate any alerts

**Weekly:**
- Review balance check execution times
- Check for any pattern in imbalances

**Monthly:**
- Audit the monitoring system itself
- Update alert thresholds if needed
- Review and improve investigation runbook

### Troubleshooting

**Problem:** Balance check not running
```elixir
# Check Oban status
Oban.check_queue(:maintenance)

# Check cron configuration
Application.get_env(:ysc, Oban)

# Manually trigger
Ysc.Ledgers.BalanceCheckWorker.check_balance_now()
```

**Problem:** False positives (balance shows imbalanced but isn't)
```elixir
# Verify calculation
Ysc.Ledgers.verify_ledger_balance()

# Check for rounding issues
entries = Ysc.Repo.all(Ysc.Ledgers.LedgerEntry)
totals = Enum.reduce(entries, Decimal.new(0), fn entry, acc ->
  Decimal.add(acc, entry.amount.amount)
end)
```

**Problem:** Alerts not being received
- Check log aggregation system
- Verify error logging configuration
- Test external alert integrations

---

## Summary

✅ **Automated Monitoring** - Nightly checks at midnight UTC
✅ **Detailed Diagnostics** - Account-level imbalance detection
✅ **Comprehensive Alerts** - Rich information for investigation
✅ **Easy Investigation** - Built-in commands and workflow
✅ **Production Ready** - Scheduled, tested, and documented

The ledger balance monitoring system provides peace of mind that your financial data integrity is continuously verified with detailed diagnostics when issues arise.

---

## Related Documentation

- `WEBHOOK_SECURITY_IMPROVEMENTS.md` - Webhook replay protection and balance verification
- `STRIPE_WEBHOOK_FIXES_IMPLEMENTED_V2.md` - Refund entity implementation
- `LEDGER_SYSTEM_README.md` - Overall ledger system documentation

**Last Updated:** November 20, 2024

