defmodule YscWeb.ShopOrdersLive do
  @moduledoc """
  A member's merch order history. Not gated on active membership: a lapsed
  member can still find their receipts.

  The first HTML is a skeleton. Order-history and cart-count queries run after
  the WebSocket connects so the HTTP response is never blocked on those loads,
  and they run once instead of on both the disconnected and connected mounts.
  """
  use YscWeb, :live_view

  require Ysc.Logging

  import Ysc.MoneyHelper, only: [format_price: 1]
  import YscWeb.Live.AsyncHelpers
  import YscWeb.ShopComponents

  alias Ysc.Merch.{Cart, Orders}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Your orders")
      |> assign(:async_data_loaded, false)
      |> assign(:orders, [])
      |> assign(:cart_count, 0)

    {:ok, maybe_load_orders(socket)}
  end

  defp maybe_load_orders(socket) do
    if connected?(socket) do
      user = socket.assigns.current_user

      start_async(socket, :load_orders, fn ->
        allow_sandbox_access()

        %{orders: Orders.list_user_orders(user), cart_count: Cart.count(user)}
      end)
    else
      socket
    end
  end

  @impl true
  def handle_async(
        :load_orders,
        {:ok, %{orders: orders, cart_count: cart_count}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:async_data_loaded, true)
     |> assign(:orders, orders)
     |> assign(:cart_count, cart_count)}
  end

  def handle_async(:load_orders, {:exit, reason}, socket) do
    Ysc.Logging.error("ShopOrdersLive: failed to load orders", error: reason)

    {:noreply, assign(socket, :async_data_loaded, true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shop_frame
      id="shop-orders-page"
      title="Your Orders"
      active={:orders}
      cart_count={@cart_count}
    >
      <.shop_page_loading :if={!@async_data_loaded} id="shop-orders-loading" />

      <div
        :if={@async_data_loaded && @orders == []}
        id="orders-empty"
        class="rounded-3xl bg-zinc-50 px-6 py-24 text-center"
      >
        <.icon name="hero-shopping-bag" class="mx-auto mb-6 size-12 text-zinc-400" />
        <h2 class="type-title text-2xl text-zinc-900">No orders yet</h2>
        <p class="mt-3 text-lg text-zinc-600">
          When you buy something from the shop, it will show up here.
        </p>
        <.button
          id="orders-browse"
          navigate={~p"/shop"}
          class="mt-8 motion-safe:active:scale-[0.98]"
        >Browse the shop</.button>
      </div>

      <ul
        :if={@async_data_loaded && @orders != []}
        id="orders-list"
        class="-mx-4 space-y-2"
      >
        <li :for={order <- @orders} id={"order-#{order.id}"}>
          <.link
            navigate={~p"/shop/orders/#{order.id}"}
            class="flex items-center gap-3 rounded-2xl p-4 transition hover:bg-zinc-50 motion-safe:active:scale-[0.99] sm:gap-5"
          >
            <div class="flex shrink-0 -space-x-3 sm:-space-x-4">
              <.shop_thumb
                :for={item <- Enum.take(order.items, 3)}
                image={item.variant && item.variant.image}
                class="size-10 ring-2 ring-white sm:size-14 sm:ring-4"
              />
            </div>
            <div class="min-w-0 flex-1">
              <p class="break-words text-base text-zinc-900 sm:text-lg">
                {order.reference_id}
              </p>
              <p class="text-sm text-zinc-500 sm:text-base">
                <span class="whitespace-nowrap">
                  {Calendar.strftime(order.inserted_at, "%B %-d, %Y")}
                </span>
                <span class="whitespace-nowrap">
                  · {Enum.sum(Enum.map(order.items, & &1.quantity))} items
                </span>
              </p>
            </div>
            <div class="flex shrink-0 flex-col-reverse items-end gap-1.5 sm:flex-row sm:items-center sm:gap-5">
              <.order_status_badge order={order} />
              <p class="text-right text-base text-zinc-900 sm:w-24 sm:text-lg">
                {format_price(order.total_amount)}
              </p>
            </div>
          </.link>
        </li>
      </ul>
    </.shop_frame>
    """
  end
end
