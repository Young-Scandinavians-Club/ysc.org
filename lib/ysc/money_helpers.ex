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
    cleaned =
      string
      |> String.replace(",", "")
      |> String.replace("$", "")
      |> String.trim()

    if cleaned == "" do
      nil
    else
      case Decimal.parse(cleaned) do
        :error ->
          nil

        {decimal, ""} ->
          Money.new(:USD, decimal)

        {decimal, _} ->
          Money.new(:USD, decimal)
      end
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
  Converts Money to cents (integer) for Stripe and similar APIs.

  Rounds to the currency's minor units (`Money.round/1`) before converting so
  fractional-cent arithmetic does not truncate to 0 cents or raise when
  converting to an integer.
  """
  def money_to_cents(%Money{} = money) do
    case Money.round(money, rounding_mode: :half_up) do
      %Money{amount: amount} ->
        amount
        |> Decimal.mult(100)
        |> Decimal.round(0, :half_up)
        |> Decimal.to_integer()

      {:error, _} ->
        0
    end
  end

  def money_to_cents(_), do: 0
end
