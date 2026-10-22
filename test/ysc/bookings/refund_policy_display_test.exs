defmodule Ysc.Bookings.RefundPolicyDisplayTest do
  use ExUnit.Case, async: true

  alias Ysc.Bookings.RefundPolicyDisplay

  describe "refund_percentage_int/1" do
    test "rounds Decimal percentages to whole numbers" do
      assert RefundPolicyDisplay.refund_percentage_int(Decimal.new("75.4")) ==
               75

      assert RefundPolicyDisplay.refund_percentage_int(Decimal.new("100")) ==
               100

      assert RefundPolicyDisplay.refund_percentage_int(Decimal.new("0")) == 0
    end

    test "accepts numeric values" do
      assert RefundPolicyDisplay.refund_percentage_int(50.9) == 50
    end
  end

  describe "rules_sorted_desc/1 and rules_sorted_asc/1" do
    test "sort rules by days_before_checkin" do
      rules = [
        %{days_before_checkin: 7},
        %{days_before_checkin: 30},
        %{days_before_checkin: 14}
      ]

      assert Enum.map(
               RefundPolicyDisplay.rules_sorted_desc(rules),
               & &1.days_before_checkin
             ) ==
               [30, 14, 7]

      assert Enum.map(
               RefundPolicyDisplay.rules_sorted_asc(rules),
               & &1.days_before_checkin
             ) ==
               [7, 14, 30]
    end
  end

  describe "refund_schedule_bands/1" do
    test "lists bands between the union of thresholds, one percentage per stay type" do
      columns = [
        %{label: "Entire cabin", rules: [rule(21, "50"), rule(14, "0")]},
        %{label: "Individual room(s)", rules: [rule(14, "50")]}
      ]

      bands = RefundPolicyDisplay.refund_schedule_bands(columns)

      assert Enum.map(bands, & &1.label) == [
               "More than 21 days before check-in",
               "15–21 days before check-in",
               "14 days or fewer before check-in"
             ]

      assert Enum.map(bands, & &1.percentages) == [
               [100, 100],
               [50, 100],
               [0, 50]
             ]
    end

    test "returns no bands when no column has rules" do
      assert RefundPolicyDisplay.refund_schedule_bands([
               %{label: "Entire cabin", rules: []}
             ]) == []
    end
  end

  describe "cancellation_schedule_lines/1" do
    test "uses non-overlapping bands that match the refund engine" do
      rules = [rule(21, "50"), rule(14, "0")]

      assert RefundPolicyDisplay.cancellation_schedule_lines(rules) == [
               "If you cancel more than 21 days before check-in, you'll receive a full refund.",
               "If you cancel 15–21 days before check-in, you'll receive a 50% refund.",
               "If you cancel 14 days or fewer before check-in, you will not receive a refund."
             ]
    end

    test "formats a full-refund rule as the late-cancel band, not 'or more days'" do
      lines = RefundPolicyDisplay.cancellation_schedule_lines([rule(30, "100")])

      assert lines == [
               "If you cancel more than 30 days before check-in, you'll receive a full refund.",
               "If you cancel 30 days or fewer before check-in, you'll receive a full refund."
             ]

      refute Enum.any?(lines, &String.contains?(&1, "or more days"))
    end

    test "returns an empty list when there are no rules" do
      assert RefundPolicyDisplay.cancellation_schedule_lines([]) == []
      assert RefundPolicyDisplay.cancellation_schedule_lines(nil) == []
    end
  end

  describe "applied_rule_summary/1" do
    test "formats applied rule summaries using or-fewer, matching the engine" do
      rule = %{days_before_checkin: 14, refund_percentage: Decimal.new("75")}

      assert RefundPolicyDisplay.applied_rule_summary(rule) ==
               "75% refund if you cancelled 14 days or fewer before check-in."
    end

    test "formats a zero-percent applied rule" do
      rule = %{days_before_checkin: 7, refund_percentage: Decimal.new("0")}

      assert RefundPolicyDisplay.applied_rule_summary(rule) ==
               "No refund if you cancelled 7 days or fewer before check-in."
    end

    test "uses the non-overlapping band when the rest of the policy is provided" do
      rules = [rule(21, "50"), rule(14, "0")]
      applied = Enum.at(rules, 0)

      assert RefundPolicyDisplay.applied_rule_summary(applied, rules) ==
               "50% refund if you cancelled 15–21 days before check-in."

      assert RefundPolicyDisplay.applied_rule_summary(Enum.at(rules, 1), rules) ==
               "No refund if you cancelled 14 days or fewer before check-in."
    end
  end

  describe "refund_percentage_tier_class/1" do
    test "returns tier classes for refund percentages" do
      assert RefundPolicyDisplay.refund_percentage_tier_class(
               Decimal.new("100")
             ) ==
               "text-green-700 font-bold"

      assert RefundPolicyDisplay.refund_percentage_tier_class(Decimal.new("75")) ==
               "text-amber-700 font-semibold"

      assert RefundPolicyDisplay.refund_percentage_tier_class(Decimal.new("25")) ==
               "text-red-700 font-semibold"

      assert RefundPolicyDisplay.refund_percentage_tier_class(nil) ==
               "text-zinc-400"
    end
  end

  describe "unique_threshold_days_desc/1 and find_rule_for_days/2" do
    test "collects and finds rules by threshold day" do
      buyout_rules = [
        %{days_before_checkin: 30, refund_percentage: Decimal.new("100")},
        %{days_before_checkin: 7, refund_percentage: Decimal.new("0")}
      ]

      room_rules = [
        %{days_before_checkin: 14, refund_percentage: Decimal.new("50")}
      ]

      assert RefundPolicyDisplay.unique_threshold_days_desc([
               buyout_rules,
               room_rules
             ]) ==
               [30, 14, 7]

      assert RefundPolicyDisplay.find_rule_for_days(buyout_rules, 30) ==
               Enum.at(buyout_rules, 0)

      assert RefundPolicyDisplay.find_rule_for_days(room_rules, 30) == nil
      assert RefundPolicyDisplay.find_rule_for_days(nil, 30) == nil
    end
  end

  describe "policy_rules/1" do
    test "returns a list of rules or empty for missing or unloaded policies" do
      rules = [%{days_before_checkin: 14}]

      assert RefundPolicyDisplay.policy_rules(%{rules: rules}) == rules
      assert RefundPolicyDisplay.policy_rules(%{rules: []}) == []
      assert RefundPolicyDisplay.policy_rules(nil) == []
      assert RefundPolicyDisplay.policy_rules(%{}) == []
      assert RefundPolicyDisplay.rules_sorted_desc(:not_loaded) == []
    end
  end

  defp rule(days, percentage) do
    %{days_before_checkin: days, refund_percentage: Decimal.new(percentage)}
  end
end
