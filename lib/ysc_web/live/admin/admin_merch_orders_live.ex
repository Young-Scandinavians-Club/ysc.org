defmodule YscWeb.AdminMerchOrdersLive do
  @moduledoc """
  Merch orders for admins: every member purchase and club-paid order, a
  "needs attention" view of the ones Printful could not take, and a detail
  page where a failed order can be sent again.

  The first HTML is a skeleton. List, detail, and attention-count queries run
  after the WebSocket connects so the HTTP response is never blocked on those
  loads, and they run once instead of on both the disconnected and connected
  mounts.
  """
  use YscWeb, :admin_live_view

  on_mount {YscWeb.UserAuth, :ensure_full_admin}

  import YscWeb.AdminMerchComponents
  import YscWeb.ShopComponents, only: [shipping_address_lines: 1]

  alias Ysc.Accounts.UserDisplay
  alias Ysc.Merch.{AdminOrders, Orders}
  alias Ysc.Repo
  alias YscWeb.Admin.DateTimeDisplay

  @filter_labels %{
    all: "All",
    needs_attention: "Needs attention",
    club_paid: "Club-paid",
    purchases: "Purchases"
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active_page, :merch)
     |> assign(:page_title, "Merch orders")
     |> assign(:order, nil)
     |> assign(:filter, :all)
     |> assign(:search, "")
     |> assign(:list_params, %{})
     |> assign(:meta, nil)
     |> assign(:orders, [])
     |> assign(:retrying?, false)
     |> assign(:attention_count, 0)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    if connected?(socket) do
      case load_order(id) do
        nil ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(:error, "We couldn't find that order.")
           |> push_navigate(to: ~p"/admin/merch/orders")}

        order ->
          {:noreply,
           socket
           |> assign(:page_title, "Order #{order.reference_id}")
           |> assign(:order, order)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_params(params, _uri, socket) do
    filter = parse_filter(params["filter"])
    search = params |> Map.get("q", "") |> to_string() |> String.trim()

    socket =
      socket
      |> assign(:page_title, "Merch orders")
      |> assign(:order, nil)
      |> assign(:filter, filter)
      |> assign(:search, search)
      |> assign(:list_params, list_params(filter, search))

    {:noreply,
     if connected?(socket) do
       load_orders(socket, filter, search, params)
     else
       socket
     end}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/admin/merch/orders?#{list_params(socket.assigns.filter, String.trim(q))}"
     )}
  end

  def handle_event("clear-search", _params, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/admin/merch/orders?#{list_params(socket.assigns.filter, "")}"
     )}
  end

  def handle_event("retry", _params, %{assigns: %{order: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("retry", _params, socket) do
    order = socket.assigns.order

    case AdminOrders.retry_submission(order) do
      :ok ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :info,
           "Sent to Printful again.",
           title: order.reference_id
         )
         |> assign(:order, load_order(order.id))
         |> assign_attention_count()}

      {:error, reason} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, retry_error(reason),
           title: order.reference_id
         )
         |> assign(:order, load_order(order.id))}
    end
  end

  defp load_orders(socket, filter, search, params) do
    {orders, meta} =
      case AdminOrders.paginate_orders(filter, search, params) do
        {:ok, {orders, meta}} -> {orders, meta}
        {:error, meta} -> {[], meta}
      end

    socket
    |> assign(:orders, orders)
    |> assign(:meta, meta)
    |> assign_attention_count()
  end

  defp load_order(id) do
    case Orders.get_order(id) do
      nil -> nil
      order -> Repo.preload(order, :payment)
    end
  end

  defp assign_attention_count(socket),
    do: assign(socket, :attention_count, AdminOrders.needs_attention_count())

  # The query string for the list: only what is set, never a page (a new
  # filter or search starts from page 1).
  defp list_params(filter, search) do
    %{}
    |> then(&if(filter == :all, do: &1, else: Map.put(&1, :filter, filter)))
    |> then(&if(search == "", do: &1, else: Map.put(&1, :q, search)))
  end

  defp parse_filter(value) do
    Enum.find(AdminOrders.filters(), :all, &(Atom.to_string(&1) == value))
  end

  defp retry_error(:refunded),
    do: "The member's payment was refunded, so this order was not sent again."

  defp retry_error(:already_submitted),
    do: "Printful already has this order. Check it in Printful."

  defp retry_error(:not_failed), do: "This order is no longer failed."

  defp filter_label(filter), do: Map.fetch!(@filter_labels, filter)

  defp retryable?(order),
    do: order.status == :failed and is_nil(order.printful_order_id)

  defp placed_by(%{granted_by: %{} = admin}), do: UserDisplay.full_name(admin)
  defp placed_by(_), do: nil

  defp empty_title(_filter, search) when search != "", do: "No matching orders"
  defp empty_title(:needs_attention, _search), do: "All clear"
  defp empty_title(_filter, _search), do: "No orders"

  defp empty_suggestion(_filter, search) when search != "",
    do:
      "Nothing matches \"#{search}\". Try an order number, a name, an email or an item."

  defp empty_suggestion(:needs_attention, _search),
    do: "Nothing is waiting on you."

  defp empty_suggestion(:all, _search),
    do:
      "Orders appear here when a member buys something or an admin places a club-paid order."

  defp empty_suggestion(_filter, _search), do: "Try another filter."

  defp orders_count_text(total, search) do
    noun = if total == 1, do: "order", else: "orders"
    if search == "", do: "#{total} #{noun}", else: "#{total} #{noun} match"
  end

  @impl true
  def render(%{live_action: :show, order: nil} = assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <.admin_page_header subtitle="Loading this order.">
        Merch
      </.admin_page_header>

      <div class="w-full pt-4">
        <.admin_table_skeleton
          id="admin-merch-order-loading"
          rows={6}
          columns={2}
        />
      </div>
    </.side_menu>
    """
  end

  def render(%{order: nil} = assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <.admin_page_header subtitle="Everything members bought and everything the club paid for.">
        Merch
        <:actions>
          <.button id="new-club-order" navigate={~p"/admin/merch/orders/new"}>
            <.icon name="hero-plus" class="w-5 h-5" /> New club-paid order
          </.button>
        </:actions>
      </.admin_page_header>

      <div class="w-full pt-4">
        <.merch_tabs active={:orders} attention_count={@attention_count} />

        <.admin_search_bar
          id="orders-search-form"
          input_id="orders-search-input"
          name="q"
          value={@search}
          placeholder="Search by order number, name, email or item..."
          on_change="search"
          clear_event="clear-search"
          phx-submit="search"
        />

        <div id="orders-filters" class="flex flex-wrap gap-2 py-6">
          <.link
            :for={filter <- AdminOrders.filters()}
            id={"orders-filter-#{filter}"}
            patch={~p"/admin/merch/orders?#{list_params(filter, @search)}"}
            aria-current={@filter == filter && "true"}
            class={[
              "rounded-full px-4 py-2 text-sm font-semibold transition",
              if(@filter == filter,
                do: "bg-blue-600 text-white shadow-md",
                else: "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
              )
            ]}
          >
            {filter_label(filter)}
          </.link>
        </div>

        <.admin_table_skeleton
          :if={is_nil(@meta)}
          id="admin-merch-orders-loading"
          rows={8}
          columns={5}
        />

        <div :if={@meta}>
          <p id="orders-count" class="pb-4 text-sm text-zinc-500">
            {orders_count_text(@meta.total_count, @search)}
          </p>

          <.merch_orders_table
            id="admin_merch_orders_list"
            orders={@orders}
            row_navigate={&JS.navigate(~p"/admin/merch/orders/#{&1.id}")}
            empty_title={empty_title(@filter, @search)}
            empty_suggestion={empty_suggestion(@filter, @search)}
          />

          <.admin_flop_pagination
            meta={@meta}
            path={~p"/admin/merch/orders?#{@list_params}"}
            density={:comfortable}
          />
        </div>
      </div>
    </.side_menu>
    """
  end

  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <div class="flex flex-wrap items-start justify-between gap-4 py-6">
        <div>
          <.link
            id="back-to-orders"
            navigate={~p"/admin/merch/orders"}
            class="mb-3 inline-flex items-center gap-1 text-sm text-zinc-600 hover:text-zinc-900"
          >
            <.icon name="hero-arrow-left" class="size-4" /> All orders
          </.link>
          <div class="flex flex-wrap items-center gap-3">
            <.admin_page_title>
              <span class="font-mono">{@order.reference_id}</span>
            </.admin_page_title>
            <.order_kind_badge order={@order} />
            <.order_status_badge order={@order} />
          </div>
          <p class="mt-1 text-sm text-zinc-500">
            Placed {DateTimeDisplay.format_utc_date(@order.inserted_at)}<span :if={
              placed_by(@order)
            }> by {placed_by(@order)}</span>
          </p>
        </div>

        <div :if={retryable?(@order)} class="flex items-start">
          <.button
            id="retry-order"
            phx-click="retry"
            data-confirm="Send this order to Printful again?"
          >
            <.icon name="hero-arrow-path" class="w-5 h-5" /> Send to Printful again
          </.button>
        </div>
      </div>

      <div id="order-detail" class="w-full max-w-4xl space-y-10 pb-16 pt-4">
        <div
          :if={@order.status == :failed}
          id="order-failure"
          class="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800"
          role="alert"
        >
          <p class="font-semibold">This order did not reach Printful.</p>
          <p :if={@order.failure_reason} class="mt-1">{@order.failure_reason}</p>
          <p class="mt-2">
            <%= if @order.kind == :purchase do %>
              The member has paid. Send it again once the problem is fixed, or refund the payment from Money.
            <% else %>
              Fix the problem and send it again, or place a new order.
            <% end %>
          </p>
        </div>

        <div class="grid grid-cols-1 gap-10 md:grid-cols-2">
          <section id="order-recipient" class="space-y-3">
            <h2 class="text-lg text-zinc-800 type-subhead">Recipient</h2>
            <p class="text-sm text-zinc-900">
              <%= if @order.user do %>
                <.link
                  navigate={~p"/admin/users/#{@order.user.id}/details"}
                  class="font-semibold text-blue-600 hover:underline"
                >
                  {UserDisplay.full_name(@order.user)}
                </.link>
                <br />
              <% else %>
                <span class="font-semibold">{@order.recipient_name}</span>
                (not a member)<br />
              <% end %>
              <.shipping_address_lines address={@order} />
            </p>
            <p :if={@order.email} class="text-sm text-zinc-600">{@order.email}</p>
            <p :if={@order.phone} class="text-sm text-zinc-600">{@order.phone}</p>
          </section>

          <section id="order-money" class="space-y-3">
            <h2 class="text-lg text-zinc-800 type-subhead">Money</h2>
            <dl class="space-y-2 text-sm">
              <%= if @order.kind == :purchase do %>
                <div class="flex justify-between">
                  <dt class="text-zinc-500">Member paid</dt>
                  <dd id="money-paid" class="text-zinc-900">
                    {Ysc.MoneyHelper.format_money!(@order.total_amount)}
                  </dd>
                </div>
                <div class="flex justify-between">
                  <dt class="text-zinc-500">Items / shipping</dt>
                  <dd class="text-zinc-900">
                    {Ysc.MoneyHelper.format_money!(@order.subtotal)} / {Ysc.MoneyHelper.format_money!(
                      @order.shipping_amount
                    )}
                  </dd>
                </div>
              <% else %>
                <div class="flex justify-between">
                  <dt class="text-zinc-500">Member paid</dt>
                  <dd id="money-paid" class="text-zinc-900">
                    Nothing. The club pays.
                  </dd>
                </div>
              <% end %>
              <div class="flex justify-between">
                <dt class="text-zinc-500">
                  {if Ysc.Merch.Order.cost_estimated?(@order),
                    do: "Printful cost (estimate)",
                    else: "Printful cost"}
                </dt>
                <dd id="money-cost" class="text-zinc-900">
                  <%= if @order.printful_cost || @order.estimated_cost do %>
                    {Ysc.MoneyHelper.format_money!(Ysc.Merch.Order.cost(@order))}
                  <% else %>
                    Not reported yet
                  <% end %>
                </dd>
              </div>
              <div :if={@order.printful_order_id} class="flex justify-between">
                <dt class="text-zinc-500">Printful order</dt>
                <dd class="font-mono text-zinc-900">{@order.printful_order_id}</dd>
              </div>
            </dl>
            <p :if={@order.payment_id} class="text-sm">
              <.link
                id="order-payment-link"
                navigate={~p"/admin/money/payments/#{@order.payment_id}"}
                class="font-semibold text-blue-600 hover:underline"
              >
                View the payment
              </.link>
            </p>
          </section>
        </div>

        <section :if={@order.kind == :admin_comp} id="order-why" class="space-y-3">
          <h2 class="text-lg text-zinc-800 type-subhead">Why the club paid</h2>
          <p class="text-sm text-zinc-900">{@order.purpose}</p>
          <p :if={@order.event} class="text-sm text-zinc-600">
            For
            <.link
              id="order-event-link"
              navigate={~p"/admin/events/#{@order.event.id}/statistics"}
              class="font-semibold text-blue-600 hover:underline"
            >
              {@order.event.title}
            </.link>
          </p>
        </section>

        <section id="order-items" class="space-y-3">
          <h2 class="text-lg text-zinc-800 type-subhead">Items</h2>
          <ul class="divide-y divide-zinc-200 text-sm">
            <li
              :for={item <- @order.items}
              id={"order-item-#{item.id}"}
              class="flex justify-between py-2"
            >
              <span class="text-zinc-900">{item.quantity} × {item.name}</span>
              <span :if={@order.kind == :purchase} class="text-zinc-600">
                {Ysc.MoneyHelper.format_money!(
                  Money.mult!(item.unit_price, item.quantity)
                )}
              </span>
            </li>
          </ul>
        </section>

        <section :if={@order.shipments != []} id="order-shipments" class="space-y-3">
          <h2 class="text-lg text-zinc-800 type-subhead">Shipments</h2>
          <ul class="divide-y divide-zinc-200 text-sm">
            <li
              :for={shipment <- @order.shipments}
              id={"shipment-#{shipment.id}"}
              class="flex flex-wrap justify-between gap-2 py-2"
            >
              <span class="text-zinc-900">
                {shipment.carrier || "Carrier"}
                <span :if={shipment.service} class="text-zinc-500">· {shipment.service}</span>
                <span
                  :for={
                    {quantity, line} <-
                      Ysc.Merch.Shipment.contents(shipment, @order.items)
                  }
                  class="block text-zinc-500"
                >
                  {quantity} × {line.name}
                </span>
              </span>
              <span class="text-zinc-600">
                <%= if url = Ysc.Merch.Shipment.safe_tracking_url(shipment.tracking_url) do %>
                  <a
                    href={url}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="text-blue-600 hover:underline"
                  >
                    {shipment.tracking_number || "Track"}
                  </a>
                <% else %>
                  {shipment.tracking_number}
                <% end %>
              </span>
            </li>
          </ul>
        </section>
      </div>
    </.side_menu>
    """
  end
end
