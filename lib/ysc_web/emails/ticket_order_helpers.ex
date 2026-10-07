defmodule YscWeb.Emails.TicketOrderHelpers do
  @moduledoc """
  Shared ticket-order line items and per-tier summaries for purchase and refund emails.

  Purchase confirmation and refund emails render the same grouped-by-tier table
  (quantity, unit price, line total). Call `tier_summaries/3` and `ticket_refs/2`
  instead of duplicating donation-split and list-price math in each template
  module.

  Donation rows split `total_amount` minus **list** (pre-discount) prices of
  non-donation tickets. That matches the historical email table. LiveViews that
  need net (post-discount) donation shares should keep using
  `Ysc.Tickets.DonationDisplay`.

  ## Examples

      summaries = tier_summaries(ticket_order.tickets, ticket_order, discounts: true)

      refs = ticket_refs(refunded_tickets)
  """

  import YscWeb.Emails.Helpers, only: [format_money: 1]

  alias Ysc.Events.TicketTierHelpers

  @zero Money.new(0, :USD)
  @unknown_tier "Unknown Tier"
  @zero_display {"$0.00", "$0.00"}

  @doc """
  Groups `tickets` by tier for MJML tables.

  Each row includes `ticket_tier_name`, `quantity`, `price_per_ticket`, and
  `total_price` (formatted money strings).

  Options:

    * `:discounts` — when `true` (purchase confirmation), also set
      `original_price`, `discount_amount`, and `discount_percentage`. Refund
      emails omit these keys.
  """
  def tier_summaries(tickets, ticket_order, opts \\ [])

  def tier_summaries(tickets, ticket_order, opts) when is_list(tickets) do
    include_discounts? = Keyword.get(opts, :discounts, false) == true

    tickets
    |> Enum.group_by(& &1.ticket_tier_id)
    |> Enum.map(fn {_tier_id, tier_tickets} ->
      summarize_tier(tier_tickets, ticket_order, include_discounts?)
    end)
  end

  @doc """
  Maps tickets to `{reference_id, ticket_tier_name}` rows for MJML lists.

  Pass `status: true` to include each ticket's status (purchase confirmation).
  """
  def ticket_refs(tickets, opts \\ [])

  def ticket_refs(tickets, opts) when is_list(tickets) do
    include_status? = Keyword.get(opts, :status, false) == true

    Enum.map(tickets, fn ticket ->
      row = %{
        reference_id: ticket.reference_id,
        ticket_tier_name: tier_display_name(ticket)
      }

      if include_status? do
        Map.put(row, :status, ticket.status)
      else
        row
      end
    end)
  end

  @doc """
  Multiplies a unit price by quantity for a tier line total.

  Returns `$0` when `price` is not money.
  """
  def tier_total(%Money{amount: amount}, quantity) when is_integer(quantity) do
    Money.new(Decimal.mult(amount, Decimal.new(quantity)), :USD)
  end

  def tier_total(_, _), do: @zero

  @doc """
  Formats `{unit_price, line_total}` for one donation tier on an order.

  Splits the remainder of `ticket_order.total_amount` after non-donation list
  prices evenly across every donation ticket on the order, then multiplies the
  per-ticket share by how many of those tickets belong to this tier.

  Returns `{"$0.00", "$0.00"}` when the order has no tickets or the remainder
  is not positive.
  """
  def donation_amounts(
        [%{ticket_tier_id: tier_id} | _],
        %{tickets: tickets} = ticket_order
      )
      when is_list(tickets) do
    non_donation_total = non_donation_list_total(tickets)

    donation_total =
      case Money.sub(ticket_order.total_amount, non_donation_total) do
        {:ok, amount} -> amount
        _ -> @zero
      end

    donation_tickets_by_tier =
      tickets
      |> Enum.filter(&TicketTierHelpers.donation_ticket?/1)
      |> Enum.group_by(& &1.ticket_tier_id)

    this_tier_count = length(Map.get(donation_tickets_by_tier, tier_id, []))

    total_donation_count =
      Enum.sum(
        Enum.map(donation_tickets_by_tier, fn {_tid, grouped} ->
          length(grouped)
        end)
      )

    if total_donation_count > 0 && Money.positive?(donation_total) do
      {:ok, per_ticket_amount} = Money.div(donation_total, total_donation_count)
      {:ok, line_total} = Money.mult(per_ticket_amount, this_tier_count)

      {format_money(per_ticket_amount), format_money(line_total)}
    else
      @zero_display
    end
  end

  def donation_amounts(_donation_tickets, _ticket_order), do: @zero_display

  defp summarize_tier(
         [first_ticket | _] = tier_tickets,
         ticket_order,
         include_discounts?
       ) do
    if is_nil(first_ticket.ticket_tier) do
      raise ArgumentError,
            "Ticket missing ticket_tier association: ticket_id=#{first_ticket.id}, tier_id=#{first_ticket.ticket_tier_id}"
    end

    quantity = length(tier_tickets)
    tier = first_ticket.ticket_tier

    {price_per_ticket, total_price, discount_fields} =
      if TicketTierHelpers.donation_tier?(tier) do
        {per_ticket, total} = donation_amounts(tier_tickets, ticket_order)

        extras =
          if include_discounts? do
            %{
              original_price: total,
              discount_amount: @zero,
              discount_percentage: nil
            }
          else
            %{}
          end

        {per_ticket, total, extras}
      else
        paid_price_fields(tier, tier_tickets, quantity, include_discounts?)
      end

    Map.merge(
      %{
        ticket_tier_name: tier.name,
        quantity: quantity,
        price_per_ticket: price_per_ticket,
        total_price: total_price
      },
      discount_fields
    )
  end

  defp paid_price_fields(tier, _tier_tickets, quantity, false) do
    price = tier.price || @zero

    {format_money(price), format_money(tier_total(price, quantity)), %{}}
  end

  defp paid_price_fields(tier, tier_tickets, quantity, true) do
    price = tier.price || @zero
    original_total = tier_total(price, quantity)

    total_tier_discount =
      Enum.reduce(tier_tickets, @zero, fn ticket, acc ->
        add_money(acc, ticket.discount_amount || @zero)
      end)

    discounted_total =
      case Money.sub(original_total, total_tier_discount) do
        {:ok, total} -> total
        _ -> original_total
      end

    discount_pct =
      if Money.positive?(total_tier_discount) && Money.positive?(price) do
        {:ok, per_ticket_discount} = Money.div(total_tier_discount, quantity)

        per_ticket_discount.amount
        |> Decimal.div(price.amount)
        |> Decimal.mult(Decimal.new(100))
        |> Decimal.to_float()
      else
        nil
      end

    {format_money(price), format_money(discounted_total),
     %{
       original_price: format_money(original_total),
       discount_amount: format_money(total_tier_discount),
       discount_percentage: discount_pct
     }}
  end

  defp non_donation_list_total(tickets) do
    tickets
    |> Enum.reject(&TicketTierHelpers.donation_ticket?/1)
    |> Enum.reduce(@zero, fn ticket, acc ->
      case ticket.ticket_tier.price do
        %Money{} = price -> add_money(acc, price)
        _ -> acc
      end
    end)
  end

  defp add_money(%Money{} = acc, %Money{} = amount) do
    case Money.add(acc, amount) do
      {:ok, total} -> total
      _ -> acc
    end
  end

  defp tier_display_name(%{ticket_tier: nil}), do: @unknown_tier
  defp tier_display_name(%{ticket_tier: tier}), do: tier.name
  defp tier_display_name(_), do: @unknown_tier
end
