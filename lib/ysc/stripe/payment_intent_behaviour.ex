defmodule Ysc.Stripe.PaymentIntentBehaviour do
  @moduledoc """
  Behaviour for Stripe PaymentIntent API operations.
  Allows mocking in tests.
  """

  @callback retrieve(payment_intent_id :: String.t(), opts :: map()) ::
              {:ok, Stripe.PaymentIntent.t()} | {:error, Stripe.Error.t()}
end
