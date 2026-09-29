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
  @callback create_setup_intent(map()) ::
              {:ok, Stripe.SetupIntent.t()} | {:error, any()}
  @callback retrieve_invoice(String.t(), map()) ::
              {:ok, Stripe.Invoice.t()} | {:error, any()}
  @callback list_invoice_payments(map(), keyword()) ::
              {:ok, Stripe.List.t(Stripe.InvoicePayment.t())} | {:error, any()}

  # Optional so the many ad-hoc test clients don't all need stubs; callers go
  # through `Ysc.Stripe.InvoiceHelpers`, which treats a missing callback as an
  # error.
  @optional_callbacks retrieve_invoice: 2, list_invoice_payments: 2
end
