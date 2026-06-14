defmodule Ysc.Stripe.SubscriptionFixtures do
  @moduledoc """
  Builds `Stripe.Subscription` structs for tests.

  stripity_stripe 3.3 stores billing period boundaries on subscription items instead
  of the subscription itself.
  """

  @spec subscription(keyword() | map()) :: Stripe.Subscription.t()
  def subscription(attrs \\ []) do
    attrs = Map.new(attrs)
    now = System.os_time(:second)

    period_start =
      if Map.has_key?(attrs, :current_period_start) do
        normalize_timestamp(attrs[:current_period_start])
      else
        now
      end

    period_end =
      if Map.has_key?(attrs, :current_period_end) do
        normalize_timestamp(attrs[:current_period_end])
      else
        (period_start || now) + 30 * 86_400
      end

    items =
      case Map.get(attrs, :items) do
        nil -> default_items(period_start, period_end, attrs)
        items -> items
      end

    base = %Stripe.Subscription{
      id: Map.get(attrs, :id, "sub_test"),
      object: "subscription",
      status: Map.get(attrs, :status, "active"),
      customer: Map.get(attrs, :customer, "cus_test"),
      start_date:
        normalize_timestamp(Map.get(attrs, :start_date, period_start)),
      trial_end: normalize_timestamp(Map.get(attrs, :trial_end)),
      ended_at: normalize_timestamp(Map.get(attrs, :ended_at)),
      cancel_at: normalize_timestamp(Map.get(attrs, :cancel_at)),
      items: items
    }

    reserved =
      [
        :id,
        :object,
        :status,
        :customer,
        :start_date,
        :trial_end,
        :ended_at,
        :cancel_at,
        :items,
        :current_period_start,
        :current_period_end,
        :price_id,
        :product_id,
        :subscription_item_id,
        :quantity
      ]

    extra =
      attrs
      |> Map.drop(reserved)
      |> Enum.into(%{}, fn {k, v} -> {k, v} end)

    struct!(Stripe.Subscription, Map.merge(Map.from_struct(base), extra))
  end

  defp default_items(period_start, period_end, attrs) do
    price_id = Map.get(attrs, :price_id, "price_test")

    %Stripe.List{
      object: "list",
      data: [
        %Stripe.SubscriptionItem{
          id: Map.get(attrs, :subscription_item_id, "si_test"),
          object: "subscription_item",
          current_period_start: period_start,
          current_period_end: period_end,
          price: %Stripe.Price{
            id: price_id,
            product: Map.get(attrs, :product_id, "prod_test")
          },
          quantity: Map.get(attrs, :quantity, 1)
        }
      ],
      has_more: false,
      url: "/v1/subscription_items"
    }
  end

  defp normalize_timestamp(nil), do: nil
  defp normalize_timestamp(%DateTime{} = dt), do: DateTime.to_unix(dt)
  defp normalize_timestamp(timestamp) when is_integer(timestamp), do: timestamp
end
