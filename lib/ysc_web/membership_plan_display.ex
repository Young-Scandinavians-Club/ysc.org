defmodule YscWeb.MembershipPlanDisplay do
  @moduledoc """
  Display helpers for membership plan pricing configured in
  `config :ysc, :membership_plans`.
  """

  @doc """
  Formats a plan's yearly price (e.g. `"$45.00"`), or `""` when the plan or its
  price is not configured.
  """
  @spec price(atom()) :: String.t()
  def price(plan_id) when is_atom(plan_id) do
    plans = Application.get_env(:ysc, :membership_plans, [])

    case Enum.find(plans, &(&1.id == plan_id)) do
      %{amount: amount, currency: currency}
      when is_number(amount) and is_binary(currency) ->
        case currency_atom(currency) do
          nil -> ""
          atom -> Ysc.MoneyHelper.format_money!(Money.new(atom, amount))
        end

      _ ->
        ""
    end
  end

  @doc """
  Like `price/1` with the billing period, e.g. `"$45.00 per year"`. Returns
  `nil` when the price is unavailable so callers can omit the line.
  """
  @spec price_per_year(atom()) :: String.t() | nil
  def price_per_year(plan_id) when is_atom(plan_id) do
    case price(plan_id) do
      "" -> nil
      price -> "#{price} per year"
    end
  end

  defp currency_atom(currency) when is_binary(currency) do
    currency
    |> String.upcase()
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end
end
