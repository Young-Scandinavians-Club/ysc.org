defmodule Ysc.MoneyHelperTest do
  use ExUnit.Case, async: true
  alias Ysc.MoneyHelper

  describe "parse_money/1" do
    test "parses valid decimal strings" do
      assert Money.new(:USD, "10.99") == MoneyHelper.parse_money("10.99")
      assert Money.new(:USD, "1000.00") == MoneyHelper.parse_money("1,000.00")
      assert Money.new(:USD, "0.99") == MoneyHelper.parse_money("0.99")
    end

    test "returns nil for invalid input" do
      assert nil == MoneyHelper.parse_money("invalid")
      assert nil == MoneyHelper.parse_money(nil)
      assert nil == MoneyHelper.parse_money("")
      assert nil == MoneyHelper.parse_money(123)
    end
  end

  describe "format_money/1" do
    test "formats Money struct for display" do
      money = Money.new(:USD, "10.99")
      assert {:ok, "$10.99"} == MoneyHelper.format_money(money)

      money = Money.new(:USD, "1000.00")
      assert {:ok, "$1,000.00"} == MoneyHelper.format_money(money)
    end

    test "returns empty string for invalid input" do
      assert "" == MoneyHelper.format_money(nil)
      assert "" == MoneyHelper.format_money("invalid")
    end
  end
end
