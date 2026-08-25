defmodule Ysc.StripeRefundApproveTestClient do
  @moduledoc false
  # For `Bookings.approve_pending_refund/4` tests: allow `retrieve_payment_intent/2`
  # (used before refunds) and fail fast on any other StripeBehaviour callback.

  @behaviour Ysc.StripeBehaviour

  @impl true
  def retrieve_payment_intent(id, opts),
    do: Ysc.TestStripeClient.retrieve_payment_intent(id, opts)

  @impl true
  def create_payment_intent(_params, _opts),
    do: unexpected!(:create_payment_intent)

  @impl true
  def cancel_payment_intent(_id, _opts),
    do: unexpected!(:cancel_payment_intent)

  @impl true
  def create_customer(_params),
    do: unexpected!(:create_customer)

  @impl true
  def update_customer(_id, _params),
    do: unexpected!(:update_customer)

  @impl true
  def retrieve_payment_method(_id),
    do: unexpected!(:retrieve_payment_method)

  @impl true
  def list_events(_params, _opts),
    do: unexpected!(:list_events)

  @impl true
  def retrieve_charge(_id, _opts),
    do: unexpected!(:retrieve_charge)

  @impl true
  def retrieve_payout(_id, _opts),
    do: unexpected!(:retrieve_payout)

  @impl true
  def list_balance_transactions(_params, _opts),
    do: unexpected!(:list_balance_transactions)

  @impl true
  def create_terminal_connection_token(_params),
    do: unexpected!(:create_terminal_connection_token)

  @impl true
  def attach_payment_method(_id, _params),
    do: unexpected!(:attach_payment_method)

  @impl true
  def create_setup_intent(_params),
    do: unexpected!(:create_setup_intent)

  defp unexpected!(op),
    do:
      raise(
        "unexpected #{op} in approve_pending_refund test (use TestStripeClient or a dedicated stub)"
      )
end
