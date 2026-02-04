defmodule Ysc.StripeBehaviour do
  @moduledoc """
  Behaviour for Stripe API interactions to facilitate testing.
  """

  @callback create_payment_intent(map(), keyword()) ::
              {:ok, Stripe.PaymentIntent.t()} | {:error, any()}
  @callback retrieve_payment_intent(String.t(), map()) ::
              {:ok, Stripe.PaymentIntent.t()} | {:error, any()}
  @callback cancel_payment_intent(String.t(), map()) ::
              {:ok, Stripe.PaymentIntent.t()} | {:error, any()}
  @callback create_customer(map()) ::
              {:ok, Stripe.Customer.t()} | {:error, any()}
  @callback update_customer(String.t(), map()) ::
              {:ok, Stripe.Customer.t()} | {:error, any()}
  @callback retrieve_payment_method(String.t()) ::
              {:ok, Stripe.PaymentMethod.t()} | {:error, any()}
end
