defmodule YscWeb.Workers.QuickbooksSyncRefundWorker do
  @moduledoc """
  Oban worker for syncing Refund records to QuickBooks.

  This worker processes refunds asynchronously and creates SalesReceipts (with negative amounts) in QuickBooks.
  """

  require Logger
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Ysc.Repo
  alias Ysc.Ledgers.Refund
  alias Ysc.Quickbooks.Sync

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"refund_id" => refund_id}}) do
    Logger.info("Starting QuickBooks sync for refund", refund_id: refund_id)

    import Ecto.Query

    # Convert refund_id string to ULID if needed
    refund_id_ulid =
      case Ecto.ULID.cast(refund_id) do
        {:ok, ulid} -> ulid
        _ -> refund_id
      end

    # Lock the refund record to prevent concurrent processing
    case Repo.transaction(fn ->
           from(r in Refund,
             where: r.id == ^refund_id_ulid,
             lock: "FOR UPDATE NOWAIT"
           )
           |> Repo.one()
         end) do
      {:ok, nil} ->
        Logger.warning("Refund not found for QuickBooks sync",
          refund_id: refund_id
        )

        {:discard, :refund_not_found}

      {:ok, refund} ->
        # Check if already synced (double-check after acquiring lock)
        if refund.quickbooks_sync_status == "synced" &&
             refund.quickbooks_sales_receipt_id do
          Logger.info(
            "Refund already synced to QuickBooks (checked after lock)",
            refund_id: refund_id,
            sales_receipt_id: refund.quickbooks_sales_receipt_id
          )

          :ok
        else
          case Sync.sync_refund(refund) do
            {:ok, sales_receipt} ->
              Logger.info("Successfully synced refund to QuickBooks",
                refund_id: refund_id,
                sales_receipt_id: Map.get(sales_receipt, "Id")
              )

              :ok

            {:error, reason} ->
              Logger.warning("Failed to sync refund to QuickBooks",
                refund_id: refund_id,
                error: inspect(reason)
              )

              # Report to Sentry
              Sentry.capture_message("QuickBooks refund sync worker failed",
                level: :error,
                extra: %{
                  refund_id: refund_id,
                  error: inspect(reason)
                },
                tags: %{
                  quickbooks_worker: "sync_refund",
                  error_type: "sync_failed"
                }
              )

              # Oban will retry based on max_attempts
              {:error, reason}
          end
        end

      {:error, %Postgrex.Error{postgres: %{code: :lock_not_available}}} ->
        # Another worker is processing this refund
        Logger.info("Refund is locked by another worker, skipping",
          refund_id: refund_id
        )

        :ok

      {:error, reason} ->
        Logger.warning("Failed to lock refund for QuickBooks sync",
          refund_id: refund_id,
          error: inspect(reason)
        )

        # Report to Sentry (only for non-lock errors)
        unless match?(
                 %Postgrex.Error{postgres: %{code: :lock_not_available}},
                 reason
               ) do
          Sentry.capture_message("Failed to lock refund for QuickBooks sync",
            level: :error,
            extra: %{
              refund_id: refund_id,
              error: inspect(reason)
            },
            tags: %{
              quickbooks_worker: "sync_refund",
              error_type: "lock_failed"
            }
          )
        end

        {:error, reason}
    end
  end
end
