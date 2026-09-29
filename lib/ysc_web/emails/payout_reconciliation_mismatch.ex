defmodule YscWeb.Emails.PayoutReconciliationMismatch do
  @moduledoc """
  Email template alerting the Treasurer that a Stripe payout does not
  reconcile: linked payments − refunds − fees + reserve adjustment doesn't
  equal the amount Stripe actually wired to the bank.

  Sent by `Ysc.Ledgers.ReconciliationWorker` after its nightly payout re-link
  attempt, so late-settling charges get a chance to link before anyone is
  emailed.
  """
  use MjmlEEx,
    mjml_template: "templates/payout_reconciliation_mismatch.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [absolute_url: 1, format_datetime: 1, format_money: 1]

  def get_template_name, do: "payout_reconciliation_mismatch"

  def get_subject(stripe_payout_id),
    do: "Payout reconciliation mismatch: #{stripe_payout_id}"

  @doc """
  Builds template assigns from a payout and its
  `Ysc.Ledgers.Reconciliation.payout_composition/1` breakdown.
  """
  def build_assigns(payout, composition) do
    %{
      stripe_payout_id: payout.stripe_payout_id,
      payout_date: format_datetime(payout.arrival_date || payout.inserted_at),
      payout_amount: format_money(composition.payout_amount),
      payments_count: composition.payments_count,
      payments_total: format_money(composition.payments_total),
      refunds_count: composition.refunds_count,
      refunds_total: format_money(composition.refunds_total),
      fee_total: format_money(composition.fee_total),
      reserve_adjustment: format_money(composition.reserve_adjustment),
      computed_net: format_money(composition.computed_net),
      difference: format_money(composition.difference),
      quickbooks_deposit_id: payout.quickbooks_deposit_id || "Not synced",
      stripe_payout_url:
        "https://dashboard.stripe.com/payouts/#{payout.stripe_payout_id}",
      admin_money_url: absolute_url("/admin/money")
    }
  end
end
