defmodule Stripe.SubscriptionBehaviour do
  @moduledoc """
  Behaviour for Stripe subscription API operations in tests.
  """

  @callback create(params :: map()) ::
              {:ok, Stripe.Subscription.t()} | {:error, Stripe.Error.t()}

  @callback create(params :: map(), opts :: keyword()) ::
              {:ok, Stripe.Subscription.t()} | {:error, Stripe.Error.t()}
end
