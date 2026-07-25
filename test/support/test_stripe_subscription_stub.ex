defmodule Ysc.TestStripeSubscriptionStub do
  @moduledoc false
  @behaviour Stripe.SubscriptionBehaviour

  @impl true
  def create(_params), do: create_error()

  @impl true
  def create(_params, _opts), do: create_error()

  @impl true
  def update(id, params), do: update(id, params, [])

  @impl true
  def update(id, params, _opts) do
    period_end =
      DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.to_unix()

    {:ok,
     %Stripe.Subscription{
       id: id,
       status: "active",
       cancel_at_period_end: Map.get(params, :cancel_at_period_end, false),
       items: %Stripe.List{
         data: [
           %Stripe.SubscriptionItem{
             id: "si_#{id}",
             current_period_end: period_end
           }
         ],
         has_more: false,
         object: "list",
         url: "/v1/subscription_items"
       }
     }}
  end

  @impl true
  def list(_params) do
    {:ok,
     %Stripe.List{
       data: [],
       has_more: false,
       object: "list",
       url: "/v1/subscriptions"
     }}
  end

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
