defmodule YscWeb.ShopOrdersLive do
  @moduledoc """
  A member's merch order history. Not gated on active membership: a lapsed
  member can still find their receipts.
  """
  use YscWeb, :live_view

  import Ysc.MoneyHelper, only: [format_price: 1]
  import YscWeb.ShopComponents

  alias Ysc.Merch.{Cart, Orders}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Your orders")
     |> assign(:orders, Orders.list_user_orders(user))
     |> assign(:cart_count, Cart.count(user))}
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
      <div
        :if={@orders == []}
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

      <ul :if={@orders != []} id="orders-list" class="-mx-4 space-y-2">
        <li :for={order <- @orders} id={"order-#{order.id}"}>
          <.link
            navigate={~p"/shop/orders/#{order.id}"}
            class="flex items-center gap-5 rounded-2xl p-4 transition hover:bg-zinc-50 motion-safe:active:scale-[0.99]"
          >
            <div class="flex -space-x-4">
              <.shop_thumb
                :for={item <- Enum.take(order.items, 3)}
                image={item.variant && item.variant.image}
                class="size-14 ring-4 ring-white"
              />
            </div>
            <div class="min-w-0 flex-1">
              <p class="text-lg text-zinc-900">{order.reference_id}</p>
              <p class="text-zinc-500">
                {Calendar.strftime(order.inserted_at, "%B %-d, %Y")} · {Enum.sum(
                  Enum.map(order.items, & &1.quantity)
                )} items
              </p>
            </div>
            <.order_status_badge order={order} />
            <p class="w-24 text-right text-lg text-zinc-900">
              {format_price(order.total_amount)}
            </p>
          </.link>
        </li>
      </ul>
    </.shop_frame>
    """
  end
end
