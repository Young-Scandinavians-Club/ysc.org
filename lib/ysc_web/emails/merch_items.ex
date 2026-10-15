defmodule YscWeb.Emails.MerchItems do
  @moduledoc """
  The items of a merch order, for emails: name, variant, quantity, prices and a
  thumbnail, plus the table rows that show them. Every merch email uses this,
  so an order's items look the same wherever they appear.

  An order needs `items: [variant: [:image, product: :image]]` loaded (as
  `Ysc.Merch.Orders` does). Anything not loaded just means no thumbnail.
  """
  alias Ysc.Media.Image
  alias Ysc.Merch.{Order, OrderItem}
  alias YscWeb.Emails.Helpers

  @doc "Template data for each item of `order`."
  def for_order(%Order{items: items}) when is_list(items),
    do: Enum.map(items, &item/1)

  def for_order(_), do: []

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
  Table rows with quantity, unit price and line total, for the order
  confirmation. Four columns: item, quantity, price, total.
  """
  def priced_rows(items) do
    items
    |> Enum.map(fn item ->
      """
      <tr style="border-bottom:1px solid #f0f0f0;">
        <td style="padding: 12px 16px;">#{item_cell(item)}</td>
        <td style="padding: 12px 16px; font-size:16px; text-align:center; vertical-align:middle;">#{esc(item.quantity)}</td>
        <td style="padding: 12px 16px; font-size:16px; text-align:right; vertical-align:middle;">#{esc(item.unit_price)}</td>
        <td style="padding: 12px 16px; font-size:16px; text-align:right; vertical-align:middle;">#{esc(item.line_total)}</td>
      </tr>
      """
    end)
    |> raw()
  end

  # A thumbnail beside the name and variant. Nested table: the only layout
  # every email client agrees on.
  defp item_cell(item) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>#{thumbnail_cell(item)}<td style="font-size:16px; line-height:1.4; vertical-align:middle;"><strong>#{esc(item.name)}</strong>#{variant_line(item)}</td></tr></table>
    """
  end

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
