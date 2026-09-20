defmodule YscWeb.Workers.QuickbooksSyncPayoutWorker do
  @moduledoc """
  Oban worker for syncing Payout records to QuickBooks.

  The entire sync operation runs inside a database transaction holding a
  `FOR UPDATE NOWAIT` row lock on the payout. The lock is held until the
  QuickBooks API call and status update complete, preventing concurrent
  processing of the same payout. If the lock is already held, the job
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

  alias Ysc.Ledgers.Payout
  alias Ysc.Quickbooks.Sync
  alias YscWeb.Workers.QuickbooksSyncJob

  @non_retriable_errors [
    :quickbooks_accounts_not_configured,
    :payout_not_found,
    :invalid_bank_account,
    # A negative payout.paid amount (Stripe debiting our bank account to
    # cover a negative Stripe balance) syncs as a JournalEntry instead of a
    # Deposit. These two mean the JournalEntry couldn't be built correctly -
    # a config/data issue that retrying won't fix.
    :payout_journal_entry_unbalanced,
    :stripe_fees_account_not_found,
    # A stale SyncToken means the Deposit was edited elsewhere (most likely
    # a human, in QuickBooks) - Sync already sent a Discord alert for it.
    # Retrying just re-reads the same conflicted Deposit and re-alerts up to
    # max_attempts times for the same one-time event.
    :stale_object
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payout_id" => payout_id}}) do
    Ysc.Logging.info("Starting QuickBooks sync for payout",
      payout_id: payout_id
    )

    QuickbooksSyncJob.lock_and_sync(
      [
        schema: Payout,
        id: payout_id,
        entity: "payout",
        id_key: :payout_id,
        not_found: :payout_not_found,
        preload: [:payments, :refunds],
        non_retriable: @non_retriable_errors,
        success_id_key: :deposit_id
      ],
      &Sync.sync_payout/1
    )
  end
end
