defmodule Ysc.Stripe.InvoiceBehaviour do
  @moduledoc """
  Behaviour for Stripe Invoice API operations.
  Allows mocking in tests.
  """

  @callback list(params :: map()) ::
              {:ok, Stripe.List.t(any())} | {:error, Stripe.Error.t()}

  @callback retrieve(invoice_id :: String.t()) ::
              {:ok, Stripe.Invoice.t()} | {:error, Stripe.Error.t()}

  @callback pay(invoice_id :: String.t(), params :: map()) ::
              {:ok, Stripe.Invoice.t()} | {:error, Stripe.Error.t()}
end
