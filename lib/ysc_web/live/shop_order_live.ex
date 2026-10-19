defmodule YscWeb.ShopOrderLive do
  @moduledoc """
  A single merch order: the receipt, where it is in fulfillment, and (as the
  Stripe return page) confirmation that payment went through.

  Stripe sends members back here after paying. The page never trusts the
  query string; it asks `Ysc.Merch.Fulfillment` to settle the order from
  Stripe's own record, which is idempotent with the webhook.
  """
  use YscWeb, :live_view

  import YscWeb.ShopComponents

  alias Ysc.Merch.{Cart, Fulfillment, Orders}

  @recheck_ms 2_000
  @max_rechecks 8

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case Orders.get_user_order(user, id) do
      nil ->
        {:ok,
         socket
         |> YscWeb.Flash.put_toast(:error, "We couldn't find that order.",
           title: "Shop"
         )
         |> push_navigate(to: ~p"/shop/orders")}

      order ->
        socket =
          socket
          |> assign(:page_title, "Order #{order.reference_id}")
          |> assign(:order, order)
          |> assign(:rechecks, 0)
          |> assign(:payment_delayed?, false)
          |> assign(:cart_count, Cart.count(user))

        if connected?(socket) and awaiting_payment?(order) do
          send(self(), :settle_payment)
        end

        {:ok, socket}
    end
  end

  defp awaiting_payment?(order),
    do: order.status == :pending and not is_nil(order.payment_intent_id)

  @impl true
  def handle_info(:settle_payment, socket) do
    order = socket.assigns.order

    case Fulfillment.process_successful_payment(order.payment_intent_id) do
      {:ok, paid} ->
        {:noreply,
         socket
         |> assign(
           :order,
           Orders.get_user_order(socket.assigns.current_user, paid.id) || paid
         )
         |> assign(:payment_delayed?, false)}

      {:error, :not_succeeded} ->
        recheck(socket)

      {:error, _reason} ->
        {:noreply, assign(socket, :payment_delayed?, true)}
    end
  end

  defp recheck(%{assigns: %{rechecks: rechecks}} = socket)
       when rechecks >= @max_rechecks do
    {:noreply, assign(socket, :payment_delayed?, true)}
  end

  defp recheck(socket) do
    Process.send_after(self(), :settle_payment, @recheck_ms)
    {:noreply, update(socket, :rechecks, &(&1 + 1))}
  end

  defp sorted_shipments(order),
    do: Enum.sort_by(order.shipments, & &1.shipped_at, {:asc, DateTime})

  defp shipment_status_text(%{status: :delivered, delivered_at: at})
       when not is_nil(at),
       do: "Delivered #{Calendar.strftime(at, "%b %-d")}"

  defp shipment_status_text(%{status: :delivered}), do: "Delivered"
  defp shipment_status_text(%{status: :returned}), do: "Returned to sender"

  defp shipment_status_text(%{shipped_at: at}) when not is_nil(at),
    do: "Shipped #{Calendar.strftime(at, "%b %-d")}"

  defp shipment_status_text(_), do: "Shipped"

  # Steps shown to the member, with how far along the order is.
  @steps [
    {:paid, "Order placed", "hero-check"},
    {:in_production, "In production", "hero-printer"},
    {:shipped, "Shipped", "hero-truck"},
    {:delivered, "Delivered", "hero-home"}
  ]

  defp progress(order) do
    reached =
      case order.status do
        status when status in [:paid, :submitting, :submitted] -> 1
        :in_production -> 2
        :shipped -> 3
        :delivered -> 4
        _ -> 0
      end

    @steps
    |> Enum.with_index(1)
    |> Enum.map(fn {{key, label, icon}, index} ->
      %{
        key: key,
        label: label,
        icon: icon,
        done?: index <= reached,
        # The connector after this step is filled once the next one is reached.
        linked?: index < reached,
        current?: index == reached + 1
      }
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shop_frame
      id="shop-order-page"
      title="Your Order"
      active={:orders}
      cart_count={@cart_count}
    >
      <div class="space-y-10">
        <.status_banner
          order={@order}
          live_action={@live_action}
          payment_delayed?={@payment_delayed?}
        />

        <div class="grid grid-cols-1 gap-12 lg:grid-cols-3 lg:gap-16">
          <div class="space-y-10 lg:col-span-2">
            <header id="order-header" class="space-y-2">
              <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
                <p id="order-reference" class="font-mono text-xl text-zinc-900">
                  {@order.reference_id}
                </p>
                <.order_status_badge order={@order} />
              </div>
              <p class="text-zinc-500">
                Placed {Calendar.strftime(@order.inserted_at, "%B %-d, %Y")}
              </p>
              <p
                :if={delivery_estimate(@order)}
                id="order-delivery-estimate"
                class="text-lg text-zinc-900"
              >
                Estimated delivery {delivery_estimate(@order)}
              </p>
            </header>

            <ol
              :if={@order.status not in [:pending, :failed, :canceled, :refunded]}
              id="order-progress"
              class="grid grid-cols-4 text-center text-sm"
            >
              <li
                :for={step <- progress(@order)}
                id={"progress-#{step.key}"}
                class="relative space-y-3"
              >
                <span
                  :if={step.key != :delivered}
                  aria-hidden="true"
                  class={[
                    "absolute left-1/2 top-5 h-0.5 w-full -translate-y-1/2",
                    if(step.linked?, do: "bg-green-600", else: "bg-zinc-100")
                  ]}
                ></span>
                <span class={[
                  "relative mx-auto flex size-10 items-center justify-center rounded-full ring-4 ring-white",
                  cond do
                    step.done? -> "bg-green-600 text-white"
                    step.current? -> "bg-blue-50 text-blue-600"
                    true -> "bg-zinc-100 text-zinc-400"
                  end
                ]}>
                  <.icon name={step.icon} class="size-5" />
                </span>
                <span class={[
                  "block",
                  if(step.done? or step.current?,
                    do: "text-zinc-900",
                    else: "text-zinc-500"
                  )
                ]}>
                  {step.label}
                </span>
              </li>
            </ol>

            <section class="rounded-3xl bg-zinc-50 p-6 md:p-8">
              <h2 class="type-subhead mb-6 text-xl text-zinc-900">Items</h2>
              <.order_summary order={@order} />
            </section>

            <section :if={@order.shipments != []} id="order-tracking">
              <h2 class="type-subhead mb-4 text-xl text-zinc-900">Tracking</h2>
              <ul class="space-y-3">
                <li
                  :for={shipment <- sorted_shipments(@order)}
                  id={"shipment-#{shipment.id}"}
                  class="flex flex-wrap items-center justify-between gap-4 rounded-2xl bg-zinc-50 p-5"
                >
                  <div class="min-w-0">
                    <p class="text-lg text-zinc-900">
                      {shipment.carrier || "Carrier"}
                      <span :if={shipment.service} class="text-zinc-500">· {shipment.service}</span>
                    </p>
                    <p class="text-zinc-500">
                      {shipment_status_text(shipment)}
                      <span :if={shipment.tracking_number}>· {shipment.tracking_number}</span>
                    </p>
                  </div>
                  <.link
                    :if={
                      Ysc.Merch.Shipment.safe_tracking_url(shipment.tracking_url)
                    }
                    id={"track-#{shipment.id}"}
                    href={
                      Ysc.Merch.Shipment.safe_tracking_url(shipment.tracking_url)
                    }
                    target="_blank"
                    rel="noopener noreferrer"
                    class="inline-flex min-h-11 items-center gap-2 rounded-sm bg-zinc-900 px-5 text-sm font-semibold text-white transition hover:bg-zinc-700 motion-safe:active:scale-[0.97]"
                  >
                    Track package
                    <.icon name="hero-arrow-top-right-on-square" class="size-4" />
                  </.link>
                </li>
              </ul>
            </section>
          </div>

          <aside class="space-y-10 lg:sticky lg:top-28 lg:self-start">
            <section id="order-ship-to" class="rounded-3xl bg-zinc-50 p-6 md:p-8">
              <h2 class="type-subhead mb-3 text-xl text-zinc-900">Shipping to</h2>
              <p class="text-lg text-zinc-700">
                {@order.recipient_name}<br />
                {@order.address1}<br />
                <span :if={@order.address2 not in [nil, ""]}>{@order.address2}<br /></span>
                {@order.city}, {@order.state_code} {@order.zip}
              </p>
            </section>

            <div class="flex flex-col items-start gap-6 text-zinc-500">
              <p>
                Questions? Email
                <a
                  class="text-blue-600 hover:underline"
                  href={"mailto:info@ysc.org?subject=Order%20#{@order.reference_id}"}
                >info@ysc.org</a>
                and mention {@order.reference_id}.
              </p>
              <.shop_secondary_link id="order-back-to-shop" navigate={~p"/shop"}>
                Back to the shop
              </.shop_secondary_link>
            </div>
          </aside>
        </div>
      </div>
    </.shop_frame>
    """
  end

  attr :order, :any, required: true
  attr :live_action, :atom, required: true
  attr :payment_delayed?, :boolean, default: false

  defp status_banner(%{order: %{status: :pending}} = assigns) do
    ~H"""
    <div
      id="order-banner-pending"
      class="rounded-3xl bg-yellow-50 p-6 md:p-8"
      role="status"
    >
      <%= if @payment_delayed? do %>
        <h2 class="type-subhead text-xl text-yellow-900">
          We're still waiting on your payment
        </h2>
        <p class="mt-2 text-yellow-800">
          If you've just paid, it can take a minute to arrive. We'll email you as soon as it does,
          and you can refresh this page.
        </p>
      <% else %>
        <h2 class="type-subhead text-xl text-yellow-900">
          Confirming your payment…
        </h2>
        <p class="mt-2 text-yellow-800">This only takes a moment.</p>
      <% end %>
    </div>
    """
  end

  defp status_banner(%{order: %{status: :failed}} = assigns) do
    ~H"""
    <div
      id="order-banner-failed"
      class="rounded-3xl bg-red-50 p-6 md:p-8"
      role="alert"
    >
      <h2 class="type-subhead text-xl text-red-900">
        There's a problem with your order
      </h2>
      <p class="mt-2 text-red-800">
        Your payment went through, but we couldn't send your order to our printer. The club has been
        alerted and will be in touch; you can also email <a
          class="underline"
          href="mailto:info@ysc.org"
        >info@ysc.org</a>.
      </p>
    </div>
    """
  end

  defp status_banner(%{order: %{status: status}} = assigns)
       when status in [:canceled, :refunded] do
    ~H"""
    <div id="order-banner-closed" class="rounded-3xl bg-zinc-100 p-6 md:p-8">
      <h2 class="type-subhead text-xl text-zinc-900">
        {if @order.status == :refunded,
          do: "This order was refunded",
          else: "This order was canceled"}
      </h2>
    </div>
    """
  end

  defp status_banner(%{live_action: :confirmation} = assigns) do
    ~H"""
    <div
      id="order-banner-confirmed"
      class="rounded-3xl bg-green-50 p-6 md:p-8"
      role="status"
    >
      <h2 class="type-subhead text-2xl text-green-900">
        Thank you! Your order is confirmed.
      </h2>
      <p class="mt-2 text-lg text-green-800">
        We've emailed your receipt. Everything is printed to order, so it usually ships in 2–5
        business days. We'll email you again with tracking.
      </p>
    </div>
    """
  end

  defp status_banner(assigns), do: ~H""

  # Only while something is still on its way.
  defp delivery_estimate(%{status: status})
       when status in [:failed, :canceled, :refunded, :delivered],
       do: nil

  defp delivery_estimate(order), do: Ysc.Merch.Shipping.delivery_estimate(order)
end
