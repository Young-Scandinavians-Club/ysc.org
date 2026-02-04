# Newsletter Testing Documentation - Summary

## Overview

Added comprehensive documentation about newsletter testing with Keila across all developer guides. This helps developers understand how to test newsletter subscriptions, email campaigns, and the integration between the YSC application and Keila.

## What is Keila?

Keila is an open-source email marketing and newsletter platform that the YSC application uses for:
- Managing newsletter subscriptions
- Storing subscriber lists
- Creating and sending email campaigns
- Tracking subscription status

## Local Development Setup

In local development, the following containers work together:

```
YSC App (Port 4000)
    ↓
Oban Worker (KeilaSubscriber)
    ↓
Keila API (Port 4001)
    ↓
Keila Database (PostgreSQL)
    ↓
Mailpit SMTP (Port 1025)
    ↓
Mailpit UI (Port 8025) - View all emails
```

**Key Points:**
- Keila runs in Docker alongside PostgreSQL
- Pre-configured with API credentials for local testing
- All emails are caught by Mailpit (never sent to real addresses)
- Subscriptions are processed asynchronously via Oban workers

## Documentation Added

### 1. README.md - "Testing Newsletters with Keila" Section

**Location**: After "Useful Development Tools" section

**Content**:
- What is Keila and what it does
- How to access Keila (http://localhost:4001)
- How newsletter integration works (architecture diagram)
- Step-by-step testing instructions:
  - Subscribe via homepage
  - Subscribe via user settings
  - Verify in Keila
  - Check emails in Mailpit
- Testing features in IEx shell
- Configuration details (no setup needed)
- Sending test newsletters
- Common testing scenarios
- Troubleshooting Keila issues
- Important notes about async processing

### 2. QUICKREF.md - Newsletter Testing Section

**Location**: After "Git Workflow" section

**Content**:
- Quick test flow (4 steps)
- Testing in IEx examples
- Monitoring newsletter jobs
- Sending test newsletters
- Note about email catching in development

**Updated**:
- Useful URLs section - Enhanced Keila and Mailpit descriptions

### 3. DEVELOPMENT_ARCHITECTURE.md - Multiple Enhancements

**Added**:

#### Newsletter Subscription Flow Diagram
Shows complete flow from user subscription to email delivery

#### External Services Section
Enhanced to explain Keila's role and how it works

#### Development Services Section
Added section explaining Docker services including Mailpit

#### Testing Newsletters Section
Complete guide under "Common Development Tasks":
- How to subscribe test emails
- Verifying subscriptions
- Creating test campaigns
- Checking subscription status
- Key files for newsletter integration

#### Updated Codebase Structure
Added Keila-related files:
- `lib/ysc/keila/` directory
- `lib/ysc_web/workers/keila_subscriber.ex`

## Key Testing Workflows

### Quick Test (For Daily Development)

```bash
# 1. Start dev environment
make dev

# 2. Subscribe via homepage
# Visit http://localhost:4000
# Enter email in newsletter form

# 3. View in Keila
open http://localhost:4001

# 4. Check email in Mailpit
open http://localhost:8025
```

### IEx Testing (For Debugging)

```elixir
# Open shell
make shell

# Subscribe
Ysc.Keila.subscribe_email("test@example.com")
# => :ok

# Check status
Ysc.Keila.get_subscription_status("test@example.com")
# => {:ok, :active}

# Unsubscribe
Ysc.Keila.unsubscribe_email("test@example.com")
# => :ok
```

### Campaign Testing (For Marketing Features)

1. Open Keila: http://localhost:4001
2. Go to Campaigns → New Campaign
3. Design newsletter
4. Send to test contacts
5. View in Mailpit: http://localhost:8025

## Important Configuration

### Pre-configured in `config/dev.exs`

```elixir
config :ysc, :keila,
  api_url: "http://localhost:4001",
  api_key: "h4ANq5tAf4fLTW1HpjSc1nszdCpcKOxBsLbnxe8-XDs",
  project_id: "np_weLJnLY5",
  form_id: "nfrm_BzLMaLXv"
```

**Developers don't need to change these values** - they're automatically set for local development.

### Test Environment

In tests, a stub client is used:

```elixir
# config/test.exs
config :ysc, :keila_client, Ysc.Keila.ClientStub
```

This prevents real API calls during testing.

## Architecture Details

### Async Processing

Newsletter subscriptions use Oban for background processing:

1. User action (subscribe/unsubscribe)
2. Job enqueued in PostgreSQL
3. `YscWeb.Workers.KeilaSubscriber` processes job
4. Keila API called
5. Response logged

**Benefits**:
- Non-blocking UI
- Automatic retries on failure
- Job monitoring in Oban dashboard

### Integration Points

**Homepage (`lib/ysc_web/live/home_live.ex`):**
- Newsletter subscription form
- Direct Keila API call
- Immediate feedback to user

**User Settings (`lib/ysc_web/live/user_settings_live.ex`):**
- Newsletter preference checkbox
- Async sync via Oban worker
- Updates on preference change

**Account Creation (`lib/ysc/accounts.ex`):**
- Auto-subscribe based on preference
- Async processing
- No blocking during registration

### Key Files

```
lib/
├── ysc/
│   ├── keila.ex                      # Main context
│   └── keila/
│       ├── behaviour.ex              # API behaviour definition
│       └── client.ex                 # Keila API implementation
│
├── ysc_web/
│   └── workers/
│       └── keila_subscriber.ex       # Oban worker
│
test/
├── ysc/
│   ├── keila_test.exs                # Context tests
│   └── keila/
│       └── client_test.exs           # API client tests
│
└── ysc_web/
    └── workers/
        └── keila_subscriber_test.exs # Worker tests

test/support/
└── stubs/
    └── keila_client_stub.ex          # Test stub
```

## Troubleshooting

### Common Issues

**Keila container not running:**
```bash
docker-compose -f etc/docker/docker-compose.yml ps keila
docker-compose -f etc/docker/docker-compose.yml restart keila
```

**Subscription not working:**
- Check Oban dashboard: http://localhost:4000/admin/settings
- Look for `KeilaSubscriber` jobs
- Check logs for errors

**Emails not appearing:**
```bash
# Restart Mailpit
docker-compose -f etc/docker/docker-compose.yml restart mailpit

# Open UI
open http://localhost:8025
```

## Benefits of Documentation

1. **Clear understanding** - Developers know exactly how newsletters work
2. **Easy testing** - Step-by-step instructions for common scenarios
3. **Quick debugging** - Troubleshooting section helps solve issues fast
4. **Architecture clarity** - Diagrams show how everything connects
5. **Self-service** - Developers can test newsletters without guidance

## Testing in CI

Keila tests use a stub client to avoid external dependencies:

```elixir
# Tests mock the Keila API
Application.put_env(:ysc, :keila_client, Ysc.KeilaMock)

expect(Ysc.KeilaMock, :subscribe_email, fn email, _opts ->
  :ok
end)
```

This ensures:
- Fast test execution
- No external API dependencies
- Predictable test behavior
- Easy to test error cases

## Production Considerations

In production, environment variables must be set:

```bash
KEILA_API_URL=https://keila.production.example.com
KEILA_API_KEY=production_api_key
KEILA_PROJECT_ID=production_project_id
KEILA_FORM_ID=production_form_id
```

These are configured in `config/config.exs` and read from environment variables.

## Future Enhancements

Potential improvements to consider:

- Automated newsletter preview screenshots
- Subscription analytics and metrics
- A/B testing for newsletter campaigns
- Subscriber segmentation documentation
- Email template best practices
- GDPR compliance checklist

## Summary

Newsletter testing documentation is now:
✅ Comprehensive across all guides
✅ Easy to follow with step-by-step instructions
✅ Includes visual diagrams and flows
✅ Covers common scenarios and troubleshooting
✅ Self-contained (developers can test independently)
✅ Integrated with existing developer documentation

---

**Created**: 2026-02-04  
**Purpose**: Help developers understand and test newsletter functionality with Keila  
**Status**: Complete ✅
