defmodule Ysc.Webhooks.MembershipFeeBackfill do
  @moduledoc """
  Backfills the Stripe processing fee ledger entry for membership/subscription
  payments processed before the invoice `charge_id` resolution fix.

  Root cause: Stripe's `invoice.payment_succeeded` webhook delivers the
  invoice with `payments: null` - that collection is only populated on a
  live API call with `expand: ["payments"]`, never on the webhook payload.
  `Ysc.Stripe.InvoiceHelpers.charge_id/1` only inspected the local payload,
  so it could never resolve a charge for a webhook-driven invoice, and
  `extract_stripe_fee_from_invoice/1` silently fell back to a $0 fee for
  every membership payment - skipping the fee ledger entry every time.

  This module finds payments still missing that entry and books it using
  the same (now-fixed) fee resolution path used for new payments, so a
  backfilled payment's fee is computed identically to how it always should
  have been.
  """

  require Ysc.Logging

  alias Ysc.Ledgers
  alias Ysc.Ledgers.Payment
  alias Ysc.Stripe.WebhookHandler

  @doc """
  Lists payments missing a Stripe processing fee entry.

  ## Options
  - `:limit` - Maximum number of payments to return (default: 1000)
  """
  def list_affected_payments(opts \\ []) do
    Ledgers.list_payments_missing_stripe_fee(opts)
  end

  @doc """
  Resolves and books the missing Stripe fee for a single payment.

  Returns:
  - `{:ok, :no_fee}` - the resolved fee was $0 (nothing to book)
  - `{:ok, :already_booked}` - a fee entry already exists (no-op)
  - `{:ok, entries}` - the fee was booked, with the created ledger entries
  - `{:error, reason}` - fee resolution or booking failed
  """
  def backfill_payment(%Payment{} = payment) do
    invoice = %{id: payment.external_payment_id}
    fee_amount = WebhookHandler.extract_stripe_fee_from_invoice(invoice)

    Ysc.Logging.info("Resolved fee for backfill",
      payment_id: payment.id,
      external_payment_id: payment.external_payment_id,
      fee_amount: Money.to_string!(fee_amount)
    )

    Ledgers.backfill_payment_stripe_fee(payment, fee_amount)
  rescue
    error ->
      Ysc.Logging.error("Failed to backfill payment Stripe fee",
        payment_id: payment.id,
        error: Exception.message(error)
      )

      {:error, {:backfill_failed, Exception.message(error)}}
  end

  @doc """
  Runs the backfill across all affected payments.

  ## Options
  - `:limit` - Maximum number of payments to process (default: 1000)
  - `:dry_run` - If true, only lists what would be processed (default: false)

  Returns a summary map.
  """
  def run(opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    payments = list_affected_payments(opts)

    if dry_run do
      %{
        total_found: length(payments),
        would_process: payments,
        summary: "Dry run - no payments were actually processed"
      }
    else
      results =
        Enum.map(payments, fn payment ->
          {payment, backfill_payment(payment)}
        end)

      booked =
        Enum.count(results, fn
          {_payment, {:ok, entries}} when is_list(entries) -> true
          _ -> false
        end)

      no_fee =
        Enum.count(results, fn {_payment, result} ->
          result == {:ok, :no_fee}
        end)

      already_booked =
        Enum.count(results, fn {_payment, result} ->
          result == {:ok, :already_booked}
        end)

      failed =
        Enum.count(results, fn
          {_payment, {:error, _}} -> true
          _ -> false
        end)

      total_booked_amount =
        results
        |> Enum.reduce(Money.new(0, :USD), fn
          {_payment, {:ok, [fee_entry, _] = _entries}}, acc ->
            case Money.add(acc, fee_entry.amount) do
              {:ok, sum} -> sum
              {:error, _} -> acc
            end

          _, acc ->
            acc
        end)

      %{
        total_found: length(payments),
        booked: booked,
        no_fee: no_fee,
        already_booked: already_booked,
        failed: failed,
        total_booked_amount: total_booked_amount,
        results: results,
        summary:
          "Booked #{booked} fee entries totaling #{Money.to_string!(total_booked_amount)} " <>
            "(#{no_fee} had no fee, #{already_booked} already booked, #{failed} failed)"
      }
    end
  end
end
