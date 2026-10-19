defmodule YscWeb.ShopLiveHelpers do
  @moduledoc """
  Waits for shop pages that load catalog, cart, checkout, or order data after
  the WebSocket connects.
  """

  @endpoint YscWeb.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  def live_shop_page(conn, path) do
    {:ok, view, _html} = live(conn, path)
    html = render_async(view)
    {:ok, view, html}
  end
end
