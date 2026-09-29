defmodule YscWeb.Workers.QuickbooksSyncRefundWorker do
  @moduledoc """
  Oban worker for syncing Refund records to QuickBooks.

  The entire sync operation runs inside a database transaction holding a
  `FOR UPDATE NOWAIT` row lock on the refund. The lock is held until the
  QuickBooks API call and status update complete, preventing concurrent
  processing of the same refund. If the lock is already held, the job
  returns `:ok` and lets the nightly retry worker pick it up later.
  """

  require Ysc.Logging

  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [
      period: 300,
      fields: [:args, :queue],
      states: :incomplete
    ]

  alias Ysc.Ledgers.Refund
  alias Ysc.Quickbooks.Sync
  alias YscWeb.Workers.QuickbooksSyncJob

  @non_retriable_errors [
    :refund_not_found
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"refund_id" => refund_id}}) do
    Ysc.Logging.info("Starting QuickBooks sync for refund",
      refund_id: refund_id
    )

    QuickbooksSyncJob.lock_and_sync(
      [
        schema: Refund,
        id: refund_id,
        entity: "refund",
        id_key: :refund_id,
        not_found: :refund_not_found,
        non_retriable: @non_retriable_errors,
        success_id_key: :sales_receipt_id,
        already_synced: &QuickbooksSyncJob.synced_sales_receipt_id/1
      ],
      &Sync.sync_refund/1
    )
  end
end
