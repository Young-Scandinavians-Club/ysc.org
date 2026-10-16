defmodule YscWeb.DevMerchLive do
  @moduledoc false
  # Dev-only: drives demo-mode Printful orders through production, shipping and
  # delivery (or trouble) so the member order page, emails, SMS and board alerts
  # can be tried without a real printer. Routed only when
  # `config :ysc, dev_routes: true`.

  use YscWeb, :live_view

  alias Ysc.Merch.Orders
  alias Ysc.Printful
  alias Ysc.Printful.{DemoClient, DemoEvents}

  @labels %{
    production: "Start production",
    ship: "Ship",
    deliver: "Deliver",
    return: "Return to sender",
    fail: "Fail",
    cancel: "Cancel",
    hold: "Put on hold"
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "[Dev] Merch orders")
     |> assign(:demo?, Printful.demo_mode?())
     |> load_orders()}
  end

  defp load_orders(%{assigns: %{demo?: true}} = socket) do
    rows =
      for demo <- DemoClient.list_orders() do
        %{
          demo: demo,
          order: Orders.get_order_by_reference(demo["external_id"] || "")
        }
      end

    assign(socket, :rows, rows)
  end

  defp load_orders(socket), do: assign(socket, :rows, [])

  @impl true
  def handle_event("trigger", %{"id" => id, "action" => action}, socket) do
    action = Enum.find(DemoEvents.actions(), &(Atom.to_string(&1) == action))

    socket =
      case action && DemoEvents.trigger(String.to_integer(id), action) do
        {:ok, type} ->
          # The event is processed by a job; look again shortly.
          Process.send_after(self(), :refresh, 800)
          put_flash(socket, :info, "Sent #{type}")

        _ ->
          put_flash(socket, :error, "Could not apply that to the demo order")
      end

    {:noreply, load_orders(socket)}
  end

  def handle_event("refresh", _params, socket),
    do: {:noreply, load_orders(socket)}

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load_orders(socket)}

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :labels, @labels)

    ~H"""
    <div class="mx-auto max-w-5xl space-y-8 px-4 py-10">
      <div>
        <h1 class="type-title text-3xl text-zinc-900">Demo printer</h1>
        <p class="mt-2 text-zinc-600">
          Orders sent to the demo Printful. Each button sends the same event Printful would, so
          emails, texts and the member's order page behave for real. Check
          <.link href="/dev/mailbox" class="text-blue-600 underline">/dev/mailbox</.link>
          for the emails.
        </p>
      </div>

      <p
        :if={!@demo?}
        id="dev-merch-not-demo"
        class="rounded-2xl bg-amber-50 p-4 text-amber-900"
      >
        The demo printer is only used when PRINTFUL_API_TOKEN is unset.
      </p>

      <p
        :if={@demo? and @rows == []}
        id="dev-merch-empty"
        class="rounded-2xl bg-zinc-50 p-8 text-zinc-600"
      >
        No demo orders yet. Buy something in the shop first.
      </p>

      <ul :if={@rows != []} id="dev-merch-orders" class="space-y-4">
        <li
          :for={%{demo: demo, order: order} <- @rows}
          id={"demo-order-#{demo["id"]}"}
          class="space-y-4 rounded-2xl bg-zinc-50 p-6"
        >
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <p class="text-lg text-zinc-900">{demo["external_id"]}</p>
            <p class="text-sm text-zinc-500">
              Printful: <span class="font-medium">{demo["status"]}</span>
              <span :if={order}>
                · Ours: <span class="font-medium">{order.status}</span>
              </span>
              · {length(demo["shipments"] || [])} shipment(s)
            </p>
          </div>

          <div class="flex flex-wrap gap-2">
            <button
              :for={action <- DemoEvents.actions()}
              type="button"
              id={"demo-#{demo["id"]}-#{action}"}
              phx-click="trigger"
              phx-value-id={demo["id"]}
              phx-value-action={action}
              class="inline-flex min-h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-zinc-900 shadow-xs transition hover:bg-zinc-100 active:scale-[0.97]"
            >
              {Map.fetch!(@labels, action)}
            </button>
          </div>

          <.link
            :if={order}
            navigate={~p"/shop/orders/#{order.id}"}
            class="text-sm text-blue-600 hover:underline"
          >
            View as the member
          </.link>
        </li>
      </ul>

      <button
        type="button"
        id="dev-merch-refresh"
        phx-click="refresh"
        class="text-sm text-zinc-500 hover:text-zinc-900"
      >
        Refresh
      </button>
    </div>
    """
  end
end
