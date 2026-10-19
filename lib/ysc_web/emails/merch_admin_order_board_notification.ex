defmodule YscWeb.Emails.MerchAdminOrderBoardNotification do
  @moduledoc """
  Tells the board that an admin placed a club-paid merch order: who placed it,
  who it is for, what it is, what Printful expects to charge the club, and why.

  Sent for every club-paid order, in the same transaction that creates it.
  """
  use MjmlEEx,
    mjml_template: "templates/merch_admin_order_board_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [absolute_url: 1, format_money: 1]
  import YscWeb.Emails.MerchHelpers, only: [address_lines: 1]

  alias Ysc.Accounts.UserDisplay
  alias Ysc.Merch.Order

  def get_template_name, do: "merch_admin_order_board_notification"

  def get_subject(%Order{granted_by: %{} = admin, reference_id: reference_id}),
    do:
      "#{UserDisplay.full_name(admin)} placed a club-paid merch order (#{reference_id})"

  def get_subject(%Order{reference_id: reference_id}),
    do: "A club-paid merch order was placed (#{reference_id})"

  @doc """
  Template data for an order with `granted_by`, `items`, `event` and `user`
  loaded.
  """
  def prepare_email_data(%Order{} = order) do
    %{
      order: %{reference_id: order.reference_id},
      placed_by: placed_by(order),
      recipient: recipient(order),
      address_lines: address_lines(order),
      items: YscWeb.Emails.MerchItems.for_order(order),
      estimated_cost: estimated_cost(order),
      purpose: order.purpose,
      event: event(order),
      order_url: absolute_url("/admin/merch/orders/#{order.id}")
    }
  end

  defp placed_by(%Order{granted_by: %{} = admin}) do
    %{
      name: UserDisplay.full_name(admin),
      email: admin.email,
      url: absolute_url("/admin/users/#{admin.id}/details")
    }
  end

  defp placed_by(_), do: %{name: "An admin", email: nil, url: nil}

  defp recipient(%Order{user: %{} = user} = order) do
    %{
      name: UserDisplay.full_name(user),
      detail:
        if(order.granted_by_id == user.id,
          do: "the admin who placed the order",
          else: "a member (#{user.email})"
        )
    }
  end

  defp recipient(%Order{recipient_name: name}),
    do: %{name: name, detail: "custom address, not a member"}

  # Until Printful reports the real charge this is the quote from placement.
  defp estimated_cost(%Order{estimated_cost: %Money{} = cost}),
    do: format_money(cost)

  defp estimated_cost(_),
    do: "Not available yet. Printful will report it once the order is accepted."

  defp event(%Order{event: %{id: id, title: title}}),
    do: %{title: title, url: absolute_url("/admin/events/#{id}/statistics")}

  defp event(_), do: nil
end
