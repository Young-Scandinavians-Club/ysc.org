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

  require Logger
  alias Ysc.Ledgers.Reconciliation
  alias Ysc.Alerts.Discord

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting scheduled financial reconciliation")

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
    Logger.info("Manually triggering reconciliation")

    {:ok, report} = Reconciliation.run_full_reconciliation()
    # Print formatted report to console
    Logger.info(Reconciliation.format_report(report))
    handle_reconciliation_results(report)
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
        Logger.info("✅ Reconciliation passed all checks",
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
    Logger.critical("🚨 FINANCIAL RECONCILIATION DISCREPANCIES DETECTED")

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

    Logger.critical(full_alert)

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
      """

      [entity_alert | sections]
    else
      sections
    end
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
      Discord.send_ledger_imbalance_alert(
        report.checks.ledger_balance.difference,
        report.checks.ledger_balance.details
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
end
