defmodule Ysc.Stripe.SubscriptionHelpers do
  @moduledoc false

  @doc """
  Returns the subscription billing period start as a Unix timestamp.

  stripity_stripe 3.3 reads period boundaries from subscription items; older
  webhook payloads may still include top-level fields.
  """
  @spec current_period_start(Stripe.Subscription.t() | map()) :: integer() | nil
  def current_period_start(subscription) do
    legacy_period(subscription, :current_period_start) ||
      subscription_item_period(subscription, :current_period_start)
  end

  @doc """
  Returns the subscription billing period end as a Unix timestamp.
  """
  @spec current_period_end(Stripe.Subscription.t() | map()) :: integer() | nil
  def current_period_end(subscription) do
    legacy_period(subscription, :current_period_end) ||
      subscription_item_period(subscription, :current_period_end)
  end

  defp legacy_period(subscription, field) when is_map(subscription) do
    Map.get(subscription, field) || Map.get(subscription, Atom.to_string(field))
  end

  defp subscription_item_period(subscription, field) do
    subscription
    |> subscription_items()
    |> List.first()
    |> case do
      nil ->
        nil

      item ->
        Map.get(item, field) || Map.get(item, Atom.to_string(field))
    end
  end

  defp subscription_items(subscription) when is_map(subscription) do
    case Map.get(subscription, :items) || Map.get(subscription, "items") do
      %Stripe.List{data: data} when is_list(data) -> data
      %{data: data} when is_list(data) -> data
      %{"data" => data} when is_list(data) -> data
      _ -> []
    end
  end
end
