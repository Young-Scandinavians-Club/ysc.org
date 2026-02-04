defmodule Ysc.Customers.Behaviour do
  @moduledoc """
  Behaviour for customer-related operations.
  Allows mocking in tests.
  """

  @callback create_setup_intent(user :: Ysc.Accounts.User.t()) ::
              {:ok, Stripe.SetupIntent.t()} | {:error, term()}
end
