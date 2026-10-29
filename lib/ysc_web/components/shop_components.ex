defmodule YscWeb.ShopComponents do
  @moduledoc """
  Building blocks shared by the merch shop pages.

  Design language: the same page frame as the rest of the site (a plain
  `page_masthead`, nothing inside it), a segmented control and cart button below it, white
  background, generous whitespace, and soft filled surfaces (`bg-zinc-50`)
  instead of outlines. Separation comes from spacing, not borders.
  """
  use Phoenix.Component
  use YscWeb, :verified_routes

  import YscWeb.CoreComponents,
    only: [badge: 1, button: 1, icon: 1, page_masthead: 1]

  import Ysc.MoneyHelper, only: [format_price: 1]

  alias Phoenix.LiveView.JS
  alias Ysc.Media.{BlurPlaceholder, Image}
  alias Ysc.Merch.{Order, OrderItem, ShippingAddress}

  @doc """
  The frame every shop page shares: title section like every other page, then
  the shop links, then the page content.

  Every page gets the same masthead (same size, no subtitle) so the title and
  the shop links never move as you go between pages.

  The masthead sits close to the shop links so the two read as one header.

  The masthead, shop links and content all share one column, so every page
  lines up on the same left and right edges. Pages that want a narrower layout
  arrange it inside the column (a grid with a side panel, say).
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :eyebrow, :string, default: "Shop"
  attr :active, :atom, values: [:shop, :cart, :orders], required: true
  attr :cart_count, :integer, default: 0

  attr :signed_in?, :boolean,
    default: true,
    doc: "false for visitors, who have no orders to list"

  attr :can_buy?, :boolean,
    default: true,
    doc: "false for visitors and non-members, who have no cart to open"

  attr :section_only?, :boolean,
    default: false,
    doc:
      "true on a page inside the active section (a product, say): its link stays highlighted but is not announced as the current page"

  slot :inner_block, required: true

  def shop_frame(assigns) do
    ~H"""
    <div id={@id} class="py-6 md:py-12">
      <div class="mx-auto max-w-(--breakpoint-xl) px-4">
        <.page_masthead
          id={"#{@id}-masthead"}
          eyebrow={@eyebrow}
          title={@title}
          margin_class="mb-6 md:mb-8"
        />
      </div>

      <%!-- The shop links stay at the same left edge on every page; only the
            content below narrows. --%>
      <div class="mx-auto max-w-(--breakpoint-xl) px-4">
        <.shop_nav
          active={@active}
          cart_count={@cart_count}
          signed_in?={@signed_in?}
          can_buy?={@can_buy?}
          section_only?={@section_only?}
        />
      </div>

      <%!-- Room below the content so it never sits against the footer. --%>
      <div class="mx-auto max-w-(--breakpoint-xl) px-4 pb-16 md:pb-24">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Explains that only active members can buy, and where to go to become one.
  Shown in place of the buy controls to visitors and non-members.
  """
  attr :id, :string, default: "shop-members-notice"
  attr :signed_in?, :boolean, required: true, doc: "false sends to sign in"
  attr :redirect_to, :string, required: true, doc: "where sign in returns to"
  attr :class, :any, default: nil

  def shop_members_notice(assigns) do
    ~H"""
    <div id={@id} class={["rounded-2xl bg-zinc-50 p-5 md:p-6", @class]}>
      <p class="type-subhead text-lg text-zinc-900">
        Club gear is for YSC members
      </p>
      <p class="mt-1 text-base text-zinc-600">
        <%= if @signed_in? do %>
          Anyone can look around, but you need an active membership to buy.
        <% else %>
          Anyone can look around. Sign in with your member account to buy.
        <% end %>
      </p>
      <.link
        id={"#{@id}-action"}
        navigate={
          if(@signed_in?,
            do: ~p"/users/membership",
            else: ~p"/users/log-in?#{%{redirect_to: @redirect_to}}"
          )
        }
        class="mt-4 inline-flex min-h-11 items-center justify-center rounded-xl bg-zinc-900 px-6 text-base font-medium text-white transition hover:bg-zinc-700 motion-safe:active:scale-[0.97]"
      >
        {if @signed_in?, do: "See membership", else: "Sign in"}
      </.link>
    </div>
    """
  end

  @doc """
  Pulse placeholder shown while a shop page loads its data after first paint.
  """
  attr :id, :string, required: true

  def shop_page_loading(assigns) do
    ~H"""
    <div id={@id} class="mt-8 animate-pulse space-y-6">
      <div class="h-8 w-48 rounded-sm bg-zinc-200"></div>
      <div class="aspect-[4/3] max-w-xl rounded-2xl bg-zinc-200"></div>
      <div class="h-4 w-3/4 rounded-sm bg-zinc-200"></div>
      <div class="h-4 w-1/2 rounded-sm bg-zinc-100"></div>
    </div>
    """
  end

  @doc """
  Centered empty-state panel for shop pages with nothing to show.

  Pass `browse_id` to include the standard "Browse the shop" button.

  ## Examples

      <.shop_empty_state id="shop-empty" title="The shop is stocking up">
        New club gear is on the way. Check back soon.
      </.shop_empty_state>

      <.shop_empty_state
        id="cart-empty"
        title="Your cart is empty"
        browse_id="cart-browse"
      >
        Find something you like in the shop.
      </.shop_empty_state>
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :icon, :string, default: "hero-shopping-bag"

  attr :browse_id, :string,
    default: nil,
    doc: "When set, renders a Browse the shop button with this DOM id"

  slot :inner_block, required: true

  def shop_empty_state(assigns) do
    ~H"""
    <div id={@id} class="rounded-3xl bg-zinc-50 px-6 py-24 text-center">
      <.icon name={@icon} class="mx-auto mb-6 size-12 text-zinc-400" />
      <h2 class="type-title text-2xl text-zinc-900">{@title}</h2>
      <p class="mt-3 text-lg text-zinc-600">
        {render_slot(@inner_block)}
      </p>
      <.button
        :if={@browse_id}
        id={@browse_id}
        navigate={~p"/shop"}
        class="mt-8 motion-safe:active:scale-[0.98]"
      >
        Browse the shop
      </.button>
    </div>
    """
  end

  @doc """
  Shop links. Products and My orders are a segmented control (the same soft
  `bg-zinc-100` surface as the toolbar below it); the cart is its own button on
  the right, with the item count, since that is where people look for it.
  """
  attr :active, :atom, values: [:shop, :cart, :orders], required: true
  attr :cart_count, :integer, default: 0
  attr :signed_in?, :boolean, default: true
  attr :can_buy?, :boolean, default: true
  attr :section_only?, :boolean, default: false

  def shop_nav(assigns) do
    ~H"""
    <nav
      id="shop-nav"
      aria-label="Shop"
      class="mb-8 flex items-center justify-between gap-3 md:mb-10"
    >
      <div class="inline-flex items-center gap-1 rounded-xl bg-zinc-100 p-1">
        <.shop_nav_link
          id="shop-nav-products"
          to={~p"/shop"}
          icon="hero-squares-2x2"
          active={@active == :shop}
          page?={!@section_only?}
        >
          Products
        </.shop_nav_link>
        <.shop_nav_link
          :if={@signed_in?}
          id="shop-nav-orders"
          to={~p"/shop/orders"}
          icon="hero-truck"
          active={@active == :orders}
        >
          My orders
        </.shop_nav_link>
      </div>

      <.link
        :if={@can_buy?}
        id="shop-nav-cart"
        navigate={~p"/shop/cart"}
        aria-current={@active == :cart && "page"}
        class={[
          "inline-flex min-h-11 items-center gap-2 rounded-xl px-4 text-sm font-semibold transition motion-safe:active:scale-[0.97]",
          if(@active == :cart,
            do: "bg-zinc-900 text-white",
            else: "bg-zinc-100 text-zinc-900 hover:bg-zinc-200"
          )
        ]}
      >
        <.icon name="hero-shopping-bag" class="size-5" /> Cart
        <span
          :if={@cart_count > 0}
          id="shop-cart-count"
          class="inline-flex h-5 min-w-5 items-center justify-center rounded-full bg-blue-600 px-1 text-xs font-semibold leading-none tabular-nums text-white"
        >
          {@cart_count}
        </span>
      </.link>
    </nav>
    """
  end

  attr :id, :string, required: true
  attr :to, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  attr :page?, :boolean, default: true
  slot :inner_block, required: true

  defp shop_nav_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@to}
      aria-current={@active && if(@page?, do: "page", else: "true")}
      class={[
        "inline-flex min-h-9 items-center gap-2 rounded-lg px-3 text-sm transition-colors md:px-3.5",
        if(@active,
          do: "bg-white font-semibold text-zinc-900 shadow-xs",
          else: "font-medium text-zinc-600 hover:bg-zinc-200/60 hover:text-zinc-900"
        )
      ]}
    >
      <.icon name={@icon} class={["size-4", @active && "text-blue-600"]} />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  A quiet secondary action: a tinted, borderless link styled like a button.
  """
  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def shop_secondary_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class={[
        "inline-flex min-h-12 items-center justify-center rounded-sm bg-zinc-100 px-6 text-sm font-semibold text-zinc-900 transition hover:bg-zinc-200 motion-safe:active:scale-[0.97]",
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  A product or variant image, served from the media library. Zooms very
  slightly under the pointer (never for reduced motion).
  """
  attr :id, :string, required: true
  attr :image, :any, default: nil
  attr :fallback_image, :any, default: nil
  attr :class, :any, default: nil
  attr :sizes, :string, default: "(max-width: 640px) 100vw, 33vw"
  attr :loading, :string, default: "lazy"
  attr :fetchpriority, :string, default: nil

  def shop_image(assigns) do
    assigns = assign(assigns, :image, assigns.image || assigns.fallback_image)

    ~H"""
    <div class={["overflow-hidden rounded-2xl bg-zinc-100", @class]}>
      <div class="transition-transform duration-500 ease-out motion-safe:group-hover:scale-[1.03]">
        <.live_component
          id={@id}
          module={YscWeb.Components.Image}
          image={@image}
          aspect_class="aspect-square"
          preferred_type={:optimized}
          sizes={@sizes}
          loading={@loading}
          fetchpriority={@fetchpriority}
          rounded_class=""
        />
      </div>
    </div>
    """
  end

  @doc """
  A product on the listing page: a photo per color that swaps when a swatch
  is hovered or tapped, a second photo on hover, then name, price and a line
  of detail. Everything that swaps happens in the browser (`JS` commands), so
  it responds instantly and never waits on the server.
  """
  attr :tile, :map, required: true, doc: "from `Ysc.Merch.Listing.tile/2`"
  attr :price, :string, required: true

  def product_tile(assigns) do
    assigns = assign(assigns, :product, assigns.tile.product)

    ~H"""
    <li
      id={"shop-product-#{@product.id}"}
      class="group/tile"
      phx-hook="ShopTile"
    >
      <.link
        navigate={product_path(@product, @tile.active)}
        id={"shop-product-link-#{@product.id}"}
        data-tile-link
        tabindex="-1"
        aria-hidden="true"
        class="block transition-transform motion-safe:active:scale-[0.98]"
      >
        <div class="shop-tile-photo relative aspect-square overflow-hidden rounded-2xl bg-zinc-100">
          <div
            :for={color <- @tile.colors}
            id={"shop-layer-#{@product.id}-#{color.slug}"}
            data-tile-layer
            data-active={color.slug == @tile.active.slug}
            class="shop-tile-layer absolute inset-0"
          >
            <.shop_photo
              id={"shop-product-image-#{@product.id}-#{color.slug}"}
              image={color.image || @product.image}
              placeholder?={true}
            />
            <div :if={color.hover_image} class="shop-tile-hover absolute inset-0">
              <.shop_photo
                id={"shop-product-hover-#{@product.id}-#{color.slug}"}
                image={color.hover_image}
              />
            </div>
          </div>
        </div>
      </.link>

      <div
        :if={length(@tile.colors) > 1}
        class="mt-2 flex flex-wrap items-center gap-x-0.5"
        id={"shop-swatches-#{@product.id}"}
      >
        <button
          :for={color <- @tile.colors}
          type="button"
          id={"shop-swatch-#{@product.id}-#{color.slug}"}
          data-tile-swatch
          aria-label={color.name}
          aria-pressed={to_string(color.slug == @tile.active.slug)}
          title={color.name}
          phx-click={pick_color(@tile, color)}
          class="group/swatch flex size-8 items-center justify-center rounded-full outline-none"
        >
          <span
            class="shop-swatch size-5 rounded-full ring-offset-2 transition motion-safe:group-active/swatch:scale-90 group-aria-pressed/swatch:ring-2 group-aria-pressed/swatch:ring-zinc-900 group-focus-visible/swatch:ring-2 group-focus-visible/swatch:ring-blue-600"
            style={color.hex && "--swatch: #{color.hex}"}
          ></span>
        </button>
        <.link
          :if={@tile.hidden_colors > 0}
          navigate={product_path(@product, @tile.active)}
          id={"shop-more-colors-#{@product.id}"}
          class="ml-1 rounded-full px-2 py-1 text-sm font-medium text-zinc-600 transition-colors hover:text-blue-700"
        >
          +{@tile.hidden_colors}
        </.link>
      </div>

      <.link
        navigate={product_path(@product, @tile.active)}
        data-tile-link
        class={[
          "group block",
          if(length(@tile.colors) > 1, do: "mt-1", else: "mt-11")
        ]}
      >
        <h2 class="type-subhead text-lg text-zinc-900 transition-colors group-hover:text-blue-700 md:text-xl">
          {@product.name}
        </h2>
        <p class="mt-0.5 text-base text-zinc-600">{@price}</p>
      </.link>

      <p
        :if={@tile.active.name || @tile.sizes}
        class="mt-1 text-sm text-zinc-500"
        id={"shop-details-#{@product.id}"}
      >
        <span
          :for={color <- @tile.colors}
          :if={color.name}
          data-tile-color
          id={"shop-color-name-#{@product.id}-#{color.slug}"}
          class={[color.slug != @tile.active.slug && "hidden"]}
        >
          {color.name}
        </span>
        <span :if={@tile.active.name && @tile.sizes} aria-hidden="true"> · </span>
        <span :if={@tile.sizes}>{@tile.sizes}</span>
      </p>
    </li>
    """
  end

  @doc """
  A square photo that shows a blurred preview of itself, from the first byte
  of HTML, until the real image has loaded.

  Unlike `YscWeb.Components.Image`, whose blur placeholder is painted by a
  JS hook and so stays an empty box until LiveView connects, the preview here
  is a server-rendered background, and the `<img>` is visible as soon as the
  browser has it. The `ShopTile` hook adds a fade for images that are still
  loading once the page is live.
  """
  attr :id, :string, required: true
  attr :image, :any, default: nil

  attr :placeholder?, :boolean,
    default: false,
    doc: "render the blur preview (only photos that start out visible need it)"

  attr :sizes, :string, default: "(max-width: 768px) 50vw, 25vw"

  def shop_photo(assigns) do
    image = assigns.image

    assigns =
      assign(assigns,
        src: Image.display_path_with_fallback(image),
        srcset: Image.responsive_srcset(image),
        alt: image && (image.alt_text || image.title),
        blur:
          assigns.placeholder? && image &&
            BlurPlaceholder.data_uri(image.blur_hash)
      )

    ~H"""
    <div
      class="shop-photo-bg size-full"
      style={@blur && "--blur: url(#{@blur})"}
    >
      <img
        id={@id}
        src={@src}
        srcset={@srcset}
        sizes={@sizes}
        alt={@alt || ""}
        loading="lazy"
        decoding="async"
        class="shop-photo-img size-full object-cover"
      />
    </div>
    """
  end

  defp product_path(product, %{name: name}) when is_binary(name),
    do: ~p"/shop/products/#{product.id}?#{[color: name]}"

  defp product_path(product, _color), do: ~p"/shop/products/#{product.id}"

  # Show `color`'s photo, mark its swatch, name it, and point the tile's links
  # at the product in that color.
  defp pick_color(tile, color) do
    id = tile.product.id
    scope = "#shop-product-#{id}"
    layers = "#{scope} [data-tile-layer]"
    layer = "#shop-layer-#{id}-#{color.slug}"

    # The photo on show stays underneath (data-prev) while the new one fades in.
    JS.remove_attribute("data-prev", to: layers)
    |> JS.set_attribute({"data-prev", ""}, to: "#{layers}[data-active]")
    |> JS.remove_attribute("data-active", to: layers)
    |> JS.set_attribute({"data-active", ""}, to: layer)
    |> JS.set_attribute({"aria-pressed", "false"},
      to: "#{scope} [data-tile-swatch]"
    )
    |> JS.set_attribute({"aria-pressed", "true"},
      to: "#shop-swatch-#{id}-#{color.slug}"
    )
    |> JS.add_class("hidden", to: "#{scope} [data-tile-color]")
    |> JS.remove_class("hidden", to: "#shop-color-name-#{id}-#{color.slug}")
    |> JS.set_attribute({"href", product_path(tile.product, color)},
      to: "#{scope} [data-tile-link]"
    )
  end

  @doc "Small square thumbnail for list rows."
  attr :image, :any, default: nil
  attr :fallback_image, :any, default: nil
  attr :class, :any, default: "size-16"

  def shop_thumb(assigns) do
    assigns = assign(assigns, :image, assigns.image || assigns.fallback_image)

    ~H"""
    <img
      src={Image.thumbnail_path_with_fallback(@image)}
      alt=""
      loading="lazy"
      class={["shrink-0 rounded-xl bg-zinc-100 object-cover", @class]}
    />
    """
  end

  @doc """
  Street lines of a merch delivery address.

  Renders `address1`, optional `address2`, then `City, ST ZIP`, omitting
  blanks. Pass `name` to put the recipient on the first line (shop order
  and checkout); omit it when the name is already rendered (admin order
  detail, where it may be a member link).

  ## Examples

      <.shipping_address_lines address={@order} name={@order.recipient_name} />
      <.shipping_address_lines address={@address} />
  """
  attr :address, :map, required: true

  attr :name, :string,
    default: nil,
    doc: "Optional first line (recipient name)"

  def shipping_address_lines(assigns) do
    assigns =
      assign(assigns, :lines, ShippingAddress.display_lines(assigns.address))

    ~H"""
    <%= if @name not in [nil, ""] do %>
      {@name}<br />
    <% end %>
    <%= for {line, idx} <- Enum.with_index(@lines) do %>
      <%= if idx > 0 do %>
        <br />
      <% end %>
      {line}
    <% end %>
    """
  end

  @doc "Status of an order, in member-friendly words."
  attr :order, Order, required: true

  def order_status_badge(assigns) do
    {label, type} = status_display(assigns.order.status)
    assigns = assign(assigns, label: label, type: type)

    ~H"""
    <.badge type={@type}>{@label}</.badge>
    """
  end

  @doc false
  def status_display(:pending), do: {"Awaiting payment", "yellow"}
  def status_display(:paid), do: {"Paid", "sky"}
  def status_display(:submitting), do: {"Getting ready", "sky"}
  def status_display(:submitted), do: {"Being prepared", "sky"}
  def status_display(:in_production), do: {"Being made", "sky"}
  def status_display(:shipped), do: {"Shipped", "green"}
  def status_display(:delivered), do: {"Delivered", "green"}
  def status_display(:failed), do: {"Problem with order", "red"}
  def status_display(:canceled), do: {"Canceled", "zinc"}
  def status_display(:refunded), do: {"Refunded", "zinc"}

  @doc """
  Line items and totals for an order. Club-paid orders show "Paid by the club".
  """
  attr :order, Order, required: true

  def order_summary(assigns) do
    ~H"""
    <div id={"order-summary-#{@order.id}"}>
      <ul class="space-y-5">
        <li
          :for={item <- @order.items}
          id={"order-item-#{item.id}"}
          class="flex items-center gap-4"
        >
          <.shop_thumb image={item.variant && item.variant.image} class="size-16" />
          <div class="min-w-0 flex-1">
            <p class="truncate text-zinc-900">{OrderItem.title(item)}</p>
            <p
              :if={OrderItem.variant_label(item)}
              class="truncate text-sm text-zinc-500"
            >
              {OrderItem.variant_label(item)}
            </p>
            <p class="text-sm tabular-nums text-zinc-500">
              {item.quantity} × {format_price(item.unit_price)}
            </p>
          </div>
          <p class="text-zinc-900">
            {format_price(Money.mult!(item.unit_price, item.quantity))}
          </p>
        </li>
      </ul>

      <dl class="mt-8 space-y-2 text-sm">
        <%= if @order.kind == :admin_comp do %>
          <div class="flex justify-between text-base font-semibold text-zinc-900">
            <dt>Paid by the club</dt>
            <dd>{format_price(@order.total_amount)}</dd>
          </div>
        <% else %>
          <div class="flex justify-between text-zinc-600">
            <dt>Subtotal</dt>
            <dd>{format_price(@order.subtotal)}</dd>
          </div>
          <div class="flex justify-between text-zinc-600">
            <dt>Shipping</dt>
            <dd>{format_price(@order.shipping_amount)}</dd>
          </div>
          <div class="flex justify-between pt-2 text-base font-semibold text-zinc-900">
            <dt>Total</dt>
            <dd>{format_price(@order.total_amount)}</dd>
          </div>
        <% end %>
      </dl>
    </div>
    """
  end

  @doc """
  The floating cart: a solid white pill centered along the bottom edge once the cart has
  something in it, and an "added" card that opens from the pill.

  See `YscWeb.ShopCartPeek` for the card's lifecycle. The pill links to the
  cart; the card offers cart and checkout and can be dismissed. Depth comes
  from the shadow, not outlines. Both are solid white, not translucent, so they
  read the same over any page content.
  """
  attr :summary, :map, required: true, doc: "`%{count: n, subtotal: Money}`"

  attr :peek, :map,
    default: nil,
    doc: "what was just added: name, detail, image, quantity"

  attr :open?, :boolean, default: false

  attr :reveal_after, :string,
    default: nil,
    doc:
      "DOM id of an element (the page's own cart link) that the pill stays hidden behind until it scrolls out of view"

  def cart_dock(assigns) do
    ~H"""
    <div
      :if={@summary.count > 0}
      id="cart-dock"
      class="cart-dock print:hidden"
      phx-hook={@reveal_after && "CartDockReveal"}
      data-reveal-after={@reveal_after}
    >
      <%!-- Announced to assistive tech when something is added. --%>
      <p id="cart-dock-status" class="sr-only" role="status" aria-live="polite">
        <%= if @open? && @peek do %>
          {@peek.name} added to your cart. {@summary.count} items, {format_price(
            @summary.subtotal
          )}.
        <% end %>
      </p>

      <div
        :if={@peek}
        id="cart-peek"
        class="cart-peek w-[min(22rem,calc(100vw-2rem))] rounded-3xl bg-white p-5 shadow-2xl shadow-zinc-900/15"
        data-open={to_string(@open?)}
        aria-hidden={to_string(!@open?)}
        phx-hook="CartPeekHover"
        phx-window-keydown="dismiss_cart_peek"
        phx-key="Escape"
      >
        <div class="flex items-start gap-3">
          <.shop_thumb image={@peek.image} class="size-14" />
          <div class="min-w-0 flex-1">
            <p class="type-eyebrow text-xs text-green-700">Added to cart</p>
            <p class="truncate text-zinc-900">{@peek.name}</p>
            <p :if={@peek.detail} class="truncate text-sm text-zinc-500">
              {@peek.detail} · Qty {@peek.quantity}
            </p>
          </div>
          <button
            type="button"
            id="cart-peek-dismiss"
            phx-click="dismiss_cart_peek"
            aria-label="Dismiss"
            tabindex={if(@open?, do: "0", else: "-1")}
            class="-m-2 inline-flex size-11 items-center justify-center rounded-full text-zinc-500 transition-colors hover:bg-zinc-900/5 hover:text-zinc-900"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="mt-5 grid grid-cols-2 gap-2">
          <.link
            id="cart-peek-view"
            navigate={~p"/shop/cart"}
            tabindex={if(@open?, do: "0", else: "-1")}
            class="inline-flex min-h-11 items-center justify-center rounded-sm bg-zinc-900/5 px-4 text-sm font-semibold text-zinc-900 transition hover:bg-zinc-900/10 motion-safe:active:scale-[0.97]"
          >
            View cart
          </.link>
          <.link
            id="cart-peek-checkout"
            navigate={~p"/shop/checkout"}
            tabindex={if(@open?, do: "0", else: "-1")}
            class="inline-flex min-h-11 items-center justify-center rounded-sm bg-zinc-900 px-4 text-sm font-semibold text-white transition hover:bg-zinc-700 motion-safe:active:scale-[0.97]"
          >
            Checkout
          </.link>
        </div>
      </div>

      <.link
        id="cart-pill"
        navigate={~p"/shop/cart"}
        aria-label={"Cart, #{@summary.count} items, #{format_price(@summary.subtotal)}"}
        class="inline-flex min-h-16 items-center gap-4 rounded-full bg-white py-3 pl-6 pr-8 shadow-xl shadow-zinc-900/15 transition-transform motion-safe:active:scale-[0.97]"
      >
        <span class="relative">
          <.icon name="hero-shopping-bag" class="size-8 text-zinc-900" />
          <span
            id={"cart-dock-count-#{@summary.count}"}
            class="cart-count-pop absolute -right-3 -top-3 inline-flex h-6 min-w-6 items-center justify-center rounded-full bg-blue-600 px-1.5 text-sm font-semibold leading-none tabular-nums text-white"
          >
            {@summary.count}
          </span>
        </span>
        <span class="flex flex-col leading-tight">
          <span id="cart-dock-label" class="text-lg font-semibold text-zinc-900">
            Your cart
          </span>
          <span
            id="cart-dock-subtotal"
            class="text-base tabular-nums text-zinc-500"
          >
            {format_price(@summary.subtotal)}
          </span>
        </span>
      </.link>
    </div>
    """
  end
end
