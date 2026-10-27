defmodule YscWeb.AdminMerchComponents do
  @moduledoc """
  Pieces of the merch admin screens shared between the orders page and a
  member's admin detail page.
  """
  use Phoenix.Component
  use YscWeb, :verified_routes

  import YscWeb.AdminComponents
  import YscWeb.CoreComponents

  alias Ysc.Accounts.UserDisplay
  alias Ysc.Merch.Order
  alias Ysc.MoneyHelper
  alias YscWeb.ShopComponents

  @doc """
  The Products / Orders tabs at the top of the merch admin pages. Orders shows
  how many failed orders are waiting for an admin.
  """
  attr :active, :atom, values: [:products, :orders], required: true
  attr :attention_count, :integer, default: 0

  def merch_tabs(assigns) do
    ~H"""
    <.admin_tabs id="merch-tabs" aria_label="Merch tabs">
      <.admin_tab
        id="merch-tab-products"
        active={@active == :products}
        navigate={~p"/admin/merch"}
      >
        Products
      </.admin_tab>
      <.admin_tab
        id="merch-tab-orders"
        active={@active == :orders}
        navigate={~p"/admin/merch/orders"}
      >
        Orders
        <span :if={@attention_count > 0} id="merch-attention-count" class="ml-2">
          <.badge type="red">{@attention_count}</.badge>
        </span>
      </.admin_tab>
    </.admin_tabs>
    """
  end

  @doc "Badge naming who pays for an order."
  attr :order, Order, required: true

  def order_kind_badge(assigns) do
    ~H"""
    <.badge type={if(@order.kind == :admin_comp, do: "violet", else: "zinc")}>
      {if @order.kind == :admin_comp, do: "Club-paid", else: "Purchase"}
    </.badge>
    """
  end

  @doc "Badge for an order's progress."
  attr :order, Order, required: true

  def order_status_badge(assigns) do
    {label, type} = ShopComponents.status_display(assigns.order.status)
    assigns = assign(assigns, label: label, type: type)

    ~H"""
    <.badge type={@type}>{@label}</.badge>
    """
  end

  @doc """
  The money side of an order in a few words: what the member paid, or what
  Printful is charging the club.
  """
  def money_summary(%Order{kind: :purchase} = order),
    do: "Paid #{MoneyHelper.format_money!(order.total_amount)}"

  def money_summary(%Order{kind: :admin_comp} = order) do
    cond do
      order.printful_cost ->
        "Club pays #{MoneyHelper.format_money!(order.printful_cost)}"

      order.estimated_cost ->
        "Club pays ~#{MoneyHelper.format_money!(order.estimated_cost)}"

      true ->
        "Club pays (cost pending)"
    end
  end

  @doc "Who the order is for, in one line."
  def recipient_name(%Order{user: %{} = user}), do: UserDisplay.full_name(user)
  def recipient_name(%Order{recipient_name: name}), do: name

  @doc "Short item summary, e.g. `5 × Club Tee, 20 × Sticker`."
  def items_summary(%Order{items: items}) when is_list(items) do
    items
    |> Enum.map_join(", ", &"#{&1.quantity} × #{&1.name}")
  end

  def items_summary(_), do: ""

  attr :id, :string, required: true, doc: "id of the desktop table"
  attr :orders, :list, required: true
  attr :row_navigate, :any, default: nil, doc: "fn order -> JS command"
  attr :empty_title, :string, default: "No orders yet"
  attr :empty_suggestion, :string, default: ""
  attr :show_recipient?, :boolean, default: true

  def merch_orders_table(assigns) do
    ~H"""
    <.admin_list_empty_state
      :if={@orders == []}
      id={"#{@id}-empty"}
      title={@empty_title}
      suggestion={@empty_suggestion}
    />

    <div :if={@orders != []}>
      <.admin_mobile_list id={"#{@id}-mobile"}>
        <.admin_mobile_list_card
          :for={order <- @orders}
          id={"#{@id}-card-#{order.id}"}
          footer_align={:between}
        >
          <.link navigate={~p"/admin/merch/orders/#{order.id}"} class="mb-3 block">
            <p class="font-mono text-sm text-zinc-900">{order.reference_id}</p>
            <p :if={@show_recipient?} class="text-sm text-zinc-600">
              For {recipient_name(order)}
            </p>
            <p class="mt-1 text-sm text-zinc-600">{items_summary(order)}</p>
            <p class="mt-1 text-sm text-zinc-900">{money_summary(order)}</p>
          </.link>
          <:footer>
            <div class="flex items-center gap-2">
              <.order_kind_badge order={order} />
              <.order_status_badge order={order} />
            </div>
          </:footer>
        </.admin_mobile_list_card>
      </.admin_mobile_list>

      <div class="hidden md:block">
        <table id={@id}>
          <thead>
            <tr>
              <th>Order</th>
              <th :if={@show_recipient?}>For</th>
              <th>Items</th>
              <th>Money</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody id={"#{@id}-rows"}>
            <tr
              :for={order <- @orders}
              id={"#{@id}-row-#{order.id}"}
              class="cursor-pointer"
              phx-click={@row_navigate && @row_navigate.(order)}
            >
              <td>
                <p class="font-mono text-sm text-zinc-900">{order.reference_id}</p>
                <p class="text-xs text-zinc-500">
                  {Calendar.strftime(order.inserted_at, "%b %-d, %Y")}
                </p>
              </td>
              <td :if={@show_recipient?}>{recipient_name(order)}</td>
              <td class="max-w-xs truncate">{items_summary(order)}</td>
              <td>{money_summary(order)}</td>
              <td>
                <div class="flex items-center gap-2">
                  <.order_kind_badge order={order} />
                  <.order_status_badge order={order} />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
