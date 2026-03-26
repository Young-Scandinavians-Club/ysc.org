defmodule Ysc.StripeSubscriptionRetrieverErrorMock do
  @moduledoc false

  def retrieve(_stripe_id) do
    {:error,
     %Stripe.Error{
       source: :stripe,
       code: :api_connection_error,
       message: "test failure"
     }}
  end
end
