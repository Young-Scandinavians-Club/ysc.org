defmodule YscWeb.Workers.QuickbooksSyncJob do
  @moduledoc """
  Shared lock, result handling, and error classification for QuickBooks
  payment, refund, and payout Oban workers.

  Those workers all:

  1. Cast the Oban arg to a ULID
  2. `FOR UPDATE NOWAIT` the ledger row for the duration of the QuickBooks call
  3. Treat `lock_not_available` as a skip (`:ok`) for the nightly retry worker
  4. Discard missing rows, configured non-retriable atoms, and QuickBooks
     validation faults; retry everything else

  Expense-report export is a different flow (claim, then release the lock
  before calling QuickBooks) and stays on its own worker.

  ## Examples

      QuickbooksSyncJob.lock_and_sync(
        [
          schema: Ysc.Ledgers.Payment,
          id: payment_id,
          entity: "payment",
          id_key: :payment_id,
          not_found: :payment_not_found,
          non_retriable: [:payment_not_found, :no_income_account_for_item],
          success_id_key: :sales_receipt_id,
          already_synced: &QuickbooksSyncJob.synced_sales_receipt_id/1
        ],
        &Ysc.Quickbooks.Sync.sync_payment/1
      )
  """

  require Ysc.Logging

  import Ecto.Query

  alias Ysc.Ci.QueryExplain.Fixtures
  alias Ysc.Ledgers.Payment
  alias Ysc.Repo

  @doc """
  Casts an Oban job id to a ULID when possible; otherwise returns it unchanged.
  """
  def cast_id(id) do
    case Ecto.ULID.cast(id) do
      {:ok, ulid} -> ulid
      _ -> id
    end
  end

  @doc """
  True when Postgres refused `FOR UPDATE NOWAIT` because another session
  already holds the row lock.
  """
  def lock_not_available?(%Postgrex.Error{
        postgres: %{code: :lock_not_available}
      }),
      do: true

  def lock_not_available?(_), do: false

  @doc """
  QuickBooks validation faults are configuration/data problems; retrying
  the same payload will not fix them.
  """
  def validation_fault?(reason) when is_binary(reason) do
    String.contains?(reason, "2010:") or
      String.contains?(reason, "Request has invalid or unsupported property") or
      String.contains?(reason, "ValidationFault")
  end

  def validation_fault?(_), do: false

  @doc """
  Sales-receipt id when a payment or refund is already marked synced.

  Used as the `:already_synced` callback for those two workers. Payouts
  always re-read QuickBooks for drift, so they omit the callback.
  """
  def synced_sales_receipt_id(%{
        quickbooks_sync_status: "synced",
        quickbooks_sales_receipt_id: sales_receipt_id
      })
      when not is_nil(sales_receipt_id) do
    sales_receipt_id
  end

  def synced_sales_receipt_id(_), do: nil

  @doc """
  Locks the ledger row, runs `fun` inside the transaction, and classifies
  the Oban result.

  ## Options

    * `:schema` — Ecto schema module (required)
    * `:id` — Oban arg id (required)
    * `:entity` — lowercase name used in log messages, e.g. `"payment"` (required)
    * `:id_key` — log metadata key, e.g. `:payment_id` (required)
    * `:not_found` — atom discarded when the row is missing (required)
    * `:success_id_key` — log metadata key for the QuickBooks id (required)
    * `:non_retriable` — atoms that should `{:discard, reason}` instead of retry
    * `:preload` — associations to load after the lock, before `fun`
    * `:already_synced` — `record -> nil | qb_id`; skip `fun` when non-nil
  """
  def lock_and_sync(opts, fun) when is_list(opts) and is_function(fun, 1) do
    schema = Keyword.fetch!(opts, :schema)
    id = Keyword.fetch!(opts, :id)
    preload = Keyword.get(opts, :preload, [])
    already_synced = Keyword.get(opts, :already_synced)

    Repo.transaction(fn ->
      case Repo.one(locked_row_query(schema, cast_id(id))) do
        nil ->
          Repo.rollback(Keyword.fetch!(opts, :not_found))

        record ->
          record = Repo.preload(record, preload)

          case already_synced_id(already_synced, record) do
            nil -> fun.(record)
            qb_id -> {:already_synced, qb_id}
          end
      end
    end)
    |> handle_result(opts)
  rescue
    error in Postgrex.Error ->
      case handle_lock_error(error, opts) do
        :ok -> :ok
        {:reraise, error} -> reraise error, __STACKTRACE__
      end
  end

  @doc """
  Skip (`:ok`) when the row is locked; otherwise `{:reraise, error}` so the
  caller can `reraise` with its own stacktrace.
  """
  def handle_lock_error(%Postgrex.Error{} = error, opts) when is_list(opts) do
    if lock_not_available?(error) do
      entity = Keyword.fetch!(opts, :entity)
      id_key = Keyword.fetch!(opts, :id_key)
      id = Keyword.fetch!(opts, :id)

      Ysc.Logging.info(
        "#{String.capitalize(entity)} is locked by another process, skipping",
        [{id_key, id}]
      )

      :ok
    else
      {:reraise, error}
    end
  end

  @doc """
  Maps a QuickBooks sync failure to Oban's `{:discard, _}` or `{:error, _}`.
  """
  def classify_error(reason, opts) when is_list(opts) do
    entity = Keyword.fetch!(opts, :entity)
    id_key = Keyword.fetch!(opts, :id_key)
    id = Keyword.fetch!(opts, :id)
    non_retriable = Keyword.get(opts, :non_retriable, [])

    cond do
      reason in non_retriable ->
        Ysc.Logging.warning(
          "Discarding #{entity} sync — non-retriable error",
          [{id_key, id}, {:error, inspect(reason)}]
        )

        {:discard, reason}

      is_binary(reason) and validation_fault?(reason) ->
        Ysc.Logging.warning(
          "Discarding #{entity} sync — QuickBooks validation error",
          [{id_key, id}, {:error, reason}]
        )

        {:discard, reason}

      is_binary(reason) ->
        Ysc.Logging.warning(
          "Failed to sync #{entity} to QuickBooks",
          [{id_key, id}, {:error, reason}]
        )

        {:error, reason}

      true ->
        Ysc.Logging.warning(
          "Failed to sync #{entity} to QuickBooks",
          [{id_key, id}, {:error, inspect(reason)}]
        )

        {:error, reason}
    end
  end

  @doc false
  def ci_query_explain_query do
    locked_row_query(Payment, Fixtures.ulid())
  end

  defp locked_row_query(schema, id) do
    from(row in schema, where: row.id == ^id, lock: "FOR UPDATE NOWAIT")
  end

  defp already_synced_id(nil, _record), do: nil

  defp already_synced_id(fun, record) when is_function(fun, 1),
    do: fun.(record)

  defp handle_result(result, opts) do
    entity = Keyword.fetch!(opts, :entity)
    id_key = Keyword.fetch!(opts, :id_key)
    id = Keyword.fetch!(opts, :id)
    not_found = Keyword.fetch!(opts, :not_found)
    success_id_key = Keyword.fetch!(opts, :success_id_key)
    entity_label = String.capitalize(entity)

    case result do
      {:ok, {:already_synced, qb_id}} ->
        Ysc.Logging.info(
          "#{entity_label} already synced (checked under lock)",
          [{id_key, id}, {success_id_key, qb_id}]
        )

        :ok

      {:ok, {:ok, qb_resource}} ->
        Ysc.Logging.info(
          "Successfully synced #{entity} to QuickBooks",
          [{id_key, id}, {success_id_key, Map.get(qb_resource, "Id")}]
        )

        :ok

      {:ok, {:error, reason}} ->
        classify_error(reason, opts)

      {:error, ^not_found} ->
        Ysc.Logging.warning(
          "#{entity_label} not found for QuickBooks sync",
          [{id_key, id}]
        )

        {:discard, not_found}

      {:error, reason} ->
        Ysc.Logging.warning(
          "#{entity_label} sync transaction failed",
          [{id_key, id}, {:error, inspect(reason)}]
        )

        {:error, reason}
    end
  end
end
