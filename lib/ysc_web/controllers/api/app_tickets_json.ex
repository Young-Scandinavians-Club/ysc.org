defmodule YscWeb.Api.AppTicketsJSON do
  @moduledoc """
  JSON rendering for the admin/volunteer mobile app's ticket purchase endpoint.
  """

  def payment_intent(%{
        payment_intent: payment_intent,
        ticket_order: ticket_order
      }) do
    %{
      ticket_order_id: to_string(ticket_order.id),
      ticket_order_reference: ticket_order.reference_id,
      payment_intent_id: payment_intent.id,
      client_secret: payment_intent.client_secret,
      amount: payment_intent.amount,
      currency: payment_intent.currency
    }
  end

  @doc """
  Renders the completed, already-fulfilled order from an offline (cash/check)
  ticket sale. No payment intent — the order is a $0 grant with the collected
  amount recorded in `admin_grant_notes`.
  """
  def offline_order(%{ticket_order: ticket_order}) do
    %{
      ticket_order_id: to_string(ticket_order.id),
      ticket_order_reference: ticket_order.reference_id,
      status: to_string(ticket_order.status),
      ticket_count: length(ticket_order.tickets || []),
      notes: ticket_order.admin_grant_notes
    }
  end
end
