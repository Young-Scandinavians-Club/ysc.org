defmodule Ysc.Printful.AmountTest do
  use ExUnit.Case, async: true

  alias Ysc.Printful.Amount

  test "reads strings, integers and floats" do
    assert Money.equal?(Amount.to_money("7.15"), Money.new(:USD, "7.15"))
    assert Money.equal?(Amount.to_money(12), Money.new(:USD, "12"))
    assert Money.equal?(Amount.to_money(38.03), Money.new(:USD, "38.03"))
  end

  test "rounds float noise to cents" do
    assert Money.equal?(
             Amount.to_money(7.550000000000001),
             Money.new(:USD, "7.55")
           )
  end

  test "is nil for anything that is not an amount" do
    assert Amount.to_money(nil) == nil
    assert Amount.to_money("") == nil
    assert Amount.to_money("free") == nil
    assert Amount.to_money(%{}) == nil
  end
end
