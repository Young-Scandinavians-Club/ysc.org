# Reconciliation Process Audit

**Date:** 2026-02-02
**Files Audited:**

- `lib/ysc/ledgers/reconciliation_worker.ex` (264 lines)
- `lib/ysc/ledgers/reconciliation.ex` (936 lines)

## Executive Summary

The reconciliation system provides comprehensive financial integrity checks across payments, refunds, and ledger entries. While the overall architecture is solid, **4 critical issues** and several design concerns were identified that could lead to incorrect reconciliation results or system crashes.

---

## Critical Issues ⚠️

### 1. Fragile Refund Detection Logic (HIGH SEVERITY)

**Location:** `reconciliation.ex:362-363`

**Issue:**

```elixir
refund_entries = Enum.filter(entries, fn entry ->
  entry.description =~ "Refund" || entry.description =~ "refund"
end)
```

**Problem:**

- Relies on text matching in the `description` field to identify refunds
- Case-sensitive for lowercase "refund" but not uppercase variations
- Will fail if descriptions use different wording ("returned", "reversal", etc.)
- No validation that the refund amount matches
- Could incorrectly match entries with "Refund" in description that aren't actual refunds

**Impact:** Refund reconciliation will report false negatives (missing refunds that exist)

**Recommendation:**

```elixir
# Use refund_id or transaction type instead
refund_transactions =
  from(t in LedgerTransaction,
    where: t.payment_id == ^refund.payment_id,
    where: t.refund_id == ^refund.id,
    where: t.type == :refund
  )
  |> Repo.all()

refund_entries =
  from(e in LedgerEntry,
    where: e.payment_id == ^refund.payment_id,
    join: t in LedgerTransaction, on: t.id == e.transaction_id,
    where: t.refund_id == ^refund.id
  )
  |> Repo.all()
```

---

### 2. No Error Handling for Reconciliation Failures (HIGH SEVERITY)

**Location:** `reconciliation_worker.ex:36, 46`

**Issue:**

```elixir
def perform(%Oban.Job{}) do
  Logger.info("Starting scheduled financial reconciliation")
  {:ok, report} = Reconciliation.run_full_reconciliation()  # ⚠️ Will crash if {:error, ...}
  handle_reconciliation_results(report)
end
```

**Problem:**

- Pattern matches on `{:ok, report}` only
- If `run_full_reconciliation/0` returns `{:error, reason}`, worker crashes
- No database connection error handling
- No timeout handling for long-running reconciliation

**Impact:** Worker crashes prevent reconciliation from running, no alerts sent

**Recommendation:**

```elixir
def perform(%Oban.Job{}) do
  Logger.info("Starting scheduled financial reconciliation")

  case Reconciliation.run_full_reconciliation() do
    {:ok, report} ->
      handle_reconciliation_results(report)

    {:error, reason} ->
      Logger.error("Reconciliation failed to run", error: reason)
      Discord.send_reconciliation_failure_alert(reason)
      {:error, reason}  # Let Oban retry
  end
end
```

---

### 3. Worker Returns :ok for Errors (MEDIUM SEVERITY)

**Location:** `reconciliation_worker.ex:75-77`

**Issue:**

```elixir
:error ->
  alert_on_discrepancies(report)
  {:ok, report}  # ⚠️ Returns :ok even when discrepancies found
```

**Problem:**

- Reconciliation with discrepancies returns `{:ok, report}` instead of `{:error, ...}`
- Oban won't retry if discrepancies are transient (e.g., race conditions)
- Prevents using Oban's backoff/retry logic for resolving temporary issues

**Impact:** Transient reconciliation failures aren't automatically retried

**Discussion:**
This may be intentional design - discrepancies need human investigation, not automatic retries. However, should be documented.

**Recommendation:**

```elixir
# Option 1: Keep as-is but document
:error ->
  alert_on_discrepancies(report)
  # Return :ok because discrepancies require manual investigation
  # Retrying won't resolve data issues
  {:ok, report}

# Option 2: Add severity levels
:error ->
  if critical_error?(report) do
    # Retry critical errors (e.g., DB issues, race conditions)
    {:error, report}
  else
    # Don't retry data discrepancies
    alert_on_discrepancies(report)
    {:ok, report}
  end
```

---

### 4. Silent Failures in Entry Total Calculation (MEDIUM SEVERITY)

**Location:** `reconciliation.ex:397-419`

**Issue:**

```elixir
case debit_credit do
  "debit" -> ...
  "credit" -> ...
  _ -> acc  # ⚠️ Silently ignores unexpected values
end
```

**Problem:**

- If `debit_credit` is `nil`, malformed, or an unexpected enum value, it's silently ignored
- Entry amounts are excluded from totals without warning
- Could mask data corruption or schema migration issues

**Impact:** Incorrect reconciliation totals, false positives (reports match when they don't)

**Recommendation:**

```elixir
case debit_credit do
  "debit" ->
    {:ok, sum} = Money.add(acc, entry.amount)
    sum

  "credit" ->
    {:ok, sum} = Money.sub(acc, entry.amount)
    sum

  other ->
    Logger.error("Invalid debit_credit value in ledger entry",
      entry_id: entry.id,
      value: other
    )
    # Report to Sentry
    Sentry.capture_message("Invalid debit_credit in reconciliation")
    acc  # Still skip but with alert
end
```

---

## Design Issues 🔧

### 5. No Transaction Isolation

**Location:** Throughout `reconciliation.ex`

**Issue:**

- Reconciliation runs multiple queries without database transaction
- Data can change between payment check and ledger check
- Race conditions during high transaction volume

**Impact:** Inconsistent reconciliation results, false positives/negatives

**Recommendation:**

```elixir
def run_full_reconciliation do
  Repo.transaction(fn ->
    # Run all checks in transaction with REPEATABLE READ isolation
    payment_check = reconcile_payments()
    refund_check = reconcile_refunds()
    # ... rest of checks
  end, timeout: :infinity)
end
```

---

### 6. Memory Scalability Concerns

**Location:** `reconciliation.ex:110, 161`

**Issue:**

```elixir
# Loads ALL payments/refunds into memory
payments = Repo.all(Payment)
refunds = Repo.all(Refund)
```

**Problem:**

- No pagination or streaming
- Large datasets (10K+ payments) could cause memory issues
- Could cause worker timeout

**Impact:** Worker crashes or timeouts on large datasets

**Recommendation:**

```elixir
# Use streaming for large datasets
def reconcile_payments do
  discrepancies =
    Payment
    |> Repo.stream()
    |> Stream.chunk_every(100)
    |> Enum.reduce([], fn payment_batch, acc ->
      batch_discrepancies =
        Enum.reduce(payment_batch, [], fn payment, inner_acc ->
          case check_payment_consistency(payment) do
            {:ok, _} -> inner_acc
            {:error, issues} ->
              [%{payment_id: payment.id, issues: issues} | inner_acc]
          end
        end)

      acc ++ batch_discrepancies
    end)

  # Or better: add streaming support to check_payment_consistency
end
```

---

### 7. Entity Type Mismatch Risk

**Location:** `reconciliation.ex:537, 570, 596`

**Issue:**

```elixir
where: e.related_entity_type == :membership  # Atom comparison
```

**Problem:**

- Assumes `related_entity_type` is stored as atom
- Could be string in database (e.g., "membership")
- Depends on EctoEnum configuration

**Impact:** Entity reconciliation reports mismatches when data is correct

**Recommendation:**

```elixir
# Explicitly handle both atom and string
where: e.related_entity_type in [:membership, "membership"]

# Or ensure EctoEnum is configured consistently
```

---

### 8. Fragile Money Type Assumptions

**Location:** `reconciliation.ex:433, 452, 524, etc.`

**Issue:**

```elixir
select: sum(fragment("(?.amount).amount", e))
```

**Problem:**

- Assumes Money is stored as composite type `(amount, currency)`
- Fragile to Money library version changes
- Could break with database schema changes

**Recommendation:**

```elixir
# Use Ecto type casting instead of raw fragments
# Or add migration safety checks
```

---

### 9. Missing Orphaned Refund Entry Detection

**Location:** `reconciliation.ex:461-477`

**Issue:**

- Only checks for orphaned payment entries
- Doesn't check for ledger entries with invalid `refund_id`
- Refund entries are detected via payment_id, not directly

**Impact:** Won't detect orphaned refund-specific entries

**Recommendation:**

```elixir
defp find_orphaned_refund_entries do
  query =
    from(e in LedgerEntry,
      left_join: r in Refund,
      on: e.refund_id == r.id,
      where: not is_nil(e.refund_id),
      where: is_nil(r.id),
      select: %{
        entry_id: e.id,
        refund_id: e.refund_id,
        amount: e.amount,
        description: e.description
      }
    )

  Repo.all(query)
end
```

---

## Medium Issues ⚡

### 10. Logger.critical Doesn't Stop Execution

**Location:** `reconciliation_worker.ex:82`

**Issue:**

- Uses `Logger.critical` for financial discrepancies
- Continues execution instead of escalating
- No PagerDuty/on-call integration

**Recommendation:** Add critical alert escalation for financial issues

---

### 11. Alert Truncation Without Warning

**Location:** `reconciliation_worker.ex:222, 231`

**Issue:**

```elixir
|> Enum.take(5)  # Only shows first 5
```

**Problem:**

- Limits to 5 discrepancies without indicating total count
- Could miss severity if worst issues are #6-10

**Recommendation:**

```elixir
|> Enum.take(5)
# Add: "(showing 5 of #{total_count})"
```

---

### 12. No Rate Limiting on Discord Alerts

**Issue:**

- Could spam Discord if reconciliation runs frequently
- No deduplication of alerts

**Recommendation:** Add rate limiting or alert deduplication

---

### 13. IO.puts in Production Code

**Location:** `reconciliation_worker.ex:48`

**Issue:**

```elixir
IO.puts(Reconciliation.format_report(report))
```

**Problem:**

- `IO.puts` doesn't work well in production (no logging infrastructure)
- Output lost in production environments

**Recommendation:** Use Logger or return formatted report

---

### 14. No Reconciliation Timeout Configuration

**Issue:**

- No timeout for long-running reconciliation
- Could block worker queue indefinitely

**Recommendation:** Add configurable timeout (e.g., 5 minutes)

---

## Testing Gaps 🧪

1. **No tests exist** for reconciliation worker (0% coverage)
2. Missing test coverage for:
   - Error handling paths
   - Discord alert formatting
   - Large dataset performance
   - Race condition scenarios
   - Refund detection edge cases
   - Money arithmetic edge cases
   - Orphaned entry detection

---

## Positive Findings ✅

1. **Comprehensive coverage** of reconciliation scenarios
2. **Good separation of concerns** (worker vs. logic)
3. **Detailed Sentry reporting** with context
4. **Telemetry events** for monitoring
5. **Human-readable reports** via `format_report/1`
6. **Multiple reconciliation dimensions** (payments, refunds, entities, balance)

---

## Recommendations Summary

### Immediate (High Priority)

1. ✅ Fix refund detection logic (use refund_id, not string matching)
2. ✅ Add error handling to worker perform/1 and run_now/0
3. ✅ Add explicit error logging for invalid debit_credit values
4. ✅ Document worker return value behavior (:ok for errors)

### Short Term (Medium Priority)

1. Add transaction isolation to reconciliation
2. Add pagination/streaming for large datasets
3. Add orphaned refund entry detection
4. Replace IO.puts with Logger
5. Add reconciliation timeout configuration

### Long Term (Nice to Have)

1. Add rate limiting to Discord alerts
2. Add critical alert escalation (PagerDuty)
3. Add deduplication for repeated alerts
4. Consider separating critical vs. transient errors for Oban retry logic
5. Add performance benchmarks for large datasets

---

## Test Coverage Recommendations

Create tests for:

1. Worker behavior (Oban.Job execution, logging, Discord alerts)
2. Error handling (database failures, timeout)
3. Alert formatting (with various discrepancy types)
4. Edge cases (empty datasets, large datasets, race conditions)
5. Refund detection (various description formats)

**Estimated Tests:** 15-20 tests
**Expected Coverage:** 60-70% (some paths require complex setup)
