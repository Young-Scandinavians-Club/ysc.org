defmodule YscWeb.Api.AppTicketsJSON do
  @moduledoc """
  JSON rendering for the admin/volunteer mobile app's ticket purchase endpoint.
  """

  def payment_intent(%{
        payment_intent: payment_intent,
        ticket_order: ticket_order,
        warnings: warnings
      }) do
    %{
      ticket_order_id: to_string(ticket_order.id),
      ticket_order_reference: ticket_order.reference_id,
      payment_intent_id: payment_intent.id,
      client_secret: payment_intent.client_secret,
      amount: payment_intent.amount,
      currency: payment_intent.currency,
      warnings: warnings
    }
  end

  @doc """
  Renders the completed, already-fulfilled order from an offline (cash/check)
  ticket sale. No payment intent — the order is a $0 grant with the collected
  amount recorded in `admin_grant_notes`.
  """
  def offline_order(%{ticket_order: ticket_order, warnings: warnings}) do
    %{
      ticket_order_id: to_string(ticket_order.id),
      ticket_order_reference: ticket_order.reference_id,
      status: to_string(ticket_order.status),
      ticket_count: length(ticket_order.tickets || []),
      payment_channel: ticket_order.payment_channel,
      amount_collected: money_string(ticket_order.offline_amount_collected),
      notes: ticket_order.admin_grant_notes,
      warnings: warnings
    }
  end

  defp money_string(nil), do: nil
  defp money_string(%Money{} = money), do: Money.to_string!(money)
end
