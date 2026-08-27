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

  alias Ysc.Repo
  alias Ysc.Ledgers.Payout
  alias Ysc.Quickbooks.Sync
  import Ecto.Query

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

    payout_id_ulid =
      case Ecto.ULID.cast(payout_id) do
        {:ok, ulid} -> ulid
        _ -> payout_id
      end

    Repo.transaction(fn ->
      case from(p in Payout,
             where: p.id == ^payout_id_ulid,
             lock: "FOR UPDATE NOWAIT"
           )
           |> Repo.one() do
        nil ->
          Repo.rollback(:payout_not_found)

        payout ->
          # Sync.sync_payout/1 is the single source of truth for create vs.
          # update vs. no-op - it checks quickbooks_deposit_id itself and, if
          # one already exists, diffs it against QuickBooks before deciding
          # whether there's anything to do. No pre-check needed here.
          payout = Repo.preload(payout, [:payments, :refunds])
          Sync.sync_payout(payout)
      end
    end)
    |> handle_result(payout_id)
  rescue
    e in Postgrex.Error ->
      if match?(%{postgres: %{code: :lock_not_available}}, e) do
        Ysc.Logging.info("Payout is locked by another process, skipping",
          payout_id: payout_id
        )

        :ok
      else
        reraise e, __STACKTRACE__
      end
  end

  defp handle_result(result, payout_id) do
    case result do
      {:ok, {:ok, deposit}} ->
        Ysc.Logging.info("Successfully synced payout to QuickBooks",
          payout_id: payout_id,
          deposit_id: Map.get(deposit, "Id")
        )

        :ok

      {:ok, {:error, reason}} ->
        classify_error(reason, payout_id)

      {:error, :payout_not_found} ->
        Ysc.Logging.warning("Payout not found for QuickBooks sync",
          payout_id: payout_id
        )

        {:discard, :payout_not_found}

      {:error, reason} ->
        Ysc.Logging.warning("Payout sync transaction failed",
          payout_id: payout_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp classify_error(reason, payout_id) when reason in @non_retriable_errors do
    Ysc.Logging.warning("Discarding payout sync — non-retriable error",
      payout_id: payout_id,
      error: inspect(reason)
    )

    {:discard, reason}
  end

  defp classify_error(reason, payout_id) when is_binary(reason) do
    if validation_fault?(reason) do
      Ysc.Logging.warning(
        "Discarding payout sync — QuickBooks validation error",
        payout_id: payout_id,
        error: reason
      )

      {:discard, reason}
    else
      Ysc.Logging.warning("Failed to sync payout to QuickBooks",
        payout_id: payout_id,
        error: reason
      )

      {:error, reason}
    end
  end

  defp classify_error(reason, payout_id) do
    Ysc.Logging.warning("Failed to sync payout to QuickBooks",
      payout_id: payout_id,
      error: inspect(reason)
    )

    {:error, reason}
  end

  defp validation_fault?(reason) when is_binary(reason) do
    String.contains?(reason, "2010:") or
      String.contains?(reason, "Request has invalid or unsupported property") or
      String.contains?(reason, "ValidationFault")
  end
end
