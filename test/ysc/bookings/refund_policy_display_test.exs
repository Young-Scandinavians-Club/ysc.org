defmodule Ysc.Bookings.RefundPolicyDisplayTest do
  use ExUnit.Case, async: true

  alias Ysc.Bookings.RefundPolicyDisplay

  describe "refund_percentage_int/1" do
    test "rounds Decimal percentages to whole numbers" do
      assert RefundPolicyDisplay.refund_percentage_int(Decimal.new("75.4")) == 75
      assert RefundPolicyDisplay.refund_percentage_int(Decimal.new("100")) == 100
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

      assert Enum.map(RefundPolicyDisplay.rules_sorted_desc(rules), & &1.days_before_checkin) ==
               [30, 14, 7]

      assert Enum.map(RefundPolicyDisplay.rules_sorted_asc(rules), & &1.days_before_checkin) ==
               [7, 14, 30]
    end
  end

  describe "rule_threshold_summary/1" do
    test "formats booking checkout policy lines" do
      rule = %{days_before_checkin: 30, refund_percentage: Decimal.new("100")}

      assert RefundPolicyDisplay.rule_threshold_summary(rule) ==
               "If you cancel 30 or more days before check-in, you'll receive a 100% refund."
    end
  end

  describe "cancellation_rule_summary/1" do
    test "formats no-refund rules" do
      rule = %{days_before_checkin: 7, refund_percentage: Decimal.new("0")}

      assert RefundPolicyDisplay.cancellation_rule_summary(rule) ==
               "If you cancel within 7 days of your check-in date, you will not receive a refund."
    end

    test "formats partial refund rules" do
      rule = %{days_before_checkin: 14, refund_percentage: Decimal.new("50")}

      assert RefundPolicyDisplay.cancellation_rule_summary(rule) ==
               "If you cancel within 14 days of your check-in date, you receive a 50% refund."
    end

    test "formats full refund rules" do
      rule = %{days_before_checkin: 30, refund_percentage: Decimal.new("100")}

      assert RefundPolicyDisplay.cancellation_rule_summary(rule) ==
               "If you cancel 30 or more days before your check-in date, you are eligible for a full refund."
    end
  end

  describe "applied_rule_summary/1" do
    test "formats applied rule summaries" do
      rule = %{days_before_checkin: 14, refund_percentage: Decimal.new("75")}

      assert RefundPolicyDisplay.applied_rule_summary(rule) ==
               "75% refund if cancelled 14 days or more before check-in."
    end
  end

  describe "refund_percentage_tier_class/1" do
    test "returns tier classes for refund percentages" do
      assert RefundPolicyDisplay.refund_percentage_tier_class(Decimal.new("100")) ==
               "text-green-700 font-bold"

      assert RefundPolicyDisplay.refund_percentage_tier_class(Decimal.new("75")) ==
               "text-amber-700 font-semibold"

      assert RefundPolicyDisplay.refund_percentage_tier_class(Decimal.new("25")) ==
               "text-red-700 font-semibold"

      assert RefundPolicyDisplay.refund_percentage_tier_class(nil) == "text-zinc-400"
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

      assert RefundPolicyDisplay.unique_threshold_days_desc([buyout_rules, room_rules]) ==
               [30, 14, 7]

      assert RefundPolicyDisplay.find_rule_for_days(buyout_rules, 30) ==
               Enum.at(buyout_rules, 0)

      assert RefundPolicyDisplay.find_rule_for_days(room_rules, 30) == nil
      assert RefundPolicyDisplay.find_rule_for_days(nil, 30) == nil
    end
  end
end
