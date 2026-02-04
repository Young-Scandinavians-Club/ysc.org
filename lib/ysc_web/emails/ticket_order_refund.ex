defmodule YscWeb.Emails.TicketOrderRefund do
  @moduledoc """
  Email template for ticket order refunds.

  Sends a confirmation email to users after their ticket order has been refunded.
  """
  use MjmlEEx,
    mjml_template: "templates/ticket_order_refund.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Tickets

  def get_template_name() do
    "ticket_order_refund"
  end

  def get_subject() do
    "Your ticket refund has been processed"
  end

  def event_url(event_id) do
    YscWeb.Endpoint.url() <> "/events/#{event_id}"
  end

  @doc """
  Prepares ticket order refund email data.

  ## Parameters:
  - `refund`: The refund record with preloaded associations
  - `ticket_order`: The ticket order that was refunded
  - `refunded_tickets`: List of tickets that were refunded

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(refund, ticket_order, refunded_tickets) do
    # Validate input
    if is_nil(refund) do
      raise ArgumentError, "Refund cannot be nil"
    end

    if is_nil(ticket_order) do
      raise ArgumentError, "Ticket order cannot be nil"
    end

    # Ensure we have all necessary preloaded data
    ticket_order =
      case Tickets.get_ticket_order(ticket_order.id) do
        nil ->
          raise ArgumentError, "Ticket order not found: #{ticket_order.id}"

        loaded_order ->
          loaded_order
      end

    # Validate required associations
    if is_nil(ticket_order.user) do
      raise ArgumentError,
            "Ticket order missing user association: #{ticket_order.id}"
    end

    if is_nil(ticket_order.event) do
      raise ArgumentError,
            "Ticket order missing event association: #{ticket_order.id}"
    end

    # Format dates and times
    event_date_time = format_event_datetime(ticket_order.event)
    refund_date = format_datetime(refund.inserted_at)

    # Format money amounts
    refund_amount = format_money(refund.amount)

    # Group refunded tickets by tier for summary
    ticket_summaries = prepare_ticket_summaries(refunded_tickets, ticket_order)

    %{
      first_name: ticket_order.user.first_name || "Valued Member",
      event: %{
        title: ticket_order.event.title,
        description: ticket_order.event.description,
        start_date: ticket_order.event.start_date,
        start_time: ticket_order.event.start_time,
        location_name: ticket_order.event.location_name,
        address: ticket_order.event.address
      },
      event_date_time: event_date_time,
      event_url: event_url(ticket_order.event.id),
      ticket_order: %{
        reference_id: ticket_order.reference_id
      },
      refund: %{
        reference_id: refund.reference_id,
        amount: refund_amount,
        reason: refund.reason || "Refund processed",
        refund_date: refund_date
      },
      refund_date: refund_date,
      refund_amount: refund_amount,
      ticket_summaries: ticket_summaries,
      refunded_tickets:
        Enum.map(refunded_tickets, fn ticket ->
          ticket_tier_name =
            if ticket.ticket_tier do
              ticket.ticket_tier.name
            else
              "Unknown Tier"
            end

          %{
            reference_id: ticket.reference_id,
            ticket_tier_name: ticket_tier_name
          }
        end)
    }
  end

  defp prepare_ticket_summaries(tickets, ticket_order) do
    tickets
    |> Enum.group_by(& &1.ticket_tier_id)
    |> Enum.map(fn {_tier_id, tier_tickets} ->
      first_ticket = List.first(tier_tickets)

      if is_nil(first_ticket.ticket_tier) do
        raise ArgumentError,
              "Ticket missing ticket_tier association: ticket_id=#{first_ticket.id}, tier_id=#{first_ticket.ticket_tier_id}"
      end

      quantity = length(tier_tickets)
      tier = first_ticket.ticket_tier

      # Check if this is a donation tier
      is_donation = tier.type == "donation" || tier.type == :donation

      {price_per_ticket, total_price} =
        if is_donation do
          # Calculate donation amount from ticket_order
          calculate_donation_amounts(tier_tickets, ticket_order)
        else
          # Regular tier pricing
          price = tier.price || Money.new(0, :USD)

          {format_money(price),
           format_money(calculate_tier_total(price, quantity))}
        end

      %{
        ticket_tier_name: tier.name,
        quantity: quantity,
        price_per_ticket: price_per_ticket,
        total_price: total_price
      }
    end)
  end

  defp calculate_donation_amounts(donation_tickets, ticket_order) do
    if ticket_order && ticket_order.tickets do
      # Calculate non-donation ticket costs
      non_donation_total =
        ticket_order.tickets
        |> Enum.filter(fn t ->
          t.ticket_tier.type != "donation" && t.ticket_tier.type != :donation
        end)
        |> Enum.reduce(Money.new(0, :USD), fn t, acc ->
          case t.ticket_tier.price do
            nil ->
              acc

            price when is_struct(price, Money) ->
              case Money.add(acc, price) do
                {:ok, new_total} -> new_total
                _ -> acc
              end

            _ ->
              acc
          end
        end)

      # Calculate total donation amount
      donation_total =
        case Money.sub(ticket_order.total_amount, non_donation_total) do
          {:ok, amount} -> amount
          _ -> Money.new(0, :USD)
        end

      # Group all donation tickets by tier
      donation_tickets_by_tier =
        ticket_order.tickets
        |> Enum.filter(fn t ->
          t.ticket_tier.type == "donation" || t.ticket_tier.type == :donation
        end)
        |> Enum.group_by(& &1.ticket_tier_id)

      # Get the tier_id for this specific donation tier
      tier_id = List.first(donation_tickets).ticket_tier_id
      this_tier_tickets = Map.get(donation_tickets_by_tier, tier_id, [])

      # Count tickets in this tier
      this_tier_count = length(this_tier_tickets)

      total_donation_count =
        Enum.sum(
          Enum.map(donation_tickets_by_tier, fn {_tid, tickets} ->
            length(tickets)
          end)
        )

      if total_donation_count > 0 && Money.positive?(donation_total) do
        per_ticket_amount =
          case Money.div(donation_total, total_donation_count) do
            {:ok, amount} -> amount
            _ -> Money.new(0, :USD)
          end

        tier_total =
          case Money.mult(per_ticket_amount, this_tier_count) do
            {:ok, amount} -> amount
            _ -> Money.new(0, :USD)
          end

        {format_money(per_ticket_amount), format_money(tier_total)}
      else
        {"$0.00", "$0.00"}
      end
    else
      {"$0.00", "$0.00"}
    end
  end

  defp calculate_tier_total(price, quantity) do
    case price do
      %Money{amount: amount} ->
        Money.new(Decimal.mult(amount, Decimal.new(quantity)), :USD)

      _ ->
        Money.new(0, :USD)
    end
  end

  defp format_event_datetime(event) do
    case {event.start_date, event.start_time} do
      {nil, _} ->
        "TBD"

      {date, nil} ->
        Calendar.strftime(date, "%B %d, %Y")

      {date, time} ->
        # Convert DateTime to Date if needed
        date_only =
          if is_struct(date, DateTime), do: DateTime.to_date(date), else: date

        datetime = DateTime.new!(date_only, time, "Etc/UTC")
        # Convert to PST
        pst_datetime = DateTime.shift_zone!(datetime, "America/Los_Angeles")
        Calendar.strftime(pst_datetime, "%B %d, %Y at %I:%M %p %Z")
    end
  end

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    # Convert to PST
    pst_datetime = DateTime.shift_zone!(datetime, "America/Los_Angeles")
    Calendar.strftime(pst_datetime, "%B %d, %Y at %I:%M %p %Z")
  end

  defp format_money(%Money{} = money) do
    Money.to_string!(money,
      separator: ".",
      delimiter: ",",
      fractional_digits: 2
    )
  end

  defp format_money(_), do: "$0.00"
end
