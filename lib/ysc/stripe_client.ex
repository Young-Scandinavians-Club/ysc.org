defmodule Ysc.StripeClient do
  @moduledoc """
  Default implementation of Ysc.StripeBehaviour that calls the Stripe library.
  """
  @behaviour Ysc.StripeBehaviour

  def create_payment_intent(params, opts),
    do: Stripe.PaymentIntent.create(params, opts)

  def retrieve_payment_intent(id, opts),
    do: Stripe.PaymentIntent.retrieve(id, opts)

  def cancel_payment_intent(id, opts), do: Stripe.PaymentIntent.cancel(id, opts)
  def create_customer(params), do: Stripe.Customer.create(params)
  def update_customer(id, params), do: Stripe.Customer.update(id, params)
  def retrieve_payment_method(id), do: Stripe.PaymentMethod.retrieve(id)
end
