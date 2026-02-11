# Custom Logging Module

This document describes the custom logging module (`Ysc.Logging`) that automatically integrates with Sentry for error tracking.

## Overview

The `Ysc.Logging` module is a wrapper around Elixir's standard `Logger` that automatically captures errors and exceptions to Sentry when logging at the error level. This eliminates the need to write separate `Logger.error` and `Sentry.capture_exception` calls throughout the codebase.

**Important:** All logging calls are **silent (noop)** when running in the test environment to keep test output clean and focused.

## Usage

### Basic Error Logging

```elixir
require Ysc.Logging

# Simple error log (no Sentry)
Ysc.Logging.error("Something went wrong", user_id: user.id)
```

### Error Logging with Exception

```elixir
require Ysc.Logging

try do
  # Some operation
rescue
  error ->
    Ysc.Logging.error("Payment processing failed",
      error: error,
      stacktrace: __STACKTRACE__,
      payment_id: payment.id
    )
end
```

### Error Logging with Sentry Context

```elixir
require Ysc.Logging

rescue
  error ->
    Ysc.Logging.error("Failed to process webhook",
      error: error,
      stacktrace: __STACKTRACE__,
      webhook_id: webhook.id,
      extra: %{
        event_type: webhook.event_type,
        provider: webhook.provider
      },
      tags: %{
        service: "stripe",
        operation: "webhook"
      }
    )
end
```

### Other Log Levels

```elixir
# These do NOT send to Sentry
Ysc.Logging.info("User logged in", user_id: user.id)
Ysc.Logging.warning("Rate limit approaching", current: 90, max: 100)
Ysc.Logging.debug("Processing step", step: 1)
```

## Options

The `error/2` macro accepts the following special options:

- `:error` - An exception struct to capture in Sentry (required for Sentry capture)
- `:stacktrace` - Stacktrace to attach (usually `__STACKTRACE__`)
- `:extra` - Additional context as a map for Sentry
- `:tags` - Tags to categorize the error in Sentry

All other keyword options are passed to `Logger.error` as metadata.

## Benefits

1. **Reduced Boilerplate**: No need to write separate logging and Sentry calls
2. **Consistent Error Tracking**: All errors with exceptions are automatically sent to Sentry
3. **Rich Context**: Easily attach extra metadata and tags for better debugging
4. **Backward Compatible**: Other log levels (info, warning, debug) work exactly like standard Logger

## Before and After

### Before (Old Pattern)

```elixir
rescue
  error ->
    Logger.error("Failed to process payment",
      payment_id: payment.id,
      error: Exception.message(error),
      stacktrace: Exception.format_stacktrace(__STACKTRACE__)
    )

    Sentry.capture_exception(error,
      stacktrace: __STACKTRACE__,
      extra: %{
        payment_id: payment.id,
        user_id: user.id
      },
      tags: %{
        service: "stripe"
      }
    )
end
```

### After (New Pattern)

```elixir
require Ysc.Logging

rescue
  error ->
    Ysc.Logging.error("Failed to process payment",
      error: error,
      stacktrace: __STACKTRACE__,
      payment_id: payment.id,
      extra: %{
        payment_id: payment.id,
        user_id: user.id
      },
      tags: %{
        service: "stripe"
      }
    )
end
```

## Migration Notes

The codebase has been updated to use `Ysc.Logging` in the following modules:

- `Ysc.Stripe.WebhookHandler`
- `YscWeb.Workers.WebhookRetryWorker`
- `Ysc.Stripe.WebhookReconciliationWorker`
- `YscWeb.Workers.EventNotificationWorker`
- `YscWeb.Workers.EmailNotifier`
- `YscWeb.Workers.BookingCheckoutReminderWorker`
- `YscWeb.Workers.BookingCheckinReminderWorker`
- `YscWeb.FlowrouteWebhookController`
- `Ysc.Messages`
- `Ysc.Ledgers`

## Implementation Details

The `Ysc.Logging.error/2` macro:

1. Extracts Sentry-specific options (`:error`, `:stacktrace`, `:extra`, `:tags`)
2. Logs the message with metadata using `Logger.error/2`
3. If an `:error` is present, captures it to Sentry with the provided context
4. Returns `:ok`

The macro is compile-time safe and has minimal runtime overhead when no error is present.

### Test Environment Behavior

In the test environment (`MIX_ENV=test`):

- Logs are still emitted to Logger (so tests can capture and verify them)
- Sentry integration code is not compiled into the test build (compile-time optimization)
- No external API calls are made during tests
- Tests can use `ExUnit.CaptureLog` to verify logging behavior

The test/non-test check is done at **compile-time** using `Mix.env()`, so:
- In production releases, Sentry code is included and functional
- In test builds, Sentry code is completely omitted (not just skipped at runtime)
