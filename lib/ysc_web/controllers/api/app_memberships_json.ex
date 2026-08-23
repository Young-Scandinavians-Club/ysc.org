defmodule YscWeb.Api.AppMembershipsJSON do
  @moduledoc """
  JSON rendering for the admin/volunteer mobile app's membership endpoints.

  Deliberately omits `stripe_price_id` — that's an internal implementation
  detail the app never needs (it only ever sends the plan `id` back).
  """

  alias YscWeb.UserAuth

  def status(%{membership: nil}) do
    %{has_active_membership: false}
  end

  def status(%{membership: membership}) do
    %{
      has_active_membership: true,
      plan_type:
        plan_type_string(UserAuth.get_membership_plan_type(membership)),
      plan_name: UserAuth.get_membership_plan_display_name(membership),
      renewal_date: iso8601(UserAuth.get_membership_renewal_date(membership)),
      cancel_at_period_end: cancel_at_period_end(membership)
    }
  end

  defp plan_type_string(nil), do: nil
  defp plan_type_string(plan_type), do: Atom.to_string(plan_type)

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp cancel_at_period_end(%{type: :lifetime}), do: false

  defp cancel_at_period_end(%Ysc.Subscriptions.Subscription{} = sub),
    do: sub.cancel_at_period_end

  defp cancel_at_period_end(_), do: nil

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

  def setup_intent(%{setup_intent: setup_intent}) do
    %{
      client_secret: setup_intent.client_secret
    }
  end
end
