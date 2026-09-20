defmodule YscWeb.Workers.QuickbooksSyncPaymentWorker do
  @moduledoc """
  Oban worker for syncing Payment records to QuickBooks.

  The entire sync operation runs inside a database transaction holding a
  `FOR UPDATE NOWAIT` row lock on the payment. The lock is held until the
  QuickBooks API call and status update complete, preventing concurrent
  processing of the same payment. If the lock is already held, the job
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

  alias Ysc.Ledgers.Payment
  alias Ysc.Quickbooks.Sync
  alias YscWeb.Workers.QuickbooksSyncJob

  @non_retriable_errors [
    :payment_not_found,
    :no_income_account_for_item
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_id" => payment_id}}) do
    Ysc.Logging.info("Starting QuickBooks sync for payment",
      payment_id: payment_id
    )

    QuickbooksSyncJob.lock_and_sync(
      [
        schema: Payment,
        id: payment_id,
        entity: "payment",
        id_key: :payment_id,
        not_found: :payment_not_found,
        non_retriable: @non_retriable_errors,
        success_id_key: :sales_receipt_id,
        already_synced: &QuickbooksSyncJob.synced_sales_receipt_id/1
      ],
      &Sync.sync_payment/1
    )
  end
end
