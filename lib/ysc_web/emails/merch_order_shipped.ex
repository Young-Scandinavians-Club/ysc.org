defmodule YscWeb.Emails.MerchOrderShipped do
  @moduledoc """
  Tells a member their merch order has shipped, with the tracking link.
  """
  use MjmlEEx,
    mjml_template: "templates/merch_order_shipped.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [absolute_url: 1, member_greeting_name: 1]

  alias Ysc.Merch.{Order, Shipment}

  def get_template_name, do: "merch_order_shipped"

  def get_subject(%Order{reference_id: reference_id}),
    do: "Your merch is on its way (#{reference_id})"

  @doc """
  Template data for an order (with `user` loaded when it has one) and the
  shipment being announced.
  """
  def prepare_email_data(%Order{} = order, %Shipment{} = shipment) do
    %{
      first_name: greeting_name(order),
      order: %{reference_id: order.reference_id},
      shipment: %{
        carrier: shipment.carrier,
        service: shipment.service,
        tracking_number: shipment.tracking_number,
        tracking_url: Shipment.safe_tracking_url(shipment.tracking_url),
        reshipment: shipment.reshipment
      },
      items: YscWeb.Emails.MerchItems.for_order(order),
      delivery_estimate: Ysc.Merch.Shipping.delivery_estimate(order),
      ship_to: %{name: order.recipient_name, lines: address_lines(order)},
      order_url: order_url(order)
    }
  end

  defp greeting_name(%Order{user: %{} = user}), do: member_greeting_name(user)

  defp greeting_name(%Order{recipient_name: name}),
    do:
      name
      |> to_string()
      |> String.split(" ", trim: true)
      |> List.first()
      |> member_greeting_name()

  defp address_lines(order) do
    [
      order.address1,
      order.address2,
      "#{order.city}, #{order.state_code} #{order.zip}"
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp order_url(%Order{user_id: nil}), do: absolute_url("/shop")
  defp order_url(%Order{id: id}), do: absolute_url("/shop/orders/#{id}")
end
