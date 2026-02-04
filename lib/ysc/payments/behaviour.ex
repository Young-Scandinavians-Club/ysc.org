defmodule Ysc.Payments.Behaviour do
  @moduledoc """
  Behaviour for payment-related operations.
  Allows mocking in tests.
  """

  @callback upsert_and_set_default_payment_method_from_stripe(
              user :: Ysc.Accounts.User.t(),
              stripe_payment_method :: Stripe.PaymentMethod.t()
            ) :: {:ok, Ysc.Payments.PaymentMethod.t()} | {:error, term()}
end
