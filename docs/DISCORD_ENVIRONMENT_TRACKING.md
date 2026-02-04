# Discord Environment Tracking

## Overview

All Discord alerts automatically include the **environment name** in their footer. This critical feature helps teams immediately identify which environment (dev, staging, production) is sending alerts, preventing confusion and ensuring proper incident response.

## Implementation Date
November 20, 2024

## How It Works

### Environment Detection

The system determines the environment in this order:

1. **`APP_ENV` environment variable** (if set)
   ```bash
   export APP_ENV="production"
   ```

2. **`config_env()` from runtime.exs** (default behavior)
   - Returns `:dev`, `:test`, or `:prod` based on Elixir's config environment

3. **Fallback to "UNKNOWN"** (if neither is available)

### Footer Format

Every Discord alert footer follows this format:

```
YSC Financial System | ENV: [ENVIRONMENT]
```

If a custom footer is provided, it's appended:

```
YSC Financial System | ENV: [ENVIRONMENT] | [Custom Footer]
```

### Examples

**Development Environment:**
```
YSC Financial System | ENV: DEV
```

**Production Environment:**
```
YSC Financial System | ENV: PRODUCTION
```

**With Custom Footer:**
```
YSC Financial System | ENV: PRODUCTION | Duration: 1234ms
```

**Staging Environment (custom):**
```bash
export APP_ENV="staging"
```
```
YSC Financial System | ENV: STAGING
```

## Configuration

### Runtime Configuration

In `config/runtime.exs`:

```elixir
config :ysc,
  environment: System.get_env("APP_ENV") || to_string(config_env())
```

### Discord Module

The Discord alert module automatically reads this configuration:

```elixir
defp get_environment do
  # Try to get environment from runtime config first
  config_env = Application.get_env(:ysc, :environment)

  # Fallback to Mix.env() if available
  env = if config_env do
    config_env
  else
    if Code.ensure_loaded?(Mix) do
      Mix.env()
    else
      :unknown
    end
  end

  # Format environment name (uppercase)
  env
  |> to_string()
  |> String.upcase()
end
```

## Setting Custom Environment Names

### Development

```bash
export APP_ENV="dev"
# or
export APP_ENV="development"
```

### Staging

```bash
export APP_ENV="staging"
```

### Production

```bash
export APP_ENV="production"
# or
export APP_ENV="prod"
```

### Custom Environments

You can use any custom name:

```bash
export APP_ENV="qa"
export APP_ENV="uat"
export APP_ENV="demo"
```

## Usage Examples

### Automatic in All Alerts

**Simple Alert:**
```elixir
Ysc.Alerts.Discord.send_critical("Ledger imbalance detected!")
```

**Result:**
```
🚨 CRITICAL ALERT
Ledger imbalance detected!

Footer: YSC Financial System | ENV: PRODUCTION
```

**Alert with Custom Footer:**
```elixir
Ysc.Alerts.Discord.send_alert(
  title: "Payment Processing",
  description: "Processing completed",
  footer: "Batch ID: 12345"
)
```

**Result:**
```
Payment Processing
Processing completed

Footer: YSC Financial System | ENV: PRODUCTION | Batch ID: 12345
```

### Reconciliation Reports

Reconciliation reports automatically include environment:

```elixir
Discord.send_reconciliation_report(report, :success)
```

**Result:**
```
✅ Reconciliation Passed
Financial reconciliation completed

Overall Status: ✅ PASS
Duration: 1234ms
...

Footer: YSC Financial System | ENV: PRODUCTION | Duration: 1234ms
```

## Benefits

### 1. **Environment Identification**
Instantly know which environment sent the alert without checking logs or context.

### 2. **Prevent Confusion**
Avoid mistaking dev alerts for production incidents or vice versa.

### 3. **Proper Incident Response**
Team members can prioritize correctly based on environment severity.

### 4. **Audit Trail**
Environment information is permanently recorded in Discord message history.

### 5. **Multi-Environment Monitoring**
Monitor multiple environments in the same Discord channel with clear distinction.

## Best Practices

### 1. Set APP_ENV in Production

Always explicitly set `APP_ENV` in production deployments:

```bash
# In your deployment configuration
APP_ENV=production
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
```

### 2. Use Different Channels for Different Environments

**Recommended Setup:**
- **#alerts-production** - Production alerts only
- **#alerts-staging** - Staging alerts only
- **#alerts-dev** - Development alerts (optional)

Each channel uses a different `DISCORD_WEBHOOK_URL`.

### 3. Color Coding by Environment

Consider using different alert colors or emojis based on environment in critical workflows:

```elixir
def send_environment_aware_alert(message, opts \\ []) do
  env = get_environment()

  emoji = case env do
    "PRODUCTION" -> "🔴"
    "STAGING" -> "🟡"
    "DEV" -> "🔵"
    _ -> "⚪"
  end

  Ysc.Alerts.Discord.send_alert([
    title: "#{emoji} #{opts[:title]}",
    description: message
  ] ++ opts)
end
```

### 4. Monitor Environment Variable

Verify environment is set correctly:

```elixir
# In IEx
Application.get_env(:ysc, :environment)
# => "production"
```

### 5. Include in Deployment Checklist

**Deployment Checklist:**
- [ ] Set `APP_ENV` environment variable
- [ ] Set `DISCORD_WEBHOOK_URL` for correct channel
- [ ] Verify environment shown in test alert
- [ ] Confirm alerts route to correct Discord channel

## Testing

### Test Environment Detection

```elixir
# In IEx
Application.get_env(:ysc, :environment)
```

### Test Alert with Environment

```elixir
Ysc.Alerts.Discord.send_info("Test alert - verifying environment")
```

Check Discord message footer shows correct environment.

### Verify Different Environments

**Development:**
```bash
APP_ENV=dev iex -S mix
> Ysc.Alerts.Discord.send_info("Dev test")
```

**Staging:**
```bash
APP_ENV=staging iex -S mix
> Ysc.Alerts.Discord.send_info("Staging test")
```

**Production:**
```bash
APP_ENV=production iex -S mix
> Ysc.Alerts.Discord.send_info("Production test")
```

## Troubleshooting

### Environment Shows as "UNKNOWN"

**Cause:** Neither `APP_ENV` nor `config_env()` is available.

**Solution:**
```bash
export APP_ENV="production"
```

### Environment Shows Unexpected Value

**Check configuration:**
```elixir
# In IEx
Application.get_env(:ysc, :environment)  # Runtime config
Mix.env()  # Mix environment
```

**Verify environment variable:**
```bash
echo $APP_ENV
```

### Environment Not Updating

**Restart application** after changing `APP_ENV`:
```bash
export APP_ENV="production"
mix phx.server  # Restart needed
```

## Related Documentation

- [Discord Alerts Guide](DISCORD_ALERTS.md) - Full Discord integration
- [Reconciliation System](RECONCILIATION_SYSTEM.md) - Automated checks
- [Ledger Balance Monitoring](LEDGER_BALANCE_MONITORING.md) - Balance verification

## Summary

✅ **All Discord alerts include environment name**
✅ **Automatic detection from APP_ENV or config_env()**
✅ **Clear footer format with environment**
✅ **Custom environment names supported**
✅ **No code changes needed for existing alerts**

---

**Implementation Date**: November 20, 2024
**Status**: Active ✅
**Maintained By**: Engineering Team

