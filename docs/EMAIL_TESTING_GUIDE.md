# Email Testing Documentation - Summary

## Overview

Added comprehensive documentation about email testing in development, covering both application emails (via Swoosh) and newsletter emails (via Keila/Mailpit).

## Two Email Systems

The YSC application uses **two different email systems** for different purposes:

### 1. Swoosh Mailbox (Application Emails)

**URL**: http://localhost:4000/dev/mailbox

**Purpose**: View transactional emails sent by the YSC application

**Emails Captured**:
- User registration confirmations
- Password reset emails
- Account notifications
- Membership-related emails
- Event confirmations
- Payment receipts
- Ticket confirmations
- All other app-generated emails

**How it works**:
```
YSC App → Swoosh.Adapters.Local → In-memory storage → /dev/mailbox
```

**Key characteristics**:
- Built into Phoenix via Swoosh
- Emails stored in memory (cleared on restart)
- No external dependencies
- Enabled in development by default
- Accessible at `/dev/mailbox` endpoint

### 2. Mailpit (Newsletter Emails)

**URL**: http://localhost:8025

**Purpose**: Catch newsletter emails sent by Keila

**Emails Captured**:
- Newsletter campaigns
- Newsletter subscription confirmations
- Marketing emails

**How it works**:
```
Keila → Mailpit SMTP (port 1025) → Mailpit UI (port 8025)
```

**Key characteristics**:
- External Docker container
- Separate SMTP server
- Used exclusively by Keila
- Persists across restarts (until container restart)

## Documentation Added

### 1. README.md - "Testing Emails in Development" Section

**Location**: Before "Testing Newsletters with Keila" section

**Content**:
- Introduction to Swoosh email testing
- How to access Swoosh mailbox
- Complete list of email types captured
- Architecture diagram showing email flow
- Step-by-step testing instructions for:
  - User registration emails
  - Password reset emails
  - Event/ticket emails
- Email preview features explanation
- Comparison table: Swoosh Mailbox vs Mailpit
- Why two systems are needed
- Email template testing workflow
- Troubleshooting email testing issues

**Updated**:
- Useful Development Tools section - Added Swoosh mailbox link

### 2. QUICKREF.md - Email Testing Section

**Location**: After "Newsletter Testing" section

**Content**:
- Quick test flow for application emails
- Common email test scenarios
- Email systems comparison table
- Tips for choosing the right tool

**Updated**:
- Useful URLs section - Added Swoosh mailbox entry with description

### 3. DEVELOPMENT_ARCHITECTURE.md - Multiple Enhancements

**Added**:

#### Updated Port Reference Table
Added Swoosh Mailbox entry showing it shares port 4000 with the app

#### Testing Application Emails Section
Complete guide under "Common Development Tasks":
- How to view all sent emails
- Testing registration emails
- Testing password resets
- Testing transactional emails
- Email systems comparison table
- Key email files reference

## Key Information

### Quick Access URLs

```
Application Emails:  http://localhost:4000/dev/mailbox
Newsletter Emails:   http://localhost:8025
```

### When to Use Each

**Use Swoosh Mailbox when testing:**
- User registration/login flows
- Password reset functionality
- Account notification emails
- Payment confirmations
- Ticket confirmations
- Event notifications
- Any email sent by the YSC app

**Use Mailpit when testing:**
- Newsletter campaigns
- Newsletter subscriptions
- Marketing emails
- Any email sent by Keila

### Testing Workflows

#### Test Registration Email

```bash
# 1. Start dev server
make dev

# 2. Register a user
# Visit http://localhost:4000/users/register
# Enter email: test@example.com

# 3. View confirmation email
open http://localhost:4000/dev/mailbox
```

#### Test Password Reset Email

```bash
# 1. Request password reset
# Visit http://localhost:4000/users/reset-password

# 2. Check mailbox for reset link
open http://localhost:4000/dev/mailbox
```

#### Test Ticket Confirmation

```bash
# 1. Purchase a ticket
# Complete checkout process

# 2. Check mailbox for confirmation
open http://localhost:4000/dev/mailbox
```

## Configuration

### Swoosh Configuration

Located in `config/config.exs`:

```elixir
config :ysc, Ysc.Mailer, adapter: Swoosh.Adapters.Local
```

This configures Swoosh to use the Local adapter, which stores emails in memory.

### Development Routes

Located in `lib/ysc_web/router.ex`:

```elixir
if Application.compile_env(:ysc, :dev_routes) do
  scope "/dev" do
    pipe_through :browser
    
    forward "/mailbox", Plug.Swoosh.MailboxPreview
  end
end
```

The `/dev/mailbox` route is only available when `dev_routes` is enabled (default in development).

## Important Behaviors

### Swoosh Mailbox

**Persists**: Only while Phoenix server is running
**Cleared when**: Server restarts
**Storage**: In-memory
**External dependencies**: None

**Implications**:
- Fast and simple for development
- No need for external SMTP server
- Emails disappear on restart (regenerate as needed)
- Perfect for rapid development and testing

### Mailpit

**Persists**: While Docker container is running
**Cleared when**: Container restarts
**Storage**: Container filesystem
**External dependencies**: Docker

**Implications**:
- Survives Phoenix restarts
- Good for testing newsletter campaigns
- Requires Docker to be running
- Separate from app lifecycle

## Email Template Development

When developing email templates (MJML):

```bash
# 1. Edit template
# Example: lib/ysc_web/emails/templates/user_confirmation.mjml.eex

# 2. Trigger the email
# Perform action that sends email

# 3. View in mailbox
open http://localhost:4000/dev/mailbox

# 4. Inspect HTML and text versions
# Click email to see full preview
```

## Troubleshooting

### Emails Not Appearing in /dev/mailbox

**Check dev_routes configuration:**
```elixir
# Should be set in config/dev.exs
config :ysc, dev_routes: true
```

**Verify Swoosh configuration:**
```elixir
# In config/config.exs
config :ysc, Ysc.Mailer, adapter: Swoosh.Adapters.Local
```

**Restart Phoenix server:**
```bash
# Press Ctrl+C twice
make dev
```

### Mailbox Empty After Restart

This is **expected behavior**:
- Emails stored in memory
- Cleared when server restarts
- Simply trigger new test emails

### Can't Access /dev/mailbox

**Check you're in development mode:**
```bash
# Should be running with MIX_ENV=dev (default)
echo $MIX_ENV  # Should be empty or "dev"
```

**Verify route exists:**
```bash
# Check router.ex has the forward directive
# Look for: forward "/mailbox", Plug.Swoosh.MailboxPreview
```

## Comparison with Production

### Development (Swoosh.Adapters.Local)
- Emails stored in memory
- Viewable at /dev/mailbox
- No emails actually sent
- Perfect for testing

### Production (Different Adapter)
- Uses real SMTP service (e.g., SendGrid, AWS SES)
- Emails actually sent to recipients
- No /dev/mailbox route available
- Configured via environment variables

## Benefits

1. **No external dependencies** - Swoosh Local adapter works out of the box
2. **Fast testing** - Immediate email preview without SMTP delays
3. **Easy debugging** - See exactly what users will receive
4. **Template testing** - Test both HTML and text versions
5. **Safe development** - Never accidentally send emails to real addresses
6. **Complete separation** - App emails and newsletter emails are separate
7. **Clear organization** - Know where to look for each type of email

## Testing in CI/CD

In test environment, emails can be:
- Stored in memory (same as dev)
- Tested for content, recipients, subject
- Verified without actually sending

Example test:
```elixir
test "sends registration email" do
  user = insert(:user)
  
  email = Ysc.Emails.user_confirmation_email(user)
  
  assert email.to == user.email
  assert email.subject =~ "Confirm your account"
end
```

## Summary

Email testing documentation now provides:
✅ Clear explanation of two email systems
✅ Step-by-step testing workflows
✅ Quick access URLs for both systems
✅ Comparison table showing differences
✅ Troubleshooting common issues
✅ Email template development guide
✅ Configuration details
✅ When to use each system

Developers now have complete understanding of:
- How to test application emails (Swoosh)
- How to test newsletter emails (Keila/Mailpit)
- Which tool to use for which purpose
- How to debug email issues

---

**Created**: 2026-02-04  
**Purpose**: Help developers test emails in local development  
**Status**: Complete ✅
