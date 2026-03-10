defmodule Ysc.Stripe.InvoiceBehaviour do
  @moduledoc """
  Behaviour for Stripe Invoice API operations.
  Allows mocking in tests.
  """

  @callback list(params :: map()) ::
              {:ok, Stripe.List.t()} | {:error, Stripe.Error.t()}
end
