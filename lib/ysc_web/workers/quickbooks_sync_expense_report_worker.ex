defmodule YscWeb.Workers.QuickbooksSyncExpenseReportWorker do
  @moduledoc """
  Oban worker for syncing ExpenseReport records to QuickBooks.

  This worker processes expense reports asynchronously and creates Bills in QuickBooks.

  Jobs are unique per `expense_report_id` while incomplete so a treasurer
  reverting and re-approving (or a backup enqueue racing the original job)
  cannot start a second export of the same report. `period: :infinity` keeps
  that uniqueness for as long as the job is still running — receipt uploads
  can outlast a short unique window, and this worker releases its row lock
  before calling QuickBooks.
  """

  require Ysc.Logging

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      period: :infinity,
      fields: [:args],
      keys: [:expense_report_id],
      states: :incomplete
    ]

  alias Ysc.ExpenseReports
  alias Ysc.ExpenseReports.ExpenseReport
  alias Ysc.ExpenseReports.QuickbooksSync
  alias Ysc.Repo
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"expense_report_id" => expense_report_id}}) do
    Ysc.Logging.info("Starting QuickBooks sync for expense report",
      expense_report_id: expense_report_id
    )

    # Convert expense_report_id string to ULID if needed
    expense_report_id_ulid =
      case Ecto.ULID.cast(expense_report_id) do
        {:ok, ulid} -> ulid
        _ -> expense_report_id
      end

    # Lock the row and, still holding the lock, atomically claim it (flip
    # quickbooks_sync_status to "processing") if it's eligible. Claiming
    # inside the same transaction as the lock closes the race where a
    # concurrent correction (ExpenseReports.update_expense_report/2,
    # update_expense_item_amount/2, etc.) changes the report between the
    # eligibility check and the actual QuickBooks export: any such write now
    # blocks on this row lock until the claim commits, and once claimed, the
    # "processing" guard in ExpenseReports.update_unless_report_paid/2
    # refuses corrections until the export finishes.
    case Repo.transaction(fn -> claim_for_sync(expense_report_id_ulid) end) do
      {:ok, :not_found} ->
        Ysc.Logging.warning("Expense report not found for QuickBooks sync",
          expense_report_id: expense_report_id
        )

        # Not found is expected sometimes (e.g. stale job); don't retry.
        {:discard, :expense_report_not_found}

      {:ok, {:skip, reason, details}} ->
        Ysc.Logging.info(
          "Skipping QuickBooks sync for expense report",
          Keyword.merge(
            [expense_report_id: expense_report_id, reason: reason],
            details
          )
        )

        :ok

      {:ok, {:claimed, expense_report}} ->
        case QuickbooksSync.sync_expense_report(expense_report) do
          {:ok, bill} ->
            Ysc.Logging.info(
              "Successfully synced expense report to QuickBooks",
              expense_report_id: expense_report_id,
              bill_id: Map.get(bill, "Id")
            )

            :ok

          {:error, reason} ->
            Ysc.Logging.warning(
              "Failed to sync expense report to QuickBooks",
              expense_report_id: expense_report_id,
              error: inspect(reason)
            )

            # Oban will retry based on max_attempts
            {:error, reason}
        end

      {:error, %Postgrex.Error{postgres: %{code: :lock_not_available}}} ->
        # Another worker is processing this expense report
        Ysc.Logging.info("Expense report is locked by another worker, skipping",
          expense_report_id: expense_report_id
        )

        :ok

      {:error, reason} ->
        Ysc.Logging.warning("Failed to lock expense report for QuickBooks sync",
          expense_report_id: expense_report_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Locks the row, then -- still holding the lock -- decides whether the
  # report is eligible for export and, if so, durably claims it by flipping
  # quickbooks_sync_status to "processing" before the lock is released.
  # "processing" stays eligible for reclaim (alongside "pending"/"failed") so
  # this same job can pick back up its own claim on retry after a crash that
  # never reached the error handler in QuickbooksSync.sync_expense_report/1.
  defp claim_for_sync(expense_report_id) do
    from(er in ExpenseReports.ExpenseReport,
      where: er.id == ^expense_report_id,
      lock: "FOR UPDATE NOWAIT"
    )
    |> Repo.one()
    |> case do
      nil ->
        :not_found

      %ExpenseReport{quickbooks_bill_id: bill_id} = report
      when not is_nil(bill_id) ->
        {:skip, :already_has_bill_id,
         bill_id: bill_id, sync_status: report.quickbooks_sync_status}

      %ExpenseReport{status: status} when status != "approved" ->
        {:skip, :not_approved, status: status}

      %ExpenseReport{quickbooks_sync_status: "synced"} = report ->
        {:skip, :already_synced, sync_status: report.quickbooks_sync_status}

      %ExpenseReport{quickbooks_sync_status: sync_status}
      when sync_status not in [nil, "pending", "failed", "processing"] ->
        {:skip, :unexpected_sync_status, sync_status: sync_status}

      report ->
        if report.quickbooks_sync_status == "failed" do
          Ysc.Logging.info(
            "Retrying QuickBooks sync for previously failed expense report",
            expense_report_id: report.id,
            previous_error: report.quickbooks_sync_error
          )
        end

        # `Ecto.Changeset.change/2` rather than `ExpenseReport.changeset/2`:
        # this record isn't preloaded yet, and the full changeset's
        # `cast_assoc(:expense_items, ...)` / receipt validation raise on an
        # unloaded association. A plain field flip needs none of that.
        #
        # Stamp `quickbooks_last_sync_attempt_at` here — not later in
        # `QuickbooksSync.sync_expense_report/1` — so the backup worker's
        # stale-claim query does not treat a just-claimed report as abandoned
        # (`is_nil(last_sync_attempt_at)`).
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        {:ok, claimed} =
          report
          |> Ecto.Changeset.change(%{
            quickbooks_sync_status: "processing",
            quickbooks_last_sync_attempt_at: now
          })
          |> Repo.update()

        preloaded =
          claimed
          |> Repo.preload([
            :expense_items,
            :income_items,
            :address,
            :bank_account,
            :event
          ])
          |> Repo.preload(user: :billing_address)

        Ysc.Logging.debug("Claimed expense report for QuickBooks sync",
          expense_report_id: preloaded.id,
          expense_items_count:
            if(Ecto.assoc_loaded?(preloaded.expense_items),
              do: length(preloaded.expense_items),
              else: :not_loaded
            ),
          income_items_count:
            if(Ecto.assoc_loaded?(preloaded.income_items),
              do: length(preloaded.income_items),
              else: :not_loaded
            )
        )

        {:claimed, preloaded}
    end
  end
end
