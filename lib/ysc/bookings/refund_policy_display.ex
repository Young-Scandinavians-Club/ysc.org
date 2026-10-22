defmodule Ysc.Bookings.RefundPolicyDisplay do
  @moduledoc """
  Human-readable labels for refund policy rules.

  Rule thresholds match `Ysc.Bookings.calculate_refund_from_policy/3`: a rule
  applies when the cancellation is within its `days_before_checkin`, and the
  tightest matching rule wins. Cancelling earlier than every threshold is a
  full refund.

  Use `refund_schedule_bands/1` for comparison tables, `cancellation_schedule_lines/1`
  for the member cancellation flow, and `applied_rule_summary/1` on receipts.
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
  Refund percentage bands for one or more stay types.

  `columns` is a list of `%{label: String.t(), rules: [rule]}`. Returns
  `[%{label: band_label, percentages: [integer]}]` from earliest notice to
  check-in, or `[]` when no column has rules.
  """
  def refund_schedule_bands(columns) when is_list(columns) do
    thresholds =
      columns
      |> Enum.map(& &1.rules)
      |> unique_threshold_days_desc()

    refund_bands(thresholds, columns)
  end

  @doc """
  Member-facing cancellation schedule for one policy, earliest notice first.

  Example for rules 21/50% and 14/0%:

      [
        "If you cancel more than 21 days before check-in, you'll receive a full refund.",
        "If you cancel 15–21 days before check-in, you'll receive a 50% refund.",
        "If you cancel 14 days or fewer before check-in, you will not receive a refund."
      ]
  """
  def cancellation_schedule_lines(rules) when is_list(rules) do
    [%{rules: rules}]
    |> refund_schedule_bands()
    |> Enum.map(&schedule_line/1)
  end

  def cancellation_schedule_lines(_), do: []

  @doc """
  Summary for an applied refund rule on receipts and confirmations.

  The engine applies a rule when the cancellation is that many days or fewer
  before check-in and it is the tightest match. Pass `all_rules` so the
  sentence uses the same non-overlapping band as the refund table.

  Example: `"75% refund if you cancelled 8–14 days before check-in."`
  """
  def applied_rule_summary(rule, all_rules \\ [])

  def applied_rule_summary(
        %{days_before_checkin: days, refund_percentage: percentage},
        all_rules
      )
      when is_list(all_rules) do
    refund_pct = refund_percentage_int(percentage)
    when_clause = applied_when_clause(days, all_rules)

    if refund_pct == 0 do
      "No refund if you cancelled #{when_clause}."
    else
      "#{refund_pct}% refund if you cancelled #{when_clause}."
    end
  end

  def applied_rule_summary(rule, _all_rules), do: applied_rule_summary(rule, [])

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

  # Rows for the refund table: everything earlier than the loosest threshold is a
  # full refund, then one band per threshold down to check-in.
  defp refund_bands([], _columns), do: []

  defp refund_bands([loosest | _] = thresholds, columns) do
    full = %{
      label: "More than #{loosest} days before check-in",
      percentages: Enum.map(columns, fn _ -> 100 end)
    }

    lower_bounds = Enum.drop(thresholds, 1) ++ [nil]

    bands =
      thresholds
      |> Enum.zip(lower_bounds)
      |> Enum.map(fn {upper, lower} ->
        %{
          label: band_label(upper, lower),
          percentages: Enum.map(columns, &refund_for_band(&1.rules, upper))
        }
      end)

    [full | bands]
  end

  defp band_label(upper, nil), do: "#{upper} days or fewer before check-in"

  defp band_label(upper, lower) when lower + 1 == upper,
    do: "#{upper} days before check-in"

  defp band_label(upper, lower),
    do: "#{lower + 1}–#{upper} days before check-in"

  # The tightest rule that still covers the band's upper edge; none means the
  # band is looser than every rule, so a full refund.
  defp refund_for_band(rules, upper) when is_list(rules) do
    rules
    |> Enum.filter(&(&1.days_before_checkin >= upper))
    |> Enum.min_by(& &1.days_before_checkin, fn -> nil end)
    |> case do
      nil -> 100
      rule -> refund_percentage_int(rule.refund_percentage)
    end
  end

  defp refund_for_band(_rules, _upper), do: 100

  defp schedule_line(%{label: label, percentages: [percentage | _]}) do
    when_clause = schedule_when_clause(label)

    cond do
      percentage == 0 ->
        "If you cancel #{when_clause}, you will not receive a refund."

      percentage == 100 ->
        "If you cancel #{when_clause}, you'll receive a full refund."

      true ->
        "If you cancel #{when_clause}, you'll receive a #{percentage}% refund."
    end
  end

  defp schedule_when_clause("More than " <> rest), do: "more than " <> rest
  defp schedule_when_clause(label), do: label

  # The applied rule covers cancellations from the next-tighter threshold up
  # through this one, matching refund_schedule_bands/1.
  defp applied_when_clause(days, all_rules) when is_list(all_rules) do
    tighter =
      all_rules
      |> Enum.map(& &1.days_before_checkin)
      |> Enum.filter(&(&1 < days))
      |> Enum.max(fn -> nil end)

    band_label(days, tighter)
  end

  defp threshold_days_from_rules(rules) when is_list(rules) do
    Enum.map(rules, & &1.days_before_checkin)
  end

  defp threshold_days_from_rules(_), do: []
end
