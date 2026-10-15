defmodule Ysc.Printful.Amount do
  @moduledoc """
  Reads a dollar amount out of a Printful response.

  Printful is not consistent: shipping rates and sync variants send amounts as
  strings (`"7.15"`), while `/orders/estimate-costs` sends JSON numbers
  (`7.550000000000001`). Floats are rounded to cents.
  """
  alias Ysc.MoneyHelper

  @spec to_money(term()) :: Money.t() | nil
  def to_money(value) when is_binary(value) do
    case MoneyHelper.parse_money(value) do
      %Money{} = money -> money
      _ -> nil
    end
  end

  def to_money(value) when is_integer(value),
    do: Money.new(:USD, Decimal.new(value))

  def to_money(value) when is_float(value) do
    Money.new(:USD, value |> Decimal.from_float() |> Decimal.round(2))
  end

  def to_money(_), do: nil
end
