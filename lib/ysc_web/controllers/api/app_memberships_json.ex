defmodule YscWeb.Api.AppMembershipsJSON do
  @moduledoc """
  JSON rendering for the admin/volunteer mobile app's membership endpoints.

  Deliberately omits `stripe_price_id` — that's an internal implementation
  detail the app never needs (it only ever sends the plan `id` back).
  """

  def plans(%{plans: plans}) do
    %{data: Enum.map(plans, &plan/1)}
  end

  defp plan(p) do
    %{
      id: to_string(p.id),
      name: p.name,
      interval: p.interval,
      amount: p.amount,
      currency: p.currency,
      description: p.description
    }
  end

  def subscription(%{subscription: subscription}) do
    %{
      id: subscription.id,
      status: subscription.status
    }
  end
end
