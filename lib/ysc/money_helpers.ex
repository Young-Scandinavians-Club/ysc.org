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

  @doc """
  Formats Money for HTML form input values.

  Returns an empty string for nil and non-money values.
  """
  def format_money_for_input(nil), do: ""
  def format_money_for_input(%Money{} = money), do: format_money!(money)
  def format_money_for_input(_), do: ""

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
  Converts integer cents to a `Money` struct.

  Use when building `Money` values from Stripe amounts and similar cent-based APIs.
  """
  def cents_to_money(cents, currency) when is_integer(cents) do
    Money.new(currency, cents_to_dollars(cents))
  end

  def cents_to_money(_, _currency), do: Money.new(0, :USD)

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

  @doc """
  Parses a dollar amount string (e.g. `"10.99"`, `"$25.00"`) to cents for Stripe APIs.

  Returns `0` for blank, zero, or invalid input. Rounds to the nearest cent.
  """
  def parse_dollar_string_to_cents(nil), do: 0

  def parse_dollar_string_to_cents(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed in ["", "0", "0.00"] ->
        0

      true ->
        cleaned = trimmed |> String.replace(~r/[^\d.]/, "")

        if cleaned == "" do
          0
        else
          case parse_money(cleaned) do
            %Money{} = money -> money_to_cents(money)
            _ -> 0
          end
        end
    end
  end

  def parse_dollar_string_to_cents(_), do: 0
end
