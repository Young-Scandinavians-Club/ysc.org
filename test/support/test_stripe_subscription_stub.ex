defmodule Ysc.TestStripeSubscriptionStub do
  @moduledoc false
  @behaviour Stripe.SubscriptionBehaviour

  @impl true
  def create(_params), do: create_error()

  @impl true
  def create(_params, _opts), do: create_error()

  defp create_error do
    {:error,
     %Stripe.Error{
       source: :stripe,
       code: :invalid_request_error,
       message: "Stripe subscription create stubbed in test",
       request_id: nil,
       extra: %{},
       user_message: nil
     }}
  end
end
