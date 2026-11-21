defmodule YscWeb.MembershipUserMessages do
  @moduledoc false

  def payment_method_saved_membership_activated(returning_member?)
      when is_boolean(returning_member?) do
    if returning_member? do
      "Payment method saved. Your membership is renewed."
    else
      "Payment method saved and your membership is now active!"
    end
  end

  def membership_activated_welcome(returning_member?)
      when is_boolean(returning_member?) do
    if returning_member? do
      "Your membership is renewed."
    else
      "Your membership is active. Welcome!"
    end
  end

  def membership_activated_short(returning_member?)
      when is_boolean(returning_member?) do
    if returning_member? do
      "Your membership is renewed."
    else
      "Your membership is active!"
    end
  end

  def plan_name(plan_id) when is_atom(plan_id) do
    plan_id |> Atom.to_string() |> String.capitalize()
  end

  def plan_name(plan_id) when is_binary(plan_id), do: String.capitalize(plan_id)

  @doc """
  Lead-in for the /users/membership upgrade banner.

  The dollar amount that follows is the full-year plan difference — a
  ceiling, not today's bill. Stripe charges the prorated leftover of the
  year, so members partway through often pay less.
  """
  def upgrade_banner_before_amount(new_plan_name)
      when is_binary(new_plan_name) do
    "You'll switch to #{new_plan_name} today. We'll charge you extra for the rest of this membership year — at most"
  end

  def upgrade_banner_after_amount(new_plan_name)
      when is_binary(new_plan_name) do
    "If you're already partway through the year, you'll pay less than that. Next year you'll pay the #{new_plan_name} price."
  end

  def upgrade_confirm_helper(formatted_max) when is_binary(formatted_max) do
    "You'll be charged today — at most #{formatted_max}."
  end
end
