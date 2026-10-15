defmodule YscWeb.Emails.MerchOrderUpdate do
  @moduledoc """
  A status update on a merch order other than "shipped": delivered, returned,
  failed or canceled. Wording lives in `Ysc.Merch.UpdateCopy`.
  """
  use MjmlEEx,
    mjml_template: "templates/merch_order_update.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [absolute_url: 1, member_greeting_name: 1]

  alias Ysc.Merch.{Order, UpdateCopy}

  def get_template_name, do: "merch_order_update"

  def get_subject(kind, %Order{reference_id: reference_id}) do
    {headline, _} = UpdateCopy.email(kind, false)
    "#{headline} (#{reference_id})"
  end

  def prepare_email_data(kind, %Order{} = order)
      when kind in [:delivered, :returned, :failed, :canceled] do
    {headline, paragraphs} = UpdateCopy.email(kind, order.kind == :admin_comp)

    %{
      first_name: greeting_name(order),
      headline: headline,
      paragraphs: paragraphs,
      order: %{reference_id: order.reference_id},
      items: YscWeb.Emails.MerchItems.for_order(order),
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

  defp order_url(%Order{user_id: nil}), do: absolute_url("/shop")
  defp order_url(%Order{id: id}), do: absolute_url("/shop/orders/#{id}")
end
