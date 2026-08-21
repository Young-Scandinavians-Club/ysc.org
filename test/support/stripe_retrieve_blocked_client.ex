defmodule Ysc.StripeRetrieveBlockedClient do
  @moduledoc false
  # Fails `retrieve_payment_intent/2` so tests that must not touch Stripe refund
  # paths still fail loudly if that code regresses.

  @behaviour Ysc.StripeBehaviour

  @impl true
  def retrieve_payment_intent(_id, _opts),
    do: {:error, :retrieve_blocked_in_test}

  @impl true
  defdelegate create_payment_intent(p, o), to: Ysc.TestStripeClient

  @impl true
  defdelegate cancel_payment_intent(id, o), to: Ysc.TestStripeClient

  @impl true
  defdelegate create_customer(p), to: Ysc.TestStripeClient

  @impl true
  defdelegate update_customer(id, p), to: Ysc.TestStripeClient

  @impl true
  defdelegate retrieve_payment_method(id), to: Ysc.TestStripeClient

  @impl true
  defdelegate list_events(p, o), to: Ysc.TestStripeClient

  @impl true
  defdelegate retrieve_charge(id, o), to: Ysc.TestStripeClient

  @impl true
  defdelegate retrieve_payout(id, o), to: Ysc.TestStripeClient

  @impl true
  defdelegate list_balance_transactions(p, o), to: Ysc.TestStripeClient

  @impl true
  defdelegate create_terminal_connection_token(p), to: Ysc.TestStripeClient

  @impl true
  defdelegate attach_payment_method(id, p), to: Ysc.TestStripeClient
end
