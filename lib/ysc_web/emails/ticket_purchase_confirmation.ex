defmodule YscWeb.Emails.TicketPurchaseConfirmation do
  @moduledoc """
  Email template for ticket purchase confirmation.

  Sends a confirmation email to users after successful ticket purchase.
  """
  use MjmlEEx,
    mjml_template: "templates/ticket_purchase_confirmation.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      absolute_url: 1,
      event_url: 1,
      format_datetime: 1,
      format_event_start_datetime: 3,
      format_money: 1,
      member_greeting_name: 1
    ]

  alias Ysc.Tickets
  alias YscWeb.Emails.TicketOrderHelpers

  def get_template_name() do
    "ticket_purchase_confirmation"
  end

  def get_subject() do
    "Your tickets are confirmed! 🎫"
  end

  def tickets_qr_url(order_id) do
    absolute_url("/tickets/#{order_id}/qr")
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

    ticket_order = ensure_ticket_order_loaded(ticket_order)

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

    ticket_summaries =
      TicketOrderHelpers.tier_summaries(ticket_order.tickets, ticket_order,
        discounts: true
      )

    # Format dates and times
    event_date_time =
      format_event_start_datetime(
        ticket_order.event.start_date,
        ticket_order.event.start_time,
        "TBD"
      )

    purchase_date = format_datetime(ticket_order.completed_at)

    # An in-person cash/check sale recorded via the admin app has no Stripe
    # `payment` row (it is a $0 admin grant); `payment_channel` /
    # `offline_amount_collected` on the order carry how the money changed hands.
    paid_in_person? = not is_nil(ticket_order.payment_channel)

    payment_date =
      cond do
        ticket_order.payment ->
          format_datetime(ticket_order.payment.payment_date)

        paid_in_person? ->
          format_datetime(ticket_order.completed_at)

        true ->
          "N/A"
      end

    # Get payment method information
    payment_method =
      cond do
        ticket_order.payment ->
          get_payment_method_description(ticket_order.payment)

        paid_in_person? ->
          offline_payment_method_description(ticket_order.payment_channel)

        true ->
          "Free"
      end

    # An in-person sale is booked as a $0 admin grant, so `total_amount` on the
    # order is $0 even though the buyer handed over cash/a check — which reads
    # as a contradiction next to the per-tier prices in the table. Show what
    # was actually collected (or, if no amount was recorded, the tier-price
    # total) so the receipt is internally consistent.
    displayed_total =
      cond do
        not paid_in_person? ->
          ticket_order.total_amount

        not is_nil(ticket_order.offline_amount_collected) ->
          ticket_order.offline_amount_collected

        true ->
          tier_price_total(ticket_order)
      end

    # Format money amounts
    total_amount = format_money(displayed_total)

    # Use stored discount_amount from ticket_order, or calculate from tickets if not stored
    discount_amount =
      ticket_order.discount_amount ||
        calculate_discount_from_tickets(ticket_order)

    total_discount_str = format_money(discount_amount)

    # Calculate gross total (total_amount + discount_amount)
    gross_total_str =
      case Money.add(displayed_total, discount_amount) do
        {:ok, gross} -> format_money(gross)
        _ -> total_amount
      end

    # Prepare agenda data if available
    # Handle case where event.agendas might be nil
    agendas = ticket_order.event.agendas || []

    agenda_data = prepare_agenda_data(agendas)

    %{
      first_name: member_greeting_name(ticket_order.user),
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
      tickets_qr_url: tickets_qr_url(ticket_order.id),
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
      paid_in_person: paid_in_person?,
      total_amount: total_amount,
      gross_total: gross_total_str,
      total_discount: total_discount_str,
      has_discounts: Money.positive?(discount_amount),
      ticket_summaries: ticket_summaries,
      tickets:
        TicketOrderHelpers.ticket_refs(ticket_order.tickets, status: true)
    }
  end

  defp offline_payment_method_description("cash"), do: "Cash (paid in person)"
  defp offline_payment_method_description("check"), do: "Check (paid in person)"
  defp offline_payment_method_description(_), do: "Paid in person"

  # Sum of tier price × quantity across the order's tickets — the fallback
  # "what these tickets are worth" figure for an in-person sale that recorded
  # no explicit collected amount.
  defp tier_price_total(ticket_order) do
    ticket_order.tickets
    |> Enum.group_by(& &1.ticket_tier_id)
    |> Enum.reduce(Money.new(0, :USD), fn {_tier_id, tier_tickets}, acc ->
      tier = List.first(tier_tickets).ticket_tier
      price = (tier && tier.price) || Money.new(0, :USD)

      case Money.add(
             acc,
             TicketOrderHelpers.tier_total(price, length(tier_tickets))
           ) do
        {:ok, sum} -> sum
        _ -> acc
      end
    end)
  end

  defp get_payment_method_description(payment) do
    case payment.payment_method do
      nil ->
        "Credit or debit card"

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

  defp ensure_ticket_order_loaded(ticket_order) do
    if ticket_order_email_data_loaded?(ticket_order) do
      ticket_order
    else
      case Tickets.get_ticket_order(ticket_order.id) do
        nil ->
          raise ArgumentError, "Ticket order not found: #{ticket_order.id}"

        loaded_order ->
          loaded_order
      end
    end
  end

  defp ticket_order_email_data_loaded?(ticket_order) do
    Ecto.assoc_loaded?(ticket_order.user) and
      Ecto.assoc_loaded?(ticket_order.event) and
      Ecto.assoc_loaded?(ticket_order.tickets) and
      ticket_order.tickets != []
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
end
