defmodule YscWeb.ShopLive do
  @moduledoc """
  The merch shop: every product members can buy.

  The first HTML is a skeleton. Catalog and cart-summary queries run after the
  WebSocket connects so the HTTP response is never blocked on those loads, and
  they run once instead of on both the disconnected and connected mounts.
  """
  use YscWeb, :live_view

  on_mount {YscWeb.ShopAccess, :ensure_member}

  require Ysc.Logging

  import Ysc.MoneyHelper, only: [format_price: 1]
  import YscWeb.Live.AsyncHelpers
  import YscWeb.ShopComponents

  alias Ysc.Merch
  alias Ysc.Merch.{Cart, Listing}
  alias Phoenix.LiveView.JS
  alias YscWeb.ShopCartPeek

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Shop")
     |> assign(:products, [])
     |> assign(:color_options, [])
     |> assign(:tiles, [])
     |> assign(:sort, "featured")
     |> assign(:selected_colors, [])
     |> assign(:filter_colors_param, nil)
     |> assign(:async_data_loaded, false)
     |> assign(:catalog_task_started?, false)
     |> ShopCartPeek.init_placeholder()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = assign_listing_params(socket, params)

    {:noreply,
     cond do
       not connected?(socket) ->
         socket

       socket.assigns.async_data_loaded ->
         apply_listing(socket)

       socket.assigns.catalog_task_started? ->
         socket

       true ->
         load_catalog_async(socket)
     end}
  end

  @impl true
  def handle_async(
        :load_shop,
        {:ok, %{products: products, cart_summary: cart_summary}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:async_data_loaded, true)
     |> assign(:products, products)
     |> assign(:color_options, Listing.available_colors(products))
     |> assign(:cart_summary, cart_summary)
     |> apply_listing()}
  end

  def handle_async(:load_shop, {:exit, reason}, socket) do
    Ysc.Logging.error("ShopLive: failed to load catalog", error: reason)

    {:noreply, assign(socket, :async_data_loaded, true)}
  end

  defp load_catalog_async(socket) do
    user = socket.assigns.current_user

    socket
    |> assign(:catalog_task_started?, true)
    |> start_async(:load_shop, fn ->
      allow_sandbox_access()

      %{
        products: Merch.list_shop_products(),
        cart_summary: Cart.summary(user)
      }
    end)
  end

  defp assign_listing_params(socket, params) do
    socket
    |> assign(:sort, Listing.parse_sort(params["sort"]))
    |> assign(:filter_colors_param, params["colors"])
  end

  defp apply_listing(socket) do
    colors =
      parse_colors(
        socket.assigns.filter_colors_param,
        socket.assigns.color_options
      )

    tiles =
      socket.assigns.products
      |> Listing.filter(colors)
      |> Listing.sort(socket.assigns.sort)
      |> Enum.map(&Listing.tile(&1, colors))

    socket
    |> assign(:selected_colors, colors)
    |> assign(:tiles, tiles)
  end

  @impl true
  def handle_event("sort", %{"sort" => sort}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         listing_path(Listing.parse_sort(sort), socket.assigns.selected_colors)
     )}
  end

  # Only colors some product really offers, in the order the page lists them.
  defp parse_colors(names, options) when is_list(names) do
    for %{name: name} <- options, name in names, do: name
  end

  defp parse_colors(_names, _options), do: []

  defp listing_path(sort, colors) do
    query =
      [
        sort: if(sort != "featured", do: sort),
        colors: if(colors != [], do: colors)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    if query == [], do: ~p"/shop", else: ~p"/shop?#{query}"
  end

  defp toggle_color(colors, name) do
    if name in colors, do: List.delete(colors, name), else: colors ++ [name]
  end

  # Answers are plain text; `contact` is where members write with problems.
  defp faq_items do
    [
      {"does-the-club-make-money", "Does the club make money on the merch?",
       "No. The club does not make money on merch. The shop is just for fun, and a way to show your support for the club when you are out and about."},
      {"delivery-time", "Why might delivery take longer than usual?",
       "Everything is printed to order. Nothing sits in a warehouse waiting for you: your item is made after you order and then shipped, so it can take a bit longer to arrive than a typical online order. We email you as soon as it ships, with a tracking link."},
      {"shipping", "Where do you ship, and what does it cost?",
       "We currently ship within the United States. Shipping is charged at what it really costs, and you see the exact amount at checkout before you pay."},
      {"tracking", "How do I follow my order?",
       "You get a confirmation email right away, then an email (and a text message, if you have those turned on) when your order ships and if anything changes. You can also check My orders at any time."},
      {"problems", "Something is wrong with my order. Who do I ask?",
       "Write to us at the address below with your order number and we will sort it out."}
    ]
  end

  # Splits an answer around a phrase that should render as a link.
  defp answer_before(answer, phrase),
    do: answer |> String.split(phrase, parts: 2) |> List.first()

  defp answer_after(answer, phrase),
    do: answer |> String.split(phrase, parts: 2) |> List.last()

  defp count_label(1), do: "1 item"
  defp count_label(count), do: "#{count} items"

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
        :if={!@async_data_loaded}
        id="shop-loading"
        class="mt-8 grid grid-cols-2 gap-x-4 gap-y-10 md:grid-cols-3 md:gap-x-8 md:gap-y-14 lg:grid-cols-4"
      >
        <div :for={_ <- 1..8} class="animate-pulse">
          <div class="aspect-square rounded-2xl bg-zinc-200"></div>
          <div class="mt-3 h-4 w-3/4 rounded-sm bg-zinc-200"></div>
          <div class="mt-2 h-3 w-1/2 rounded-sm bg-zinc-100"></div>
        </div>
      </div>

      <div
        :if={@async_data_loaded && @products == []}
        id="shop-empty"
        class="rounded-3xl bg-zinc-50 px-6 py-24 text-center"
      >
        <.icon name="hero-shopping-bag" class="mx-auto mb-6 size-12 text-zinc-400" />
        <h2 class="type-title text-2xl text-zinc-900">The shop is stocking up</h2>
        <p class="mt-3 text-lg text-zinc-600">
          New club gear is on the way. Check back soon.
        </p>
      </div>

      <div :if={@async_data_loaded && @products != []} id="shop-toolbar">
        <div class="flex items-center justify-between gap-4">
          <p
            id="shop-count"
            class="shrink-0 whitespace-nowrap text-base font-medium text-zinc-900"
            aria-live="polite"
          >
            {count_label(length(@tiles))}
          </p>

          <div class="flex min-w-0 items-center gap-2">
            <div :if={length(@color_options) > 1} class="relative">
              <button
                type="button"
                id="shop-filter-toggle"
                aria-controls="shop-filter-panel"
                phx-click={JS.toggle(to: "#shop-filter-panel")}
                class="inline-flex items-center gap-2 rounded-xl bg-zinc-100 px-3 py-2.5 md:px-4 text-base font-medium text-zinc-900 transition hover:bg-zinc-200 motion-safe:active:scale-[0.97]"
              >
                <.icon name="hero-adjustments-horizontal" class="size-5" /> Color
                <span
                  :if={@selected_colors != []}
                  id="shop-filter-count"
                  class="rounded-full bg-zinc-900 px-2 text-sm text-white"
                >
                  {length(@selected_colors)}
                </span>
              </button>

              <div
                id="shop-filter-panel"
                phx-click-away={JS.hide(to: "#shop-filter-panel")}
                phx-key="escape"
                phx-window-keydown={JS.hide(to: "#shop-filter-panel")}
                class="absolute right-0 z-20 mt-2 hidden w-72 rounded-2xl bg-white p-3 shadow-xl ring-1 ring-zinc-900/5"
              >
                <ul class="flex flex-col">
                  <li :for={option <- @color_options}>
                    <.link
                      patch={
                        listing_path(
                          @sort,
                          toggle_color(@selected_colors, option.name)
                        )
                      }
                      id={"shop-filter-color-#{option.slug}"}
                      aria-current={option.name in @selected_colors && "true"}
                      class="flex items-center gap-3 rounded-xl px-3 py-2.5 text-base text-zinc-800 transition-colors hover:bg-zinc-50 motion-safe:active:scale-[0.98]"
                    >
                      <span
                        class="shop-swatch size-5 shrink-0 rounded-full"
                        style={option.hex && "--swatch: #{option.hex}"}
                      ></span>
                      <span class={[
                        "flex-1",
                        option.name in @selected_colors &&
                          "font-semibold text-zinc-900"
                      ]}>
                        {option.name}
                      </span>
                      <.icon
                        :if={option.name in @selected_colors}
                        name="hero-check"
                        class="size-5 text-zinc-900"
                      />
                    </.link>
                  </li>
                </ul>
              </div>
            </div>

            <form id="shop-sort-form" phx-change="sort" class="relative min-w-0">
              <label for="shop-sort" class="sr-only">Sort by</label>
              <select
                id="shop-sort"
                name="sort"
                class="w-full appearance-none truncate rounded-xl border-0 bg-zinc-100 py-2.5 pl-3 pr-9 md:pl-4 md:pr-10 text-base font-medium text-zinc-900 transition-colors hover:bg-zinc-200 focus:ring-2 focus:ring-blue-600"
              >
                <option
                  :for={{value, label} <- Listing.sorts()}
                  value={value}
                  selected={value == @sort}
                >
                  {label}
                </option>
              </select>
              <.icon
                name="hero-chevron-down"
                class="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-zinc-600"
              />
            </form>
          </div>
        </div>

        <div
          :if={@selected_colors != []}
          id="shop-active-filters"
          class="mt-4 flex flex-wrap items-center gap-2"
        >
          <.link
            :for={name <- @selected_colors}
            patch={listing_path(@sort, toggle_color(@selected_colors, name))}
            id={"shop-remove-filter-#{Listing.slug(name)}"}
            aria-label={"Remove #{name} filter"}
            class="inline-flex items-center gap-1.5 rounded-full bg-zinc-100 py-1.5 pl-4 pr-3 text-base text-zinc-900 transition hover:bg-zinc-200 motion-safe:active:scale-[0.97]"
          >
            {name} <.icon name="hero-x-mark" class="size-4" />
          </.link>
          <.link
            patch={listing_path(@sort, [])}
            id="shop-clear-filters"
            class="rounded-full px-3 py-1.5 text-base font-medium text-blue-700 transition-colors hover:text-blue-800"
          >
            Clear all
          </.link>
        </div>
      </div>

      <div
        :if={(@async_data_loaded && @products != []) and @tiles == []}
        id="shop-no-matches"
        class="mt-8 rounded-3xl bg-zinc-50 px-6 py-20 text-center"
      >
        <h2 class="type-title text-2xl text-zinc-900">Nothing in that color</h2>
        <p class="mt-3 text-lg text-zinc-600">
          Try a different color, or see everything.
        </p>
        <.link
          patch={listing_path(@sort, [])}
          id="shop-no-matches-clear"
          class="mt-6 inline-block rounded-xl bg-zinc-900 px-6 py-3 text-base font-medium text-white transition hover:bg-zinc-700 motion-safe:active:scale-[0.97]"
        >
          Clear all
        </.link>
      </div>

      <ul
        :if={@tiles != []}
        id="shop-products"
        class="mt-8 grid grid-cols-2 gap-x-4 gap-y-10 md:grid-cols-3 md:gap-x-8 md:gap-y-14 lg:grid-cols-4"
      >
        <.product_tile
          :for={tile <- @tiles}
          tile={tile}
          price={price_label(tile.product)}
        />
      </ul>

      <section
        :if={@async_data_loaded && @products != []}
        id="shop-faq"
        aria-labelledby="shop-faq-title"
        class="mt-20 md:mt-28"
      >
        <h2
          id="shop-faq-title"
          class="type-title text-2xl text-zinc-900 md:text-3xl"
        >
          Good to know
        </h2>

        <%!-- Static content: ignoring patches keeps open answers open while
              the list above is sorted or filtered. --%>
        <div
          id="shop-faq-items"
          phx-update="ignore"
          class="mt-6 flex max-w-3xl flex-col gap-3"
        >
          <details
            :for={{key, question, answer} <- faq_items()}
            id={"shop-faq-#{key}"}
            class="group rounded-2xl bg-zinc-50 transition-colors open:bg-zinc-100"
          >
            <summary class="flex cursor-pointer list-none items-center justify-between gap-4 rounded-2xl px-5 py-4 text-lg font-medium text-zinc-900 outline-none focus-visible:ring-2 focus-visible:ring-blue-600 motion-safe:active:scale-[0.99] [&::-webkit-details-marker]:hidden">
              {question}
              <.icon
                name="hero-chevron-down"
                class="size-5 shrink-0 text-zinc-500 transition-transform group-open:rotate-180"
              />
            </summary>
            <p class="px-5 pb-5 text-base text-zinc-600">
              <%= if key == "tracking" do %>
                {answer_before(answer, "My orders")}
                <.link
                  id="shop-faq-orders"
                  navigate={~p"/shop/orders"}
                  class="font-medium text-blue-700 hover:text-blue-800"
                >
                  My orders
                </.link>
                {answer_after(answer, "My orders")}
              <% else %>
                {answer}
              <% end %>
              <a
                :if={key == "problems"}
                id="shop-faq-contact"
                href="mailto:info@ysc.org"
                class="font-medium text-blue-700 hover:text-blue-800"
              >
                info@ysc.org
              </a>
            </p>
          </details>
        </div>
      </section>

      <.cart_dock summary={@cart_summary} />
    </.shop_frame>
    """
  end
end
