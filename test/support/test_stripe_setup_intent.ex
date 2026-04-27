defmodule Ysc.TestStripeSetupIntent do
  @moduledoc false

  @behaviour Ysc.Stripe.SetupIntentBehaviour

  @impl true
  def create(params) do
    customer = Map.get(params, :customer) || "cus_test"
    n = :erlang.unique_integer([:positive])

    {:ok,
     %Stripe.SetupIntent{
       id: "seti_test_#{n}",
       client_secret: "seti_test_#{n}_secret",
       status: "requires_payment_method",
       customer: customer
     }}
  end

  @impl true
  def retrieve(id, _opts) when is_binary(id) do
    {:ok,
     %Stripe.SetupIntent{
       id: id,
       client_secret: "#{id}_secret",
       status: "requires_payment_method",
       customer: "cus_test"
     }}
  end
end
