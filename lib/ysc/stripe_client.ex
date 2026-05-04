defmodule Ysc.StripeClient do
  @moduledoc """
  Default implementation of Ysc.StripeBehaviour that calls the Stripe library.

  All calls are wrapped with `Ysc.Stripe.RetryHelper.stripe_retry/1` so that
  transient Stripe 429 rate-limit responses are retried automatically with
  exponential backoff.
  """
  @behaviour Ysc.StripeBehaviour

  import Ysc.Stripe.RetryHelper, only: [stripe_retry: 1]

  def create_payment_intent(params, opts),
    do: stripe_retry(fn -> Stripe.PaymentIntent.create(params, opts) end)

  def retrieve_payment_intent(id, opts),
    do: stripe_retry(fn -> Stripe.PaymentIntent.retrieve(id, opts) end)

  def cancel_payment_intent(id, opts),
    do: stripe_retry(fn -> Stripe.PaymentIntent.cancel(id, opts) end)

  def create_customer(params),
    do: stripe_retry(fn -> Stripe.Customer.create(params) end)

  def update_customer(id, params),
    do: stripe_retry(fn -> Stripe.Customer.update(id, params) end)

  def retrieve_payment_method(id),
    do: stripe_retry(fn -> Stripe.PaymentMethod.retrieve(id) end)

  def list_events(params, opts \\ []),
    do: stripe_retry(fn -> Stripe.Event.list(params, opts) end)

  def retrieve_charge(id, opts \\ []),
    do: stripe_retry(fn -> Stripe.Charge.retrieve(id, opts) end)

  def retrieve_payout(id, opts \\ []),
    do: stripe_retry(fn -> Stripe.Payout.retrieve(id, opts) end)

  def list_balance_transactions(params, opts \\ []),
    do: stripe_retry(fn -> Stripe.BalanceTransaction.list(params, opts) end)
end
