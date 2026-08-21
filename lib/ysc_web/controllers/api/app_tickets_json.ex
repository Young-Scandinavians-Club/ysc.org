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
end
