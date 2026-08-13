defmodule Stripe.RefundBehaviour do
  @moduledoc """
  Behaviour for Stripe refund API operations in tests.
  """

  @callback create(params :: map()) ::
              {:ok, Stripe.Refund.t()} | {:error, Stripe.Error.t()}

  @callback create(params :: map(), opts :: keyword()) ::
              {:ok, Stripe.Refund.t()} | {:error, Stripe.Error.t()}
end
