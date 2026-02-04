defmodule YscWeb.Workers.QuickbooksSyncRetryWorker do
  @moduledoc """
  Oban worker that runs nightly to find and retry syncing any Payment, Refund, or Payout
  records that haven't been successfully synced to QuickBooks.

  This worker:
  1. Finds all payments with sync_status != "synced" or NULL
  2. Finds all refunds with sync_status != "synced" or NULL
  3. Finds all payouts with sync_status != "synced" or NULL
  4. Enqueues sync jobs for each unsynced record

  This ensures that any records that failed to sync initially, or were created
  before the sync system was in place, will eventually be synced.
  """

  require Logger
  use Oban.Worker, queue: :maintenance

  alias Ysc.Repo
  alias Ysc.Ledgers.{Payment, Refund, Payout}
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.info("Starting nightly QuickBooks sync retry job")

    payments_count = enqueue_unsynced_payments()
    refunds_count = enqueue_unsynced_refunds()
    payouts_count = enqueue_unsynced_payouts()

    total = payments_count + refunds_count + payouts_count

    Logger.info("QuickBooks sync retry job completed",
      payments_enqueued: payments_count,
      refunds_enqueued: refunds_count,
      payouts_enqueued: payouts_count,
      total_enqueued: total
    )

    :ok
  end

  defp enqueue_unsynced_payments do
    # Find payments that are not synced (status is nil, "pending", or "failed")
    unsynced_payments =
      from(p in Payment,
        where:
          is_nil(p.quickbooks_sync_status) or
            p.quickbooks_sync_status != "synced",
        select: p.id,
        limit: 1000
      )
      |> Repo.all()

    count = length(unsynced_payments)

    if count > 0 do
      Logger.info("Found unsynced payments", count: count)

      Enum.each(unsynced_payments, fn payment_id ->
        %{payment_id: to_string(payment_id)}
        |> YscWeb.Workers.QuickbooksSyncPaymentWorker.new()
        |> Oban.insert()
      end)
    end

    count
  end

  defp enqueue_unsynced_refunds do
    # Find refunds that are not synced (status is nil, "pending", or "failed")
    unsynced_refunds =
      from(r in Refund,
        where:
          is_nil(r.quickbooks_sync_status) or
            r.quickbooks_sync_status != "synced",
        select: r.id,
        limit: 1000
      )
      |> Repo.all()

    count = length(unsynced_refunds)

    if count > 0 do
      Logger.info("Found unsynced refunds", count: count)

      Enum.each(unsynced_refunds, fn refund_id ->
        %{refund_id: to_string(refund_id)}
        |> YscWeb.Workers.QuickbooksSyncRefundWorker.new()
        |> Oban.insert()
      end)
    end

    count
  end

  defp enqueue_unsynced_payouts do
    # Find payouts that are not synced (status is nil, "pending", or "failed")
    unsynced_payouts =
      from(p in Payout,
        where:
          is_nil(p.quickbooks_sync_status) or
            p.quickbooks_sync_status != "synced",
        select: p.id,
        limit: 1000
      )
      |> Repo.all()

    count = length(unsynced_payouts)

    if count > 0 do
      Logger.info("Found unsynced payouts", count: count)

      Enum.each(unsynced_payouts, fn payout_id ->
        %{payout_id: to_string(payout_id)}
        |> YscWeb.Workers.QuickbooksSyncPayoutWorker.new()
        |> Oban.insert()
      end)
    end

    count
  end
end
