defmodule YscWeb.Workers.QuickbooksSyncPayoutWorker do
  @moduledoc """
  Oban worker for syncing Payout records to QuickBooks.

  This worker processes Stripe payouts asynchronously and creates Deposits in QuickBooks.
  """

  require Logger
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Ysc.Quickbooks.Sync

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payout_id" => payout_id}}) do
    Logger.info("Starting QuickBooks sync for payout", payout_id: payout_id)

    alias Ysc.Repo
    alias Ysc.Ledgers.Payout
    import Ecto.Query

    # Convert payout_id string to ULID if needed
    payout_id_ulid =
      case Ecto.ULID.cast(payout_id) do
        {:ok, ulid} -> ulid
        _ -> payout_id
      end

    # Lock the payout record to prevent concurrent processing
    case Repo.transaction(fn ->
           from(p in Payout,
             where: p.id == ^payout_id_ulid,
             lock: "FOR UPDATE NOWAIT"
           )
           |> Repo.one()
         end) do
      {:ok, nil} ->
        Logger.warning("Payout not found for QuickBooks sync",
          payout_id: payout_id
        )

        {:discard, :payout_not_found}

      {:ok, payout} ->
        # Check if already synced (double-check after acquiring lock)
        if payout.quickbooks_sync_status == "synced" &&
             payout.quickbooks_deposit_id do
          Logger.info(
            "Payout already synced to QuickBooks (checked after lock)",
            payout_id: payout_id,
            deposit_id: payout.quickbooks_deposit_id
          )

          :ok
        else
          # Preload payments and refunds for the sync
          payout = Repo.preload(payout, [:payments, :refunds])

          case Sync.sync_payout(payout) do
            {:ok, deposit} ->
              Logger.info("Successfully synced payout to QuickBooks",
                payout_id: payout_id,
                deposit_id: Map.get(deposit, "Id")
              )

              :ok

            {:error, reason} ->
              Logger.warning("Failed to sync payout to QuickBooks",
                payout_id: payout_id,
                error: inspect(reason)
              )

              # Report to Sentry
              Sentry.capture_message("QuickBooks payout sync worker failed",
                level: :error,
                extra: %{
                  payout_id: payout_id,
                  error: inspect(reason)
                },
                tags: %{
                  quickbooks_worker: "sync_payout",
                  error_type: "sync_failed"
                }
              )

              # Oban will retry based on max_attempts
              {:error, reason}
          end
        end

      {:error, %Postgrex.Error{postgres: %{code: :lock_not_available}}} ->
        # Another worker is processing this payout
        Logger.info("Payout is locked by another worker, skipping",
          payout_id: payout_id
        )

        :ok

      {:error, reason} ->
        Logger.warning("Failed to lock payout for QuickBooks sync",
          payout_id: payout_id,
          error: inspect(reason)
        )

        # Report to Sentry (only for non-lock errors)
        unless match?(
                 %Postgrex.Error{postgres: %{code: :lock_not_available}},
                 reason
               ) do
          Sentry.capture_message("Failed to lock payout for QuickBooks sync",
            level: :error,
            extra: %{
              payout_id: payout_id,
              error: inspect(reason)
            },
            tags: %{
              quickbooks_worker: "sync_payout",
              error_type: "lock_failed"
            }
          )
        end

        {:error, reason}
    end
  end
end
