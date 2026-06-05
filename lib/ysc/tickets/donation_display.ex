defmodule Ysc.Tickets.DonationDisplay do
  @moduledoc """
  Computes per-ticket donation display amounts from a ticket order.

  Donation tiers share the remainder of `total_amount` after non-donation ticket
  net prices are subtracted. Callers should compute once per order and reuse the
  map instead of recalculating inside ticket loops.
  """

  alias Ysc.MoneyHelper

  @doc """
  Returns `%{ticket_id => formatted_amount}` for donation tickets on the order.

  Non-donation tickets are omitted. When donation totals cannot be split, each
  donation ticket maps to `"Donation"`.
  """
  def amounts_by_ticket_id(%{tickets: tickets, total_amount: total_amount})
      when is_list(tickets) do
    donation_tickets = Enum.filter(tickets, &donation_ticket?/1)
    donation_count = length(donation_tickets)

    with true <- donation_count > 0,
         %Money{} = total_amount <- total_amount,
         %Money{} = non_donation_total <- non_donation_total(tickets),
         {:ok, donation_total} <- Money.sub(total_amount, non_donation_total),
         true <- Money.positive?(donation_total),
         {:ok, per_ticket_amount} <- Money.div(donation_total, donation_count) do
      formatted = format_amount(per_ticket_amount)

      Map.new(donation_tickets, fn ticket ->
        {ticket.id, formatted}
      end)
    else
      _ ->
        Map.new(donation_tickets, fn ticket -> {ticket.id, "Donation"} end)
    end
  end

  def amounts_by_ticket_id(_), do: %{}

  @doc """
  Looks up a precomputed donation display string, defaulting to `"Donation"`.
  """
  def amount_for_ticket(ticket_order, ticket_id) do
    ticket_order
    |> amounts_by_ticket_id()
    |> Map.get(ticket_id, "Donation")
  end

  defp non_donation_total(tickets) do
    Enum.reduce(tickets, Money.new(0, :USD), fn ticket, acc ->
      if donation_ticket?(ticket) do
        acc
      else
        add_ticket_net_price(acc, ticket)
      end
    end)
  end

  defp add_ticket_net_price(acc, ticket) do
    discount = ticket.discount_amount || Money.new(0, :USD)

    case ticket.ticket_tier.price do
      nil ->
        acc

      %Money{} = price ->
        ticket_total =
          case Money.sub(price, discount) do
            {:ok, net} -> net
            _ -> price
          end

        case Money.add(acc, ticket_total) do
          {:ok, new_total} -> new_total
          _ -> acc
        end

      _ ->
        acc
    end
  end

  defp donation_ticket?(%{ticket_tier: %{type: type}})
       when type in [:donation, "donation"],
       do: true

  defp donation_ticket?(_), do: false

  defp format_amount(%Money{} = amount) do
    MoneyHelper.format_money!(amount)
  rescue
    _ -> "Donation"
  end
end
