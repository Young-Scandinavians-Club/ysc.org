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
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Ysc.Repo
  alias Ysc.Ledgers.Payment
  alias Ysc.Quickbooks.Sync
  import Ecto.Query

  @non_retriable_errors [
    :payment_not_found,
    :no_income_account_for_item
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_id" => payment_id}}) do
    Ysc.Logging.info("Starting QuickBooks sync for payment",
      payment_id: payment_id
    )

    payment_id_ulid =
      case Ecto.ULID.cast(payment_id) do
        {:ok, ulid} -> ulid
        _ -> payment_id
      end

    Repo.transaction(fn ->
      case from(p in Payment,
             where: p.id == ^payment_id_ulid,
             lock: "FOR UPDATE NOWAIT"
           )
           |> Repo.one() do
        nil ->
          Repo.rollback(:payment_not_found)

        %Payment{
          quickbooks_sync_status: "synced",
          quickbooks_sales_receipt_id: sr_id
        }
        when not is_nil(sr_id) ->
          {:already_synced, sr_id}

        payment ->
          Sync.sync_payment(payment)
      end
    end)
    |> handle_result(payment_id)
  rescue
    e in Postgrex.Error ->
      if match?(%{postgres: %{code: :lock_not_available}}, e) do
        Ysc.Logging.info("Payment is locked by another process, skipping",
          payment_id: payment_id
        )

        :ok
      else
        reraise e, __STACKTRACE__
      end
  end

  defp handle_result(result, payment_id) do
    case result do
      {:ok, {:already_synced, sales_receipt_id}} ->
        Ysc.Logging.info("Payment already synced (checked under lock)",
          payment_id: payment_id,
          sales_receipt_id: sales_receipt_id
        )

        :ok

      {:ok, {:ok, sales_receipt}} ->
        Ysc.Logging.info("Successfully synced payment to QuickBooks",
          payment_id: payment_id,
          sales_receipt_id: Map.get(sales_receipt, "Id")
        )

        :ok

      {:ok, {:error, reason}} ->
        classify_error(reason, payment_id)

      {:error, :payment_not_found} ->
        Ysc.Logging.warning("Payment not found for QuickBooks sync",
          payment_id: payment_id
        )

        {:discard, :payment_not_found}

      {:error, reason} ->
        Ysc.Logging.warning("Payment sync transaction failed",
          payment_id: payment_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp classify_error(reason, payment_id)
       when reason in @non_retriable_errors do
    Ysc.Logging.warning("Discarding payment sync — non-retriable error",
      payment_id: payment_id,
      error: inspect(reason)
    )

    {:discard, reason}
  end

  defp classify_error(reason, payment_id) when is_binary(reason) do
    if validation_fault?(reason) do
      Ysc.Logging.warning(
        "Discarding payment sync — QuickBooks validation error",
        payment_id: payment_id,
        error: reason
      )

      {:discard, reason}
    else
      Ysc.Logging.warning("Failed to sync payment to QuickBooks",
        payment_id: payment_id,
        error: reason
      )

      {:error, reason}
    end
  end

  defp classify_error(reason, payment_id) do
    Ysc.Logging.warning("Failed to sync payment to QuickBooks",
      payment_id: payment_id,
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
