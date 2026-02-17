defmodule Mix.Tasks.Quickbooks.RetrySyncs do
  @moduledoc """
  Manually retry all failed or pending QuickBooks syncs for payments, refunds, and payouts.

  This task finds all records with sync_status != "synced" (including nil, "pending", "failed")
  and enqueues sync jobs for them.

  Usage:
    # Retry all unsynced records (payments, refunds, payouts)
    mix quickbooks.retry_syncs

    # Retry only payments
    mix quickbooks.retry_syncs --payments-only

    # Retry only refunds
    mix quickbooks.retry_syncs --refunds-only

    # Retry only payouts
    mix quickbooks.retry_syncs --payouts-only

    # Dry run - just show what would be retried without actually enqueuing jobs
    mix quickbooks.retry_syncs --dry-run

    # Limit the number of records to retry (default: 1000 per type)
    mix quickbooks.retry_syncs --limit 50
  """

  use Mix.Task
  require Ysc.Logging

  @shortdoc "Retry failed or pending QuickBooks syncs"

  alias Ysc.Repo
  alias Ysc.Ledgers.{Payment, Refund, Payout}
  import Ecto.Query

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          payments_only: :boolean,
          refunds_only: :boolean,
          payouts_only: :boolean,
          dry_run: :boolean,
          limit: :integer
        ]
      )

    Mix.Task.run("app.start")

    dry_run = Keyword.get(opts, :dry_run, false)
    limit = Keyword.get(opts, :limit, 1000)

    payments_only = Keyword.get(opts, :payments_only, false)
    refunds_only = Keyword.get(opts, :refunds_only, false)
    payouts_only = Keyword.get(opts, :payouts_only, false)

    # If no specific type is selected, do all
    do_all = !payments_only && !refunds_only && !payouts_only

    if dry_run do
      Ysc.Logging.info("=== DRY RUN MODE - No jobs will be enqueued ===")
    end

    Ysc.Logging.info("Starting QuickBooks sync retry", limit: limit)

    payments_count =
      if do_all || payments_only do
        retry_unsynced_payments(limit, dry_run)
      else
        0
      end

    refunds_count =
      if do_all || refunds_only do
        retry_unsynced_refunds(limit, dry_run)
      else
        0
      end

    payouts_count =
      if do_all || payouts_only do
        retry_unsynced_payouts(limit, dry_run)
      else
        0
      end

    total = payments_count + refunds_count + payouts_count

    Ysc.Logging.info("QuickBooks sync retry completed",
      payments_enqueued: payments_count,
      refunds_enqueued: refunds_count,
      payouts_enqueued: payouts_count,
      total_enqueued: total,
      dry_run: dry_run
    )

    if dry_run do
      Ysc.Logging.info(
        "This was a dry run. Run without --dry-run to actually enqueue sync jobs."
      )
    end
  end

  defp retry_unsynced_payments(limit, dry_run) do
    Ysc.Logging.info("=== Checking Payments ===")

    # Find payments that are not synced (status is nil, "pending", or "failed")
    unsynced_payments =
      from(p in Payment,
        where:
          is_nil(p.quickbooks_sync_status) or
            p.quickbooks_sync_status != "synced",
        select: %{
          id: p.id,
          reference_id: p.reference_id,
          sync_status: p.quickbooks_sync_status,
          last_attempt: p.quickbooks_last_sync_attempt_at,
          amount: p.amount
        },
        order_by: [desc: p.inserted_at],
        limit: ^limit
      )
      |> Repo.all()

    count = length(unsynced_payments)

    if count > 0 do
      Ysc.Logging.info("Found unsynced payments", count: count)

      # Show first few as examples
      Enum.take(unsynced_payments, 5)
      |> Enum.each(fn payment ->
        Ysc.Logging.info("  Payment: #{payment.reference_id}",
          id: payment.id,
          status: payment.sync_status || "nil",
          last_attempt: payment.last_attempt,
          amount: Money.to_string!(payment.amount)
        )
      end)

      if count > 5 do
        Ysc.Logging.info("  ... and #{count - 5} more")
      end

      unless dry_run do
        Ysc.Logging.info("Enqueuing sync jobs for payments...")

        Enum.each(unsynced_payments, fn payment ->
          %{payment_id: to_string(payment.id)}
          |> YscWeb.Workers.QuickbooksSyncPaymentWorker.new()
          |> Oban.insert()
        end)

        Ysc.Logging.info("Successfully enqueued #{count} payment sync jobs")
      end
    else
      Ysc.Logging.info("No unsynced payments found")
    end

    count
  end

  defp retry_unsynced_refunds(limit, dry_run) do
    Ysc.Logging.info("")
    Ysc.Logging.info("=== Checking Refunds ===")

    # Find refunds that are not synced (status is nil, "pending", or "failed")
    unsynced_refunds =
      from(r in Refund,
        where:
          is_nil(r.quickbooks_sync_status) or
            r.quickbooks_sync_status != "synced",
        select: %{
          id: r.id,
          reference_id: r.reference_id,
          sync_status: r.quickbooks_sync_status,
          last_attempt: r.quickbooks_last_sync_attempt_at,
          amount: r.amount
        },
        order_by: [desc: r.inserted_at],
        limit: ^limit
      )
      |> Repo.all()

    count = length(unsynced_refunds)

    if count > 0 do
      Ysc.Logging.info("Found unsynced refunds", count: count)

      # Show first few as examples
      Enum.take(unsynced_refunds, 5)
      |> Enum.each(fn refund ->
        Ysc.Logging.info("  Refund: #{refund.reference_id}",
          id: refund.id,
          status: refund.sync_status || "nil",
          last_attempt: refund.last_attempt,
          amount: Money.to_string!(refund.amount)
        )
      end)

      if count > 5 do
        Ysc.Logging.info("  ... and #{count - 5} more")
      end

      unless dry_run do
        Ysc.Logging.info("Enqueuing sync jobs for refunds...")

        Enum.each(unsynced_refunds, fn refund ->
          %{refund_id: to_string(refund.id)}
          |> YscWeb.Workers.QuickbooksSyncRefundWorker.new()
          |> Oban.insert()
        end)

        Ysc.Logging.info("Successfully enqueued #{count} refund sync jobs")
      end
    else
      Ysc.Logging.info("No unsynced refunds found")
    end

    count
  end

  defp retry_unsynced_payouts(limit, dry_run) do
    Ysc.Logging.info("")
    Ysc.Logging.info("=== Checking Payouts ===")

    # Find payouts that are not synced (status is nil, "pending", or "failed")
    unsynced_payouts =
      from(p in Payout,
        where:
          is_nil(p.quickbooks_sync_status) or
            p.quickbooks_sync_status != "synced",
        select: %{
          id: p.id,
          stripe_payout_id: p.stripe_payout_id,
          sync_status: p.quickbooks_sync_status,
          last_attempt: p.quickbooks_last_sync_attempt_at,
          amount: p.amount,
          arrival_date: p.arrival_date
        },
        order_by: [desc: p.inserted_at],
        limit: ^limit
      )
      |> Repo.all()

    count = length(unsynced_payouts)

    if count > 0 do
      Ysc.Logging.info("Found unsynced payouts", count: count)

      # Show first few as examples
      Enum.take(unsynced_payouts, 5)
      |> Enum.each(fn payout ->
        Ysc.Logging.info("  Payout: #{payout.stripe_payout_id}",
          id: payout.id,
          status: payout.sync_status || "nil",
          last_attempt: payout.last_attempt,
          amount: Money.to_string!(payout.amount),
          arrival_date: payout.arrival_date
        )
      end)

      if count > 5 do
        Ysc.Logging.info("  ... and #{count - 5} more")
      end

      unless dry_run do
        Ysc.Logging.info("Enqueuing sync jobs for payouts...")

        Enum.each(unsynced_payouts, fn payout ->
          %{payout_id: to_string(payout.id)}
          |> YscWeb.Workers.QuickbooksSyncPayoutWorker.new()
          |> Oban.insert()
        end)

        Ysc.Logging.info("Successfully enqueued #{count} payout sync jobs")
      end
    else
      Ysc.Logging.info("No unsynced payouts found")
    end

    count
  end
end
