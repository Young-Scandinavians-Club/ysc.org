# Newsletter Rate Limiting

## Overview

The newsletter subscription form implements comprehensive rate limiting to prevent bot abuse and spam. This is critical since the form is publicly accessible and unauthenticated.

## Protection Layers

### 1. Rate Limiting (`Ysc.NewsletterRateLimit`)

**Dual rate limiting strategy:**

- **Per IP Address**: 3 subscription attempts per minute
  - Prevents a single bot from spamming subscriptions
  - Protects against distributed attacks from one source

- **Per Email Address**: 1 subscription per hour
  - Prevents email address enumeration
  - Protects against subscribe/unsubscribe abuse cycles
  - Reduces load on the newsletter service

### 2. Turnstile CAPTCHA

Uses Cloudflare Turnstile in `interaction-only` mode:
- Runs invisible background checks on all users
- Only shows a challenge if suspicious behavior is detected
- Only generates a token if a challenge was shown
- If no token is present, Turnstile deemed the request safe

### 3. Combined Protection Flow

```
User submits newsletter form
  ↓
Check IP rate limit (3/minute)
  ↓ (pass)
Check email rate limit (1/hour)
  ↓ (pass)
Check if Turnstile token exists
  ↓ (yes)           ↓ (no)
Verify token    →  Allow (trusted)
  ↓ (valid)
Subscribe to newsletter
```

## Implementation Details

### Rate Limiter Module

Located at: `lib/ysc/newsletter_rate_limit.ex`

```elixir
# Check both IP and email
Ysc.NewsletterRateLimit.check(ip, email)

# Or check individually
Ysc.NewsletterRateLimit.check_ip(ip)
Ysc.NewsletterRateLimit.check_email(email)
```

### Integration in HomeLive

```elixir
def handle_event("subscribe_newsletter", params, socket) do
  email = params["email"]
  remote_ip = socket.assigns.remote_ip

  # Check rate limits first (by IP and email)
  case Ysc.NewsletterRateLimit.check(remote_ip, email) do
    :ok ->
      verify_and_subscribe(params, email, socket)

    {:error, :rate_limited, _retry_after} ->
      {:noreply, socket |> assign(newsletter_error: "...")}
  end
end
```

### Startup Configuration

The rate limiter is started in the supervision tree (`lib/ysc/application.ex`):

```elixir
{Ysc.NewsletterRateLimit, [clean_period: :timer.minutes(1)]}
```

## Testing

Comprehensive test suite at: `test/ysc/newsletter_rate_limit_test.exs`

Tests cover:
- ✅ IP rate limiting (3 per minute)
- ✅ Email rate limiting (1 per hour)
- ✅ Combined checks
- ✅ IP/email normalization
- ✅ Isolation between different IPs/emails
- ✅ Retry-after calculation

Run tests:
```bash
mix test test/ysc/newsletter_rate_limit_test.exs
```

## Error Messages

**Rate limit exceeded:**
```
"Too many subscription attempts. Please try again later."
```

**Turnstile verification required:**
```
"Please complete the verification to continue."
```

## Monitoring

Rate limit events are logged with Sentry integration:

```elixir
Ysc.Logging.warning("Newsletter subscription rate limit exceeded by IP",
  extra: %{ip: ip, limit: @ip_limit}
)
```

Monitor these logs to detect:
- Bot attacks
- DDoS attempts
- Unusual traffic patterns

## Configuration

Rate limits are hardcoded in `lib/ysc/newsletter_rate_limit.ex`:

```elixir
@ip_limit 3
@ip_scale_ms :timer.minutes(1)

@email_limit 1
@email_scale_ms :timer.hours(1)
```

To adjust limits, modify these constants and redeploy.

## Why These Limits?

**IP Limit (3/minute):**
- Allows legitimate users to retry if they make a typo
- Low enough to prevent rapid bot submissions
- Won't affect normal user behavior

**Email Limit (1/hour):**
- Prevents email enumeration attacks
- Stops subscribe/unsubscribe abuse cycles
- One hour is sufficient for legitimate retries
- Protects newsletter service costs

## Future Enhancements

Potential improvements:
- [ ] Make limits configurable via environment variables
- [ ] Add metrics/dashboards for rate limit hits
- [ ] Implement exponential backoff for repeated violations
- [ ] Consider IP reputation services for advanced bot detection
