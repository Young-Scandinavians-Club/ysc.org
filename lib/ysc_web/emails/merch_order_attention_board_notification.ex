defmodule YscWeb.Emails.MerchOrderAttentionBoardNotification do
  @moduledoc """
  Tells the board a merch order needs a human: a paid order that couldn't be
  sent to Printful, was canceled or put on hold by Printful, or came back.
  """
  use MjmlEEx,
    mjml_template:
      "templates/merch_order_attention_board_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [absolute_url: 1, format_money: 1]

  alias Ysc.Merch.Order

  def get_template_name, do: "merch_order_attention_board_notification"

  def get_subject(kind, %Order{reference_id: reference_id}),
    do: "Merch order needs attention: #{label(kind)} (#{reference_id})"

  @doc "Short name of what went wrong."
  def label(:submit_failed), do: "couldn't be sent to Printful"
  def label(:failed), do: "Printful couldn't make it"
  def label(:canceled), do: "canceled by Printful"
  def label(:on_hold), do: "on hold at Printful"
  def label(:returned), do: "package returned"

  @doc "What a board member should do about it."
  def action(kind, %Order{kind: :admin_comp}), do: club_paid_action(kind)

  def action(kind, %Order{kind: :purchase})
      when kind in [:submit_failed, :failed, :canceled],
      do:
        "The member has paid and will not receive their order. Refund the payment from Admin > Money, " <>
          "or resolve the problem in Printful and resubmit."

  def action(:on_hold, _),
    do:
      "Printful has paused this order, most often because the club's payment method on file was declined. Check billing in Printful."

  def action(:returned, _),
    do:
      "The package came back to Printful. Contact the member to confirm their address."

  defp club_paid_action(:on_hold), do: action(:on_hold, nil)
  defp club_paid_action(:returned), do: action(:returned, nil)

  defp club_paid_action(_),
    do:
      "This was a club-paid order and it will not arrive. Check the order in Printful and place it again if it is still needed."

  def prepare_email_data(kind, %Order{} = order, reason) do
    %{
      label: label(kind),
      reason: reason,
      action: action(kind, order),
      order: %{reference_id: order.reference_id},
      order_kind:
        if(order.kind == :admin_comp,
          do: "Club-paid order",
          else: "Member purchase"
        ),
      who: who(order),
      amount_paid: format_money(order.total_amount),
      items: Enum.map(order.items, &%{name: &1.name, quantity: &1.quantity}),
      admin_url: absolute_url("/admin/merch")
    }
  end

  defp who(%Order{user: %{} = user}),
    do: "#{user.first_name} #{user.last_name} (#{user.email})"

  defp who(%Order{recipient_name: name, email: email}),
    do: "#{name}#{if email, do: " (#{email})"}"
end
