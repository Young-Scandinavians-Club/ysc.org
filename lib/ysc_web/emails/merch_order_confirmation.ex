defmodule YscWeb.Emails.MerchOrderConfirmation do
  @moduledoc """
  Order confirmation for the merch shop.

  Sent when a member's payment succeeds, and when an admin places a club-paid
  order on someone's behalf (`kind: :admin_comp`), in which case it says the
  club is covering the cost.
  """
  use MjmlEEx,
    mjml_template: "templates/merch_order_confirmation.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [format_datetime: 1, format_money: 1]

  import YscWeb.Emails.MerchHelpers,
    only: [address_lines: 1, greeting_name: 1, member_order_url: 1]

  alias Ysc.Merch.Order
  alias YscWeb.Emails.MerchItems

  def get_template_name, do: "merch_order_confirmation"

  def get_subject(%Order{reference_id: reference_id}) do
    "We've got your merch order (#{reference_id})"
  end

  @doc """
  Template data for an order with `items` and slim `user` loaded
  (`Ysc.Merch.Orders.get_order_for_email/1`).
  """
  def prepare_email_data(%Order{} = order) do
    comp? = order.kind == :admin_comp

    %{
      first_name: greeting_name(order),
      comp: comp?,
      purpose: order.purpose,
      order: %{
        reference_id: order.reference_id,
        ordered_at: format_datetime(order.inserted_at)
      },
      items: MerchItems.for_order(order),
      subtotal: format_money(order.subtotal),
      shipping: format_money(order.shipping_amount),
      total: format_money(order.total_amount),
      delivery_estimate: Ysc.Merch.Shipping.delivery_estimate(order),
      ship_to: %{
        name: order.recipient_name,
        lines: address_lines(order)
      },
      order_url: member_order_url(order)
    }
  end
end
