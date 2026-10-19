defmodule YscWeb.ShopProductLive do
  @moduledoc """
  A single merch product: pick a color and size, then add it to the cart.

  The first HTML is a skeleton. Product and cart-summary queries run after the
  WebSocket connects so the HTTP response is never blocked on those loads, and
  they run once instead of on both the disconnected and connected mounts.
  """
  use YscWeb, :live_view

  on_mount {YscWeb.ShopAccess, :ensure_member}

  require Ysc.Logging

  import Ysc.MoneyHelper, only: [format_price: 1]
  import YscWeb.Live.AsyncHelpers
  import YscWeb.ShopComponents

  alias Ysc.Media.Image
  alias Ysc.Merch
  alias Ysc.Merch.{Cart, CartItem, VariantSelection}
  alias YscWeb.ShopCartPeek

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Shop")
      |> assign(:product_id, id)
      |> assign(:requested_color, params["color"])
      |> assign(:async_data_loaded, false)
      |> assign(:product, nil)
      |> assign(:selection, nil)
      |> assign(:quantity, 1)
      |> assign(:photo_index, 0)
      |> assign(:variant, nil)
      |> assign(:gallery, [])
      |> ShopCartPeek.init_placeholder()

    {:ok, maybe_load_product(socket)}
  end

  defp maybe_load_product(socket) do
    if connected?(socket) do
      user = socket.assigns.current_user
      id = socket.assigns.product_id

      start_async(socket, :load_product, fn ->
        allow_sandbox_access()

        %{product: fetch_product(id), cart_summary: Cart.summary(user)}
      end)
    else
      socket
    end
  end

  @impl true
  def handle_async(
        :load_product,
        {:ok, %{product: nil}},
        socket
      ) do
    {:noreply, redirect_unavailable(socket)}
  end

  def handle_async(
        :load_product,
        {:ok, %{product: product, cart_summary: cart_summary}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:async_data_loaded, true)
     |> assign(:page_title, product.name)
     |> assign(:product, product)
     |> assign(
       :selection,
       initial_selection(product, socket.assigns.requested_color)
     )
     |> assign(:cart_summary, cart_summary)
     |> assign_selected_variant()
     |> assign_gallery()}
  end

  def handle_async(:load_product, {:exit, reason}, socket) do
    Ysc.Logging.error("ShopProductLive: failed to load product", error: reason)

    {:noreply, redirect_unavailable(socket)}
  end

  defp redirect_unavailable(socket) do
    socket
    |> YscWeb.Flash.put_toast(
      :error,
      "That product isn't available any more.",
      title: "Shop"
    )
    |> push_navigate(to: ~p"/shop")
  end

  # The listing links here with the color the shopper was looking at.
  defp initial_selection(product, color) do
    default = default_selection(product)

    if is_binary(color),
      do: VariantSelection.select_color(product.variants, default, color),
      else: default
  end

  # Opens on the color whose photo is first, so "Make first" in the admin sets
  # the default color as well as the first photo.
  defp default_selection(product) do
    default = VariantSelection.default(product.variants)

    case Merch.colors(product) do
      [first | _] ->
        VariantSelection.select_color(product.variants, default, first)

      [] ->
        default
    end
  end

  defp fetch_product(id) do
    Merch.get_shop_product(id)
  rescue
    Ecto.Query.CastError -> nil
  end

  # The photos follow the color; picking a new color starts from its first one.
  defp assign_gallery(socket) do
    %{product: product, selection: selection} = socket.assigns
    assign(socket, :gallery, Merch.gallery(product, selection.color))
  end

  defp assign_selected_variant(socket) do
    %{product: product, selection: selection} = socket.assigns
    assign(socket, :variant, VariantSelection.find(product.variants, selection))
  end

  @impl true
  def handle_event(
        _event,
        _params,
        %{assigns: %{async_data_loaded: false}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event("select_color", %{"color" => color}, socket) do
    selection =
      VariantSelection.select_color(
        socket.assigns.product.variants,
        socket.assigns.selection,
        color
      )

    {:noreply,
     socket
     |> assign(:selection, selection)
     |> assign(:photo_index, 0)
     |> assign_selected_variant()
     |> assign_gallery()}
  end

  def handle_event("select_size", %{"size" => size}, socket) do
    selection =
      VariantSelection.select_size(
        socket.assigns.product.variants,
        socket.assigns.selection,
        size
      )

    {:noreply,
     socket |> assign(:selection, selection) |> assign_selected_variant()}
  end

  def handle_event("select_photo", %{"index" => index}, socket) do
    {:noreply,
     assign(socket, :photo_index, clamp_index(index, socket.assigns.gallery))}
  end

  def handle_event("prev_photo", _params, socket) do
    count = length(socket.assigns.gallery)
    {:noreply, update(socket, :photo_index, &step_index(&1, -1, count))}
  end

  def handle_event("next_photo", _params, socket) do
    count = length(socket.assigns.gallery)
    {:noreply, update(socket, :photo_index, &step_index(&1, 1, count))}
  end

  def handle_event("set_quantity", %{"quantity" => quantity}, socket) do
    {:noreply, assign(socket, :quantity, parse_quantity(quantity))}
  end

  def handle_event("increment", _params, socket) do
    {:noreply, update(socket, :quantity, &min(&1 + 1, CartItem.max_quantity()))}
  end

  def handle_event("decrement", _params, socket) do
    {:noreply, update(socket, :quantity, &max(&1 - 1, 1))}
  end

  def handle_event("add_to_cart", _params, %{assigns: %{variant: nil}} = socket) do
    {:noreply,
     YscWeb.Flash.put_toast(socket, :error, "Choose your options first.",
       title: "Shop"
     )}
  end

  def handle_event("add_to_cart", _params, socket) do
    %{current_user: user, variant: variant, quantity: quantity} = socket.assigns

    case Cart.add(user, variant.id, quantity) do
      {:ok, _item} ->
        {:noreply,
         ShopCartPeek.show(
           socket,
           user,
           peek_item(socket.assigns, variant, quantity)
         )}

      {:error, :unavailable} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, "Sorry, that option just sold out.",
           title: "Shop"
         )
         |> push_navigate(to: ~p"/shop")}

      {:error, _changeset} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "We couldn't add that to your cart. Please try again.",
           title: "Shop"
         )}
    end
  end

  def handle_event("dismiss_cart_peek", _params, socket),
    do: {:noreply, ShopCartPeek.dismiss(socket)}

  def handle_event("pause_cart_peek", _params, socket),
    do: {:noreply, ShopCartPeek.pause(socket)}

  def handle_event("resume_cart_peek", _params, socket),
    do: {:noreply, ShopCartPeek.resume(socket)}

  @impl true
  def handle_info({:hide_cart_peek, token}, socket),
    do: {:noreply, ShopCartPeek.hide_if_current(socket, token)}

  defp peek_item(%{product: product}, variant, quantity) do
    %{
      name: product.name,
      detail:
        [variant.color, variant.size]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" / "),
      image: variant.image || product.image,
      quantity: quantity
    }
  end

  defp parse_quantity(value) do
    case Integer.parse(to_string(value)) do
      {n, _} -> n |> max(1) |> min(CartItem.max_quantity())
      :error -> 1
    end
  end

  defp price_for(%{variant: nil, product: product}),
    do: Merch.starting_price(product)

  defp price_for(%{variant: variant}), do: variant.retail_price

  defp price_prefix(%{variant: nil, product: product}) do
    prices = Enum.map(product.variants, & &1.retail_price)
    lowest = Merch.starting_price(product)
    if Enum.all?(prices, &Money.equal?(&1, lowest)), do: "", else: "From "
  end

  defp price_prefix(_), do: ""

  defp clamp_index(index, gallery) do
    case Integer.parse(to_string(index)) do
      {n, _} -> n |> max(0) |> min(max(length(gallery) - 1, 0))
      :error -> 0
    end
  end

  # Wraps around, so next on the last photo shows the first.
  defp step_index(_index, _delta, count) when count < 2, do: 0
  defp step_index(index, delta, count), do: Integer.mod(index + delta, count)

  # What the member still needs to choose, used on the button itself.
  defp missing_option_hint(%{
         variant: nil,
         product: product,
         selection: selection
       }) do
    variants = product.variants

    cond do
      VariantSelection.colors(variants) != [] and is_nil(selection.color) ->
        "Choose a color"

      VariantSelection.sizes(variants) != [] and is_nil(selection.size) ->
        "Choose a size"

      true ->
        "Not available"
    end
  end

  defp missing_option_hint(_), do: nil

  defp paragraphs(nil), do: []

  defp paragraphs(text) do
    text
    |> String.split(~r/\n{2,}/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # What the full-screen viewer shows, in gallery order.
  defp slides_json(gallery, product_name) do
    gallery
    |> Enum.with_index(1)
    |> Enum.map(fn {photo, index} ->
      %{
        href: Image.display_path_with_fallback(photo),
        alt: "#{product_name}, photo #{index}"
      }
    end)
    |> Jason.encode!()
  end

  defp line_total(%{variant: variant, quantity: quantity}),
    do: Money.mult!(variant.retail_price, quantity)

  @impl true
  def render(%{async_data_loaded: false} = assigns) do
    ~H"""
    <.shop_frame
      id="shop-product-page"
      title="Shop"
      active={:shop}
      section_only?={true}
      cart_count={@cart_summary.count}
    >
      <.shop_page_loading id="shop-product-loading" />
    </.shop_frame>
    """
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:colors, Merch.colors(assigns.product))
      |> assign(
        :sizes,
        VariantSelection.sizes(
          assigns.product.variants,
          assigns.selection.color
        )
      )
      |> assign(:all_sizes, VariantSelection.sizes(assigns.product.variants))
      |> assign(:current_photo, Enum.at(assigns.gallery, assigns.photo_index))
      |> assign(:photo_count, length(assigns.gallery))
      |> assign(
        :slides_json,
        slides_json(assigns.gallery, assigns.product.name)
      )

    ~H"""
    <.shop_frame
      id="shop-product-page"
      title={@product.name}
      active={:shop}
      section_only?={true}
      cart_count={@cart_summary.count}
    >
      <.link
        id="back-to-products"
        navigate={~p"/shop"}
        class="-mt-4 mb-6 inline-flex min-h-11 items-center gap-1.5 text-zinc-500 transition-colors hover:text-zinc-900"
      >
        <.icon name="hero-arrow-left" class="size-4" /> All products
      </.link>

      <div class="grid grid-cols-1 gap-10 lg:grid-cols-2 lg:gap-20">
        <div
          id="product-gallery"
          class="space-y-4"
          phx-hook="ProductLightbox"
          data-slides={@slides_json}
          data-index={@photo_index}
        >
          <div class="group relative">
            <div
              id="photo-zoom"
              role="button"
              tabindex="0"
              data-lightbox-open
              aria-label={"View #{@product.name} photos full screen"}
              class="cursor-zoom-in rounded-2xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-zinc-900"
            >
              <.shop_image
                id={"product-photo-#{(@current_photo && @current_photo.id) || "none"}"}
                image={@current_photo}
                sizes="(max-width: 1024px) 100vw, 50vw"
                loading="eager"
                fetchpriority="high"
              />
            </div>

            <span
              aria-hidden="true"
              class="pointer-events-none absolute left-3 top-3 inline-flex size-9 items-center justify-center rounded-full bg-white/80 text-zinc-900 shadow-lg backdrop-blur-xl transition lg:opacity-0 lg:group-hover:opacity-100"
            >
              <.icon name="hero-magnifying-glass-plus" class="size-5" />
            </span>

            <button
              :if={@photo_count > 1}
              type="button"
              id="photo-prev"
              phx-click="prev_photo"
              aria-label="Previous photo"
              class="absolute left-3 top-1/2 inline-flex size-11 -translate-y-1/2 items-center justify-center rounded-full bg-white/80 text-zinc-900 shadow-lg backdrop-blur-xl transition motion-safe:active:scale-95 lg:opacity-0 lg:group-focus-within:opacity-100 lg:group-hover:opacity-100"
            >
              <.icon name="hero-chevron-left" class="size-5" />
            </button>
            <button
              :if={@photo_count > 1}
              type="button"
              id="photo-next"
              phx-click="next_photo"
              aria-label="Next photo"
              class="absolute right-3 top-1/2 inline-flex size-11 -translate-y-1/2 items-center justify-center rounded-full bg-white/80 text-zinc-900 shadow-lg backdrop-blur-xl transition motion-safe:active:scale-95 lg:opacity-0 lg:group-focus-within:opacity-100 lg:group-hover:opacity-100"
            >
              <.icon name="hero-chevron-right" class="size-5" />
            </button>
            <p
              :if={@photo_count > 1}
              id="photo-counter"
              class="absolute bottom-3 right-3 rounded-full bg-zinc-900/60 px-3 py-1 text-xs font-medium text-white backdrop-blur-xl"
            >
              {@photo_index + 1} / {@photo_count}
            </p>
          </div>

          <ul
            :if={@photo_count > 1}
            id="photo-thumbs"
            class="-m-1 flex gap-3 overflow-x-auto p-1"
            aria-label="Product photos"
          >
            <li :for={{photo, index} <- Enum.with_index(@gallery)} class="shrink-0">
              <button
                type="button"
                id={"photo-thumb-#{index}"}
                phx-click="select_photo"
                phx-value-index={index}
                aria-label={"Show photo #{index + 1}"}
                aria-current={to_string(index == @photo_index)}
                class={[
                  "block rounded-xl p-0.5 transition motion-safe:active:scale-95",
                  if(index == @photo_index,
                    do: "ring-2 ring-zinc-900",
                    else: "opacity-60 hover:opacity-100"
                  )
                ]}
              >
                <.shop_thumb image={photo} class="size-20" />
              </button>
            </li>
          </ul>
        </div>

        <div class="space-y-10 lg:sticky lg:top-28 lg:self-start lg:py-4">
          <div class="space-y-5">
            <p id="shop-product-price" class="type-title text-4xl text-zinc-900">
              {price_prefix(assigns)}{format_price(price_for(assigns))}
            </p>
            <div
              :if={paragraphs(@product.description) != []}
              id="product-description"
              class="space-y-4"
            >
              <p
                :for={paragraph <- paragraphs(@product.description)}
                class="whitespace-pre-line text-lg text-zinc-700"
              >
                {paragraph}
              </p>
            </div>
          </div>

          <div :if={@colors != []} id="shop-colors" class="space-y-3">
            <p class="text-sm font-medium text-zinc-900">
              Color
              <span class="ml-1 font-normal text-zinc-500">{@selection.color}</span>
            </p>
            <div class="flex flex-wrap gap-3">
              <button
                :for={color <- @colors}
                type="button"
                id={"color-#{slug(color)}"}
                phx-click="select_color"
                phx-value-color={color}
                aria-pressed={to_string(@selection.color == color)}
                class={[
                  option_class(@selection.color == color),
                  "inline-flex items-center gap-2.5"
                ]}
              >
                <span
                  id={"color-dot-#{slug(color)}"}
                  class={
                    [
                      "shop-swatch size-5 shrink-0 rounded-full",
                      # On the dark selected pill a dark dot needs its own light edge.
                      @selection.color == color && "ring-2 ring-white/70"
                    ]
                  }
                  style={"--swatch: #{VariantSelection.color_hex(@product.variants, color) || "#d4d4d8"}"}
                  aria-hidden="true"
                ></span>
                {color}
              </button>
            </div>
          </div>

          <div :if={@all_sizes != []} id="shop-sizes" class="space-y-3">
            <p class="text-sm font-medium text-zinc-900">
              Size
              <span class="ml-1 font-normal text-zinc-500">{@selection.size}</span>
            </p>
            <div class="flex flex-wrap gap-3">
              <button
                :for={size <- @all_sizes}
                type="button"
                id={"size-#{slug(size)}"}
                phx-click="select_size"
                phx-value-size={size}
                aria-pressed={to_string(@selection.size == size)}
                disabled={size not in @sizes}
                class={[
                  option_class(@selection.size == size),
                  size not in @sizes && "cursor-not-allowed opacity-40 line-through"
                ]}
              >
                {size}
              </button>
            </div>
          </div>

          <form
            id="add-to-cart-form"
            phx-change="set_quantity"
            phx-submit="add_to_cart"
            class="flex flex-col gap-3"
          >
            <label for="quantity" class="sr-only">Quantity</label>
            <div
              class="inline-flex h-12 shrink-0 items-center self-start rounded-sm bg-zinc-100"
              role="group"
              aria-label="Quantity"
            >
              <button
                type="button"
                id="quantity-decrement"
                phx-click="decrement"
                disabled={@quantity <= 1}
                aria-label="Decrease quantity"
                class="inline-flex size-12 items-center justify-center rounded-sm text-zinc-900 transition-colors hover:bg-zinc-200 motion-safe:active:scale-95 disabled:cursor-not-allowed disabled:opacity-30 disabled:hover:bg-transparent"
              >
                <.icon name="hero-minus" class="size-5" />
              </button>
              <input
                type="number"
                id="quantity"
                name="quantity"
                inputmode="numeric"
                value={@quantity}
                min="1"
                max={CartItem.max_quantity()}
                class="h-12 w-12 border-0 bg-transparent p-0 text-center text-base font-medium tabular-nums text-zinc-900 [appearance:textfield] focus:ring-0 [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
              />
              <button
                type="button"
                id="quantity-increment"
                phx-click="increment"
                disabled={@quantity >= CartItem.max_quantity()}
                aria-label="Increase quantity"
                class="inline-flex size-12 items-center justify-center rounded-sm text-zinc-900 transition-colors hover:bg-zinc-200 motion-safe:active:scale-95 disabled:cursor-not-allowed disabled:opacity-30 disabled:hover:bg-transparent"
              >
                <.icon name="hero-plus" class="size-5" />
              </button>
            </div>

            <.button
              id="add-to-cart"
              type="submit"
              disabled={is_nil(@variant)}
              class="h-12 w-full text-base motion-safe:active:scale-[0.98]"
            >
              <%= if @variant do %>
                <.icon name="hero-shopping-bag" class="size-5" /> Add to cart ·
                <span id="add-to-cart-total" class="tabular-nums">
                  {format_price(line_total(assigns))}
                </span>
              <% else %>
                {missing_option_hint(assigns)}
              <% end %>
            </.button>
          </form>

          <ul class="space-y-2 text-sm text-zinc-500">
            <li class="flex items-center gap-2">
              <.icon name="hero-sparkles" class="size-4" />
              Printed to order for the club
            </li>
            <li class="flex items-center gap-2">
              <.icon name="hero-truck" class="size-4" />
              Ships in 2–5 business days. Shipping is calculated at checkout.
            </li>
          </ul>
        </div>
      </div>

      <.cart_dock
        summary={@cart_summary}
        peek={@cart_peek}
        open?={@cart_peek_open?}
      />
    </.shop_frame>
    """
  end

  defp option_class(selected?) do
    [
      "min-w-14 rounded-xl px-5 py-3 text-base font-medium transition motion-safe:active:scale-[0.97]",
      if(selected?,
        do: "bg-zinc-900 text-white",
        else: "bg-zinc-100 text-zinc-800 hover:bg-zinc-200"
      )
    ]
  end

  defp slug(value),
    do: value |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
end
