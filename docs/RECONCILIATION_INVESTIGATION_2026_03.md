# Reconciliation Investigation – Bookings & Events Failing

**Date:** 2026-03-04  
**Report:** Entity Totals show Bookings ❌ and Events ❌; Payments, Refunds, Memberships, Donations ✅

## Summary

- **Refunds and memberships (including account upgrades)** are **not** the cause. The report shows Refunds ✅ and Memberships ✅; reconciliation logic for both is correct.
- **Events ❌** is explained by the **known limitation** (mixed event+donation payments). No bug in recon logic.
- **Bookings ❌** has no obvious bug in code; likely causes are data (e.g. wrong `related_entity_type` on some entries) or environment-specific behaviour. The report now includes **ledger vs payment totals** when entity totals fail so you can compare amounts and investigate.

## 1. Refunds and memberships

- **Payments** and **Refunds** checks compare totals in the `payments` / `refunds` tables with ledger totals; both pass, so refund counting is correct.
- **Memberships** compare:
  - **Ledger:** `membership_revenue` account (credits − debits).
  - **Stripe:** `stripe_account` entries with `related_entity_type == :membership` (debits − credits).
- Account upgrades are just membership payments; they create the same ledger shape (stripe debit :membership, credit to membership_revenue). So membership reconciliation and upgrade handling are correct.

## 2. Events ❌ – known limitation (mixed event+donation)

For **mixed event+donation** (and event+donation+discount) payments:

- **One** `stripe_account` debit is created with `related_entity_type: :event` for the **full** amount (e.g. $150).
- Revenue is split:
  - `event_revenue`: event portion only (e.g. $100).
  - `donation_revenue`: donation portion (e.g. $50).

So:

- **Event reconciliation** compares:
  - Ledger: `event_revenue` net (e.g. $100).
  - Stripe: all `:event` debits − credits (e.g. $150).
- These **will not match** whenever there are mixed payments. This is a **ledger design choice**, not a bug in reconciliation. The overall ledger still balances.

See `docs/RECONCILIATION_FIX_2026_02_15.md` for the original fix and known limitations.

## 3. Bookings ❌ – no bug found in reconciliation logic

Booking reconciliation:

- **Ledger:** `tahoe_booking_revenue` + `clear_lake_booking_revenue` (each: credits − debits).
- **Stripe:** `stripe_account` entries with `related_entity_type == :booking` (debits − credits).

In code:

- Bookings use `create_payment_entries` with a single entity type and property; there is no mixed booking/donation flow.
- Stripe fee entries use `related_entity_type: :administration`, so they do not affect booking totals.
- Refunds use the same `related_entity_type` as the original revenue entry, so booking refunds stay in `:booking`.

So the **logic** is consistent. A real mismatch can still occur if:

- Some ledger entries have the wrong `related_entity_type` or wrong revenue account (e.g. from a migration or manual change).
- Some booking payment or refund was recorded via a different or legacy path that doesn’t match the above.

To investigate:

- Use the **new diagnostic output**: when entity totals fail, the report (and Discord) now show **ledger total vs stripe/payment total** for each failing entity (e.g. Bookings: ledger $X vs $Y). That will show whether the gap is small (rounding/data) or large (structural).
- Optionally run a one-off query to list `stripe_account` entries with `related_entity_type == :booking` and compare counts/amounts to booking revenue entries.

## 4. Changes made

1. **`lib/ysc/ledgers/reconciliation.ex`**
   - **Moduledoc:** Added a short “Entity totals – known limitation (Events)” section describing why Events can show FAIL with mixed event+donation payments.
   - **`format_report/1`:** When an entity total does not match, the report now includes a line per failing entity with ledger total vs stripe/payment total (e.g. `Bookings ledger: $X vs stripe/payment: $Y`).
   - **`format_entity_detail/2`:** New helper to format that line only when `match` is false.

2. **`lib/ysc/alerts/discord.ex`**
   - **Entity Totals field:** When an entity (Bookings, Events, Donations) fails, the Discord message now appends the same amounts (e.g. `(ledger: $X vs $Y)`).
   - **Note when Events fail:** Added a short note that “Events ❌ can be due to mixed event+donation payments” and reference to `RECONCILIATION_FIX_2026_02_15.md`.

3. **`docs/RECONCILIATION_INVESTIGATION_2026_03.md`**
   - This investigation summary.

## 5. What to do next

- **Events:** Treat as expected when you have mixed event+donation payments. Use the new note in the report/Discord to avoid treating it as a bug. If you want Events to pass despite mixed payments, the ledger would need to record split stripe receivables by type (e.g. separate :event and :donation debits for the same payment); that would be a design change, not a recon fix.
- **Bookings:** From the next reconciliation report (or Discord), read the **Bookings** line with the two amounts. If the difference is small, consider rounding or one-off data fixes. If it’s large, use it to track down which payments or entries are off (e.g. by comparing to a query over `ledger_entries` and `stripe_account` + `related_entity_type == :booking`).
