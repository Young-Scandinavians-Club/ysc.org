defmodule YscWeb.Emails.MerchItems do
  @moduledoc """
  The items of a merch order, for emails: name, variant, quantity, prices and a
  thumbnail, plus the table rows that show them. Every merch email uses this,
  so an order's items look the same wherever they appear.

  An order needs `items: [variant: [:image, product: :image]]` loaded (as
  `Ysc.Merch.Orders.get_order_for_email/1` and fat `get_order/1` do). Anything
  not loaded just means no thumbnail.
  """
  alias Ysc.Media.Image
  alias Ysc.Merch.{Order, OrderItem, Shipment}
  alias YscWeb.Emails.Helpers

  @doc "Template data for each item of `order`."
  def for_order(%Order{items: items}) when is_list(items),
    do: Enum.map(items, &item/1)

  def for_order(_), do: []

  @doc """
  Template data for what is in one parcel of `order`, and whether the order
  has more in it than this parcel.

  A shipment that records its items shows just those, at the quantity in the
  parcel. One that does not (an older shipment, or Printful gave no detail)
  shows the whole order, which is then not "part" of anything.
  """
  @spec for_shipment(Order.t(), Shipment.t()) :: {[map()], boolean()}
  def for_shipment(%Order{items: order_items} = order, %Shipment{} = shipment)
      when is_list(order_items) do
    case Shipment.contents(shipment, order_items) do
      [] ->
        {for_order(order), false}

      lines ->
        in_parcel = lines |> Enum.map(&elem(&1, 0)) |> Enum.sum()
        in_order = order_items |> Enum.map(& &1.quantity) |> Enum.sum()

        {Enum.map(lines, fn {quantity, line} ->
           item(%{line | quantity: quantity})
         end), in_parcel < in_order}
    end
  end

  def for_shipment(order, _shipment), do: {for_order(order), false}

  defp item(%OrderItem{} = item) do
    %{
      name: OrderItem.title(item),
      variant: OrderItem.variant_label(item),
      quantity: item.quantity,
      unit_price: Helpers.format_money(item.unit_price),
      line_total:
        Helpers.format_money(Money.mult!(item.unit_price, item.quantity)),
      thumbnail: thumbnail(item)
    }
  end

  # The variant's own photo (its color), else the product's.
  defp thumbnail(%OrderItem{variant: %{image: %Image{} = image}}),
    do: image_url(image)

  defp thumbnail(%OrderItem{variant: %{product: %{image: %Image{} = image}}}),
    do: image_url(image)

  defp thumbnail(_), do: nil

  defp image_url(image) do
    case Image.thumbnail_path_with_fallback(image, nil) do
      "/" <> _ = path -> Helpers.absolute_url(path)
      url -> url
    end
  end

  @doc """
  Table rows (item with thumbnail, quantity) for use inside an `<mj-table>`.
  """
  def rows(items) do
    items
    |> Enum.map(fn item ->
      """
      <tr style="border-bottom:1px solid #f0f0f0;">
        <td style="padding: 12px 0;">#{item_cell(item)}</td>
        <td style="padding: 12px 0 12px 16px; font-size:16px; text-align:right; vertical-align:middle; white-space:nowrap;">&times; #{esc(item.quantity)}</td>
      </tr>
      """
    end)
    |> raw()
  end

  @doc """
  Table rows with the line total, for the order confirmation. Two columns,
  item and total: the quantity and unit price sit under the name. Separate
  quantity and price columns got a few characters wide on a phone.
  """
  def priced_rows(items) do
    items
    |> Enum.map(fn item ->
      """
      <tr style="border-bottom:1px solid #f0f0f0;">
        <td style="padding: 12px 8px 12px 0; width:100%;">#{item_cell(item, price_line(item))}</td>
        <td style="padding: 12px 0 12px 8px; font-size:16px; text-align:right; vertical-align:middle; white-space:nowrap;">#{esc(item.line_total)}</td>
      </tr>
      """
    end)
    |> raw()
  end

  defp price_line(%{quantity: 1, unit_price: _}), do: nil

  defp price_line(item),
    do: "#{esc(item.quantity)} &times; #{esc(item.unit_price)}"

  # A thumbnail beside the name and variant. Nested table: the only layout
  # every email client agrees on. `extra` is a further muted line under them.
  defp item_cell(item, extra \\ nil) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>#{thumbnail_cell(item)}<td style="font-size:16px; line-height:1.4; vertical-align:middle;"><strong>#{esc(item.name)}</strong>#{variant_line(item)}#{extra_line(extra)}</td></tr></table>
    """
  end

  defp extra_line(nil), do: ""

  defp extra_line(text),
    do: ~s(<br /><span style="color:#71717a;">#{text}</span>)

  # No photo: an empty box the same size, so every row lines up.
  defp thumbnail_cell(%{thumbnail: nil}),
    do:
      ~s(<td style="padding-right:16px; vertical-align:middle;"><div style="width:64px; height:64px; border-radius:8px; background-color:#f4f4f5;"></div></td>)

  defp thumbnail_cell(%{thumbnail: url}) do
    ~s(<td style="padding-right:16px; vertical-align:middle;"><img src="#{esc(url)}" alt="" width="64" height="64" style="display:block; width:64px; height:64px; border-radius:8px; object-fit:cover; background-color:#f4f4f5;" /></td>)
  end

  defp variant_line(%{variant: nil}), do: ""

  defp variant_line(%{variant: variant}),
    do: ~s(<br /><span style="color:#71717a;">#{esc(variant)}</span>)

  defp esc(value),
    do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp raw(parts), do: parts |> Enum.join() |> Phoenix.HTML.raw()
end
