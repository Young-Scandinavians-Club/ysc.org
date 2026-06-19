defmodule Ysc.MoneyHelperTest do
  use ExUnit.Case, async: true
  alias Ysc.MoneyHelper

  describe "parse_money/1" do
    test "parses valid decimal strings" do
      assert Money.new(:USD, "10.99") == MoneyHelper.parse_money("10.99")
      assert Money.new(:USD, "1000.00") == MoneyHelper.parse_money("1,000.00")
      assert Money.new(:USD, "0.99") == MoneyHelper.parse_money("0.99")
    end

    test "parses strings with dollar sign" do
      assert Money.new(:USD, "23.00") == MoneyHelper.parse_money("$23.00")
      assert Money.new(:USD, "1.50") == MoneyHelper.parse_money("$1.50")
    end

    test "returns nil for invalid input" do
      assert nil == MoneyHelper.parse_money("invalid")
      assert nil == MoneyHelper.parse_money(nil)
      assert nil == MoneyHelper.parse_money("")
      assert nil == MoneyHelper.parse_money(123)
    end

    test "returns nil when trimmed input is empty" do
      assert nil == MoneyHelper.parse_money("   ")
      assert nil == MoneyHelper.parse_money("\t")
    end

    test "parses numeric prefix when extra characters follow the number" do
      assert Money.new(:USD, "10.99") == MoneyHelper.parse_money("10.99 USD")
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

  describe "format_money_for_input/1" do
    test "formats Money for form inputs" do
      money = Money.new(:USD, "10.99")
      assert MoneyHelper.format_money_for_input(money) == "$10.99"
    end

    test "returns empty string for nil and non-money values" do
      assert MoneyHelper.format_money_for_input(nil) == ""
      assert MoneyHelper.format_money_for_input("invalid") == ""
    end
  end

  describe "format_money!/1" do
    test "returns formatted string for Money" do
      money = Money.new(:USD, "10.99")
      assert MoneyHelper.format_money!(money) == "$10.99"
    end

    test "returns empty string for invalid values" do
      assert MoneyHelper.format_money!(nil) == ""
    end
  end

  describe "cents_to_dollars/1" do
    test "converts integer cents to a decimal dollars amount" do
      assert Decimal.equal?(
               MoneyHelper.cents_to_dollars(150),
               Decimal.new("1.50")
             )
    end

    test "returns zero for nil and non-integers" do
      assert Decimal.equal?(
               MoneyHelper.cents_to_dollars(nil),
               Decimal.new("0.0")
             )

      assert Decimal.equal?(
               MoneyHelper.cents_to_dollars(:not_int),
               Decimal.new("0.0")
             )
    end
  end

  describe "money_to_cents/1" do
    test "supports Money with decimal or integer amounts" do
      decimal_money = Money.new(:USD, "10.99")
      assert MoneyHelper.money_to_cents(decimal_money) == 1099

      integer_amount = %Money{amount: 50, currency: :USD}
      assert MoneyHelper.money_to_cents(integer_amount) == 5000
    end

    test "rounds sub-cent policy amounts to the nearest cent before converting" do
      assert MoneyHelper.money_to_cents(Money.new!(:USD, "0.009")) == 1
      assert MoneyHelper.money_to_cents(Money.new!(:USD, "0.005")) == 1
      assert MoneyHelper.money_to_cents(Money.new!(:USD, "0.004")) == 0
    end

    test "rounds entitlement-style fractional dollar amounts before converting" do
      money = %Money{
        amount: Decimal.new("76.66666666666666666666666666667"),
        currency: :USD
      }

      assert MoneyHelper.money_to_cents(money) == 7667
    end

    test "returns zero for non-Money values" do
      assert MoneyHelper.money_to_cents(nil) == 0
    end
  end

  describe "cents_to_money/2" do
    test "converts integer cents to Money" do
      assert MoneyHelper.cents_to_money(1099, :USD) == Money.new(:USD, "10.99")
      assert MoneyHelper.cents_to_money(7667, :USD) == Money.new(:USD, "76.67")
    end

    test "returns zero money for invalid cents" do
      assert MoneyHelper.cents_to_money(nil, :USD) == Money.new(0, :USD)
    end
  end

  describe "usd_from_db_sum/1" do
    test "returns zero USD for nil aggregate results" do
      assert MoneyHelper.usd_from_db_sum(nil) == Money.new(0, :USD)
    end

    test "wraps integer dollar amounts from SQL sums" do
      assert MoneyHelper.usd_from_db_sum(1099) == Money.new(1099, :USD)
    end

    test "wraps decimal dollar amounts from SQL sums" do
      assert MoneyHelper.usd_from_db_sum(Decimal.new("1099")) ==
               Money.new(Decimal.new("1099"), :USD)
    end

    test "returns zero USD for unexpected aggregate types" do
      assert MoneyHelper.usd_from_db_sum("invalid") == Money.new(0, :USD)
    end
  end

  describe "parse_dollar_string_to_cents/1" do
    test "parses dollar strings to rounded cents" do
      assert MoneyHelper.parse_dollar_string_to_cents("10.99") == 1099
      assert MoneyHelper.parse_dollar_string_to_cents("$25.50") == 2550
      assert MoneyHelper.parse_dollar_string_to_cents("76.666") == 7667
    end

    test "returns zero for blank or zero input" do
      assert MoneyHelper.parse_dollar_string_to_cents("") == 0
      assert MoneyHelper.parse_dollar_string_to_cents("0") == 0
      assert MoneyHelper.parse_dollar_string_to_cents("0.00") == 0
      assert MoneyHelper.parse_dollar_string_to_cents(nil) == 0
    end

    test "returns zero for invalid input" do
      assert MoneyHelper.parse_dollar_string_to_cents("invalid") == 0
      assert MoneyHelper.parse_dollar_string_to_cents("12.34.56") == 0
    end
  end
end
