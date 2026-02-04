defmodule Stripe.CustomerBehaviour do
  @moduledoc """
  Behavior for Stripe customer mocking in tests.

  Defines callbacks for mocking Stripe customer operations in test scenarios.
  """
  @callback retrieve(String.t(), keyword()) ::
              {:ok, Stripe.Customer.t()} | {:error, Stripe.Error.t()}
  @callback update(String.t(), map(), keyword()) ::
              {:ok, Stripe.Customer.t()} | {:error, Stripe.Error.t()}
end
