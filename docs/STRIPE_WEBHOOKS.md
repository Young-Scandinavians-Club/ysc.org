# Stripe Webhooks

How Stripe webhook events are received, stored, processed, retried and reconciled.

| Piece                  | Location                                                    |
| ---------------------- | ----------------------------------------------------------- |
| Endpoint (`/webhooks/stripe`, signature-verified) | `lib/ysc_web/endpoint.ex` (Stripe webhook plug) |
| Handler                | `lib/ysc/stripe/webhook_handler.ex`                         |
| Event storage          | `lib/ysc/webhooks/webhook_event.ex`, `lib/ysc/webhooks.ex`  |
| Manual reprocessing    | `lib/ysc/webhooks/reprocessor.ex`                           |
| Nightly retry          | `lib/ysc_web/workers/webhook_retry_worker.ex` (03:00 UTC)   |
| Nightly Stripe diff    | `lib/ysc/stripe/webhook_reconciliation_worker.ex` (02:00 UTC) |
| Tests                  | `test/ysc/stripe/webhook_handler_test.exs`                  |

Schedules live in the Oban `crontab` in `config/config.exs`.

## Guarantees

1. **Store first.** An event is persisted to `webhook_events` before Stripe gets a success response. If storage fails Stripe gets an error and retries. Never return `:ok` for an event that is not stored.
2. **All or nothing.** Handlers run in a single DB transaction together with marking the event `:processed`. A failure rolls back everything; there is no partial success.
3. **External calls stay out of transactions.** Stripe API calls happen before the transaction where possible; emails are enqueued as Oban jobs so a mail failure can never fail or roll back a webhook.
4. **Idempotent.** `webhook_events` has a unique index on `(provider, event_id)`, so a duplicate delivery is detected and handled by current state (`pending`, `processing`, `processed`, `failed`). Refunds are additionally unique on `refunds.external_refund_id`.
5. **Replay protection.** Live deliveries older than 5 minutes (`@webhook_max_age_seconds`) are rejected with `{:error, :webhook_too_old}`. Reprocessing paths pass `replay: true` to skip the check.

## Event lifecycle

`WebhookState`: `pending` → `processing` → `processed` | `failed`.

`WebhookEvent` rows are keyed by `provider` (`stripe` / `quickbooks`) and `event_id`. The raw payload is kept so any event can be replayed.

## Known race conditions and how they are handled

- **Invoice before subscription.** `invoice.payment_succeeded` can arrive before `customer.subscription.created`. The handler fetches the subscription from Stripe and creates it locally before recording the payment, so payments are never recorded with a `nil` `entity_id`.
- **`charge.refunded` + `refund.created` for the same refund.** Each refund is processed individually and keyed on the Stripe refund id, so the second event is skipped ("Refund already processed"). Partial refunds are tracked independently.
- **WordPress-originated events** (from the legacy site sharing the Stripe account) are acknowledged and ignored.
- **Payout webhooks** (`payout.paid`) are acknowledged without creating ledger payouts or QuickBooks jobs when `STRIPE_PROCESS_PAYOUT_WEBHOOKS=false` (see `config/runtime.exs`). Ignored in `:test`.

## Safety nets

### Nightly Stripe reconciliation (`WebhookReconciliationWorker`, 02:00 UTC)

Fetches the last 24h of events from the Stripe API, compares with `webhook_events`, stores any missing events and processes them. Posts a summary to Discord. Run on demand:

```elixir
Ysc.Stripe.WebhookReconciliationWorker.run_now()
```

### Nightly retry (`WebhookRetryWorker`, 03:00 UTC)

Retries events that did not finish, oldest first:

- `pending` and `failed` events, between 5 minutes and 7 days old
- `processing` events stuck for more than 60 minutes
- at most 100 per run, using `FOR UPDATE SKIP LOCKED` so concurrent runs never process the same row

Backed by two composite indexes on `webhook_events`: `(state, inserted_at)` and `(state, updated_at)`.

### Manual reprocessing (`Ysc.Webhooks.Reprocessor`)

From a remote console (`fly ssh console --pty -C "/app/bin/ysc remote"`):

```elixir
alias Ysc.Webhooks.Reprocessor

Reprocessor.get_failed_webhook_stats()
Reprocessor.list_failed_webhooks(limit: 20, provider: "stripe")
Reprocessor.get_failed_webhook_details(webhook_id)
Reprocessor.reprocess_webhook(webhook_id)
Reprocessor.reprocess_all_failed_webhooks()
Reprocessor.reprocess_webhooks_by_type("stripe", "invoice.payment_succeeded")

# Stuck in pending/processing
Reprocessor.list_pending_or_processing_webhooks()
Reprocessor.reprocess_all_pending_or_processing_webhooks()
```

Payouts that were linked incorrectly are fixed with `relink_payout_transactions/1`; see [REPROCESS_PAYOUTS.md](REPROCESS_PAYOUTS.md).

## Monitoring

| Signal                                   | Healthy             | Investigate          |
| ---------------------------------------- | ------------------- | -------------------- |
| Webhook processing time                  | 200–500 ms          | > 1 s                |
| Failure rate                             | < 0.1%              | > 0.5% (critical > 1%) |
| `webhook_not_found_after_rollback` in Sentry | never           | any                  |
| Payments with `entity_id = nil`          | 0                   | any                  |
| Failed `webhook_events` rows             | 0 after nightly retry | persisting         |

Look for these log events: `Refund already processed, skipping (idempotency)` (good), `Created subscription from Stripe before processing payment` (race handled), `Failed to fetch subscription from Stripe` / `Failed to process refund in ledger` (needs a look). Nightly results go to Discord; see [DISCORD_ALERTS.md](DISCORD_ALERTS.md).

## Testing

```bash
mix test test/ysc/stripe/webhook_handler_test.exs
```

Coverage areas: replay protection, deduplication, refund idempotency (including the `charge.refunded` + `refund.created` pair and partial refunds), subscription race conditions, transactional rollback, and ledger balance after refunds. Use the `build_stripe_event/3` helper in the test file when adding cases, and assert on resulting rows (payments, refunds, ledger entries) rather than log output.

Locally, forward live events with the Stripe CLI:

```bash
stripe listen --forward-to localhost:4000/webhooks/stripe
```
