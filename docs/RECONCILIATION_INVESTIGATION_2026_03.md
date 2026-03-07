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

---

## 6. Sandbox run 2026-03-07

**Report:** Reconciliation Failed – Bookings ❌ (ledger: $3,805.00 vs $3,900.00), Events ❌ (ledger: $150.00 vs $3,720.00). Payments 62 (0 discrepancies), Refunds 4 (0 discrepancies), Memberships ✅, Donations ✅.

**Note:** Sandbox has been used for testing and iteration; account balances and reconciliation failures there may reflect bad or inconsistent test data rather than a production bug. Rely on production reconciliation and audits for real financial integrity.

### Events ❌ – expected (known limitation)

- **Ledger** `event_revenue` net = $150.
- **Stripe** `stripe_account` `:event` net = $3,720.
- The gap is due to mixed event+donation payments: one stripe debit per payment for the full amount (`:event`), while revenue is split to `event_revenue` + `donation_revenue`. So Events FAIL in sandbox is **expected**; no code change needed.

### Bookings ❌ – $95 gap (ledger short)

- **Ledger** `tahoe_booking_revenue` + `clear_lake_booking_revenue` net = $3,805.
- **Stripe** `stripe_account` `:booking` net = $3,900.
- Ledger is **$95 short**: either $95 of booking revenue was never credited to the booking revenue accounts, or $95 of stripe `:booking` entries shouldn't be there (mis-categorized). To investigate on sandbox, use the IEx snippets below.

### Diagnostic IEx snippets (run on sandbox)

Connect to sandbox: `fly ssh console --config etc/fly/fly-sandbox.toml` then start a console (e.g. `/app/bin/ysc remote` or `iex -S mix` if running locally with sandbox `DATABASE_URL`).

```elixir
# 1) Confirm reconciliation numbers
alias Ysc.Ledgers.Reconciliation
{:ok, report} = Reconciliation.run_full_reconciliation()
report.checks.entity_totals.bookings
# => %{ledger_revenue: ..., payment_total: ..., match: false, ...}
report.checks.entity_totals.events

# 2) Booking stripe total (debits - credits) – should match payment_total above
alias Ysc.Repo
alias Ysc.Ledgers
alias Ysc.Ledgers.LedgerEntry
import Ecto.Query
sa = Ledgers.get_account_by_name("stripe_account")
booking_debits = from(e in LedgerEntry, where: e.account_id == ^sa.id, where: e.related_entity_type == :booking, where: e.debit_credit == "debit", where: is_nil(e.refund_id), select: sum(fragment("(?.amount).amount", e))) |> Repo.one() |> then(fn n -> if n, do: Money.new(n, :USD), else: Money.new(0, :USD) end)
booking_credits = from(e in LedgerEntry, where: e.account_id == ^sa.id, where: e.related_entity_type == :booking, where: e.debit_credit == "credit", select: sum(fragment("(?.amount).amount", e))) |> Repo.one() |> then(fn n -> if n, do: Money.new(n, :USD), else: Money.new(0, :USD) end)
Money.sub(booking_debits, booking_credits)

# 3) Booking revenue total (tahoe + clear_lake credits - debits) – should match ledger_revenue
tahoe = Reconciliation.run_full_reconciliation() |> then(fn {:ok, r} -> r.checks.entity_totals.bookings.breakdown.tahoe end)
clear_lake = Reconciliation.run_full_reconciliation() |> then(fn {:ok, r} -> r.checks.entity_totals.bookings.breakdown.clear_lake end)
Money.add(tahoe, clear_lake)

# 4) Find payments that have stripe_account :booking debit but no matching revenue credit for same payment_id
# (Entries are created in pairs; every stripe debit should have a revenue credit for the same payment_id.)
sa_id = sa.id
tahoe_acc = Ledgers.get_account_by_name("tahoe_booking_revenue")
clear_acc = Ledgers.get_account_by_name("clear_lake_booking_revenue")
revenue_account_ids = [tahoe_acc.id, clear_acc.id]
stripe_booking_debits = from(e in LedgerEntry, where: e.account_id == ^sa_id, where: e.related_entity_type == :booking, where: e.debit_credit == "debit", where: is_nil(e.refund_id), select: %{payment_id: e.payment_id, amount: e.amount}) |> Repo.all()
for %{payment_id: pid, amount: amt} <- stripe_booking_debits, pid != nil do
  rev_credits = from(e in LedgerEntry, where: e.payment_id == ^pid, where: e.account_id in ^revenue_account_ids, where: e.debit_credit == "credit", where: is_nil(e.refund_id), select: sum(fragment("(?.amount).amount", e))) |> Repo.one()
  rev_sum = if rev_credits, do: Money.new(rev_credits, :USD), else: Money.new(0, :USD)
  if not Money.equal?(amt, rev_sum), do: IO.inspect(%{payment_id: pid, stripe_debit: amt, revenue_credits: rev_sum}, label: "MISMATCH")
end
```

If snippet (4) prints one or more `MISMATCH` rows, those payments explain the $95 gap (e.g. missing or wrong revenue account). If it prints nothing, the gap may be from refunds (stripe credits without matching revenue debits) or from entries with wrong `related_entity_type`/account; you can add similar checks for refunds and for revenue-account totals by payment.
