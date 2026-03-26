defmodule Ysc.StripeSubscriptionRetrieverRenewedMock do
  @moduledoc false

  # Active subscription with a future period — simulates Stripe showing a renewal after local expiry.

  def retrieve(_stripe_id) do
    now = System.os_time(:second)
    future = now + 86_400 * 30

    {:ok,
     %Stripe.Subscription{
       id: "sub_renewed_mock",
       status: "active",
       start_date: now - 86_400,
       current_period_start: now - 86_400,
       current_period_end: future,
       trial_end: nil,
       ended_at: nil,
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
