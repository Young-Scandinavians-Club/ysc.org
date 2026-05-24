defmodule Ysc.TestStripePaymentMethodStub do
  @moduledoc false
  @behaviour Ysc.Stripe.PaymentMethodBehaviour

  @impl true
  def retrieve(id), do: {:ok, %Stripe.PaymentMethod{id: id, type: "card"}}

  @impl true
  def retrieve(id, _opts),
    do: {:ok, %Stripe.PaymentMethod{id: id, type: "card"}}

  @impl true
  def list(_params) do
    {:ok,
     %Stripe.List{
       data: [],
       has_more: false,
       object: "list",
       url: "/v1/payment_methods"
     }}
  end

  @impl true
  def update(id, _params),
    do: {:ok, %Stripe.PaymentMethod{id: id, type: "card"}}

  @impl true
  def update(id, _params, _opts),
    do: {:ok, %Stripe.PaymentMethod{id: id, type: "card"}}
end
