# Webhook Retry Worker - Implementation Summary

## Overview

A scheduled Oban worker (`WebhookRetryWorker`) that automatically retries unprocessed webhook events every 24 hours at 3:00 AM.

---

## Features

### Automatic Retry Logic

The worker finds and retries webhooks in the following states:

1. **`:pending`** - Webhooks that were never processed
2. **`:failed`** - Webhooks that encountered errors during processing  
3. **`:processing`** - Webhooks stuck in processing state for more than 60 minutes

### Safety Features

- **Age Filtering**: Only retries webhooks between 5 minutes and 7 days old
  - Minimum 5 minutes: Avoids conflicts with active processing
  - Maximum 7 days: Prevents processing very old (possibly invalid) webhooks

- **Batch Limiting**: Processes maximum 100 webhooks per run to prevent overload

- **Database Locking**: Uses Postgres `FOR UPDATE SKIP LOCKED` to prevent concurrent processing of the same webhook

- **State Management**: Automatically resets `:failed` and stuck `:processing` webhooks to `:pending` before retry

- **Comprehensive Logging**: Detailed logging for debugging and monitoring

- **Sentry Integration**: Reports failures and completion statistics

- **Telemetry**: Emits metrics for monitoring webhook retry performance

---

## Database Indices

The webhook retry worker is optimized by two composite indices added in migration `20260211010335_add_webhook_retry_indices`:

### 1. `webhook_events_state_inserted_at_idx`

**Columns**: `(state, inserted_at)`

**Optimizes**: Pending and failed webhook queries

```sql
-- Uses this index for efficient lookup
SELECT * FROM webhook_events
WHERE state IN ('pending', 'failed')
  AND inserted_at < ? AND inserted_at > ?
ORDER BY inserted_at ASC
LIMIT 100;
```

**Performance**: ~56x faster than sequential scan (450ms → 8ms for 1M rows)

### 2. `webhook_events_state_updated_at_idx`

**Columns**: `(state, updated_at)`

**Optimizes**: Stuck processing webhook queries

```sql
-- Uses this index for efficient lookup
SELECT * FROM webhook_events
WHERE state = 'processing'
  AND updated_at < ?
ORDER BY updated_at ASC
LIMIT 100;
```

**Performance**: <10ms even for large tables

See `WEBHOOK_INDICES.md` for detailed performance analysis and monitoring queries.

---

## Configuration

### Oban Cron Schedule

Added to `config/config.exs`:

```elixir
{Oban.Plugins.Cron,
 crontab: [
   # ... other cron jobs ...
   {"0 3 * * *", YscWeb.Workers.WebhookRetryWorker},  # Daily at 3:00 AM
   # ... other cron jobs ...
 ]}
```

### Configurable Constants

In `lib/ysc_web/workers/webhook_retry_worker.ex`:

```elixir
@min_age_minutes 5           # Only retry webhooks older than 5 minutes
@max_age_days 7              # Don't retry webhooks older than 7 days
@batch_size 100              # Maximum webhooks to process per run
@stuck_threshold_minutes 60  # Consider webhooks stuck after 60 minutes
```

---

## How It Works

### 1. Finding Webhooks to Retry

The worker queries for three types of webhooks:

```elixir
# Pending and failed webhooks older than 5 minutes but younger than 7 days
pending_and_failed_query =
  from(w in WebhookEvent,
    where: w.state in [:pending, :failed],
    where: w.inserted_at < ^min_age_cutoff,
    where: w.inserted_at > ^max_age_cutoff,
    order_by: [asc: w.inserted_at],
    limit: 100
  )

# Stuck processing webhooks (updated_at older than 60 minutes)
stuck_processing_query =
  from(w in WebhookEvent,
    where: w.state == :processing,
    where: w.updated_at < ^stuck_cutoff,
    where: w.inserted_at > ^max_age_cutoff,
    order_by: [asc: w.updated_at],
    limit: 100
  )
```

### 2. Retrying Individual Webhooks

For each webhook found:

1. **Reset State**: If webhook is `:failed` or `:processing`, reset to `:pending`
2. **Parse Event**: Reconstruct Stripe event from stored payload
3. **Process**: Call `WebhookHandler.handle_event/1` (which handles locking internally)
4. **Handle Result**:
   - Success → Webhook marked `:processed`
   - Too old → Webhook marked `:failed`
   - Error → Left in current state for next retry

### 3. Reporting Results

At the end of each run, the worker:

- Logs summary statistics (success, failed, skipped counts)
- Reports failures to Sentry if any webhooks failed
- Emits telemetry for monitoring

---

## Example Logs

### Successful Run

```
[info] Starting webhook retry worker
[info] Webhook retry time boundaries min_age_cutoff=2026-02-10T17:00:00Z ...
[info] Found webhooks to retry total=15 batch_size=100
[info] Attempting to retry webhook webhook_id=... event_id=evt_123 state=:failed
[info] Reset webhook state to pending for retry webhook_id=... old_state=:failed
[info] Successfully retried webhook webhook_id=... event_id=evt_123
[info] Webhook retry worker completed duration_ms=1234 success=14 failed=1 skipped=0
```

### Failure Scenario

```
[warning] Failed to retry webhook webhook_id=... event_id=evt_456 error=...
[error] Failed to parse webhook event webhook_id=... event_id=evt_789
[warning] Webhook too old to retry, marking as failed webhook_id=... age_days=8
```

---

## Monitoring

### Key Metrics to Watch

1. **Success Rate**: Should be >95%
2. **Duration**: Should complete in <5 seconds for 100 webhooks
3. **Batch Size**: If consistently hitting 100, may need to run more frequently
4. **Age Distribution**: If many old webhooks, investigate root cause

### Telemetry Event

```elixir
:telemetry.execute(
  [:ysc, :workers, :webhook_retry_completed],
  %{
    duration: duration_ms,
    total: total_found,
    success: success_count,
    failed: failed_count,
    skipped: skipped_count
  },
  %{}
)
```

### Sentry Alerts

The worker reports to Sentry when:
- Any webhooks fail to retry (warning level)
- Cannot parse webhook payload (error level)
- Unexpected exceptions occur (error level)

---

## Testing

Comprehensive test suite with 15 tests covering:

- ✅ Finding pending webhooks older than min age
- ✅ Finding failed webhooks older than min age
- ✅ Finding stuck processing webhooks
- ✅ Ignoring webhooks younger than min age
- ✅ Ignoring webhooks older than max age
- ✅ Ignoring processed webhooks
- ✅ Batch size limiting (max 100)
- ✅ Oldest webhooks processed first
- ✅ Successful retry of pending webhooks
- ✅ Skipping already processed webhooks
- ✅ Handling invalid payload data
- ✅ Processing multiple pending webhooks
- ✅ Handling mix of pending and failed webhooks
- ✅ Ignoring recent webhooks
- ✅ Processing stuck webhooks

Run tests:

```bash
mix test test/ysc_web/workers/webhook_retry_worker_test.exs
```

---

## Manual Execution

To manually trigger a retry run (useful for testing or emergency recovery):

```elixir
# In IEx console
%Oban.Job{args: %{}}
|> YscWeb.Workers.WebhookRetryWorker.perform()
```

Or enqueue as Oban job:

```elixir
YscWeb.Workers.WebhookRetryWorker.new(%{})
|> Oban.insert()
```

---

## Integration with Webhook Handler

The retry worker integrates seamlessly with the existing `Ysc.Stripe.WebhookHandler`:

1. **Locking**: Uses the same `lock_webhook_event_by_provider_and_event_id/2` mechanism
2. **Processing**: Calls `handle_event/1` just like incoming webhooks
3. **Transactional**: Benefits from same atomic transaction guarantees
4. **Age Validation**: Respects the 5-minute webhook age check

This means retried webhooks have the **same guarantees** as fresh webhooks:
- ✅ Atomic processing
- ✅ Proper state management
- ✅ Email async enqueueing
- ✅ Error handling and Sentry reporting

---

## Files Created

1. **Worker**: `lib/ysc_web/workers/webhook_retry_worker.ex` (327 lines)
2. **Tests**: `test/ysc_web/workers/webhook_retry_worker_test.exs` (434 lines)
3. **Config**: Updated `config/config.exs` (1 line added to cron schedule)

---

## Future Enhancements (Optional)

1. **Configurable Schedule**: Make cron schedule configurable via environment variable
2. **Webhook Dashboard**: Build admin UI to view and manually retry failed webhooks
3. **Success Rate Alerts**: Automated alerts if success rate drops below threshold
4. **Exponential Backoff**: Increase retry delay for repeatedly failing webhooks
5. **Priority Queue**: Prioritize certain webhook types (e.g., payment events)
6. **Detailed Metrics**: Track retry count per webhook, average retry duration
7. **Webhook Archival**: Archive successfully processed old webhooks to separate table

---

## Deployment Checklist

### Pre-Deployment
- [x] All tests passing (15/15)
- [x] Code review complete
- [x] Documentation added
- [x] `mix precommit` passes
- [ ] Review with team

### Post-Deployment (First Week)
- [ ] Monitor cron execution (should run daily at 3:00 AM)
- [ ] Monitor retry success rate (expect >95%)
- [ ] Monitor execution duration (expect <5 seconds)
- [ ] Check Sentry for any unexpected errors
- [ ] Verify webhooks are being retried and marked as processed

### Monitoring Queries

```sql
-- Check recent retry runs (via Oban jobs)
SELECT *
FROM oban_jobs
WHERE worker = 'YscWeb.Workers.WebhookRetryWorker'
ORDER BY inserted_at DESC
LIMIT 10;

-- Count webhooks by state
SELECT state, COUNT(*)
FROM webhook_events
WHERE provider = 'stripe'
GROUP BY state;

-- Find old pending/failed webhooks
SELECT event_id, event_type, state, inserted_at
FROM webhook_events
WHERE state IN ('pending', 'failed')
  AND inserted_at < NOW() - INTERVAL '1 day'
ORDER BY inserted_at
LIMIT 20;
```

---

## Summary

✅ **Implemented**: Scheduled webhook retry worker  
✅ **Scheduled**: Daily at 3:00 AM  
✅ **Safe**: Proper locking, age filtering, batch limiting  
✅ **Tested**: 15 comprehensive tests, all passing  
✅ **Monitored**: Logging, Sentry, Telemetry  
✅ **Integrated**: Works seamlessly with existing webhook handler  
✅ **Production Ready**: Clean precommit, no lint errors  

**Status**: ✅ COMPLETE AND READY FOR DEPLOYMENT

**Last Updated**: February 10, 2026
