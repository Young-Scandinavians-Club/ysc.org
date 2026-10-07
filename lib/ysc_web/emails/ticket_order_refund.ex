defmodule YscWeb.Emails.TicketOrderRefund do
  @moduledoc """
  Email template for ticket order refunds.

  Sends a confirmation email to users after their ticket order has been refunded.
  """
  use MjmlEEx,
    mjml_template: "templates/ticket_order_refund.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      event_url: 1,
      format_datetime: 1,
      format_event_start_datetime: 3,
      format_money: 1,
      member_greeting_name: 1
    ]

  alias Ysc.Tickets
  alias YscWeb.Emails.TicketOrderHelpers

  def get_template_name() do
    "ticket_order_refund"
  end

  def get_subject() do
    "Your ticket refund is on the way"
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

    # Always reload so callers that updated related records in the DB see fresh data.
    ticket_order =
      case Tickets.get_ticket_order_for_email(ticket_order.id) do
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
    event_date_time =
      format_event_start_datetime(
        ticket_order.event.start_date,
        ticket_order.event.start_time,
        "TBD"
      )

    refund_date = format_datetime(refund.inserted_at)

    # Format money amounts
    refund_amount = format_money(refund.amount)

    # Group refunded tickets by tier for summary
    ticket_summaries =
      TicketOrderHelpers.tier_summaries(refunded_tickets, ticket_order)

    %{
      first_name: member_greeting_name(ticket_order.user),
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
        reason: refund.reason || "Refund issued",
        refund_date: refund_date
      },
      refund_date: refund_date,
      refund_amount: refund_amount,
      ticket_summaries: ticket_summaries,
      refunded_tickets: TicketOrderHelpers.ticket_refs(refunded_tickets)
    }
  end
end
