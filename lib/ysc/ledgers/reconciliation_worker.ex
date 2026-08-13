defmodule Ysc.Ledgers.ReconciliationWorker do
  @moduledoc """
  Oban worker that runs financial reconciliation checks periodically.

  This worker:
  - Runs comprehensive reconciliation checks
  - Alerts on discrepancies
  - Logs detailed reports
  - Can be triggered manually or scheduled

  ## Scheduling

  Configured to run daily at 1 AM UTC via Oban.Plugins.Cron.

  ## Manual Triggering

      # Trigger immediately
      Ysc.Ledgers.ReconciliationWorker.run_now()

      # Schedule for later
      Ysc.Ledgers.ReconciliationWorker.schedule_reconciliation()
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3

  require Ysc.Logging
  alias Ysc.Ledgers
  alias Ysc.Ledgers.Reconciliation
  alias Ysc.Alerts.Discord
  alias Ysc.Stripe.WebhookHandler

  # Payout linking (payments/refunds -> payout) only runs once, when the
  # `payout.paid` webhook arrives. A charge that settles into a payout before
  # its own Payment record exists locally (e.g. an ACH/us_bank_account charge,
  # which can take several days to clear) is silently skipped and never
  # retried - see docs/REPROCESS_PAYOUTS.md, previously a manual-only fix via
  # `WebhookHandler.relink_payout_transactions/1`. Re-attempt linking here for
  # recently-created payouts before alerting, so the common "payment showed up
  # late" case self-heals instead of paging a human every night.
  @payout_autoheal_lookback_days 30

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Ysc.Logging.info("Starting scheduled financial reconciliation")

    autoheal_payout_links()

    # Note: run_full_reconciliation/0 currently always returns {:ok, report}
    # even when discrepancies are found. Discrepancies are indicated via
    # report.overall_status == :error, not as an error tuple.
    #
    # Future enhancement: Consider distinguishing between:
    # - {:error, reason} for system failures (DB errors, timeouts) that should retry
    # - {:ok, report} for successful execution (even with discrepancies found)
    # This would enable Oban retry logic for transient system issues while
    # still handling data discrepancies as successful report generation.
    {:ok, report} = Reconciliation.run_full_reconciliation()
    handle_reconciliation_results(report)
  end

  @doc """
  Manually triggers a reconciliation check immediately.
  """
  def run_now do
    Ysc.Logging.info("Manually triggering reconciliation")

    autoheal_payout_links()

    {:ok, report} = Reconciliation.run_full_reconciliation()
    # Print formatted report to console
    Ysc.Logging.info(Reconciliation.format_report(report))
    handle_reconciliation_results(report)
  end

  # Finds payouts whose linked payments/refunds/fees don't sum to the payout
  # amount ("composition mismatch" - i.e. a charge in the payout has no
  # locally-linked payment/refund yet) and retries linking via the Stripe
  # BalanceTransaction API. Skips payouts older than
  # @payout_autoheal_lookback_days: a payout that's stayed unreconciled that
  # long isn't waiting on a late-settling charge, it needs a human to look at
  # `docs/REPROCESS_PAYOUTS.md`, so we don't hit Stripe for it every night.
  defp autoheal_payout_links do
    cutoff =
      DateTime.add(DateTime.utc_now(), -@payout_autoheal_lookback_days, :day)

    %{discrepancies: discrepancies} = Reconciliation.reconcile_payouts()

    discrepancies
    |> Enum.filter(&composition_mismatch?/1)
    |> Enum.each(&attempt_payout_relink(&1, cutoff))
  end

  defp composition_mismatch?(%{issues: issues}) do
    Enum.any?(issues, &String.starts_with?(&1, "Payout composition mismatch"))
  end

  defp attempt_payout_relink(
         %{payout_id: payout_id, stripe_payout_id: stripe_payout_id},
         cutoff
       ) do
    payout = Ledgers.get_payout!(payout_id)

    if DateTime.compare(payout.inserted_at, cutoff) == :lt do
      Ysc.Logging.debug(
        "Skipping payout auto-heal: payout older than lookback window",
        payout_id: payout_id,
        stripe_payout_id: stripe_payout_id
      )
    else
      Ysc.Logging.info(
        "Auto-healing payout link before reconciliation alert",
        payout_id: payout_id,
        stripe_payout_id: stripe_payout_id
      )

      WebhookHandler.relink_payout_transactions(payout)
    end
  rescue
    error ->
      Ysc.Logging.error("Payout auto-heal failed",
        payout_id: payout_id,
        stripe_payout_id: stripe_payout_id,
        error: Exception.format(:error, error, __STACKTRACE__)
      )
  end

  @doc """
  Schedules a reconciliation check to run later.
  """
  def schedule_reconciliation(opts \\ []) do
    schedule_in = Keyword.get(opts, :schedule_in, 0)

    %{}
    |> new(schedule_in: schedule_in)
    |> Oban.insert()
  end

  defp handle_reconciliation_results(report) do
    case report.overall_status do
      :ok ->
        Ysc.Logging.info("✅ Reconciliation passed all checks",
          duration_ms: report.duration_ms
        )

        # Send success notification to Discord
        send_success_notification(report)

        {:ok, report}

      :error ->
        alert_on_discrepancies(report)
        {:ok, report}
    end
  end

  defp alert_on_discrepancies(report) do
    Ysc.Logging.warning("🚨 FINANCIAL RECONCILIATION DISCREPANCIES DETECTED")

    # Build detailed alert message
    alert_sections = build_alert_sections(report)

    full_alert = """
    🚨 CRITICAL: Financial Reconciliation Discrepancies Detected

    **Timestamp:** #{report.timestamp}
    **Duration:** #{report.duration_ms}ms

    #{Enum.join(alert_sections, "\n\n")}

    **Action Required:**
    Investigate these discrepancies immediately. Run detailed checks:
    ```
    Ysc.Ledgers.Reconciliation.run_full_reconciliation()
    ```

    Or in IEx:
    ```
    {:ok, report} = Ysc.Ledgers.Reconciliation.run_full_reconciliation()
    IO.puts(Ysc.Ledgers.Reconciliation.format_report(report))
    ```
    """

    Ysc.Logging.warning(full_alert)

    # Send Discord alert
    send_discord_alert(report)

    # Additional integrations can be added here:
    # send_slack_notification(full_alert)
    # send_email_alert(full_alert)
    # send_pagerduty_alert(report)

    :ok
  end

  defp build_alert_sections(report) do
    []
    |> maybe_add_payment_alert(report)
    |> maybe_add_refund_alert(report)
    |> maybe_add_balance_alert(report)
    |> maybe_add_orphaned_alert(report)
    |> maybe_add_entity_alert(report)
    |> maybe_add_payout_alert(report)
  end

  defp maybe_add_payment_alert(sections, report) do
    if report.checks.payments.discrepancies_count > 0 do
      payment_alert = """
      **PAYMENT DISCREPANCIES**
      - Total Discrepancies: #{report.checks.payments.discrepancies_count}
      - Payments Total: #{Money.to_string!(report.checks.payments.totals.payments_table)}
      - Ledger Total: #{Money.to_string!(report.checks.payments.totals.ledger_entries)}
      - Match: #{report.checks.payments.totals.match}

      Issues:
      #{format_payment_issues(report.checks.payments.discrepancies)}
      """

      [payment_alert | sections]
    else
      sections
    end
  end

  defp maybe_add_refund_alert(sections, report) do
    if report.checks.refunds.discrepancies_count > 0 do
      refund_alert = """
      **REFUND DISCREPANCIES**
      - Total Discrepancies: #{report.checks.refunds.discrepancies_count}
      - Refunds Total: #{Money.to_string!(report.checks.refunds.totals.refunds_table)}
      - Ledger Total: #{Money.to_string!(report.checks.refunds.totals.ledger_entries)}
      - Match: #{report.checks.refunds.totals.match}

      Issues:
      #{format_refund_issues(report.checks.refunds.discrepancies)}
      """

      [refund_alert | sections]
    else
      sections
    end
  end

  defp maybe_add_balance_alert(sections, report) do
    if report.checks.ledger_balance.balanced do
      sections
    else
      balance_alert = """
      **LEDGER IMBALANCE**
      - Difference: #{Money.to_string!(report.checks.ledger_balance.difference)}
      - Message: #{report.checks.ledger_balance.message}
      """

      [balance_alert | sections]
    end
  end

  defp maybe_add_orphaned_alert(sections, report) do
    if report.checks.orphaned_entries.status == :error do
      orphaned_alert = """
      **ORPHANED ENTRIES**
      - Orphaned Entries: #{report.checks.orphaned_entries.orphaned_entries_count}
      - Orphaned Transactions: #{report.checks.orphaned_entries.orphaned_transactions_count}
      """

      [orphaned_alert | sections]
    else
      sections
    end
  end

  defp maybe_add_entity_alert(sections, report) do
    if report.checks.entity_totals.status == :error do
      entity_alert = """
      **ENTITY TOTAL MISMATCHES**
      - Memberships: #{if report.checks.entity_totals.memberships.match, do: "✅", else: "❌"}
        Ledger: #{Money.to_string!(report.checks.entity_totals.memberships.ledger_revenue)}
        Payments: #{Money.to_string!(report.checks.entity_totals.memberships.payment_total)}

      - Bookings: #{if report.checks.entity_totals.bookings.match, do: "✅", else: "❌"}
        Ledger: #{Money.to_string!(report.checks.entity_totals.bookings.ledger_revenue)}
        Payments: #{Money.to_string!(report.checks.entity_totals.bookings.payment_total)}

      - Events: #{if report.checks.entity_totals.events.match, do: "✅", else: "❌"}
        Ledger: #{Money.to_string!(report.checks.entity_totals.events.ledger_revenue)}
        Payments: #{Money.to_string!(report.checks.entity_totals.events.payment_total)}

      - Donations: #{if report.checks.entity_totals.donations.match, do: "✅", else: "❌"}
        Ledger: #{Money.to_string!(report.checks.entity_totals.donations.ledger_revenue)}
        Payments: #{Money.to_string!(report.checks.entity_totals.donations.payment_total)}
      """

      [entity_alert | sections]
    else
      sections
    end
  end

  defp maybe_add_payout_alert(sections, report) do
    payouts = Map.get(report.checks, :payouts)

    if payouts && payouts.discrepancies_count > 0 do
      payout_alert = """
      **PAYOUT DISCREPANCIES**
      - Total Discrepancies: #{payouts.discrepancies_count}
      - Total Payouts: #{payouts.total_payouts}

      Issues:
      #{format_payout_issues(payouts.discrepancies)}

      Fix: relink with `Ysc.Stripe.WebhookHandler.relink_payout_transactions/1`
      (see docs/REPROCESS_PAYOUTS.md).
      """

      [payout_alert | sections]
    else
      sections
    end
  end

  defp format_payout_issues(discrepancies) do
    discrepancies
    |> Enum.take(5)
    |> Enum.map_join("\n", fn disc ->
      "  - #{disc.stripe_payout_id}:\n    #{Enum.join(disc.issues, "\n    ")}"
    end)
  end

  defp format_payment_issues(discrepancies) do
    discrepancies
    # Limit to first 5 for brevity
    |> Enum.take(5)
    |> Enum.map_join("\n", fn disc ->
      "  - Payment #{disc.payment_id}:\n    #{Enum.join(disc.issues, "\n    ")}"
    end)
  end

  defp format_refund_issues(discrepancies) do
    discrepancies
    # Limit to first 5 for brevity
    |> Enum.take(5)
    |> Enum.map_join("\n", fn disc ->
      "  - Refund #{disc.refund_id}:\n    #{Enum.join(disc.issues, "\n    ")}"
    end)
  end

  defp send_success_notification(report) do
    # Send Discord success notification
    Discord.send_reconciliation_report(report, :success)
  end

  defp send_discord_alert(report) do
    # Send main reconciliation report with error status
    Discord.send_reconciliation_report(report, :error)

    # Send specific alerts for critical issues
    if !report.checks.ledger_balance.balanced do
      # Reconciliation stores raw ledger detail tuples; Discord expects a map with
      # :total_accounts_affected or nil for a generic alert body.
      imbalance_details =
        case report.checks.ledger_balance.details do
          %{total_accounts_affected: _} = d -> d
          _ -> nil
        end

      Discord.send_ledger_imbalance_alert(
        report.checks.ledger_balance.difference,
        imbalance_details
      )
    end

    if report.checks.payments.discrepancies_count > 0 do
      Discord.send_payment_discrepancy_alert(
        report.checks.payments.discrepancies_count,
        report.checks.payments.total_payments,
        report.checks.payments.discrepancies
      )
    end

    :ok
  end

  @doc false
  def ci_query_explain_query, do: Reconciliation.ci_query_explain_query()
end
