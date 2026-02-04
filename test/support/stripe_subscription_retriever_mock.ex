defmodule Ysc.StripeSubscriptionRetrieverMock do
  @moduledoc false

  # Returns a canceled subscription so ExpirationWorker tests don't call the real Stripe API.
  # Uses past timestamps so the worker treats it as expired and updates local state.

  def retrieve(_stripe_id) do
    now = System.os_time(:second)
    past = now - 86_400

    {:ok,
     %Stripe.Subscription{
       id: "sub_mock",
       status: "canceled",
       start_date: past,
       current_period_start: past,
       current_period_end: past,
       trial_end: nil,
       ended_at: past,
       cancel_at: nil,
       items: %Stripe.List{
         data: [],
         has_more: false,
         object: "list",
         url: "/v1/subscription_items"
       }
     }}
  end
end
