defmodule Ysc.Ledgers.Reconciliation do
  @moduledoc """
  Reconciliation module to ensure data consistency between business entities
  (payments, refunds, bookings, tickets, subscriptions) and ledger entries.

  This module provides comprehensive checks to verify:
  - All payments have corresponding ledger entries
  - All refunds have corresponding ledger entries
  - Entity totals match ledger totals
  - No orphaned ledger entries exist
  - The ledger is balanced

  ## Usage

      # Run full reconciliation
      {:ok, report} = Reconciliation.run_full_reconciliation()

      # Run specific checks
      {:ok, payment_report} = Reconciliation.reconcile_payments()
      {:ok, refund_report} = Reconciliation.reconcile_refunds()
  """

  import Ecto.Query, warn: false
  alias Ysc.Repo
  alias Ysc.Ledgers
  alias Ysc.Ledgers.{Payment, Refund, LedgerEntry, LedgerTransaction}
  require Logger

  @doc """
  Runs a full reconciliation check across all financial entities.

  Returns a comprehensive report with all findings.
  """
  def run_full_reconciliation do
    Logger.info("Starting full reconciliation process")
    start_time = System.monotonic_time(:millisecond)

    # Run all reconciliation checks
    payment_check = reconcile_payments()
    refund_check = reconcile_refunds()
    ledger_balance_check = check_ledger_balance()
    orphaned_entries_check = check_orphaned_entries()
    entity_totals_check = reconcile_entity_totals()

    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    # Compile overall report
    report = %{
      timestamp: DateTime.utc_now(),
      duration_ms: duration_ms,
      overall_status:
        determine_overall_status([
          payment_check,
          refund_check,
          ledger_balance_check,
          orphaned_entries_check,
          entity_totals_check
        ]),
      checks: %{
        payments: payment_check,
        refunds: refund_check,
        ledger_balance: ledger_balance_check,
        orphaned_entries: orphaned_entries_check,
        entity_totals: entity_totals_check
      }
    }

    log_reconciliation_results(report)

    # Emit telemetry event for reconciliation completion
    :telemetry.execute(
      [:ysc, :ledgers, :reconciliation_completed],
      %{duration: duration_ms, count: 1},
      %{
        status: if(report.overall_status == :ok, do: "success", else: "error"),
        has_errors: report.overall_status != :ok
      }
    )

    # Emit error count if there are errors
    if report.overall_status != :ok do
      error_count =
        Enum.count(report.checks, fn {_key, check} ->
          check.status != :ok
        end)

      :telemetry.execute(
        [:ysc, :ledgers, :reconciliation_errors],
        %{count: error_count},
        %{}
      )
    end

    {:ok, report}
  end

  @doc """
  Reconciles payments with their ledger entries.

  Checks:
  - Every payment has a ledger transaction
  - Every payment has corresponding ledger entries
  - Payment amounts match ledger entry totals
  """
  def reconcile_payments do
    Logger.info("Reconciling payments with ledger entries")

    # Get all payments
    payments = Repo.all(Payment)
    total_payments = length(payments)

    # Check each payment
    discrepancies =
      Enum.reduce(payments, [], fn payment, acc ->
        case check_payment_consistency(payment) do
          {:ok, _} -> acc
          {:error, issues} -> [%{payment_id: payment.id, issues: issues} | acc]
        end
      end)

    # Calculate totals
    total_payment_amount =
      payments
      |> Enum.reduce(Money.new(0, :USD), fn payment, acc ->
        {:ok, sum} = Money.add(acc, payment.amount)
        sum
      end)

    # Get total from ledger entries for payments
    ledger_payment_total = calculate_payment_total_from_ledger()

    amount_match = Money.equal?(total_payment_amount, ledger_payment_total)

    %{
      status:
        if(Enum.empty?(discrepancies) && amount_match, do: :ok, else: :error),
      total_payments: total_payments,
      discrepancies_count: length(discrepancies),
      discrepancies: discrepancies,
      totals: %{
        payments_table: total_payment_amount,
        ledger_entries: ledger_payment_total,
        match: amount_match
      }
    }
  end

  @doc """
  Reconciles refunds with their ledger entries.

  Checks:
  - Every refund has a ledger transaction
  - Every refund has corresponding ledger entries
  - Refund amounts match ledger entry totals
  """
  def reconcile_refunds do
    Logger.info("Reconciling refunds with ledger entries")

    # Get all refunds
    refunds = Repo.all(Refund)
    total_refunds = length(refunds)

    # Check each refund
    discrepancies =
      Enum.reduce(refunds, [], fn refund, acc ->
        case check_refund_consistency(refund) do
          {:ok, _} -> acc
          {:error, issues} -> [%{refund_id: refund.id, issues: issues} | acc]
        end
      end)

    # Calculate totals
    total_refund_amount =
      refunds
      |> Enum.reduce(Money.new(0, :USD), fn refund, acc ->
        {:ok, sum} = Money.add(acc, refund.amount)
        sum
      end)

    # Get total from ledger entries for refunds
    ledger_refund_total = calculate_refund_total_from_ledger()

    amount_match = Money.equal?(total_refund_amount, ledger_refund_total)

    %{
      status:
        if(Enum.empty?(discrepancies) && amount_match, do: :ok, else: :error),
      total_refunds: total_refunds,
      discrepancies_count: length(discrepancies),
      discrepancies: discrepancies,
      totals: %{
        refunds_table: total_refund_amount,
        ledger_entries: ledger_refund_total,
        match: amount_match
      }
    }
  end

  @doc """
  Checks if the ledger is balanced (debits = credits).
  """
  def check_ledger_balance do
    case Ledgers.verify_ledger_balance() do
      {:ok, :balanced} ->
        %{
          status: :ok,
          balanced: true,
          message: "Ledger is balanced"
        }

      {:error, {:imbalanced, difference}} ->
        # Get detailed imbalance information
        {:error, details} = Ledgers.get_ledger_imbalance_details()

        %{
          status: :error,
          balanced: false,
          difference: difference,
          message: "Ledger is imbalanced by #{Money.to_string!(difference)}",
          details: details
        }
    end
  end

  @doc """
  Checks for orphaned ledger entries (entries without valid parent records).
  """
  def check_orphaned_entries do
    Logger.info("Checking for orphaned ledger entries")

    # Check for entries with invalid payment_id
    orphaned_payment_entries = find_orphaned_payment_entries()

    # Check for transactions with invalid payment_id
    orphaned_transactions = find_orphaned_transactions()

    %{
      status:
        if(
          Enum.empty?(orphaned_payment_entries) &&
            Enum.empty?(orphaned_transactions),
          do: :ok,
          else: :error
        ),
      orphaned_entries_count: length(orphaned_payment_entries),
      orphaned_entries: orphaned_payment_entries,
      orphaned_transactions_count: length(orphaned_transactions),
      orphaned_transactions: orphaned_transactions
    }
  end

  @doc """
  Reconciles entity-specific totals (bookings, tickets, subscriptions) with ledger entries.
  """
  def reconcile_entity_totals do
    Logger.info("Reconciling entity-specific totals")

    membership_check = reconcile_membership_payments()
    booking_check = reconcile_booking_payments()
    event_check = reconcile_event_payments()

    all_ok =
      membership_check.status == :ok &&
        booking_check.status == :ok &&
        event_check.status == :ok

    %{
      status: if(all_ok, do: :ok, else: :error),
      memberships: membership_check,
      bookings: booking_check,
      events: event_check
    }
  end

  ## Private Helper Functions

  defp check_payment_consistency(payment) do
    issues = []

    # Check if payment has a ledger transaction
    transaction = get_transaction_for_payment(payment.id)

    issues =
      if transaction == nil do
        ["No ledger transaction found" | issues]
      else
        # Check if transaction amount matches payment amount
        if Money.equal?(transaction.total_amount, payment.amount) do
          issues
        else
          [
            "Transaction amount (#{Money.to_string!(transaction.total_amount)}) doesn't match payment amount (#{Money.to_string!(payment.amount)})"
            | issues
          ]
        end
      end

    # Check if payment has ledger entries
    entries = Ledgers.get_entries_by_payment(payment.id)

    issues =
      if Enum.empty?(entries) do
        ["No ledger entries found" | issues]
      else
        # Check if ledger entries balance
        total = calculate_entries_total(entries)

        if Money.equal?(total, Money.new(0, :USD)) do
          issues
        else
          [
            "Ledger entries don't balance (total: #{Money.to_string!(total)})"
            | issues
          ]
        end
      end

    if Enum.empty?(issues) do
      {:ok, :consistent}
    else
      {:error, issues}
    end
  end

  defp check_refund_consistency(refund) do
    issues = []

    # Check if refund has a ledger transaction
    transaction = get_transaction_for_refund(refund.id)

    issues =
      if transaction == nil do
        ["No ledger transaction found" | issues]
      else
        # Check if transaction amount matches refund amount
        if Money.equal?(transaction.total_amount, refund.amount) do
          issues
        else
          [
            "Transaction amount (#{Money.to_string!(transaction.total_amount)}) doesn't match refund amount (#{Money.to_string!(refund.amount)})"
            | issues
          ]
        end
      end

    # Check if refund's payment exists
    payment = Repo.get(Payment, refund.payment_id)

    issues =
      if payment == nil do
        ["Referenced payment not found" | issues]
      else
        issues
      end

    # Check if refund has ledger entries
    # Query entries directly by refund_id for accurate relationship tracking
    refund_entries = Ledgers.get_entries_by_refund(refund.id)

    issues =
      if Enum.empty?(refund_entries) do
        ["No refund ledger entries found" | issues]
      else
        issues
      end

    if Enum.empty?(issues) do
      {:ok, :consistent}
    else
      {:error, issues}
    end
  end

  defp get_transaction_for_payment(payment_id) do
    from(t in LedgerTransaction,
      where: t.payment_id == ^payment_id,
      where: t.type == :payment,
      limit: 1
    )
    |> Repo.one()
  end

  defp get_transaction_for_refund(refund_id) do
    from(t in LedgerTransaction,
      where: t.refund_id == ^refund_id,
      where: t.type == :refund,
      limit: 1
    )
    |> Repo.one()
  end

  defp calculate_entries_total(entries) do
    require Logger

    Enum.reduce(entries, Money.new(0, :USD), fn entry, acc ->
      # Handle both atom and string values for debit_credit (EctoEnum)
      debit_credit =
        case entry.debit_credit do
          atom when is_atom(atom) -> to_string(atom)
          str when is_binary(str) -> str
          _ -> nil
        end

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
            value: inspect(other),
            account_id: entry.account_id,
            payment_id: entry.payment_id
          )

          # Report to Sentry
          Sentry.capture_message("Invalid debit_credit in reconciliation",
            level: :error,
            extra: %{
              entry_id: entry.id,
              debit_credit: inspect(other),
              account_id: entry.account_id,
              payment_id: entry.payment_id
            },
            tags: %{component: "reconciliation"}
          )

          acc
      end
    end)
  end

  defp calculate_payment_total_from_ledger do
    # Sum all positive entries for stripe_account (receivables from payments)
    # This represents all money coming in from payments (debit entries to stripe_account)
    query =
      from(e in LedgerEntry,
        join: a in assoc(e, :account),
        join: t in LedgerTransaction,
        on: t.payment_id == e.payment_id,
        where: a.name == "stripe_account",
        where: t.type == :payment,
        where: e.debit_credit == "debit",
        select: sum(fragment("(?.amount).amount", e))
      )

    case Repo.one(query) do
      nil -> Money.new(0, :USD)
      amount -> Money.new(amount, :USD)
    end
  end

  defp calculate_refund_total_from_ledger do
    # Sum all revenue reversal entries for refunds using the refund_id column
    # With the refund_id foreign key, we can directly identify refund entries
    # and sum only the debit side (revenue reversals) to match the refund amounts
    query =
      from(e in LedgerEntry,
        join: a in assoc(e, :account),
        where: not is_nil(e.refund_id),
        where: a.account_type == "revenue",
        where: e.debit_credit == "debit",
        select: sum(fragment("(?.amount).amount", e))
      )

    case Repo.one(query) do
      nil -> Money.new(0, :USD)
      amount -> Money.new(0, :USD) |> Money.add!(Money.new(amount, :USD))
    end
  end

  defp find_orphaned_payment_entries do
    query =
      from(e in LedgerEntry,
        left_join: p in Payment,
        on: e.payment_id == p.id,
        where: not is_nil(e.payment_id),
        where: is_nil(p.id),
        select: %{
          entry_id: e.id,
          payment_id: e.payment_id,
          amount: e.amount,
          description: e.description
        }
      )

    Repo.all(query)
  end

  defp find_orphaned_transactions do
    # Check for transactions with invalid payment_id
    payment_orphans =
      from(t in LedgerTransaction,
        left_join: p in Payment,
        on: t.payment_id == p.id,
        where: not is_nil(t.payment_id),
        where: is_nil(p.id),
        select: %{
          transaction_id: t.id,
          type: t.type,
          payment_id: t.payment_id,
          refund_id: t.refund_id,
          reason: "payment_not_found"
        }
      )
      |> Repo.all()

    # Check for refund transactions with invalid refund_id
    refund_orphans =
      from(t in LedgerTransaction,
        left_join: r in Refund,
        on: t.refund_id == r.id,
        where: not is_nil(t.refund_id),
        where: is_nil(r.id),
        select: %{
          transaction_id: t.id,
          type: t.type,
          payment_id: t.payment_id,
          refund_id: t.refund_id,
          reason: "refund_not_found"
        }
      )
      |> Repo.all()

    payment_orphans ++ refund_orphans
  end

  defp reconcile_membership_payments do
    # Get all membership payments from ledger entries (credit entries to revenue account)
    ledger_total =
      from(e in LedgerEntry,
        join: a in assoc(e, :account),
        where: a.name == "membership_revenue",
        where: e.debit_credit == "credit",
        select: sum(fragment("(?.amount).amount", e))
      )
      |> Repo.one()
      |> case do
        nil -> Money.new(0, :USD)
        amount -> Money.new(amount, :USD)
      end

    # Get all membership payments from payment records (debit entries to stripe_account)
    # Exclude refund entries by checking that refund_id is null
    payments_total =
      from(e in LedgerEntry,
        join: p in Payment,
        on: e.payment_id == p.id,
        where: e.related_entity_type == :membership,
        where: e.debit_credit == "debit",
        where: is_nil(e.refund_id),
        select: sum(fragment("(?.amount).amount", e))
      )
      |> Repo.one()
      |> case do
        nil -> Money.new(0, :USD)
        amount -> Money.new(amount, :USD)
      end

    %{
      status:
        if(Money.equal?(ledger_total, payments_total), do: :ok, else: :error),
      ledger_revenue: ledger_total,
      payment_total: payments_total,
      match: Money.equal?(ledger_total, payments_total)
    }
  end

  defp reconcile_booking_payments do
    # Similar logic for bookings
    ledger_totals = %{
      tahoe: get_revenue_total("tahoe_booking_revenue"),
      clear_lake: get_revenue_total("clear_lake_booking_revenue")
    }

    {:ok, total} = Money.add(ledger_totals.tahoe, ledger_totals.clear_lake)

    # Get booking payments (debit entries to stripe_account)
    # Exclude refund entries by checking that refund_id is null
    payments_total =
      from(e in LedgerEntry,
        join: p in Payment,
        on: e.payment_id == p.id,
        where: e.related_entity_type == :booking,
        where: e.debit_credit == "debit",
        where: is_nil(e.refund_id),
        select: sum(fragment("(?.amount).amount", e))
      )
      |> Repo.one()
      |> case do
        nil -> Money.new(0, :USD)
        amount -> Money.new(amount, :USD)
      end

    %{
      status: if(Money.equal?(total, payments_total), do: :ok, else: :error),
      ledger_revenue: total,
      payment_total: payments_total,
      breakdown: ledger_totals,
      match: Money.equal?(total, payments_total)
    }
  end

  defp reconcile_event_payments do
    ledger_total = get_revenue_total("event_revenue")

    # Get event payments (debit entries to stripe_account)
    # Exclude refund entries by checking that refund_id is null
    payments_total =
      from(e in LedgerEntry,
        join: p in Payment,
        on: e.payment_id == p.id,
        where: e.related_entity_type == :event,
        where: e.debit_credit == "debit",
        where: is_nil(e.refund_id),
        select: sum(fragment("(?.amount).amount", e))
      )
      |> Repo.one()
      |> case do
        nil -> Money.new(0, :USD)
        amount -> Money.new(amount, :USD)
      end

    %{
      status:
        if(Money.equal?(ledger_total, payments_total), do: :ok, else: :error),
      ledger_revenue: ledger_total,
      payment_total: payments_total,
      match: Money.equal?(ledger_total, payments_total)
    }
  end

  defp get_revenue_total(account_name) do
    from(e in LedgerEntry,
      join: a in assoc(e, :account),
      where: a.name == ^account_name,
      where: e.debit_credit == "credit",
      select: sum(fragment("(?.amount).amount", e))
    )
    |> Repo.one()
    |> case do
      nil -> Money.new(0, :USD)
      amount -> Money.new(amount, :USD)
    end
  end

  defp determine_overall_status(checks) do
    all_ok =
      Enum.all?(checks, fn check ->
        check.status == :ok
      end)

    if all_ok, do: :ok, else: :error
  end

  defp log_reconciliation_results(report) do
    case report.overall_status do
      :ok ->
        Logger.info("✅ Reconciliation completed successfully",
          duration_ms: report.duration_ms,
          timestamp: report.timestamp
        )

      :error ->
        Logger.warning("❌ Reconciliation found discrepancies",
          duration_ms: report.duration_ms,
          timestamp: report.timestamp,
          payment_issues: report.checks.payments.discrepancies_count,
          refund_issues: report.checks.refunds.discrepancies_count,
          ledger_balanced: report.checks.ledger_balance.balanced
        )

        # Report to Sentry with comprehensive context
        Sentry.capture_message("Financial reconciliation found discrepancies",
          level: :error,
          extra: %{
            duration_ms: report.duration_ms,
            timestamp: report.timestamp,
            payment_discrepancies_count:
              report.checks.payments.discrepancies_count,
            refund_discrepancies_count:
              report.checks.refunds.discrepancies_count,
            ledger_balanced: report.checks.ledger_balance.balanced,
            orphaned_entries_count:
              report.checks.orphaned_entries.orphaned_entries_count,
            orphaned_transactions_count:
              report.checks.orphaned_entries.orphaned_transactions_count,
            payments_total_match: report.checks.payments.totals.match,
            refunds_total_match: report.checks.refunds.totals.match,
            memberships_match: report.checks.entity_totals.memberships.match,
            bookings_match: report.checks.entity_totals.bookings.match,
            events_match: report.checks.entity_totals.events.match,
            payments_table_total:
              Money.to_string!(report.checks.payments.totals.payments_table),
            payments_ledger_total:
              Money.to_string!(report.checks.payments.totals.ledger_entries),
            refunds_table_total:
              Money.to_string!(report.checks.refunds.totals.refunds_table),
            refunds_ledger_total:
              Money.to_string!(report.checks.refunds.totals.ledger_entries)
          },
          tags: %{
            reconciliation: "full",
            has_payment_issues: report.checks.payments.discrepancies_count > 0,
            has_refund_issues: report.checks.refunds.discrepancies_count > 0,
            ledger_imbalanced: !report.checks.ledger_balance.balanced,
            has_orphaned_entries:
              report.checks.orphaned_entries.orphaned_entries_count > 0
          }
        )

        # Log specific issues
        if report.checks.payments.discrepancies_count > 0 do
          Logger.warning("Payment discrepancies found",
            count: report.checks.payments.discrepancies_count
          )

          # Report payment discrepancies to Sentry with details
          Sentry.capture_message("Payment reconciliation discrepancies found",
            level: :error,
            extra: %{
              discrepancies_count: report.checks.payments.discrepancies_count,
              total_payments: report.checks.payments.total_payments,
              payments_table_total:
                Money.to_string!(report.checks.payments.totals.payments_table),
              ledger_entries_total:
                Money.to_string!(report.checks.payments.totals.ledger_entries),
              amounts_match: report.checks.payments.totals.match,
              discrepancies: Enum.take(report.checks.payments.discrepancies, 10)
            },
            tags: %{
              reconciliation: "payments",
              discrepancy_type: "payment"
            }
          )
        end

        if report.checks.refunds.discrepancies_count > 0 do
          Logger.warning("Refund discrepancies found",
            count: report.checks.refunds.discrepancies_count
          )

          # Report refund discrepancies to Sentry with details
          Sentry.capture_message("Refund reconciliation discrepancies found",
            level: :error,
            extra: %{
              discrepancies_count: report.checks.refunds.discrepancies_count,
              total_refunds: report.checks.refunds.total_refunds,
              refunds_table_total:
                Money.to_string!(report.checks.refunds.totals.refunds_table),
              ledger_entries_total:
                Money.to_string!(report.checks.refunds.totals.ledger_entries),
              amounts_match: report.checks.refunds.totals.match,
              discrepancies: Enum.take(report.checks.refunds.discrepancies, 10)
            },
            tags: %{
              reconciliation: "refunds",
              discrepancy_type: "refund"
            }
          )
        end

        if !report.checks.ledger_balance.balanced do
          Logger.warning("Ledger is imbalanced",
            difference:
              Money.to_string!(report.checks.ledger_balance.difference)
          )

          # Report ledger imbalance to Sentry
          Sentry.capture_message("Ledger is imbalanced",
            level: :error,
            extra: %{
              difference:
                Money.to_string!(report.checks.ledger_balance.difference),
              details: report.checks.ledger_balance.details
            },
            tags: %{
              reconciliation: "ledger_balance",
              discrepancy_type: "imbalance"
            }
          )
        end

        if report.checks.orphaned_entries.orphaned_entries_count > 0 do
          Logger.warning("Orphaned ledger entries found",
            count: report.checks.orphaned_entries.orphaned_entries_count
          )

          # Report orphaned entries to Sentry
          Sentry.capture_message("Orphaned ledger entries found",
            level: :error,
            extra: %{
              orphaned_entries_count:
                report.checks.orphaned_entries.orphaned_entries_count,
              orphaned_transactions_count:
                report.checks.orphaned_entries.orphaned_transactions_count,
              orphaned_entries:
                Enum.take(report.checks.orphaned_entries.orphaned_entries, 10),
              orphaned_transactions:
                Enum.take(
                  report.checks.orphaned_entries.orphaned_transactions,
                  10
                )
            },
            tags: %{
              reconciliation: "orphaned_entries",
              discrepancy_type: "orphaned"
            }
          )
        end

        # Report entity total mismatches
        if report.checks.entity_totals.status == :error do
          entity_issues = []

          entity_issues =
            if report.checks.entity_totals.memberships.match do
              entity_issues
            else
              [
                %{
                  type: "membership",
                  ledger_revenue:
                    Money.to_string!(
                      report.checks.entity_totals.memberships.ledger_revenue
                    ),
                  payment_total:
                    Money.to_string!(
                      report.checks.entity_totals.memberships.payment_total
                    )
                }
                | entity_issues
              ]
            end

          entity_issues =
            if report.checks.entity_totals.bookings.match do
              entity_issues
            else
              [
                %{
                  type: "booking",
                  ledger_revenue:
                    Money.to_string!(
                      report.checks.entity_totals.bookings.ledger_revenue
                    ),
                  payment_total:
                    Money.to_string!(
                      report.checks.entity_totals.bookings.payment_total
                    )
                }
                | entity_issues
              ]
            end

          entity_issues =
            if report.checks.entity_totals.events.match do
              entity_issues
            else
              [
                %{
                  type: "event",
                  ledger_revenue:
                    Money.to_string!(
                      report.checks.entity_totals.events.ledger_revenue
                    ),
                  payment_total:
                    Money.to_string!(
                      report.checks.entity_totals.events.payment_total
                    )
                }
                | entity_issues
              ]
            end

          if entity_issues != [] do
            Sentry.capture_message(
              "Entity total reconciliation mismatches found",
              level: :error,
              extra: %{
                entity_issues: entity_issues,
                memberships_match:
                  report.checks.entity_totals.memberships.match,
                bookings_match: report.checks.entity_totals.bookings.match,
                events_match: report.checks.entity_totals.events.match
              },
              tags: %{
                reconciliation: "entity_totals",
                discrepancy_type: "entity_mismatch"
              }
            )
          end
        end
    end
  end

  @doc """
  Generates a human-readable report from reconciliation results.
  """
  def format_report(report) do
    """
    ╔══════════════════════════════════════════════════════════════════
    ║ FINANCIAL RECONCILIATION REPORT
    ╠══════════════════════════════════════════════════════════════════
    ║ Status: #{format_status(report.overall_status)}
    ║ Timestamp: #{report.timestamp}
    ║ Duration: #{report.duration_ms}ms
    ╠══════════════════════════════════════════════════════════════════
    ║ PAYMENTS
    ╠══════════════════════════════════════════════════════════════════
    ║ Total Payments: #{report.checks.payments.total_payments}
    ║ Discrepancies: #{report.checks.payments.discrepancies_count}
    ║ Payments Table Total: #{Money.to_string!(report.checks.payments.totals.payments_table)}
    ║ Ledger Entries Total: #{Money.to_string!(report.checks.payments.totals.ledger_entries)}
    ║ Amounts Match: #{format_boolean(report.checks.payments.totals.match)}
    ╠══════════════════════════════════════════════════════════════════
    ║ REFUNDS
    ╠══════════════════════════════════════════════════════════════════
    ║ Total Refunds: #{report.checks.refunds.total_refunds}
    ║ Discrepancies: #{report.checks.refunds.discrepancies_count}
    ║ Refunds Table Total: #{Money.to_string!(report.checks.refunds.totals.refunds_table)}
    ║ Ledger Entries Total: #{Money.to_string!(report.checks.refunds.totals.ledger_entries)}
    ║ Amounts Match: #{format_boolean(report.checks.refunds.totals.match)}
    ╠══════════════════════════════════════════════════════════════════
    ║ LEDGER BALANCE
    ╠══════════════════════════════════════════════════════════════════
    ║ Balanced: #{format_boolean(report.checks.ledger_balance.balanced)}
    #{if report.checks.ledger_balance.balanced do
      ""
    else
      "║ Difference: #{Money.to_string!(report.checks.ledger_balance.difference)}"
    end}
    ╠══════════════════════════════════════════════════════════════════
    ║ ORPHANED ENTRIES
    ╠══════════════════════════════════════════════════════════════════
    ║ Orphaned Entries: #{report.checks.orphaned_entries.orphaned_entries_count}
    ║ Orphaned Transactions: #{report.checks.orphaned_entries.orphaned_transactions_count}
    ╠══════════════════════════════════════════════════════════════════
    ║ ENTITY TOTALS
    ╠══════════════════════════════════════════════════════════════════
    ║ Memberships Match: #{format_boolean(report.checks.entity_totals.memberships.match)}
    ║ Bookings Match: #{format_boolean(report.checks.entity_totals.bookings.match)}
    ║ Events Match: #{format_boolean(report.checks.entity_totals.events.match)}
    ╚══════════════════════════════════════════════════════════════════
    """
  end

  defp format_status(:ok), do: "✅ PASS"
  defp format_status(:error), do: "❌ FAIL"

  defp format_boolean(true), do: "✅ Yes"
  defp format_boolean(false), do: "❌ No"
end
