defmodule Ysc.MoneyHelper do
  @moduledoc """
  Utility module for working with monetary values.

  Provides functions for parsing, formatting, and converting money values.
  """
  @doc """
  Converts string input to Money type for changesets.

  Examples:
    iex> parse_money("10.99")
    %Money{amount: 1099, currency: :USD}

    iex> parse_money("invalid")
    nil
  """
  def parse_money(nil), do: nil
  def parse_money(""), do: nil

  def parse_money(string) when is_binary(string) do
    case string |> String.replace(",", "") |> Decimal.parse() do
      :error ->
        nil

      {decimal, ""} ->
        Money.new(:USD, decimal)

      {decimal, _} ->
        Money.new(:USD, decimal)

      _ ->
        nil
    end
  end

  def parse_money(_), do: nil

  @doc """
  Formats Money for display in forms.

  Examples:
    iex> format_money(%Money{amount: 1099, currency: :USD})
    "10.99"
  """
  def format_money(%Money{} = money) do
    Money.to_string(money, separator: ".", delimiter: ",", fractional_digits: 2)
  end

  def format_money(_), do: ""

  def format_money!(value) do
    case format_money(value) do
      {:ok, str} -> str
      str when is_binary(str) -> str
      _ -> ""
    end
  end

  def cents_to_dollars(nil), do: Decimal.new("0.0")

  def cents_to_dollars(cents) when is_integer(cents) do
    cents
    |> Decimal.new()
    |> Decimal.div(Decimal.new(100))
    |> Decimal.round(2)
  end

  def cents_to_dollars(_), do: Decimal.new("0.0")

  @doc """
  Converts Money to cents (integer).

  Examples:
    iex> money_to_cents(%Money{amount: Decimal.new("10.99"), currency: :USD})
    1099
  """
  def money_to_cents(%Money{amount: amount}) when is_struct(amount, Decimal) do
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  def money_to_cents(%Money{amount: amount}) when is_integer(amount) do
    amount * 100
  end

  def money_to_cents(_), do: 0
end
