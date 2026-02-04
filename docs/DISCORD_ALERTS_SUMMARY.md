# Discord Alerts - Implementation Summary

## Date
November 20, 2024

## Overview

Implemented a comprehensive Discord alerting system for sending financial notifications, reconciliation reports, and critical alerts to Discord channels via webhooks.

## Components Created

### 1. Discord Alerts Module
**File**: `lib/ysc/alerts/discord.ex`

Full-featured Discord webhook integration with:
- Multiple alert levels (critical, error, warning, success, info)
- Rich embed formatting
- Custom fields and colors
- Automatic reconciliation report formatting
- Specialized financial alert functions

### 2. Configuration
**File**: `config/config.exs`

Added Discord configuration:
```elixir
config :ysc, Ysc.Alerts.Discord,
  webhook_url: System.get_env("DISCORD_WEBHOOK_URL"),
  enabled: true
```

### 3. Integration with Reconciliation Worker
**File**: `lib/ysc/ledgers/reconciliation_worker.ex`

Updated to automatically send Discord alerts:
- Success notifications when reconciliation passes
- Error notifications when discrepancies found
- Ledger imbalance alerts
- Payment discrepancy alerts

### 4. Documentation
**File**: `docs/DISCORD_ALERTS.md`

Comprehensive guide covering:
- Setup instructions
- Usage examples
- Alert types and colors
- Troubleshooting
- Best practices
- Security considerations

## Features

### Environment Tracking

**All Discord alerts automatically include the environment name** in their footer. This critical feature helps teams immediately identify which environment is sending the alert, preventing confusion between dev, staging, and production alerts.

**How it works:**
1. Environment is determined from `APP_ENV` environment variable (if set)
2. Falls back to `config_env()` from Elixir's runtime configuration
3. Displays in footer as: `YSC Financial System | ENV: [ENVIRONMENT]`

**Examples:**
- Development: `YSC Financial System | ENV: DEV`
- Staging: `YSC Financial System | ENV: STAGING`
- Production: `YSC Financial System | ENV: PRODUCTION`

Custom footers are appended after the environment:
```
YSC Financial System | ENV: PRODUCTION | Duration: 1234ms
```

### Alert Levels

| Function | Level | Color | Icon | Use Case |
|----------|-------|-------|------|----------|
| `send_critical/2` | Critical | Dark Red | 🚨 | Ledger imbalance, system failures |
| `send_error/2` | Error | Red | ❌ | Payment errors, processing failures |
| `send_warning/2` | Warning | Orange | ⚠️ | High refund rate, suspicious activity |
| `send_success/2` | Success | Green | ✅ | Successful reconciliation, completed tasks |
| `send_info/2` | Info | Blue | ℹ️ | General notifications, status updates |

### Specialized Functions

1. **`send_reconciliation_report/2`**
   - Formats full reconciliation reports
   - Includes all check statuses
   - Shows payment/refund counts
   - Displays entity total matches

2. **`send_ledger_imbalance_alert/2`**
   - Critical alert for ledger imbalances
   - Shows difference amount
   - Includes affected account counts
   - Prompts immediate investigation

3. **`send_payment_discrepancy_alert/3`**
   - Error alert for payment issues
   - Lists specific payment IDs
   - Shows issue descriptions
   - Includes total counts

### Rich Embed Support

Discord embeds support:
- **Titles** - Main heading with optional URL
- **Descriptions** - Detailed message content
- **Fields** - Structured data display (inline or full-width)
- **Colors** - Visual severity indicators
- **Timestamps** - When the event occurred
- **Footers** - Additional context
- **Images** - Thumbnails and full-size images

## Usage Examples

### Basic Alert

```elixir
Ysc.Alerts.Discord.send_critical("Ledger imbalance detected!")
```

### Custom Alert with Fields

```elixir
Ysc.Alerts.Discord.send_alert(
  title: "Payment Discrepancy",
  description: "Found payments without ledger entries",
  color: :error,
  fields: [
    %{name: "Count", value: "5", inline: true},
    %{name: "Amount", value: "$1,234.56", inline: true}
  ],
  timestamp: DateTime.utc_now()
)
```

### Automatic Reconciliation Alerts

The reconciliation worker automatically sends:

**On Success:**
```
✅ Reconciliation Passed
Financial reconciliation completed successfully
All checks passed ✅
```

**On Failure:**
```
❌ Reconciliation Failed
Found 5 payment discrepancies
Ledger imbalance: $1,000.00
Requires immediate investigation
```

## Setup

### 1. Create Discord Webhook

1. Open Discord server settings
2. Navigate to Integrations → Webhooks
3. Create new webhook
4. Copy webhook URL

### 2. Configure Environment

```bash
export DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN"
export APP_ENV="production"  # Optional: defaults to config_env()
```

**Environment Tracking**: All alerts automatically include the environment name in their footer (e.g., "YSC Financial System | ENV: PRODUCTION"). This helps distinguish between dev, staging, and production alerts.

### 3. Test

```elixir
# In IEx
Ysc.Alerts.Discord.send_info("Test alert from IEx")
```

## Integration Flow

```
Reconciliation Worker
       ↓
  Run Checks
       ↓
    Success? ────────────────→ Send Success Notification
       │                              ↓
       │                         Discord: ✅ Passed
       │
       ↓ (Failures)
Send Error Notifications
       ↓
1. Main Report (Overall Status)
2. Ledger Imbalance Alert (if applicable)
3. Payment Discrepancy Alert (if applicable)
       ↓
Discord: ❌ Failed with details
```

## HTTP Client

Uses **Finch** for HTTP requests:
- Reliable and performant
- Already part of Phoenix stack
- Connection pooling built-in
- Proper error handling

## Security

### Protected Webhook URL
- Stored in environment variable
- Never committed to git
- Can be disabled via config

### Sensitive Data
- No passwords, tokens, or keys in alerts
- Generic descriptions for public channels
- User information redacted when needed

## Status

✅ **Implementation Complete**
✅ **Compilation Successful**
✅ **Integrated with Reconciliation**
✅ **Documentation Created**
✅ **Ready for Use**

## Testing Checklist

- [ ] Create Discord webhook
- [ ] Set `DISCORD_WEBHOOK_URL` environment variable
- [ ] Send test alert from IEx
- [ ] Run manual reconciliation to test alerts
- [ ] Verify alerts appear in Discord channel
- [ ] Test different alert levels
- [ ] Confirm formatting is correct

## Next Steps

1. **Create Webhook**: Set up Discord webhook for alerts channel
2. **Configure Environment**: Add webhook URL to environment
3. **Test Integration**: Send test alerts
4. **Monitor**: Watch for automatic reconciliation alerts
5. **Refine**: Adjust alert frequency/content as needed
6. **Expand**: Add more specialized alerts as needed

## Benefits

### Immediate Notification
- Real-time alerts when issues occur
- No need to check logs manually
- Team visibility into system status

### Rich Context
- Detailed information in alerts
- Structured data with fields
- Visual severity indicators

### Team Communication
- Centralized alert channel
- Visible to entire team
- Easy to discuss and respond

### Historical Record
- Searchable alert history in Discord
- Audit trail of system events
- Pattern identification over time

## Example Alert Formats

### Success Alert

```
╔═══════════════════════════════════════════
║ ✅ Reconciliation Passed
╠═══════════════════════════════════════════
║ Overall Status: ✅ PASS
║ Duration: 1234ms
║
║ Payments: 150 | Discrepancies: 0 | Match: ✅
║ Refunds: 5 | Discrepancies: 0 | Match: ✅
║ Ledger Balance: ✅
║
║ Footer: YSC Financial System | ENV: PRODUCTION | Duration: 1234ms
╚═══════════════════════════════════════════
```

### Error Alert

```
╔═══════════════════════════════════════════
║ ❌ Reconciliation Failed
╠═══════════════════════════════════════════
║ Overall Status: ❌ FAIL
║ Duration: 1456ms
║
║ Payments: 150 | Discrepancies: 5 | Match: ❌
║ Ledger Balance: ❌ (Difference: $1,000.00)
║
║ Action Required: Investigate immediately
║ Footer: YSC Financial System | ENV: PRODUCTION | Duration: 1456ms
╚═══════════════════════════════════════════
```

## Files Created/Modified

### Created
1. `lib/ysc/alerts/discord.ex` (~470 lines)
2. `docs/DISCORD_ALERTS.md` (Comprehensive guide)
3. `docs/DISCORD_ALERTS_SUMMARY.md` (This file)

### Modified
1. `config/config.exs` (Added Discord configuration)
2. `config/runtime.exs` (Added environment configuration for alerts)
3. `lib/ysc/ledgers/reconciliation_worker.ex` (Integrated Discord alerts)

## Configuration

```elixir
# config/config.exs
config :ysc, Ysc.Alerts.Discord,
  webhook_url: System.get_env("DISCORD_WEBHOOK_URL"),
  enabled: true

# config/runtime.exs
config :ysc,
  environment: System.get_env("APP_ENV") || to_string(config_env())
```

**Environment Variables:**
- `DISCORD_WEBHOOK_URL` - Discord webhook endpoint (required)
- `APP_ENV` - Environment name for alerts (optional, defaults to config_env())

## Related Documentation

- [Discord Alerts Guide](DISCORD_ALERTS.md) - Full usage documentation
- [Reconciliation System](RECONCILIATION_SYSTEM.md) - Financial reconciliation
- [Ledger Balance Monitoring](LEDGER_BALANCE_MONITORING.md) - Balance checks

---

**Implementation Date**: November 20, 2024
**Status**: Complete ✅
**Ready for Deployment**: Yes
**Maintained By**: Engineering Team

