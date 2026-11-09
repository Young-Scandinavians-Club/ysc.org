defmodule YscWeb.ShopLiveHelpers do
  @moduledoc """
  Waits for shop pages that load catalog, cart, checkout, or order data after
  the WebSocket connects.
  """

  @endpoint YscWeb.Endpoint

  # `start_async` work can take well over LiveViewTest's 100ms default when CI
  # is busy. Main failed on seed 165008: ShopBrowseTest "unknown and hidden
  # products go back to the shop" (`assert_redirect` after `live/2` for
  # `/shop/products/not-an-id` while the product query was still in flight).
  @async_timeout 5_000

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  def live_shop_page(conn, path) do
    {:ok, view, _html} = live(conn, path)
    html = render_async(view, @async_timeout)
    {:ok, view, html}
  end

  def render_shop_async(view), do: render_async(view, @async_timeout)

  @doc """
  Wait for a `push_navigate` that fires from `handle_async` after the skeleton
  paints.

  Do not use `live_shop_page/2` here: `render_async/2` tries to render after
  the redirect and fails. Do not use bare `assert_redirect/2`: its 100ms
  default is what flakes on main.
  """
  def assert_shop_async_redirect(view, to) do
    assert_redirect(view, to, @async_timeout)
  end
end
