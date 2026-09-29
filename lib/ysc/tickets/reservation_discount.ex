defmodule Ysc.Tickets.ReservationDiscount do
  @moduledoc """
  Applies ticket-reservation discount percentages to Money amounts.

  Reservation holds store a percentage (e.g. `50` for 50% off). Checkout
  totals, ticket row amounts, and event-detail pricing all use the same
  `price × quantity × pct / 100` formula.

  Call `amount/3` for order totals and `per_ticket_amount/3` when writing
  `discount_amount` onto each ticket created from a fulfilled hold.
  """

  @zero Money.new(0, :USD)
  @hundred Decimal.new(100)

  @doc """
  Discount amount for `price * quantity` at `percentage` (0–100).

  Returns `$0.00` when price, quantity, or percentage is missing, zero, or
  invalid.
  """
  def amount(price, quantity, percentage)

  def amount(%Money{} = price, quantity, %Decimal{} = percentage)
      when is_integer(quantity) and quantity > 0 do
    if Decimal.gt?(percentage, 0) do
      {:ok, original_total} = Money.mult(price, quantity)
      apply_percentage(original_total, percentage)
    else
      @zero
    end
  end

  def amount(_price, _quantity, _percentage), do: @zero

  @doc """
  Per-ticket share of `amount/3`, divided evenly across `quantity`.

  Used when writing `discount_amount` onto each ticket created from a
  fulfilled reservation.
  """
  def per_ticket_amount(price, quantity, percentage)

  def per_ticket_amount(%Money{} = price, quantity, percentage)
      when is_integer(quantity) and quantity > 0 do
    total = amount(price, quantity, percentage)
    {:ok, per_ticket} = Money.div(total, quantity)
    per_ticket
  end

  def per_ticket_amount(_price, _quantity, _percentage), do: @zero

  defp apply_percentage(%Money{} = money, %Decimal{} = percentage) do
    discount_pct_decimal = Decimal.div(percentage, @hundred)

    case Money.mult(money, discount_pct_decimal) do
      {:ok, discount} -> discount
      {:error, _} -> @zero
    end
  end
end
