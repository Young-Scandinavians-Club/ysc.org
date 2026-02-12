defmodule YscWeb.Workers.QuickbooksSyncPaymentWorker do
  @moduledoc """
  Oban worker for syncing Payment records to QuickBooks.

  This worker processes payments asynchronously and creates SalesReceipts in QuickBooks.
  """

  require Ysc.Logging
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Ysc.Quickbooks.Sync

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_id" => payment_id}}) do
    Ysc.Logging.info("Starting QuickBooks sync for payment",
      payment_id: payment_id
    )

    alias Ysc.Repo
    alias Ysc.Ledgers.Payment
    import Ecto.Query

    # Convert payment_id string to ULID if needed
    payment_id_ulid =
      case Ecto.ULID.cast(payment_id) do
        {:ok, ulid} -> ulid
        _ -> payment_id
      end

    # Lock the payment record to prevent concurrent processing
    case Repo.transaction(fn ->
           from(p in Payment,
             where: p.id == ^payment_id_ulid,
             lock: "FOR UPDATE NOWAIT"
           )
           |> Repo.one()
         end) do
      {:ok, nil} ->
        Ysc.Logging.warning("Payment not found for QuickBooks sync",
          payment_id: payment_id
        )

        {:discard, :payment_not_found}

      {:ok, payment} ->
        # Check if already synced (double-check after acquiring lock)
        if payment.quickbooks_sync_status == "synced" &&
             payment.quickbooks_sales_receipt_id do
          Ysc.Logging.info(
            "Payment already synced to QuickBooks (checked after lock)",
            payment_id: payment_id,
            sales_receipt_id: payment.quickbooks_sales_receipt_id
          )

          :ok
        else
          case Sync.sync_payment(payment) do
            {:ok, sales_receipt} ->
              Ysc.Logging.info("Successfully synced payment to QuickBooks",
                payment_id: payment_id,
                sales_receipt_id: Map.get(sales_receipt, "Id")
              )

              :ok

            {:error, reason} ->
              Ysc.Logging.warning("Failed to sync payment to QuickBooks",
                payment_id: payment_id,
                error: inspect(reason)
              )

              # Oban will retry based on max_attempts
              {:error, reason}
          end
        end

      {:error, %Postgrex.Error{postgres: %{code: :lock_not_available}}} ->
        # Another worker is processing this payment
        Ysc.Logging.info("Payment is locked by another worker, skipping",
          payment_id: payment_id
        )

        :ok

      {:error, reason} ->
        Ysc.Logging.warning("Failed to lock payment for QuickBooks sync",
          payment_id: payment_id,
          error: inspect(reason)
        )

        # Report to Sentry (only for non-lock errors)
        unless match?(
                 %Postgrex.Error{postgres: %{code: :lock_not_available}},
                 reason
               ) do
        end

        {:error, reason}
    end
  end
end
