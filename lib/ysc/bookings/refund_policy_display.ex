defmodule Ysc.Bookings.RefundPolicyDisplay do
  @moduledoc """
  Human-readable labels for refund policy rules.

  Use `rule_threshold_summary/1` for booking checkout policy lists and
  `cancellation_rule_summary/1` for the member cancellation flow.
  """

  @doc """
  Rounds a refund percentage to a whole number for display.
  """
  def refund_percentage_int(%Decimal{} = percentage) do
    percentage
    |> Decimal.to_float()
    |> Float.round(0)
    |> trunc()
  end

  def refund_percentage_int(percentage) when is_number(percentage),
    do: trunc(percentage)

  @doc """
  Sorts rules by `days_before_checkin` descending (most permissive thresholds first).
  """
  def rules_sorted_desc(rules) when is_list(rules) do
    Enum.sort_by(rules, & &1.days_before_checkin, :desc)
  end

  def rules_sorted_desc(_), do: []

  @doc """
  Sorts rules by `days_before_checkin` ascending (most restrictive thresholds first).
  """
  def rules_sorted_asc(rules) when is_list(rules) do
    Enum.sort_by(rules, & &1.days_before_checkin, :asc)
  end

  @doc """
  Booking checkout policy line (descending days threshold style).

  Example: `"If you cancel 30 or more days before check-in, you'll receive a 100% refund."`
  """
  def rule_threshold_summary(%{
        days_before_checkin: days,
        refund_percentage: percentage
      }) do
    refund_pct = refund_percentage_int(percentage)

    "If you cancel #{days} or more days before check-in, you'll receive a #{refund_pct}% refund."
  end

  @doc """
  Cancellation flow policy line with tier-based messaging.
  """
  def cancellation_rule_summary(%{
        days_before_checkin: days,
        refund_percentage: percentage
      }) do
    refund_percentage = Decimal.to_float(percentage)

    cond do
      refund_percentage == 0.0 ->
        "If you cancel within #{days} days of your check-in date, you will not receive a refund."

      refund_percentage > 0 and refund_percentage < 100.0 ->
        refund_pct = refund_percentage_int(percentage)

        "If you cancel within #{days} days of your check-in date, you receive a #{refund_pct}% refund."

      true ->
        "If you cancel #{days} or more days before your check-in date, you are eligible for a full refund."
    end
  end

  @doc """
  Summary for an applied refund rule on receipts and confirmations.

  Example: `"75% refund if cancelled 14 days or more before check-in."`
  """
  def applied_rule_summary(%{
        days_before_checkin: days,
        refund_percentage: percentage
      }) do
    refund_pct = refund_percentage_int(percentage)

    "#{refund_pct}% refund if cancelled #{days} days or more before check-in."
  end

  @doc """
  Tailwind text classes for refund percentage tiers in comparison tables.
  """
  def refund_percentage_tier_class(nil), do: "text-zinc-400"

  def refund_percentage_tier_class(%Decimal{} = percentage) do
    percentage = Decimal.to_float(percentage)

    cond do
      percentage >= 100 -> "text-green-700 font-bold"
      percentage >= 50 -> "text-amber-700 font-semibold"
      true -> "text-red-700 font-semibold"
    end
  end

  @doc """
  Returns a policy's rules list, or `[]` when the policy is missing, has no
  rules, or `:rules` was never loaded.
  """
  def policy_rules(nil), do: []
  def policy_rules(%{rules: rules}) when is_list(rules), do: rules
  def policy_rules(_), do: []

  @doc """
  Unique `days_before_checkin` values from one or more rule lists, sorted descending.
  """
  def unique_threshold_days_desc(rule_lists) when is_list(rule_lists) do
    rule_lists
    |> Enum.flat_map(&threshold_days_from_rules/1)
    |> Enum.uniq()
    |> Enum.sort(:desc)
  end

  @doc """
  Finds the rule matching a specific days-before-check-in threshold.
  """
  def find_rule_for_days(rules, days) when is_list(rules) do
    Enum.find(rules, &(&1.days_before_checkin == days))
  end

  def find_rule_for_days(_, _days), do: nil

  defp threshold_days_from_rules(rules) when is_list(rules) do
    Enum.map(rules, & &1.days_before_checkin)
  end

  defp threshold_days_from_rules(_), do: []
end
