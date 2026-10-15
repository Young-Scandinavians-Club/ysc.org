defmodule YscWeb.ShopLive do
  @moduledoc """
  The merch shop: every product members can buy.
  """
  use YscWeb, :live_view

  on_mount {YscWeb.ShopAccess, :ensure_member}

  import Ysc.MoneyHelper, only: [format_price: 1]
  import YscWeb.ShopComponents

  alias Ysc.Merch
  alias YscWeb.ShopCartPeek

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Shop")
     |> assign(:products, Merch.list_shop_products())
     |> ShopCartPeek.init(user)}
  end

  defp price_label(product) do
    prices = Enum.map(product.variants, & &1.retail_price)
    lowest = Merch.starting_price(product)

    if Enum.all?(prices, &Money.equal?(&1, lowest)),
      do: format_price(lowest),
      else: "From #{format_price(lowest)}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shop_frame
      id="shop-page"
      title="Club Gear"
      active={:shop}
      cart_count={@cart_summary.count}
    >
      <div
        :if={@products == []}
        id="shop-empty"
        class="rounded-3xl bg-zinc-50 px-6 py-24 text-center"
      >
        <.icon name="hero-shopping-bag" class="mx-auto mb-6 size-12 text-zinc-400" />
        <h2 class="type-title text-2xl text-zinc-900">The shop is stocking up</h2>
        <p class="mt-3 text-lg text-zinc-600">
          New club gear is on the way. Check back soon.
        </p>
      </div>

      <ul
        :if={@products != []}
        id="shop-products"
        class="grid grid-cols-1 gap-x-10 gap-y-16 sm:grid-cols-2 lg:grid-cols-3"
      >
        <li :for={product <- @products} id={"shop-product-#{product.id}"}>
          <.link
            navigate={~p"/shop/products/#{product.id}"}
            class="group block transition-transform motion-safe:active:scale-[0.98]"
          >
            <.shop_image
              id={"shop-product-image-#{product.id}"}
              image={product.image}
            />
            <h2 class="type-subhead mt-5 text-xl text-zinc-900 transition-colors group-hover:text-blue-700">
              {product.name}
            </h2>
            <p class="mt-1 text-lg text-zinc-600">{price_label(product)}</p>
          </.link>
        </li>
      </ul>

      <.cart_dock summary={@cart_summary} />
    </.shop_frame>
    """
  end
end
