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

  import YscWeb.Emails.Helpers,
    only: [
      absolute_url: 1,
      format_datetime: 1,
      format_money: 1,
      member_greeting_name: 1
    ]

  alias Ysc.Merch.Order
  alias YscWeb.Emails.MerchItems

  def get_template_name, do: "merch_order_confirmation"

  def get_subject(%Order{reference_id: reference_id}) do
    "We've got your merch order (#{reference_id})"
  end

  @doc """
  Template data for an order with `items` and `user` loaded.
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
      order_url: order_url(order)
    }
  end

  defp greeting_name(%Order{user: %{} = user}), do: member_greeting_name(user)

  defp greeting_name(%Order{recipient_name: name}),
    do: name |> first_word() |> member_greeting_name()

  defp first_word(nil), do: nil

  defp first_word(name),
    do: name |> String.split(" ", trim: true) |> List.first()

  defp address_lines(order) do
    [
      order.address1,
      order.address2,
      "#{order.city}, #{order.state_code} #{order.zip}"
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  # Members get a link to their order page; the order page is member-only, so
  # custom-address admin orders without a member link to the shop instead.
  defp order_url(%Order{user_id: nil}), do: absolute_url("/shop")
  defp order_url(%Order{id: id}), do: absolute_url("/shop/orders/#{id}")
end
