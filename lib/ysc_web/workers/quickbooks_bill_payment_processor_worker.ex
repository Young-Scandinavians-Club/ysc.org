defmodule YscWeb.Workers.QuickbooksBillPaymentProcessorWorker do
  @moduledoc """
  Oban worker for processing QuickBooks BillPayment webhook events.

  This worker:
  1. Fetches the BillPayment details from QuickBooks API
  2. Finds the linked Bill(s) (expense report(s)) using the LinkedTxn field
  3. Confirms each linked Bill is actually fully paid (not just referenced by
     a BillPayment - QuickBooks allows partial payments, and voided
     BillPayments still exist as records with their amounts zeroed out)
  4. Updates the expense report status to "paid" only when payment is confirmed
  """
  require Ysc.Logging
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Ysc.Webhooks
  alias Ysc.ExpenseReports
  alias Ysc.Repo

  # Statuses an expense report may transition to "paid" from. A report that's
  # already paid is left alone (idempotent), and a report we didn't expect to
  # see a payment for (draft/rejected) is logged instead of silently flipped,
  # since that indicates something unexpected happened out-of-band in QuickBooks.
  @paid_eligible_statuses ["submitted", "approved"]

  defp client do
    Application.get_env(:ysc, :quickbooks_client, Ysc.Quickbooks.Client)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "webhook_event_id" => webhook_event_id,
          "bill_payment_id" => bill_payment_id
        }
      }) do
    Ysc.Logging.info("Processing QuickBooks BillPayment",
      webhook_event_id: webhook_event_id,
      bill_payment_id: bill_payment_id
    )

    # Lock the webhook event for processing
    case Webhooks.lock_webhook_event(webhook_event_id) do
      {:ok, webhook_event} ->
        process_bill_payment(webhook_event, bill_payment_id)

      {:error, :not_found} ->
        Ysc.Logging.warning("Webhook event not found",
          webhook_event_id: webhook_event_id
        )

        {:error, :webhook_not_found}

      {:error, :already_processing} ->
        Ysc.Logging.info("Webhook event already being processed, skipping",
          webhook_event_id: webhook_event_id
        )

        :ok
    end
  end

  defp process_bill_payment(webhook_event, bill_payment_id) do
    # Fetch the BillPayment from QuickBooks
    case client().get_bill_payment(bill_payment_id) do
      {:ok, bill_payment} ->
        Ysc.Logging.info("Retrieved BillPayment from QuickBooks",
          bill_payment_id: bill_payment_id,
          bill_payment: inspect(bill_payment, limit: 50)
        )

        cond do
          bill_payment_voided?(bill_payment) ->
            # A voided BillPayment is returned by QuickBooks with the same Id
            # but TotalAmt zeroed out. Treat it as if no payment happened -
            # marking a report paid off a voided payment would be wrong, and
            # we deliberately don't auto-revert an already-"paid" report here
            # either, since that's a business decision that deserves human
            # review rather than a silent status flip.
            Ysc.Logging.warning(
              "BillPayment appears voided (TotalAmt is zero); not marking any expense report as paid",
              bill_payment_id: bill_payment_id
            )

            Webhooks.update_webhook_state(webhook_event, :processed)
            :ok

          true ->
            # QuickBooks nests LinkedTxn under each Line item, not at the
            # top level of the BillPayment.
            linked_txns =
              bill_payment
              |> Map.get("Line", [])
              |> Enum.flat_map(fn line -> Map.get(line, "LinkedTxn", []) end)

            case linked_bill_ids(linked_txns) do
              [] ->
                Ysc.Logging.warning("BillPayment has no linked Bill",
                  bill_payment_id: bill_payment_id
                )

                Webhooks.update_webhook_state(webhook_event, :processed)
                :ok

              bill_ids ->
                finalize_linked_bills(webhook_event, bill_payment_id, bill_ids)
            end
        end

      {:error, reason} ->
        Ysc.Logging.warning("Failed to fetch BillPayment from QuickBooks",
          bill_payment_id: bill_payment_id,
          error: inspect(reason)
        )

        if reason != :not_found do
          Webhooks.update_webhook_state(webhook_event, :failed)
        end

        {:error, :fetch_failed}
    end
  end

  # A single BillPayment can settle multiple Bills at once. Process every
  # linked Bill rather than just the first match, so a split payment doesn't
  # leave other expense reports stuck unpaid.
  defp finalize_linked_bills(webhook_event, bill_payment_id, bill_ids) do
    results =
      Enum.map(bill_ids, fn bill_id ->
        process_linked_bill(bill_id, bill_payment_id)
      end)

    if Enum.any?(results, &match?({:error, _}, &1)) do
      Ysc.Logging.error(
        "One or more linked Bills failed to process for BillPayment",
        bill_payment_id: bill_payment_id,
        results: inspect(results)
      )

      Webhooks.update_webhook_state(webhook_event, :failed)
      {:error, :update_failed}
    else
      Webhooks.update_webhook_state(webhook_event, :processed)
      :ok
    end
  end

  defp process_linked_bill(bill_id, bill_payment_id) do
    case ExpenseReports.get_expense_report_by_quickbooks_bill_id(bill_id) do
      {:ok, expense_report} ->
        Ysc.Logging.info("Found expense report for Bill",
          expense_report_id: expense_report.id,
          bill_id: bill_id,
          bill_payment_id: bill_payment_id,
          current_status: expense_report.status
        )

        case confirm_bill_fully_paid(bill_id) do
          {:ok, true} ->
            lock_and_maybe_mark_paid(bill_id, bill_payment_id)

          {:ok, false} ->
            Ysc.Logging.info(
              "Bill still has an outstanding balance; not marking expense report as paid yet",
              bill_id: bill_id,
              bill_payment_id: bill_payment_id,
              expense_report_id: expense_report.id
            )

            :ok

          {:error, :not_found} ->
            # The Bill itself is gone from QuickBooks. That's the concern of
            # the Bill-deletion sync path, not this BillPayment worker, so we
            # just log and move on without changing status here.
            Ysc.Logging.warning(
              "Bill no longer exists in QuickBooks while processing BillPayment",
              bill_id: bill_id,
              bill_payment_id: bill_payment_id
            )

            :ok

          {:error, reason} ->
            # Couldn't confirm the Bill's balance - don't guess. Fail so Oban
            # retries rather than risk marking (or not marking) paid on
            # incomplete information.
            Ysc.Logging.warning(
              "Failed to confirm Bill balance from QuickBooks",
              bill_id: bill_id,
              bill_payment_id: bill_payment_id,
              error: inspect(reason)
            )

            {:error, :bill_fetch_failed}
        end

      {:error, :not_found} ->
        Ysc.Logging.warning(
          "No expense report found for QuickBooks Bill",
          bill_id: bill_id,
          bill_payment_id: bill_payment_id
        )

        :ok
    end
  end

  # Re-fetches the expense report with a row lock and applies the paid
  # transition inside a transaction, so a concurrent Bill Delete/Void webhook
  # for the same report (processed by
  # YscWeb.Workers.QuickbooksBillDeletedProcessorWorker) can't interleave its
  # own read-modify-write between our read and our write.
  defp lock_and_maybe_mark_paid(bill_id, bill_payment_id) do
    Repo.transaction(fn ->
      case ExpenseReports.get_expense_report_by_quickbooks_bill_id(bill_id,
             lock: true
           ) do
        {:ok, expense_report} ->
          maybe_mark_paid(expense_report, bill_id, bill_payment_id)

        {:error, :not_found} ->
          :ok
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_mark_paid(expense_report, bill_id, bill_payment_id) do
    cond do
      expense_report.status == "paid" ->
        Ysc.Logging.info(
          "Expense report already marked paid, skipping (idempotent)",
          expense_report_id: expense_report.id,
          bill_id: bill_id
        )

        :ok

      expense_report.status not in @paid_eligible_statuses ->
        Ysc.Logging.warning(
          "BillPayment confirmed paid for expense report in unexpected status; skipping automatic transition for manual review",
          expense_report_id: expense_report.id,
          bill_id: bill_id,
          bill_payment_id: bill_payment_id,
          current_status: expense_report.status
        )

        :ok

      true ->
        case ExpenseReports.mark_expense_report_as_paid(expense_report) do
          {:ok, updated_report} ->
            Ysc.Logging.info(
              "Successfully marked expense report as paid",
              expense_report_id: updated_report.id,
              bill_id: bill_id,
              bill_payment_id: bill_payment_id
            )

            :ok

          {:error, changeset} ->
            Ysc.Logging.error("Failed to mark expense report as paid",
              expense_report_id: expense_report.id,
              errors: inspect(changeset.errors)
            )

            {:error, :update_failed}
        end
    end
  end

  # Confirms a Bill is fully paid by checking its remaining Balance in
  # QuickBooks, rather than trusting that a linked BillPayment alone means
  # the Bill is settled (QuickBooks allows partial payments across multiple
  # BillPayments).
  defp confirm_bill_fully_paid(bill_id) do
    case client().get_bill(bill_id) do
      {:ok, bill} ->
        case to_amount(Map.get(bill, "Balance")) do
          nil ->
            Ysc.Logging.warning(
              "QuickBooks Bill response missing Balance field; treating as not fully paid",
              bill_id: bill_id
            )

            {:ok, false}

          balance ->
            {:ok, balance <= 0.005}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A voided BillPayment is returned by QuickBooks with TotalAmt reset to 0
  # while the record (and its LinkedTxn) otherwise still exists.
  defp bill_payment_voided?(bill_payment) do
    case to_amount(Map.get(bill_payment, "TotalAmt")) do
      nil -> false
      amount -> amount <= 0.005
    end
  end

  defp to_amount(nil), do: nil
  defp to_amount(%Decimal{} = amount), do: Decimal.to_float(amount)
  defp to_amount(amount) when is_number(amount), do: amount * 1.0

  defp to_amount(amount) when is_binary(amount) do
    case Float.parse(amount) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp to_amount(_), do: nil

  # Finds every linked Bill's TxnId from a list of LinkedTxn entries (as
  # gathered from each BillPayment Line item).
  # LinkedTxn format: [%{"TxnId" => "123", "TxnType" => "Bill"}]
  defp linked_bill_ids(linked_txns) do
    linked_txns
    |> Enum.filter(fn txn -> Map.get(txn, "TxnType") == "Bill" end)
    |> Enum.map(fn txn -> Map.get(txn, "TxnId") end)
    |> Enum.filter(& &1)
    |> Enum.uniq()
  end
end
