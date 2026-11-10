# Monitoring and Alerting

Where to look when something is wrong, and what runs on its own to catch problems.

| Channel   | Used for                                                   | Docs                                   |
| --------- | ---------------------------------------------------------- | -------------------------------------- |
| Sentry    | Exceptions (server and browser), `Ysc.Logging.error/2`     | below, [LOGGING.md](LOGGING.md)        |
| Discord   | Financial / reconciliation / webhook alerts and reports    | [DISCORD_ALERTS.md](DISCORD_ALERTS.md) |
| Telemetry | Latency, traffic, errors, memory (`lib/ysc_web/telemetry.ex`) | below                               |

## Scheduled health checks

All are Oban cron jobs in `config/config.exs`; each can also be run on demand from a console.

| Time (UTC) | Worker                                   | Checks                                                     | Docs                                   |
| ---------- | ---------------------------------------- | ---------------------------------------------------------- | -------------------------------------- |
| 00:00      | `Ysc.Ledgers.BalanceCheckWorker`         | Ledger debits = credits; logs imbalanced accounts (no Discord) | [RECONCILIATION_SYSTEM.md](RECONCILIATION_SYSTEM.md) |
| 01:00      | `Ysc.Ledgers.ReconciliationWorker`       | Payments, refunds, entities and payouts vs. ledger         | [RECONCILIATION_SYSTEM.md](RECONCILIATION_SYSTEM.md) |
| 02:00      | `Ysc.Stripe.WebhookReconciliationWorker` | Last 24h of Stripe events vs. `webhook_events`             | [STRIPE_WEBHOOKS.md](STRIPE_WEBHOOKS.md) |
| 03:00      | `YscWeb.Workers.WebhookRetryWorker`      | Retries pending / failed / stuck webhooks                  | [STRIPE_WEBHOOKS.md](STRIPE_WEBHOOKS.md) |
| 03:00      | `YscWeb.Workers.QuickbooksSyncRetryWorker` | Re-enqueues unsynced payments, refunds, payouts          | [QUICKBOOKS.md](QUICKBOOKS.md)         |

## Sentry

Sentry is loaded as a separate script (`/assets/sentry.min.js`) **before** the app bundle in `root.html.heex` and `admin_root.html.heex`. It is copied from `assets/vendor/bundle.tracing.replay.min.js` by `mix copy_vendor_assets`, which runs as part of `mix assets.build` / `mix assets.deploy`. It must not be `import`ed from `app.js`: the bundle is an IIFE that assigns `window.Sentry`, and esbuild leaves `window.Sentry` undefined (symptom: `Cannot read properties of undefined (reading 'init')`).

**User context.** The root layouts expose `window.currentUser = {id, email, role, state}` (or `null` when anonymous) and `app.js` calls `Sentry.setUser` from it once Sentry has initialised, so errors are tagged with the affected member. It is set on full page loads only; a login or logout is a full navigation, so no extra wiring is needed. Only those four fields are sent. To verify: log in, check `window.currentUser` in the console, trigger an error and confirm the Sentry event carries the user.

Server-side errors reach Sentry through `Ysc.Logging.error/2` (never use `Logger` directly); see [LOGGING.md](LOGGING.md). Passkey failures are tagged `component:passkey_auth`; see [AUTHENTICATION.md](AUTHENTICATION.md).

## Telemetry guardrails

Defined in `lib/ysc_web/telemetry.ex` and the basis for alerts:

| Signal     | Metric                                                         | Alert when                    |
| ---------- | -------------------------------------------------------------- | ----------------------------- |
| Latency    | `phoenix.live_view.mount.stop.duration`                        | p95 > 200 ms                  |
| Traffic    | `phoenix.endpoint.stop.duration`, `phoenix.endpoint.stop` (by status) | spike in 4xx/5xx       |
| Errors     | `phoenix.error_rendered`                                       | any non-zero count            |
| Saturation | `vm.memory.total`, `vm.memory.processes`, `vm.memory.processes_used` | > 80% of RAM (OOM risk) |

Memory in LiveView processes is the main scaling risk. Follow the LiveView performance rules in [AGENTS.md](../AGENTS.md) (streams for collections, `temporary_assigns`, `assign_async`, minimal assigns, `consume_uploaded_entry` promptly). For slow queries see [QUERY_OPTIMIZATION_GUIDE.md](QUERY_OPTIMIZATION_GUIDE.md) and [QUERY_EXPLAIN_CI.md](QUERY_EXPLAIN_CI.md).
