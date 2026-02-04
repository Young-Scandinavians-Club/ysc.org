# Ledger Logic Audit

**Date:** 2026-02-02
**Files Audited:**

- `lib/ysc/ledgers.ex` (3,511 lines)
- `lib/ysc/ledgers/reconciliation.ex` (936 lines)
- `lib/ysc/ledgers/reconciliation_worker.ex` (264 lines)

**Related:** See `RECONCILIATION_AUDIT.md` for reconciliation-specific issues

## Executive Summary

The ledgering system implements double-entry bookkeeping for financial transactions. While the overall architecture follows accounting principles, **6 critical issues** and several design concerns were identified that could lead to data inconsistencies, production crashes, or incorrect financial reporting.

**Severity Breakdown:**

- 🔴 **Critical**: 6 issues (immediate attention required)
- 🟠 **High**: 4 issues (should fix soon)
- 🟡 **Medium**: 5 issues (should address)
- 🟢 **Low**: 3 issues (nice to have)

---

## Critical Issues 🔴

### 1. Double-Credit to Stripe Account in Refunds (CRITICAL SEVERITY)

**Location:** `ledgers.ex:1442-1476`

**Issue:**

```elixir
# Entry 1: Debit Refund Expense (line 1413-1422)
# Entry 2: Credit Stripe Account (line 1427-1436)
# Entry 3a: Debit Revenue (line 1449-1458)
# Entry 3b: Credit Stripe Account AGAIN (line 1461-1471) ⚠️
```

**Problem:**

- Refund logic credits `stripe_account` twice for the same refund
- Comments (lines 1442-1446) explain this is intentional, but accounting logic is suspicious
- For a $100 refund:
  - Debit Refund Expense: $100
  - Credit Stripe Account: $100 (for refund)
  - Debit Revenue: $100
  - Credit Stripe Account: $100 (for revenue reversal)
  - **Result:** Stripe account is reduced by $200, not $100!

**Impact:** Stripe account balance incorrectly shows double the refund amount as reduction

**Accounting Analysis:**
Correct refund accounting should be:

1. **Debit Revenue** ($100) - reverses the original revenue
2. **Credit Stripe Account** ($100) - reduces the receivable

OR:

1. **Debit Refund Expense** ($100) - expense for the refund
2. **Credit Stripe Account** ($100) - reduces the receivable

But NOT both patterns combined! The current code:

- Debits both Revenue AND Refund Expense (double the expense)
- Credits Stripe Account twice (double the receivable reduction)

**Recommendation:**

```elixir
# Choose ONE approach:

# Option A: Expense-based (simpler, doesn't reverse original revenue)
def create_refund_entries_expense_based(attrs) do
  # 1. Debit Refund Expense
  {:ok, refund_expense_entry} = create_entry(%{
    account_id: refund_expense_account.id,
    amount: refund_amount,
    debit_credit: :debit
  })

  # 2. Credit Stripe Account (only once!)
  {:ok, stripe_credit_entry} = create_entry(%{
    account_id: stripe_account.id,
    amount: refund_amount,
    debit_credit: :credit
  })

  [refund_expense_entry, stripe_credit_entry]
end

# Option B: Revenue reversal (more accurate, shows in financial reports)
def create_refund_entries_revenue_reversal(attrs) do
  # Find original revenue entry
  revenue_entry = find_revenue_entry(payment_id)

  # 1. Debit Revenue (reverses original revenue)
  {:ok, revenue_reversal} = create_entry(%{
    account_id: revenue_entry.account_id,
    amount: refund_amount,
    debit_credit: :debit
  })

  # 2. Credit Stripe Account (only once!)
  {:ok, stripe_credit_entry} = create_entry(%{
    account_id: stripe_account.id,
    amount: refund_amount,
    debit_credit: :credit
  })

  [revenue_reversal, stripe_credit_entry]
end
```

**Action Required:** URGENT - Review with accounting team and fix immediately

---

### 2. No Transaction Wrapping in Entry Creation (CRITICAL SEVERITY)

**Location:** `ledgers.ex:582-718, 726-989, 1390-1479`

**Issue:**

```elixir
def create_payment_entries(attrs) do
  # Creates multiple entries without transaction
  {:ok, stripe_receivable_entry} = create_entry(%{...})  # Line 653
  {:ok, revenue_entry} = create_entry(%{...})            # Line 667
  {:ok, fee_expense_entry} = create_entry(%{...})        # Line 687
  {:ok, stripe_fee_deduction_entry} = create_entry(%{...}) # Line 700

  entries  # Returns list without ensuring atomicity
end
```

**Problem:**

- If entry #3 fails, entries #1 and #2 are already committed
- Ledger left in imbalanced state (partial transaction)
- No rollback mechanism

**Impact:**

- Data corruption possible
- Reconciliation will detect imbalance but can't auto-fix
- Manual cleanup required

**Current Mitigations:**

- `process_stripe_payout/1` (line 1511) DOES use `Repo.transaction`
- But most entry creation functions don't

**Recommendation:**

```elixir
def create_payment_entries(attrs) do
  Repo.transaction(fn ->
    # All entry creation here
    {:ok, stripe_receivable_entry} = create_entry(%{...})
    {:ok, revenue_entry} = create_entry(%{...})
    # ... more entries

    entries
  end)
end

# OR wrap at a higher level:
def process_payment(attrs) do
  Repo.transaction(fn ->
    {:ok, payment} = create_payment(attrs)
    {:ok, transaction} = create_transaction(attrs)
    entries = create_payment_entries(attrs)

    {payment, transaction, entries}
  end)
end
```

---

### 3. Nil Account Handling Missing (CRITICAL SEVERITY)

**Location:** `ledgers.ex:649-650, 684-685, 1409-1410`

**Issue:**

```elixir
revenue_account = get_account_by_name(revenue_account_name)  # Could be nil!
stripe_account = get_account_by_name("stripe_account")        # Could be nil!

# Immediately uses account.id without checking nil
create_entry(%{
  account_id: revenue_account.id,  # ⚠️ Crashes if revenue_account is nil
  ...
})
```

**Problem:**

- `get_account_by_name/1` returns `nil` if account doesn't exist
- No nil check before accessing `.id`
- Will crash with "cannot access field :id of nil"

**Impact:** Production crashes when accounts aren't initialized

**Recommendation:**

```elixir
# Option A: Add nil checks
revenue_account = get_account_by_name(revenue_account_name)

unless revenue_account do
  raise "Revenue account '#{revenue_account_name}' not found. Run ensure_basic_accounts/0"
end

# Option B: Use get! pattern
def get_account_by_name!(name) do
  case get_account_by_name(name) do
    nil -> raise "Account '#{name}' not found"
    account -> account
  end
end

# Option C: Call ensure_basic_accounts first
def create_payment_entries(attrs) do
  ensure_basic_accounts()  # Ensure accounts exist

  revenue_account = get_account_by_name(revenue_account_name)
  # ...
end
```

---

### 4. Raises Exception Instead of Error Tuple (CRITICAL SEVERITY)

**Location:** `ledgers.ex:615-640`

**Issue:**

```elixir
:booking ->
  case property do
    :tahoe -> "tahoe_booking_revenue"
    :clear_lake -> "clear_lake_booking_revenue"
    _ ->
      # Logs, reports to Sentry, then raises
      raise error_message  # ⚠️ Crashes instead of returning error
  end
```

**Problem:**

- Violates "let it crash" philosophy incorrectly
- Crashes entire process instead of returning `{:error, reason}`
- Caller can't handle error gracefully
- Crashes in production instead of showing user error message

**Impact:** User sees 500 error instead of helpful validation message

**Recommendation:**

```elixir
def create_payment_entries(attrs) do
  case validate_payment_attrs(attrs) do
    :ok ->
      # Create entries
      {:ok, entries}

    {:error, reason} ->
      {:error, reason}
  end
end

defp validate_payment_attrs(attrs) do
  if attrs.entity_type == :booking && attrs.property not in [:tahoe, :clear_lake] do
    {:error, :invalid_property}
  else
    :ok
  end
end
```

---

### 5. Fragment Queries Fragile to Money Structure (HIGH SEVERITY)

**Location:** `ledgers.ex:3334, 3343` (and in `reconciliation.ex`)

**Issue:**

```elixir
# Assumes Money is stored as composite type (amount, currency)
select: sum(fragment("(?.amount).amount", e))
```

**Problem:**

- Directly accesses PostgreSQL composite type structure
- Fragile to Money library version changes
- Fragile to database schema changes
- No type safety

**Impact:**

- Breaks if Money storage format changes
- Silent errors if structure mismatch
- Hard to debug

**Recommendation:**

```elixir
# Use Ecto types instead of fragments
select: sum(type(e.amount, Money.Ecto.Composite.Type))

# Or use Money library helpers
def calculate_total_debits do
  entries = Repo.all(from e in LedgerEntry, where: e.debit_credit == "debit")

  Enum.reduce(entries, Money.new(0, :USD), fn entry, acc ->
    {:ok, sum} = Money.add(acc, entry.amount)
    sum
  end)
end
```

---

### 6. Race Conditions in Account Creation (MEDIUM-HIGH SEVERITY)

**Location:** `ledgers.ex:71-86`

**Issue:**

```elixir
def ensure_basic_accounts do
  Enum.each(@basic_accounts, fn {name, type, normal_balance, description} ->
    case get_account_by_name(name) do
      nil ->
        create_account(%{...})  # ⚠️ Not atomic!
      _account ->
        :ok
    end
  end)
end
```

**Problem:**

- Check-then-create pattern (race condition)
- Two processes could both see `nil` and both try to create
- Second create fails with unique constraint violation

**Impact:**

- Production errors during concurrent initialization
- Can cause startup failures

**Recommendation:**

```elixir
def ensure_basic_accounts do
  Enum.each(@basic_accounts, fn {name, type, normal_balance, description} ->
    # Use INSERT ... ON CONFLICT DO NOTHING
    %LedgerAccount{}
    |> LedgerAccount.changeset(%{
      name: name,
      account_type: type,
      normal_balance: normal_balance,
      description: description
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: :name)
  end)
end
```

---

## High Priority Issues 🟠

### 7. No Validation of Entry Amounts (HIGH SEVERITY)

**Location:** `ledgers.ex:991-1012` (create_entry)

**Issue:**

- No validation that amounts are positive
- No validation that currency matches
- Could create negative entries

**Recommendation:**

```elixir
def create_entry(attrs) do
  attrs
  |> validate_entry_amount()
  |> case do
    {:ok, validated_attrs} ->
      %LedgerEntry{}
      |> LedgerEntry.changeset(validated_attrs)
      |> Repo.insert()

    {:error, reason} ->
      {:error, reason}
  end
end

defp validate_entry_amount(attrs) do
  amount = attrs[:amount]

  cond do
    is_nil(amount) ->
      {:error, :amount_required}

    Money.negative?(amount) ->
      {:error, :negative_amount}

    amount.currency != :USD ->
      {:error, :invalid_currency}

    true ->
      {:ok, attrs}
  end
end
```

---

### 8. No Index on Payment_ID for Ledger Entries

**Location:** Database schema (referenced in queries throughout)

**Issue:**

- Queries frequently filter by `payment_id` (lines 1400, 358, etc.)
- No mention of index in schema files reviewed
- Could cause slow queries at scale

**Recommendation:**

```elixir
# Add migration
create index(:ledger_entries, [:payment_id])
create index(:ledger_entries, [:account_id])
create index(:ledger_entries, [:debit_credit])
```

---

### 9. Refund Entry Detection by String Matching (HIGH SEVERITY)

**Location:** `reconciliation.ex:362-363` (covered in RECONCILIATION_AUDIT.md)

**Issue:**

```elixir
refund_entries = Enum.filter(entries, fn entry ->
  entry.description =~ "Refund" || entry.description =~ "refund"
end)
```

**Problem:** Already covered in reconciliation audit - repeated here for completeness

---

## Medium Priority Issues 🟡

### 11. Mixed String/Atom for Enum Values

**Location:** Throughout (e.g., lines 1405-1406, debit_credit handling)

**Issue:**

```elixir
# Sometimes comparing atoms
entry.debit_credit == :debit

# Sometimes converting to string
to_string(entry.debit_credit) == "debit"
```

**Problem:**

- Inconsistent handling of EctoEnum values
- Can lead to logic errors

**Recommendation:**

- Use atoms consistently
- Or use strings consistently
- Document the pattern

---

### 12. No Logging for Entry Creation

**Issue:**

- Entry creation has no audit logging
- Can't trace who created/modified entries
- No timestamp of entry modifications

**Recommendation:**

```elixir
# Add audit fields
alter table(:ledger_entries) do
  add :created_by, :string
  add :modified_by, :string
end

# Log entry creation
def create_entry(attrs) do
  # ...existing code...
  Logger.info("Created ledger entry",
    entry_id: entry.id,
    account: account.name,
    amount: Money.to_string!(attrs.amount),
    debit_credit: attrs.debit_credit
  )
end
```

---

### 13. Stripe Fee Calculation Not Verified

**Location:** `ledgers.ex:680-715`

**Issue:**

- Accepts `stripe_fee` from caller without verification
- No check that fee matches actual Stripe fee formula
- Could record incorrect fees

**Recommendation:**

```elixir
def verify_stripe_fee(amount, provided_fee) do
  # Stripe charges 2.9% + $0.30 for US cards
  expected_fee_cents = (amount.amount * 0.029) + 30
  expected_fee = Money.new(round(expected_fee_cents), :USD)

  if Money.equal?(provided_fee, expected_fee) do
    :ok
  else
    Logger.warning("Stripe fee mismatch",
      provided: Money.to_string!(provided_fee),
      expected: Money.to_string!(expected_fee)
    )
    {:error, :fee_mismatch}
  end
end
```

---

### 14. No Maximum Transaction Amount

**Issue:**

- No upper limit on transaction amounts
- Could accidentally process multi-million dollar transactions
- No sanity checks

**Recommendation:**

```elixir
@max_transaction_amount Money.new(1_000_000_00, :USD)  # $1M

defp validate_transaction_amount(amount) do
  if Money.compare(amount, @max_transaction_amount) == :gt do
    {:error, :amount_exceeds_maximum}
  else
    :ok
  end
end
```

---

### 15. Revenue Entry Lookup Can Fail Silently

**Location:** `ledgers.ex:1402-1407`

**Issue:**

```elixir
revenue_entry = Enum.find(original_entries, fn entry ->
  to_string(entry.account.account_type) == "revenue" &&
    to_string(entry.debit_credit) == "credit"
end)

# Later (line 1447):
if revenue_entry do
  # Create revenue reversal
else
  # Silently skip revenue reversal ⚠️
  entries
end
```

**Problem:**

- If original payment had no revenue entry (data corruption), refund silently skips revenue reversal
- Masks data integrity issues
- Should be an error

**Recommendation:**

```elixir
revenue_entry = find_revenue_entry(original_entries)

case revenue_entry do
  nil ->
    Logger.error("Revenue entry not found for refund",
      payment_id: payment.id
    )
    Sentry.capture_message("Missing revenue entry for refund")
    {:error, :revenue_entry_not_found}

  entry ->
    # Create reversal entries
    {:ok, entries}
end
```

---

## Low Priority Issues 🟢

### 16. Enum.each Instead of Enum.map in ensure_basic_accounts

**Location:** `ledgers.ex:72`

**Issue:**

- Uses `Enum.each` but creates side effects
- Returns `:ok` instead of results

**Recommendation:** Use `Enum.map` and return results for testing

---

### 17. No Currency Validation

**Issue:**

- System assumes USD everywhere
- No multi-currency support
- Hard-coded `:USD` in multiple places

**Recommendation:** Add currency parameter if international support needed

---

### 18. No Transaction Metadata

**Issue:**

- Entries don't store user agent, IP, or other audit metadata
- Can't trace suspicious transactions

**Recommendation:** Add metadata JSONB column for audit trail

---

## Positive Findings ✅

1. **Good separation of concerns** - Payment, Transaction, and Entry models
2. **Double-entry accounting principles** followed (mostly)
3. **Comprehensive Sentry reporting** for errors
4. **Account type system** properly structured
5. **Normal balance tracking** for proper debit/credit handling
6. **Stripe integration** well-documented

---

## Testing Gaps 🧪

1. **No tests for refund double-credit issue**
2. **No tests for transaction atomicity failures**
3. **No tests for nil account handling**
4. **No tests for concurrent account creation**
5. **No tests for balance verification edge cases**
6. **No tests for Money arithmetic edge cases**

---

## Recommendations Summary

### Immediate (Critical)

1. ✅ **URGENT:** Fix refund double-credit logic (potential financial reporting error)
2. ✅ Add transaction wrapping to all multi-entry functions
3. ✅ Add nil checks for account lookups
4. ✅ Change raises to error tuples in create_payment_entries
5. ✅ Add proper error handling throughout

### Short Term (High Priority)

1. Add amount validation to create_entry
2. Add database indexes for performance
3. Fix refund entry detection (use transaction/entry relationships)

### Medium Term

1. Add comprehensive audit logging
2. Verify Stripe fee calculations
3. Add transaction amount limits
4. Make revenue entry lookup failures explicit errors
5. Add currency validation if needed

### Long Term

1. Multi-currency support if needed
2. Transaction metadata for audit trail
3. Performance optimization for large datasets

---

## Critical Action Items

**For Immediate Review:**

1. **Refund Accounting:** Review lines 1390-1479 with accounting team
2. **Data Integrity Check:** Run reconciliation to verify no existing corruption
3. **Transaction Wrapping:** Add `Repo.transaction` to entry creation functions
4. **Nil Account Guards:** Add validation before accessing account.id

**Testing Priority:**

1. Write tests for refund logic with various scenarios
2. Write tests for transaction rollback
3. Write tests for missing account handling
4. Write integration tests for full payment/refund flow

---

## Risk Assessment

**Financial Risk:** 🔴 HIGH

- Refund double-credit could lead to incorrect financial statements
- Imbalanced ledger from partial transactions
- Incorrect Stripe fee tracking

**Operational Risk:** 🟠 MEDIUM

- Production crashes from nil accounts
- Race conditions in initialization
- Performance issues without indexes

**Compliance Risk:** 🟡 MEDIUM

- Missing metadata for compliance
- Hard to trace transaction history

---

## Conclusion

The ledger system demonstrates solid understanding of double-entry accounting principles but has critical bugs that need immediate attention. The refund double-credit issue (#1) is particularly concerning and should be verified with accounting team and fixed ASAP.

Most issues can be resolved with:

1. Better error handling (return tuples, not raises)
2. Transaction wrapping for atomicity
3. More defensive nil checks
4. Comprehensive testing

Priority should be given to financial accuracy issues before addressing performance or feature enhancements.
