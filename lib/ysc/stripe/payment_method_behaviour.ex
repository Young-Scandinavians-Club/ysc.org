defmodule Ysc.Stripe.PaymentMethodBehaviour do
  @moduledoc """
  Behaviour for Stripe PaymentMethod API operations.
  Allows mocking in tests.
  """

  @callback retrieve(payment_method_id :: String.t()) ::
              {:ok, Stripe.PaymentMethod.t()} | {:error, Stripe.Error.t()}

  @callback retrieve(payment_method_id :: String.t(), opts :: Keyword.t()) ::
              {:ok, Stripe.PaymentMethod.t()} | {:error, Stripe.Error.t()}
end
