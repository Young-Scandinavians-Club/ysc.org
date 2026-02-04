defmodule Ysc.Stripe.SetupIntentBehaviour do
  @moduledoc """
  Behaviour for Stripe SetupIntent API operations.
  Allows mocking in tests.
  """

  @callback retrieve(setup_intent_id :: String.t(), opts :: map()) ::
              {:ok, Stripe.SetupIntent.t()} | {:error, Stripe.Error.t()}
end
