# Discord Alerts Integration

## Overview

The Discord Alerts module (`Ysc.Alerts.Discord`) provides a comprehensive alerting system for sending financial notifications, reconciliation reports, and critical alerts to Discord channels via webhooks.

## Setup

### 1. Create a Discord Webhook

1. Open your Discord server
2. Go to Server Settings → Integrations → Webhooks
3. Click "New Webhook"
4. Give it a name (e.g., "YSC Financial Alerts")
5. Select the channel where alerts should be posted
6. Copy the webhook URL

### 2. Configure the Application

Add the webhook URL and optional environment name to your environment:

```bash
export DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN"
export APP_ENV="production"  # Optional: defaults to config_env() (dev, test, prod)
```

Or add it to your `.env` file:

```
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN
APP_ENV=production
```

**Environment Name**: All Discord alerts automatically include the environment name in the footer (e.g., "YSC Financial System | ENV: PRODUCTION"). This helps distinguish which environment is sending the alert. The environment is determined by:
1. `APP_ENV` environment variable (if set)
2. `config_env()` from runtime.exs (dev, test, prod)
3. Falls back to "UNKNOWN" if neither is available

### 3. Enable Discord Alerts

Discord alerts are enabled by default in `config/config.exs`:

```elixir
config :ysc, Ysc.Alerts.Discord,
  webhook_url: System.get_env("DISCORD_WEBHOOK_URL"),
  enabled: true
```

To disable alerts temporarily, set `enabled: false`.

## Usage

### Basic Alerts

#### Send a Critical Alert

```elixir
Ysc.Alerts.Discord.send_critical("Ledger imbalance detected!")
```

#### Send an Error Alert

```elixir
Ysc.Alerts.Discord.send_error("Payment processing failed")
```

#### Send a Warning

```elixir
Ysc.Alerts.Discord.send_warning("High number of refunds detected")
```

#### Send a Success Notification

```elixir
Ysc.Alerts.Discord.send_success("Daily reconciliation completed successfully")
```

#### Send an Info Message

```elixir
Ysc.Alerts.Discord.send_info("System maintenance scheduled for tonight")
```

### Custom Alerts with Fields

```elixir
Ysc.Alerts.Discord.send_alert(
  title: "Payment Discrepancy Detected",
  description: "Found payments without corresponding ledger entries",
  color: :error,
  fields: [
    %{name: "Total Discrepancies", value: "5", inline: true},
    %{name: "Total Amount", value: "$1,234.56", inline: true},
    %{name: "Status", value: "❌ Requires Investigation", inline: false}
  ],
  footer: "YSC Financial System",
  timestamp: DateTime.utc_now()
)
```

### Reconciliation Reports

The reconciliation worker automatically sends Discord alerts when discrepancies are detected:

```elixir
# Success notification (sent automatically on clean reconciliation)
Discord.send_reconciliation_report(report, :success)

# Error notification (sent automatically when discrepancies found)
Discord.send_reconciliation_report(report, :error)
```

### Ledger Imbalance Alerts

```elixir
difference = Money.new(1000, :USD)
Discord.send_ledger_imbalance_alert(difference)

# With details
Discord.send_ledger_imbalance_alert(difference, details)
```

### Payment Discrepancy Alerts

```elixir
Discord.send_payment_discrepancy_alert(
  discrepancies_count,
  total_payments,
  discrepancy_details
)
```

## Alert Types and Colors

The module supports different alert levels with corresponding colors:

| Alert Type | Color | Emoji | Use Case |
|-----------|-------|-------|----------|
| **Critical** | Dark Red | 🚨 | Ledger imbalance, system failures |
| **Error** | Red | ❌ | Payment errors, processing failures |
| **Warning** | Orange | ⚠️ | High refund rate, suspicious activity |
| **Success** | Green | ✅ | Successful reconciliation, tasks completed |
| **Info** | Blue | ℹ️ | General notifications, status updates |

## Discord Embed Structure

Discord alerts use rich embeds with the following features:

### Basic Structure

```json
{
  "title": "Alert Title",
  "description": "Main message content",
  "color": 16711680,
  "fields": [
    {
      "name": "Field Name",
      "value": "Field Value",
      "inline": true
    }
  ],
  "footer": {
    "text": "Footer text"
  },
  "timestamp": "2024-11-20T01:00:00.000Z"
}
```

### Example: Reconciliation Report

When reconciliation passes:

```
╔══════════════════════════════════════════
║ ✅ Reconciliation Passed
╠══════════════════════════════════════════
║ Financial reconciliation completed at 2024-11-20 01:00:00Z
║
║ Overall Status: ✅ PASS
║ Duration: 1234ms
║
║ Payments: Total: 150 | Discrepancies: 0 | Match: ✅
║ Refunds: Total: 5 | Discrepancies: 0 | Match: ✅
║ Ledger Balance: ✅
║ Entity Totals:
║   Memberships: ✅
║   Bookings: ✅
║   Events: ✅
║
║ Footer: YSC Financial System | ENV: PRODUCTION | Duration: 1234ms
╚══════════════════════════════════════════
```

When reconciliation fails:

```
╔══════════════════════════════════════════
║ ❌ Reconciliation Failed
╠══════════════════════════════════════════
║ Financial reconciliation completed at 2024-11-20 01:00:00Z
║
║ Overall Status: ❌ FAIL
║ Duration: 1456ms
║
║ Payments: Total: 150 | Discrepancies: 5 | Match: ❌
║ Refunds: Total: 5 | Discrepancies: 0 | Match: ✅
║ Ledger Balance: ❌
║ Entity Totals:
║   Memberships: ✅
║   Bookings: ❌
║   Events: ✅
║
║ Footer: YSC Financial System | ENV: PRODUCTION | Duration: 1456ms
╚══════════════════════════════════════════
```

## Integration with Reconciliation System

The reconciliation worker automatically sends Discord alerts:

### On Success

```elixir
# Sent when reconciliation passes all checks
Discord.send_reconciliation_report(report, :success)
```

### On Failure

Multiple alerts are sent for different types of issues:

1. **Main Report**: Overall reconciliation status
2. **Ledger Imbalance Alert**: If ledger is imbalanced
3. **Payment Discrepancy Alert**: If payment issues found

```elixir
# Main report with error status
Discord.send_reconciliation_report(report, :error)

# Specific ledger imbalance alert
if !report.checks.ledger_balance.balanced do
  Discord.send_ledger_imbalance_alert(
    report.checks.ledger_balance.difference,
    report.checks.ledger_balance.details
  )
end

# Payment discrepancy alert
if report.checks.payments.discrepancies_count > 0 do
  Discord.send_payment_discrepancy_alert(
    report.checks.payments.discrepancies_count,
    report.checks.payments.total_payments,
    report.checks.payments.discrepancies
  )
end
```

## Testing Alerts

### Test Alert Delivery

```elixir
# In IEx
Ysc.Alerts.Discord.send_info("Test alert from IEx")

# Test with fields
Ysc.Alerts.Discord.send_alert(
  title: "Test Alert",
  description: "Testing Discord integration",
  color: :info,
  fields: [
    %{name: "Test Field 1", value: "Value 1", inline: true},
    %{name: "Test Field 2", value: "Value 2", inline: true}
  ]
)
```

### Verify Configuration

```elixir
# Check if Discord is enabled
Application.get_env(:ysc, Ysc.Alerts.Discord)

# Test webhook URL is set
System.get_env("DISCORD_WEBHOOK_URL")
```

## Advanced Usage

### Custom Colors

Use custom hex colors:

```elixir
Ysc.Alerts.Discord.send_alert(
  title: "Custom Color Alert",
  description: "This uses a custom color",
  color: 0xFF6B6B  # Custom hex color
)
```

### Adding Links

```elixir
Ysc.Alerts.Discord.send_alert(
  title: "View Report",
  description: "Click the title to view the full report",
  url: "https://yourapp.com/reports/123",
  color: :info
)
```

### Adding Images

```elixir
Ysc.Alerts.Discord.send_alert(
  title: "Chart Update",
  description: "Daily revenue chart",
  thumbnail_url: "https://yourapp.com/charts/thumb.png",
  image_url: "https://yourapp.com/charts/full.png",
  color: :success
)
```

## Troubleshooting

### Alerts Not Sending

1. **Check webhook URL is set:**
   ```elixir
   System.get_env("DISCORD_WEBHOOK_URL")
   ```

2. **Check alerts are enabled:**
   ```elixir
   Application.get_env(:ysc, Ysc.Alerts.Discord)
   ```

3. **Check logs for errors:**
   ```
   grep "Discord alert" log/dev.log
   ```

4. **Verify webhook URL is valid:**
   - Should start with `https://discord.com/api/webhooks/`
   - Should include both webhook ID and token

### Webhook URL Invalid

Error: `Failed to send Discord alert`

**Solution**: Verify the webhook URL format:
```
https://discord.com/api/webhooks/[WEBHOOK_ID]/[WEBHOOK_TOKEN]
```

### Rate Limiting

Discord webhooks have rate limits:
- 30 requests per minute per webhook
- 5 requests per second

If you hit rate limits, the module will log errors. Consider:
- Batching similar alerts
- Reducing alert frequency
- Using multiple webhooks for different channels

### Message Too Long

Discord has a 2000 character limit for descriptions.

**Solution**: Truncate long messages or split into multiple alerts:

```elixir
# Limit description length
description = String.slice(long_message, 0, 1900) <> "..."

Ysc.Alerts.Discord.send_alert(
  title: "Alert",
  description: description,
  color: :info
)
```

## Security Considerations

### Webhook URL Protection

- **Never commit webhook URLs to git**
- Store in environment variables only
- Rotate webhooks if exposed
- Use different webhooks for different environments

### Sensitive Information

- **Don't include sensitive data** in alerts (passwords, tokens, keys)
- **Redact user information** when possible
- **Use generic descriptions** for public channels

### Access Control

- Limit Discord webhook channel permissions
- Only give view access to necessary team members
- Use separate webhooks for different alert types
- Monitor webhook usage in Discord audit logs

## Best Practices

### 1. Alert Granularity

**Do:**
- Send distinct alerts for different issues
- Use appropriate severity levels
- Include actionable information

**Don't:**
- Spam with too many alerts
- Send the same alert multiple times
- Use critical alerts for non-critical issues

### 2. Message Formatting

**Do:**
- Use fields for structured data
- Keep descriptions concise
- Use emojis for visual scanning
- Include timestamps

**Don't:**
- Write walls of text
- Overuse formatting
- Include debug information in production

### 3. Alert Content

**Do:**
- State the problem clearly
- Include relevant metrics
- Provide investigation steps
- Link to relevant resources

**Don't:**
- Use technical jargon unnecessarily
- Include stack traces (use logs instead)
- Alert on expected behavior

## Examples

### Complete Reconciliation Alert

```elixir
defmodule MyApp.FinanceAlerts do
  alias Ysc.Alerts.Discord

  def send_daily_summary(stats) do
    Discord.send_alert(
      title: "📊 Daily Financial Summary",
      description: "Summary for #{Date.utc_today()}",
      color: :info,
      fields: [
        %{
          name: "Total Revenue",
          value: Money.to_string!(stats.revenue),
          inline: true
        },
        %{
          name: "Total Refunds",
          value: Money.to_string!(stats.refunds),
          inline: true
        },
        %{
          name: "Net Revenue",
          value: Money.to_string!(stats.net),
          inline: true
        },
        %{
          name: "Transactions",
          value: "#{stats.transaction_count}",
          inline: true
        },
        %{
          name: "New Memberships",
          value: "#{stats.new_memberships}",
          inline: true
        },
        %{
          name: "Active Subscriptions",
          value: "#{stats.active_subscriptions}",
          inline: true
        }
      ],
      footer: "Generated at #{DateTime.utc_now()}",
      timestamp: DateTime.utc_now()
    )
    # Note: Footer will automatically be prefixed with "YSC Financial System | ENV: [PRODUCTION]"
    # Final footer: "YSC Financial System | ENV: PRODUCTION | Generated at 2024-11-20 01:00:00Z"
  end
end
```

## Related Documentation

- [Reconciliation System](RECONCILIATION_SYSTEM.md) - Financial reconciliation overview
- [Ledger Balance Monitoring](LEDGER_BALANCE_MONITORING.md) - Balance checking system
- [Stripe Webhooks](STRIPE_WEBHOOK_FIXES_IMPLEMENTED_V2.md) - Payment processing

---

**Last Updated**: November 20, 2024
**Maintained By**: Engineering Team

