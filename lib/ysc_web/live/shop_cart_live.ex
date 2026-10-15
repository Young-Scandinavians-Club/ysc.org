defmodule YscWeb.ShopCartLive do
  @moduledoc """
  The member's merch cart.
  """
  use YscWeb, :live_view

  on_mount {YscWeb.ShopAccess, :ensure_member}

  import Ysc.MoneyHelper, only: [format_price: 1]
  import YscWeb.ShopComponents

  alias Ysc.Merch.{Cart, CartItem}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Your cart")
     |> load_cart()}
  end

  defp load_cart(socket) do
    lines = Cart.list(socket.assigns.current_user)

    socket
    |> assign(:lines, lines)
    |> assign(:subtotal, Cart.subtotal(lines))
    |> assign(:cart_count, Cart.item_count(lines))
    |> assign(:can_checkout?, Cart.available_lines(lines) != [])
  end

  @impl true
  def handle_event(
        "set_quantity",
        %{"variant_id" => variant_id, "quantity" => quantity},
        socket
      ) do
    case Integer.parse(to_string(quantity)) do
      {n, _} ->
        {:ok, _} = Cart.set_quantity(socket.assigns.current_user, variant_id, n)
        {:noreply, load_cart(socket)}

      :error ->
        {:noreply, load_cart(socket)}
    end
  end

  def handle_event("remove", %{"variant_id" => variant_id}, socket) do
    :ok = Cart.remove(socket.assigns.current_user, variant_id)
    {:noreply, load_cart(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shop_frame
      id="shop-cart-page"
      title="Your Cart"
      active={:cart}
      cart_count={@cart_count}
    >
      <div
        :if={@lines == []}
        id="cart-empty"
        class="rounded-3xl bg-zinc-50 px-6 py-24 text-center"
      >
        <.icon name="hero-shopping-bag" class="mx-auto mb-6 size-12 text-zinc-400" />
        <h2 class="type-title text-2xl text-zinc-900">Your cart is empty</h2>
        <p class="mt-3 text-lg text-zinc-600">
          Find something you like in the shop.
        </p>
        <.button
          id="cart-browse"
          navigate={~p"/shop"}
          class="mt-8 motion-safe:active:scale-[0.98]"
        >Browse the shop</.button>
      </div>

      <div
        :if={@lines != []}
        class="grid grid-cols-1 gap-12 lg:grid-cols-3 lg:gap-16"
      >
        <ul id="cart-lines" class="space-y-10 lg:col-span-2">
          <li
            :for={line <- @lines}
            id={"cart-line-#{line.variant.id}"}
            class="flex flex-wrap items-center gap-x-6 gap-y-4"
          >
            <.shop_thumb
              image={line.variant.image}
              fallback_image={line.product.image}
              class={["size-24", !line.available? && "opacity-50"]}
            />

            <div class="min-w-0 flex-1 basis-48">
              <.link
                navigate={~p"/shop/products/#{line.product.id}"}
                class="type-subhead block truncate text-lg text-zinc-900 transition-colors hover:text-blue-700"
              >
                {line.product.name}
              </.link>
              <p class="truncate text-zinc-500">{variant_label(line.variant)}</p>
              <p
                :if={line.available? and line.quantity > 1}
                id={"cart-unit-price-#{line.variant.id}"}
                class="text-sm tabular-nums text-zinc-500"
              >
                {format_price(line.variant.retail_price)} each
              </p>
              <p
                :if={!line.available?}
                id={"cart-unavailable-#{line.variant.id}"}
                class="mt-1 text-sm text-red-600"
              >
                No longer available. Remove it to continue.
              </p>
            </div>

            <form
              :if={line.available?}
              id={"cart-qty-form-#{line.variant.id}"}
              phx-change="set_quantity"
            >
              <input type="hidden" name="variant_id" value={line.variant.id} />
              <label for={"cart-qty-#{line.variant.id}"} class="sr-only">Quantity</label>
              <div
                class="inline-flex h-12 items-center rounded-sm bg-zinc-100"
                role="group"
                aria-label={"Quantity of #{line.product.name}"}
              >
                <button
                  type="button"
                  id={"cart-qty-decrement-#{line.variant.id}"}
                  phx-click="set_quantity"
                  phx-value-variant_id={line.variant.id}
                  phx-value-quantity={line.quantity - 1}
                  disabled={line.quantity <= 1}
                  aria-label="Decrease quantity"
                  class="inline-flex size-12 items-center justify-center rounded-sm text-zinc-900 transition hover:bg-zinc-200 disabled:cursor-not-allowed disabled:opacity-30 disabled:hover:bg-transparent motion-safe:active:scale-95"
                >
                  <.icon name="hero-minus" class="size-4" />
                </button>
                <input
                  type="number"
                  id={"cart-qty-#{line.variant.id}"}
                  name="quantity"
                  inputmode="numeric"
                  value={line.quantity}
                  min="1"
                  max={CartItem.max_quantity()}
                  class="h-12 w-10 border-0 bg-transparent p-0 text-center text-base font-medium tabular-nums text-zinc-900 [appearance:textfield] focus:ring-0 [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
                />
                <button
                  type="button"
                  id={"cart-qty-increment-#{line.variant.id}"}
                  phx-click="set_quantity"
                  phx-value-variant_id={line.variant.id}
                  phx-value-quantity={line.quantity + 1}
                  disabled={line.quantity >= CartItem.max_quantity()}
                  aria-label="Increase quantity"
                  class="inline-flex size-12 items-center justify-center rounded-sm text-zinc-900 transition hover:bg-zinc-200 disabled:cursor-not-allowed disabled:opacity-30 disabled:hover:bg-transparent motion-safe:active:scale-95"
                >
                  <.icon name="hero-plus" class="size-4" />
                </button>
              </div>
            </form>

            <p
              :if={line.available?}
              class="w-24 text-right text-lg tabular-nums text-zinc-900"
            >
              {format_price(line.line_total)}
            </p>

            <button
              type="button"
              id={"cart-remove-#{line.variant.id}"}
              phx-click="remove"
              phx-value-variant_id={line.variant.id}
              aria-label={"Remove #{line.product.name}"}
              class="inline-flex size-11 items-center justify-center rounded-full text-zinc-400 transition hover:bg-zinc-100 hover:text-red-600 motion-safe:active:scale-90"
            >
              <.icon name="hero-trash" class="size-5" />
            </button>
          </li>
        </ul>

        <aside class="lg:sticky lg:top-28 lg:self-start">
          <div class="rounded-3xl bg-zinc-50 p-8">
            <p class="type-eyebrow text-sm text-zinc-500">Subtotal</p>
            <p
              id="cart-subtotal"
              class="type-title mt-2 text-4xl tabular-nums text-zinc-900"
            >
              {format_price(@subtotal)}
            </p>
            <p class="mt-3 text-zinc-500">Shipping is calculated at checkout.</p>

            <div class="mt-8 flex flex-col gap-3">
              <.button
                id="cart-checkout"
                navigate={~p"/shop/checkout"}
                disabled={!@can_checkout?}
                class="h-12 w-full motion-safe:active:scale-[0.98]"
              >
                Checkout <.icon name="hero-arrow-right" class="size-5" />
              </.button>
              <.shop_secondary_link
                id="cart-continue"
                navigate={~p"/shop"}
                class="w-full"
              >
                Keep shopping
              </.shop_secondary_link>
            </div>
          </div>
        </aside>
      </div>
    </.shop_frame>
    """
  end

  defp variant_label(variant) do
    [variant.color, variant.size]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> variant.name
      parts -> Enum.join(parts, " / ")
    end
  end
end
