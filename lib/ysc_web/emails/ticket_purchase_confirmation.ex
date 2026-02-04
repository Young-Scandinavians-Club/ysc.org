defmodule YscWeb.Emails.TicketPurchaseConfirmation do
  @moduledoc """
  Email template for ticket purchase confirmation.

  Sends a confirmation email to users after successful ticket purchase.
  """
  use MjmlEEx,
    mjml_template: "templates/ticket_purchase_confirmation.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Tickets

  def get_template_name() do
    "ticket_purchase_confirmation"
  end

  def get_subject() do
    "Your tickets are confirmed! 🎫"
  end

  def event_url(event_id) do
    YscWeb.Endpoint.url() <> "/events/#{event_id}"
  end

  @doc """
  Prepares ticket purchase confirmation email data for a completed ticket order.

  ## Parameters:
  - `ticket_order`: The completed ticket order with preloaded associations

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(ticket_order) do
    # Validate input
    if is_nil(ticket_order) do
      raise ArgumentError, "Ticket order cannot be nil"
    end

    if is_nil(ticket_order.id) do
      raise ArgumentError, "Ticket order missing id: #{inspect(ticket_order)}"
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

    if is_nil(ticket_order.tickets) or Enum.empty?(ticket_order.tickets) do
      raise ArgumentError, "Ticket order missing tickets: #{ticket_order.id}"
    end

    # Group tickets by tier for summary
    ticket_summaries =
      prepare_ticket_summaries(ticket_order.tickets, ticket_order)

    # Format dates and times
    event_date_time = format_event_datetime(ticket_order.event)
    purchase_date = format_datetime(ticket_order.completed_at)

    payment_date =
      if ticket_order.payment,
        do: format_datetime(ticket_order.payment.payment_date),
        else: "N/A"

    # Get payment method information
    payment_method =
      if ticket_order.payment,
        do: get_payment_method_description(ticket_order.payment),
        else: "Free"

    # Format money amounts
    total_amount = format_money(ticket_order.total_amount)

    # Use stored discount_amount from ticket_order, or calculate from tickets if not stored
    discount_amount =
      ticket_order.discount_amount ||
        calculate_discount_from_tickets(ticket_order)

    total_discount_str = format_money(discount_amount)

    # Calculate gross total (total_amount + discount_amount)
    gross_total_str =
      case Money.add(ticket_order.total_amount, discount_amount) do
        {:ok, gross} -> format_money(gross)
        _ -> total_amount
      end

    # Prepare agenda data if available
    # Handle case where event.agendas might be nil
    agendas =
      if ticket_order.event, do: ticket_order.event.agendas || [], else: []

    agenda_data = prepare_agenda_data(agendas)

    %{
      first_name: ticket_order.user.first_name || "Valued Member",
      event: %{
        title: ticket_order.event.title,
        description: ticket_order.event.description,
        start_date: ticket_order.event.start_date,
        start_time: ticket_order.event.start_time,
        location_name: ticket_order.event.location_name,
        address: ticket_order.event.address,
        age_restriction: ticket_order.event.age_restriction
      },
      event_date_time: event_date_time,
      event_url: event_url(ticket_order.event.id),
      agenda: agenda_data,
      ticket_order: %{
        reference_id: ticket_order.reference_id,
        total_amount: total_amount,
        completed_at: ticket_order.completed_at
      },
      purchase_date: purchase_date,
      payment: %{
        reference_id:
          if(ticket_order.payment,
            do: ticket_order.payment.reference_id,
            else: "N/A"
          ),
        external_payment_id:
          if(ticket_order.payment,
            do: ticket_order.payment.external_payment_id,
            else: "N/A"
          ),
        amount: total_amount,
        payment_date: payment_date
      },
      payment_date: payment_date,
      payment_method: payment_method,
      total_amount: total_amount,
      gross_total: gross_total_str,
      total_discount: total_discount_str,
      has_discounts: Money.positive?(discount_amount),
      ticket_summaries: ticket_summaries,
      tickets:
        Enum.map(ticket_order.tickets, fn ticket ->
          ticket_tier_name =
            if ticket.ticket_tier do
              ticket.ticket_tier.name
            else
              "Unknown Tier"
            end

          %{
            reference_id: ticket.reference_id,
            ticket_tier_name: ticket_tier_name,
            status: ticket.status
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

      {price_per_ticket, total_price, original_price, discount_amount,
       discount_percentage} =
        if is_donation do
          # Calculate donation amount from ticket_order
          {per_ticket, total} =
            calculate_donation_amounts(tier_tickets, ticket_order)

          {per_ticket, total, total, Money.new(0, :USD), nil}
        else
          # Regular tier pricing - use stored discount_amount from tickets
          price = tier.price || Money.new(0, :USD)
          original_total = calculate_tier_total(price, quantity)

          # Sum discount amounts from tickets (stored when tickets were created)
          total_tier_discount =
            tier_tickets
            |> Enum.reduce(Money.new(0, :USD), fn ticket, acc ->
              ticket_discount = ticket.discount_amount || Money.new(0, :USD)

              case Money.add(acc, ticket_discount) do
                {:ok, total} -> total
                {:error, _} -> acc
              end
            end)

          discounted_total =
            case Money.sub(original_total, total_tier_discount) do
              {:ok, total} -> total
              _ -> original_total
            end

          # Calculate discount percentage from stored discount amount
          discount_pct =
            if Money.positive?(total_tier_discount) && Money.positive?(price) do
              # Calculate average discount percentage
              per_ticket_discount =
                case Money.div(total_tier_discount, quantity) do
                  {:ok, discount} -> discount
                  {:error, _} -> Money.new(0, :USD)
                end

              case Money.div(per_ticket_discount, price) do
                {:ok, ratio} ->
                  Decimal.mult(ratio.amount, Decimal.new(100))
                  |> Decimal.to_float()

                _ ->
                  nil
              end
            else
              nil
            end

          {format_money(price), format_money(discounted_total),
           format_money(original_total), format_money(total_tier_discount),
           discount_pct}
        end

      %{
        ticket_tier_name: tier.name,
        quantity: quantity,
        price_per_ticket: price_per_ticket,
        total_price: total_price,
        original_price: original_price,
        discount_amount: discount_amount,
        discount_percentage: discount_percentage
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
        # If there's only one donation tier, divide evenly
        # If multiple tiers, we can't determine exact amounts per tier without original data
        # So we'll divide evenly across all donation tickets (best approximation)
        per_ticket_amount =
          case Money.div(donation_total, total_donation_count) do
            {:ok, amount} -> amount
            _ -> Money.new(0, :USD)
          end

        # For this tier, multiply by the quantity of tickets in this tier
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

  defp get_payment_method_description(payment) do
    case payment.payment_method do
      nil ->
        "Credit Card (Stripe)"

      payment_method ->
        case payment_method.type do
          :card ->
            if payment_method.last_four do
              brand = payment_method.display_brand || "Card"

              "#{String.capitalize(brand)} ending in #{payment_method.last_four}"
            else
              "Credit Card"
            end

          :bank_account ->
            if payment_method.last_four do
              bank_name = payment_method.bank_name || "Bank"
              "#{bank_name} Account ending in #{payment_method.last_four}"
            else
              "Bank Account"
            end

          _ ->
            "Payment Method"
        end
    end
  end

  defp prepare_agenda_data(agendas) when is_list(agendas) and agendas != [] do
    agendas
    |> Enum.sort_by(& &1.position)
    |> Enum.map(fn agenda ->
      %{
        title: agenda.title,
        items: prepare_agenda_items(agenda.agenda_items)
      }
    end)
  end

  defp prepare_agenda_data(_), do: []

  defp prepare_agenda_items(agenda_items) when is_list(agenda_items) do
    agenda_items
    |> Enum.sort_by(& &1.position)
    |> Enum.with_index()
    |> Enum.map(fn {item, index} ->
      %{
        title: item.title,
        description: item.description,
        start_time: format_time(item.start_time),
        end_time: format_time(item.end_time),
        background_color: generate_agenda_color(index),
        border_color: generate_agenda_border_color(index)
      }
    end)
  end

  defp prepare_agenda_items(_), do: []

  defp format_time(nil), do: nil

  defp format_time(time) do
    Calendar.strftime(time, "%I:%M %p")
  end

  defp generate_agenda_color(index) do
    palette = [
      # Red-100
      "#FEE2E2",
      # Amber-100
      "#FEF9C3",
      # Green-100
      "#DCFCE7",
      # Blue-100
      "#DBEAFE",
      # Purple-100
      "#EDE9FE",
      # Pink-100
      "#FCE7F3",
      # Yellow-100
      "#FEF3C7",
      # Sky-100
      "#E0F2FE",
      # Emerald-100
      "#D1FAE5",
      # Indigo-100
      "#E0E7FF",
      # Rose-100
      "#FDE8E9",
      # Orange-100
      "#FFF7ED",
      # Neutral-100
      "#F3F4F6",
      # Cyan-100
      "#E8F5FF",
      # Violet-100
      "#FAE8FF"
    ]

    Enum.at(palette, rem(index, length(palette)))
  end

  defp generate_agenda_border_color(index) do
    palette = [
      # Red-400
      "#F87171",
      # Amber-400
      "#FBBF24",
      # Green-400
      "#4ADE80",
      # Blue-400
      "#60A5FA",
      # Purple-400
      "#A78BFA",
      # Pink-400
      "#FB7185",
      # Yellow-400
      "#FCD34D",
      # Sky-400
      "#38BDF8",
      # Emerald-400
      "#34D399",
      # Indigo-400
      "#818CF8",
      # Rose-400
      "#FB7185",
      # Orange-400
      "#FB923C",
      # Neutral-400
      "#A3A3A3",
      # Cyan-400
      "#22D3EE",
      # Violet-400
      "#C084FC"
    ]

    Enum.at(palette, rem(index, length(palette)))
  end

  # Calculate total discount from tickets (fallback if discount_amount not stored on order)
  defp calculate_discount_from_tickets(ticket_order) do
    if ticket_order && ticket_order.tickets do
      ticket_order.tickets
      |> Enum.reduce(Money.new(0, :USD), fn ticket, acc ->
        ticket_discount = ticket.discount_amount || Money.new(0, :USD)

        case Money.add(acc, ticket_discount) do
          {:ok, total} -> total
          {:error, _} -> acc
        end
      end)
    else
      Money.new(0, :USD)
    end
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
