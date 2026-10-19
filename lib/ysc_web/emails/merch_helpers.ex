defmodule YscWeb.Emails.MerchHelpers do
  @moduledoc """
  Shared merch-order fields for member and board emails.

  Confirmation, shipped, and update emails greet the recipient the same way
  and link members to their order (strangers to the shop). Confirmation,
  shipped, and club-paid board emails also share the street-line list.

  ## Examples

      greeting_name(order)
      member_order_url(order)
      address_lines(order)
  """

  import YscWeb.Emails.Helpers, only: [absolute_url: 1, member_greeting_name: 1]

  alias Ysc.Merch.{Order, ShippingAddress}

  @doc """
  First name for member-facing merch greetings.

  Uses the linked member when the order has one; otherwise the first word of
  `recipient_name`.
  """
  def greeting_name(%Order{user: %{} = user}), do: member_greeting_name(user)

  def greeting_name(%Order{recipient_name: name}) do
    name
    |> to_string()
    |> String.split(" ", trim: true)
    |> List.first()
    |> member_greeting_name()
  end

  @doc """
  Absolute URL for the member order page, or the shop when the order is not
  linked to a member (custom-address club-paid orders).
  """
  def member_order_url(%Order{user_id: nil}), do: absolute_url("/shop")
  def member_order_url(%Order{id: id}), do: absolute_url("/shop/orders/#{id}")

  @doc """
  Street lines of the delivery address, omitting blanks.

  Delegates to `Ysc.Merch.ShippingAddress.display_lines/1`.
  """
  def address_lines(%{} = addr), do: ShippingAddress.display_lines(addr)
end
