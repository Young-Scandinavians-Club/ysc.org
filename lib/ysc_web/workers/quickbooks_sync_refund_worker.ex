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
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Ysc.Repo
  alias Ysc.Ledgers.Refund
  alias Ysc.Quickbooks.Sync
  import Ecto.Query

  @non_retriable_errors [
    :refund_not_found
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"refund_id" => refund_id}}) do
    Ysc.Logging.info("Starting QuickBooks sync for refund",
      refund_id: refund_id
    )

    refund_id_ulid =
      case Ecto.ULID.cast(refund_id) do
        {:ok, ulid} -> ulid
        _ -> refund_id
      end

    Repo.transaction(fn ->
      case from(r in Refund,
             where: r.id == ^refund_id_ulid,
             lock: "FOR UPDATE NOWAIT"
           )
           |> Repo.one() do
        nil ->
          Repo.rollback(:refund_not_found)

        %Refund{
          quickbooks_sync_status: "synced",
          quickbooks_sales_receipt_id: sr_id
        }
        when not is_nil(sr_id) ->
          {:already_synced, sr_id}

        refund ->
          Sync.sync_refund(refund)
      end
    end)
    |> handle_result(refund_id)
  rescue
    e in Postgrex.Error ->
      if match?(%{postgres: %{code: :lock_not_available}}, e) do
        Ysc.Logging.info("Refund is locked by another process, skipping",
          refund_id: refund_id
        )

        :ok
      else
        reraise e, __STACKTRACE__
      end
  end

  defp handle_result(result, refund_id) do
    case result do
      {:ok, {:already_synced, sales_receipt_id}} ->
        Ysc.Logging.info("Refund already synced (checked under lock)",
          refund_id: refund_id,
          sales_receipt_id: sales_receipt_id
        )

        :ok

      {:ok, {:ok, sales_receipt}} ->
        Ysc.Logging.info("Successfully synced refund to QuickBooks",
          refund_id: refund_id,
          sales_receipt_id: Map.get(sales_receipt, "Id")
        )

        :ok

      {:ok, {:error, reason}} ->
        classify_error(reason, refund_id)

      {:error, :refund_not_found} ->
        Ysc.Logging.warning("Refund not found for QuickBooks sync",
          refund_id: refund_id
        )

        {:discard, :refund_not_found}

      {:error, reason} ->
        Ysc.Logging.warning("Refund sync transaction failed",
          refund_id: refund_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp classify_error(reason, refund_id) when reason in @non_retriable_errors do
    Ysc.Logging.warning("Discarding refund sync — non-retriable error",
      refund_id: refund_id,
      error: inspect(reason)
    )

    {:discard, reason}
  end

  defp classify_error(reason, refund_id) when is_binary(reason) do
    if validation_fault?(reason) do
      Ysc.Logging.warning(
        "Discarding refund sync — QuickBooks validation error",
        refund_id: refund_id,
        error: reason
      )

      {:discard, reason}
    else
      Ysc.Logging.warning("Failed to sync refund to QuickBooks",
        refund_id: refund_id,
        error: reason
      )

      {:error, reason}
    end
  end

  defp classify_error(reason, refund_id) do
    Ysc.Logging.warning("Failed to sync refund to QuickBooks",
      refund_id: refund_id,
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
