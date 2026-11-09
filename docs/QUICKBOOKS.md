# QuickBooks Integration

How payments, refunds, payouts and expense reports are synced to QuickBooks Online (QBO). For first-time production setup (accounts, classes, items, env vars) see [QUICKBOOKS_PRODUCTION_CHECKLIST.md](QUICKBOOKS_PRODUCTION_CHECKLIST.md).

## What syncs where

| App record                   | QBO entity                              | Entry point                                  |
| ---------------------------- | --------------------------------------- | -------------------------------------------- |
| `Ledgers.Payment`            | SalesReceipt                            | `Ysc.Quickbooks.Sync.sync_payment/1`         |
| `Ledgers.Refund`             | RefundReceipt (reverses the original item) | `Ysc.Quickbooks.Sync.sync_refund/1`       |
| `Ledgers.Payout`             | Deposit (Stripe settlement → bank, with fee line) | `Ysc.Quickbooks.Sync.sync_payout/1` |
| `ExpenseReports.ExpenseReport` | Bill + receipt attachments            | `Ysc.ExpenseReports.QuickbooksSync`          |

The HTTP client is `Ysc.Quickbooks.Client` (behaviour in `client_behaviour.ex` so tests use a mock). Payment/refund/payout item, account and class mapping lives in `lib/ysc/quickbooks/sync.ex` (`@account_class_mapping`, `determine_item_name`, `determine_income_account_name`).

## Design: sync state lives on the record

`Payment`, `Refund` and `Payout` each carry their own sync state rather than a separate sync table, so state cannot drift from the data it describes and "what still needs syncing" is a single query.

| Field                                    | Meaning                                              |
| ---------------------------------------- | ---------------------------------------------------- |
| `quickbooks_sync_status`                 | `pending` / `synced` / `failed` (or `NULL` = never attempted) |
| `quickbooks_sales_receipt_id` (payments, refunds) / `quickbooks_deposit_id` (payouts) | QBO id once created |
| `quickbooks_sync_error`                  | Map of error details from the last failure           |
| `quickbooks_response`                    | Full QBO response body, for debugging                |
| `quickbooks_synced_at`, `quickbooks_last_sync_attempt_at` | Timestamps                          |

## Flow

```
Payment / Refund / Payout created
  → status "pending" + Oban job enqueued
  → worker takes FOR UPDATE NOWAIT lock on the row, calls QBO
  → success: "synced" + QBO id stored      failure: "failed" + error stored
```

- **Workers** (`lib/ysc_web/workers/`): `QuickbooksSyncPaymentWorker`, `…RefundWorker`, `…PayoutWorker` (default queue, 5 attempts, unique for 5 minutes). If the row lock is already held the job returns `:ok` and leaves the record for the retry worker.
- **Nightly retry** (`QuickbooksSyncRetryWorker`, 03:00 UTC): enqueues a job for every payment, refund and payout whose status is not `synced`.
- **Expense reports**: `QuickbooksSyncExpenseReportWorker`, with `QuickbooksSyncExpenseReportBackupWorker` every 6 hours picking up approved reports that were never synced. Inbound QBO events (`/webhooks/quickbooks`) are handled by `QuickbooksBillPaymentProcessorWorker` (marks a report `paid` only once the linked Bill is confirmed fully paid) and `QuickbooksBillDeletedProcessorWorker`.
- **Payouts** sync once all their linked payments and refunds have synced; syncing a payment or refund re-checks any payout waiting on it.
- **Refunds** use the same item as the original sale so revenue is reversed on the right account, and the system customer is used when the user no longer exists.

## Idempotency

Every create call sends QBO's `requestid` query parameter so a retried request replays the original response instead of creating a duplicate (scope: per company/realm, max 255 chars). Keys are derived from the record id:

| Operation          | Key                               |
| ------------------ | --------------------------------- |
| SalesReceipt       | `sr_pay_<payment_id>`             |
| RefundReceipt      | `rr_ref_<refund_id>`              |
| Deposit / journal entry | `dep_payout_…` / `je_payout_…` (payout id) |
| Bill               | `expense_report_<expense_report_id>` |

Beyond the key, the app also: stores the QBO id as soon as it is created (a bill is recorded even if the receipt upload then fails), pre-checks for existing vendors/items by name or email before creating, and retries once with a refreshed OAuth token on `401` using the same key. Read-only queries and PUT updates are naturally idempotent.

Rules of thumb when adding a QBO create call: always pass an `idempotency_key` derived from the local record id; never retry validation errors; extract the existing id from duplicate-name errors rather than failing.

## Troubleshooting

- **Status stuck at `failed`**: read `quickbooks_sync_error` / `quickbooks_response` on the record; fix the cause (usually a missing account, class or item — see the checklist; QBO error 2390 means an item has no income account), then re-enqueue the sync worker or wait for the nightly retry.
- **Payout won't sync**: confirm all linked payments/refunds are `synced`; relink with [REPROCESS_PAYOUTS.md](REPROCESS_PAYOUTS.md) if links or `fee_total` are wrong.
- **Auth failures**: QBO tokens refresh automatically; persistent `401` after a refresh means the QuickBooks connection needs to be re-authorized.
