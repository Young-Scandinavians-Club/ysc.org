# QuickBooks Refund Handling Audit

Audit of how refunds are synced to QuickBooks (RefundReceipt), used in payouts (Deposit line items), and where they align or diverge from best practices.

## Summary

**Verdict: Refunds are handled correctly.** The flow is consistent with payments and payouts, uses the correct QuickBooks entity (RefundReceipt), and integrates with deposits. Two small improvements were applied: clear `quickbooks_sync_error` on success and add 429 retry for RefundReceipt creation.

---

## 1. Refund sync flow

- **Entry:** `Ysc.Quickbooks.Sync.sync_refund/1` (public).
- **Already synced:** If `quickbooks_sync_status == "synced"` and `quickbooks_sales_receipt_id` is set, we return the existing ID and still call `check_and_enqueue_payout_syncs_for_refund/1` so payouts can be synced if they weren’t before.
- **Not synced:** We call `do_sync_refund/1`, which:
  1. Marks status `"pending"` via `update_sync_status_refund/3`.
  2. Runs the pipeline:
     - `get_payment(refund.payment_id)` → `{:error, :payment_not_found}` if payment missing.
     - `get_customer_id_for_payment(payment)` → uses system customer when user not found (same as payments).
     - `get_payment_entity_info(payment)` → entity type and class for item/class.
     - `get_quickbooks_item_id(entity_info)` → same item as original sale for correct revenue reversal.
     - `create_refund_sales_receipt/4` → builds params and calls `Quickbooks.create_refund_receipt/2` with idempotency key.
  3. On success: `update_sync_success_refund/3`, then `check_and_enqueue_payout_syncs_for_refund/1`.
  4. On failure: `update_sync_failure_refund/2` with reason, error logged with Sentry tags.

**Schema:** `Refund` has `validate_required([..., :payment_id])`, so every refund has a payment; no need to support nil `payment_id` in sync.

---

## 2. QuickBooks entity and API

- We create a **RefundReceipt** (not a negative SalesReceipt). Correct for refunds in QBO.
- **Amounts:** RefundReceipts use **positive** amounts; we pass `Money.to_decimal(refund.amount)` (positive). Client and context use `Decimal.abs` / positive totals where needed. Correct.
- **DepositToAccountRef:** We resolve “Undeposited Funds” and pass it as `refund_from_account_ref`; the context maps this to the client’s `refund_from_account_ref` and the client sends it as `DepositToAccountRef`. Correct.
- **CustomerRef:** From `get_customer_id_for_payment(payment)`, so system customer is used when the payment’s user is missing. Correct.
- **ClassRef:** We resolve class from entity (e.g. event/donation/booking) and fall back to “Administration”. Required for exports; we always set it. Correct.
- **Traceability:** We put original payment’s QuickBooks SalesReceipt ID in `PrivateNote` when available (QB doesn’t support formal RefundReceipt→SalesReceipt linking). Good for audit.

---

## 3. Idempotency and retries

- **Idempotency key:** We pass `idempotency_key: qb_idempotency_key("rr_ref", refund)` into `Quickbooks.create_refund_receipt/2`. Client uses it as `requestid` in the URL (truncated to 255 chars). Retries/duplicate calls with the same key should not create a second RefundReceipt.
- **Already synced:** We never call the API when `quickbooks_sync_status == "synced"` and `quickbooks_sales_receipt_id` is present; we return the stored ID. So we don’t double-create from our side.
- **429 rate limit:** After this audit, `create_refund_receipt` in the client was wrapped with `request_with_429_retry/1` so RefundReceipt creation is retried on 429, consistent with deposit and item creation.

---

## 4. Payout (Deposit) inclusion

- **When building payout deposit line items:** We only include refunds where `quickbooks_sync_status == "synced"` and `quickbooks_sales_receipt_id` is set. Unsynced refunds are skipped (and we don’t block the payout; the payout just doesn’t include them until they’re synced).
- **Amount:** We use **negative** amount for refund lines in the deposit (`Decimal.negate(amount)`). Correct for “money out” in the deposit.
- **LinkedTxn:** We set `linked_txn: [%{txn_id: refund.quickbooks_sales_receipt_id, txn_type: "RefundReceipt"}]` so the Deposit line links to the RefundReceipt. Required by QB for proper matching. Correct.
- **Order:** Payout sync requires all linked payments and refunds to be synced first; we verify that in `do_sync_payout` and fail with a clear error if not.

---

## 5. Status and error handling

- **Pending:** Set at start of `do_sync_refund` so UI can show “in progress”.
- **Success:** We set `quickbooks_sales_receipt_id`, `quickbooks_sync_status: "synced"`, `quickbooks_synced_at`, `quickbooks_response`, `quickbooks_last_sync_attempt_at`. After this audit we also set `quickbooks_sync_error: nil` on success so a previous failure doesn’t keep showing.
- **Failure:** We set `quickbooks_sync_status: "failed"`, `quickbooks_sync_error: %{error: ..., timestamp: ...}`, `quickbooks_last_sync_attempt_at`. We do not clear `quickbooks_sales_receipt_id` (there isn’t one on failure). Retrying sync runs the pipeline again and can overwrite with success.

---

## 6. Edge cases

| Case | Handling |
|------|----------|
| Payment not found | `get_payment` returns `{:error, :payment_not_found}`; pipeline fails; refund marked failed. |
| User not found for payment | `get_customer_id_for_payment` uses system customer if configured; otherwise `{:error, :user_not_found}` and refund fails. |
| Undeposited Funds account missing | We log and fall back to a default ID so the request is still sent; QB may reject. We always set some account. |
| Class not found | Fall back to “Administration” so we always send a class. |
| Original payment not synced to QB | We still create the RefundReceipt; PrivateNote only has external refund ID (no “Original Payment SalesReceipt”). |
| Refund in payout but refund not synced | Payout sync fails until all linked payments/refunds are synced; refund line is skipped when building deposit lines until that refund is synced. |

---

## 7. Files touched

- **Sync:** `lib/ysc/quickbooks/sync.ex` — `do_sync_refund`, `create_refund_sales_receipt`, `build_payout_line_items` (refund lines), `update_sync_*_refund`, `check_and_enqueue_payout_syncs_for_refund`.
- **Client:** `lib/ysc/quickbooks/client.ex` — `create_refund_receipt`, `build_refund_receipt_body`.
- **Context:** `lib/ysc/quickbooks.ex` — `create_refund_receipt` (builds params and calls client).

---

## 8. Improvements applied during audit

1. **Clear `quickbooks_sync_error` on refund sync success**  
   In `update_sync_success_refund/3`, we now set `quickbooks_sync_error: nil` so a successful retry doesn’t leave the old error on the record.

2. **429 retry for RefundReceipt creation**  
   In `Ysc.Quickbooks.Client.create_refund_receipt/2`, the HTTP request is wrapped in `request_with_429_retry/1` so rate limits result in retries with backoff instead of an immediate failure.
