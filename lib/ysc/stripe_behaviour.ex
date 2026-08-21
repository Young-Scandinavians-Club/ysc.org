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
  @callback list_events(map(), keyword()) ::
              {:ok, Stripe.List.t(any())} | {:error, any()}
  @callback retrieve_charge(String.t(), keyword()) ::
              {:ok, Stripe.Charge.t()} | {:error, any()}
  @callback retrieve_payout(String.t(), keyword()) ::
              {:ok, Stripe.Payout.t()} | {:error, any()}
  @callback list_balance_transactions(map(), keyword()) ::
              {:ok, Stripe.List.t(any())} | {:error, any()}
  @callback create_terminal_connection_token(map()) ::
              {:ok, Stripe.Terminal.ConnectionToken.t()} | {:error, any()}
  @callback attach_payment_method(String.t(), map()) ::
              {:ok, Stripe.PaymentMethod.t()} | {:error, any()}
end
