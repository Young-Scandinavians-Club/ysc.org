defmodule Ysc.Tickets.DonationDisplay do
  @moduledoc """
  Computes per-ticket donation display amounts from a ticket order.

  Donation tiers share the remainder of `total_amount` after non-donation ticket
  net prices are subtracted. Callers should compute once per order and reuse the
  map instead of recalculating inside ticket loops.
  """

  alias Ysc.MoneyHelper
  alias Ysc.Events.TicketTierHelpers

  @zero Money.new(0, :USD)

  @doc """
  Returns `%{ticket_id => Money.t()}` for every ticket on the order.

  - Paid tickets: `tier.price - discount_amount` (floored at $0)
  - Free tickets: $0
  - Donation tickets: even split of `total_amount` minus non-donation nets

  All donation tickets on the order (any status) share the split so a later
  partial refund of a remaining donation ticket still uses the original
  per-ticket donation amount.
  """
  def money_amounts_by_ticket_id(%{
        tickets: tickets,
        total_amount: total_amount
      })
      when is_list(tickets) do
    donation_tickets =
      Enum.filter(tickets, &TicketTierHelpers.donation_ticket?/1)

    donation_share =
      donation_share(tickets, total_amount, length(donation_tickets))

    Map.new(tickets, fn ticket ->
      amount =
        cond do
          TicketTierHelpers.donation_ticket?(ticket) -> donation_share
          free_ticket?(ticket) -> @zero
          true -> net_price(ticket)
        end

      {ticket.id, amount}
    end)
  end

  def money_amounts_by_ticket_id(_), do: %{}

  @doc """
  Returns `%{ticket_id => formatted_amount}` for donation tickets on the order.

  Non-donation tickets are omitted. When donation totals cannot be split, each
  donation ticket maps to `"Donation"`.
  """
  def amounts_by_ticket_id(order) do
    donation_tickets =
      case order do
        %{tickets: tickets} when is_list(tickets) ->
          Enum.filter(tickets, &TicketTierHelpers.donation_ticket?/1)

        _ ->
          []
      end

    amounts = money_amounts_by_ticket_id(order)

    Map.new(donation_tickets, fn ticket ->
      case Map.get(amounts, ticket.id) do
        %Money{} = money ->
          if Money.positive?(money) do
            {ticket.id, format_amount(money)}
          else
            {ticket.id, "Donation"}
          end

        _ ->
          {ticket.id, "Donation"}
      end
    end)
  end

  @doc """
  Looks up a precomputed donation display string, defaulting to `"Donation"`.
  """
  def amount_for_ticket(ticket_order, ticket_id) do
    ticket_order
    |> amounts_by_ticket_id()
    |> Map.get(ticket_id, "Donation")
  end

  defp donation_share(tickets, total_amount, donation_count) do
    with true <- donation_count > 0,
         %Money{} <- total_amount,
         %Money{} = non_donation_total <- non_donation_total(tickets),
         {:ok, donation_total} <- Money.sub(total_amount, non_donation_total),
         true <- Money.positive?(donation_total),
         {:ok, per_ticket_amount} <- Money.div(donation_total, donation_count) do
      per_ticket_amount
    else
      _ -> @zero
    end
  end

  defp non_donation_total(tickets) do
    Enum.reduce(tickets, @zero, fn ticket, acc ->
      if TicketTierHelpers.donation_ticket?(ticket) or free_ticket?(ticket) do
        acc
      else
        case Money.add(acc, net_price(ticket)) do
          {:ok, new_total} -> new_total
          _ -> acc
        end
      end
    end)
  end

  defp net_price(ticket) do
    discount = ticket.discount_amount || @zero

    case ticket.ticket_tier.price do
      %Money{} = price ->
        case Money.sub(price, discount) do
          {:ok, net} ->
            if Money.negative?(net), do: @zero, else: net

          _ ->
            price
        end

      _ ->
        @zero
    end
  end

  defp free_ticket?(%{ticket_tier: %{type: type}}) when type in [:free, "free"],
    do: true

  defp free_ticket?(_), do: false

  defp format_amount(%Money{} = amount) do
    MoneyHelper.format_money!(amount)
  rescue
    _ -> "Donation"
  end
end
