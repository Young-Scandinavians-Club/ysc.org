# Documentation Index

Start with the root [README.md](../README.md) and [QUICKREF.md](../QUICKREF.md); coding rules for agents and contributors are in [AGENTS.md](../AGENTS.md) and [STYLE_GUIDE.md](../STYLE_GUIDE.md).

These docs describe how the system works now. Point-in-time audits, fix summaries and implementation plans do not belong here: put that in the PR description or commit message. When a doc is superseded, delete it rather than adding a `_V2` or `_SUMMARY`.

## Getting started

| Doc | Covers |
| --- | --- |
| [NEW_DEVELOPER_GUIDE.md](NEW_DEVELOPER_GUIDE.md) | Prerequisites, env vars, optional integrations, local workflows |
| [DEVELOPMENT_ARCHITECTURE.md](DEVELOPMENT_ARCHITECTURE.md) | Local dev environment: processes, ports, services |
| [SEED_DATA_REFERENCE.md](SEED_DATA_REFERENCE.md) | Seeded users, events, bookings and other dev data |
| [EMAIL_TESTING_GUIDE.md](EMAIL_TESTING_GUIDE.md) | Previewing email/SMS templates |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common local problems and fixes |
| [LIFE_OF_A_CHANGESET.md](LIFE_OF_A_CHANGESET.md) | Contributing workflow: branch to merged PR |
| [LOGGING.md](LOGGING.md) | `Ysc.Logging` usage and Sentry reporting |

## Payments and finance

| Doc | Covers |
| --- | --- |
| [LEDGER_SYSTEM_README.md](LEDGER_SYSTEM_README.md) | Double-entry ledger, accounts, payments, refunds |
| [CURRENCY_HANDLING.md](CURRENCY_HANDLING.md) | Dollars vs. cents, `Money` usage |
| [STRIPE_WEBHOOKS.md](STRIPE_WEBHOOKS.md) | Webhook guarantees, retry, nightly reconciliation, reprocessing |
| [RECONCILIATION_SYSTEM.md](RECONCILIATION_SYSTEM.md) | Nightly ledger/payment/payout reconciliation and balance check |
| [REPROCESS_PAYOUTS.md](REPROCESS_PAYOUTS.md) | Re-linking payouts, fixing `fee_total` |
| [QUICKBOOKS.md](QUICKBOOKS.md) | Sync design, workers, idempotency |
| [QUICKBOOKS_PRODUCTION_CHECKLIST.md](QUICKBOOKS_PRODUCTION_CHECKLIST.md) | Accounts, classes, items, env vars for a new QuickBooks company |

## Features

| Doc | Covers |
| --- | --- |
| [TICKET_SYSTEM_README.md](TICKET_SYSTEM_README.md) | Event ticketing |
| [OVERBOOKING_PREVENTION.md](OVERBOOKING_PREVENTION.md) | Reservation locking and the concurrency tests that protect it |
| [AUTHENTICATION.md](AUTHENTICATION.md) | Step-up re-auth, passkey debugging |
| [NEWSLETTER_RATE_LIMITING.md](NEWSLETTER_RATE_LIMITING.md) | Rate limits and Turnstile on the public newsletter form |
| [MOBILE_API.md](MOBILE_API.md), [MOBILE_APP_AUTH_HANDOFF.md](MOBILE_APP_AUTH_HANDOFF.md) | Mobile API and browser-to-app sign-in |
| [admin/README.md](admin/README.md) | Admin and volunteer help guides |

## Operations

| Doc | Covers |
| --- | --- |
| [MONITORING.md](MONITORING.md) | Scheduled health checks, Sentry, telemetry guardrails |
| [DISCORD_ALERTS.md](DISCORD_ALERTS.md) | Discord alert setup and message types |
| [S3_CREDENTIALS_CONFIGURATION.md](S3_CREDENTIALS_CONFIGURATION.md) | S3/Tigris credentials and bucket permissions |
| [QUERY_OPTIMIZATION_GUIDE.md](QUERY_OPTIMIZATION_GUIDE.md), [QUERY_EXPLAIN_CI.md](QUERY_EXPLAIN_CI.md) | Query performance and the CI `EXPLAIN` check |
| [GDPR_DATA_AUDIT.md](GDPR_DATA_AUDIT.md) | Personal-data inventory and retention gaps |
