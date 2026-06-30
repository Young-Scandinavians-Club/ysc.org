defmodule YscWeb.OrderConfirmationLive do
  use YscWeb, :live_view

  require Ysc.Logging

  alias YscWeb.PaymentMethodFormatter
  alias YscWeb.PaymentMethodLogo
  alias Ysc.Tickets
  alias Ysc.Tickets.DonationDisplay
  alias Ysc.Ledgers.Refund
  alias Ysc.MoneyHelper
  alias Ysc.Repo
  import Ecto.Query

  @impl true
  def mount(%{"order_id" => order_id} = params, _session, socket) do
    user = socket.assigns.current_user

    if is_nil(user) do
      {:ok,
       socket
       |> YscWeb.Flash.put_toast(
         :error,
         "You must be signed in to view this order.",
         title: "Order"
       )
       |> redirect(to: ~p"/events")}
    else
      show_confetti = Map.get(params, "confetti") == "true"

      socket =
        socket
        |> assign(:loading_order_confirmation, true)
        |> assign(:order_id, order_id)
        |> assign(:show_confetti, show_confetti)
        |> assign(:page_title, "Order Confirmation")
        |> assign(
          :meta_description,
          "Your ticket order confirmation from Young Scandinavians Club."
        )

      if connected?(socket) do
        {:ok, load_order_confirmation(socket, user, order_id)}
      else
        {:ok, socket}
      end
    end
  end

  defp load_order_confirmation(socket, user, order_id) do
    case Tickets.get_user_ticket_order_for_confirmation(user.id, order_id) do
      nil ->
        socket
        |> YscWeb.Flash.put_toast(:error, "Order not found", title: "Order")
        |> redirect(to: ~p"/events")

      ticket_order ->
        event = ticket_order.event

        socket
        |> assign(:loading_order_confirmation, false)
        |> assign(:ticket_order, ticket_order)
        |> assign(:event, event)
        |> assign(:user_first_name, user.first_name || "Member")
        |> assign(:event_in_past, event_in_past?(event))
        |> assign(:refund_data, nil)
        |> assign(
          :payment_method_description,
          payment_method_description_without_stripe(ticket_order.payment)
        )
        |> assign(
          :payment_method_logo,
          PaymentMethodLogo.path_for_payment(ticket_order.payment)
        )
        |> assign(
          :donation_amounts_by_ticket_id,
          DonationDisplay.amounts_by_ticket_id(ticket_order)
        )
        |> assign(:async_data_loaded, false)
        |> load_order_data_async(ticket_order)
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/events/#{socket.assigns.event.id}")}
  end

  @impl true
  def handle_event("view-tickets", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/users/tickets")}
  end

  @impl true
  def handle_event("view-event", _params, socket) do
    {:noreply,
     push_navigate(socket, to: ~p"/events/#{socket.assigns.event.id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      :if={@loading_order_confirmation}
      id="order-confirmation-loading"
      class="py-8 lg:py-10 max-w-screen-xl mx-auto px-4"
      role="status"
      aria-live="polite"
    >
      <span class="sr-only">Loading order confirmation…</span>
      <!-- Header skeleton -->
      <div class="mb-10 flex flex-col md:flex-row md:items-end justify-between gap-4 border-b border-zinc-100 pb-8">
        <div class="space-y-3">
          <.skeleton_block class="h-3 w-32 rounded" />
          <.skeleton_block class="h-9 w-80 rounded" />
          <.skeleton_block class="h-4 w-64 rounded" />
        </div>
        <div class="space-y-2 md:text-right">
          <.skeleton_block class="h-3 w-28 rounded md:ml-auto" />
          <.skeleton_block class="h-5 w-24 rounded md:ml-auto" />
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-10">
        <!-- Left Column skeleton -->
        <div class="lg:col-span-2 space-y-8">
          <div class="bg-zinc-50 rounded-lg border border-zinc-200 overflow-hidden">
            <.skeleton_block class="h-48 w-full rounded-none" />
            <div class="p-8 grid grid-cols-1 md:grid-cols-3 gap-8">
              <div :for={_ <- 1..3} class="space-y-2">
                <.skeleton_block class="h-3 w-16 rounded" />
                <.skeleton_block class="h-5 w-24 rounded" />
              </div>
            </div>
          </div>
          <div class="bg-white rounded-lg border border-zinc-200 p-6 space-y-3">
            <.skeleton_block :for={_ <- 1..2} class="h-20 w-full rounded-lg" />
          </div>
        </div>
        <!-- Right Column skeleton -->
        <aside class="space-y-6">
          <.payment_summary_skeleton announce?={false} />
          <.skeleton_block class="h-12 w-full rounded-lg" />
          <.skeleton_block class="h-12 w-full rounded-lg" />
        </aside>
      </div>
    </div>
    <div
      :if={!@loading_order_confirmation}
      id="order-confirmation"
      phx-hook="Confetti"
      data-show-confetti={if @show_confetti, do: "true", else: "false"}
      class="py-8 lg:py-10 max-w-screen-xl mx-auto px-4"
    >
      <!-- Header -->
      <div class="mb-10 flex flex-col md:flex-row md:items-end justify-between gap-4 border-b border-zinc-100 pb-8">
        <div>
          <%= if @ticket_order.status == :cancelled do %>
            <div class="flex items-center gap-2 text-red-600 mb-2">
              <.icon name="hero-x-circle" class="w-6 h-6" />
              <span class="font-bold uppercase tracking-wider text-sm">
                Order Cancelled
              </span>
            </div>
            <h1 class="text-4xl font-bold text-zinc-900">
              Order Cancelled
            </h1>
            <p class="text-zinc-500 mt-2 text-lg">
              Your order for <strong>{@event.title}</strong>
              has been cancelled.
              <%= if @refund_data && @refund_data.total_refunded do %>
                A refund of
                <strong>
                  {MoneyHelper.format_money!(@refund_data.total_refunded)}
                </strong>
                has been processed.
              <% else %>
                Refund information is shown in the payment summary on the right.
              <% end %>
            </p>
          <% else %>
            <div class="flex items-center gap-2 text-green-600 mb-2">
              <.icon name="hero-check-circle-solid" class="w-6 h-6" />
              <span class="font-bold uppercase tracking-wider text-sm">
                Order Confirmed
              </span>
            </div>
            <h1 class="text-4xl font-bold text-zinc-900">
              <%= if @event_in_past do %>
                Hope you had a blast, {@user_first_name}!
              <% else %>
                See you at the event, {@user_first_name}!
              <% end %>
            </h1>
            <p class="text-zinc-500 mt-2 text-lg">
              <%= if @event_in_past do %>
                Thanks for coming to <strong>{@event.title}</strong>. See you at the next one!
              <% else %>
                Your tickets for <strong>{@event.title}</strong> are confirmed.
                We've sent a copy of these details to your email.
              <% end %>
            </p>
          <% end %>
        </div>
        <div class="text-left md:text-right">
          <p class="text-xs font-bold text-zinc-400 uppercase tracking-widest">
            Order Reference
          </p>
          <p class="font-mono text-lg font-semibold text-zinc-900 whitespace-nowrap">
            {@ticket_order.reference_id}
          </p>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-10">
        <!-- Left Column: Main Content -->
        <div class="lg:col-span-2 space-y-8">
          <!-- Event Details Card -->
          <div class="bg-zinc-50 rounded-lg border border-zinc-200 overflow-hidden">
            <!-- Event Cover Image -->
            <div class="h-48 bg-zinc-200 relative overflow-hidden">
              <%= if @event.cover_image do %>
                <.live_component
                  id={"order-confirmation-event-cover-#{@event.id}"}
                  module={YscWeb.Components.Image}
                  image_id={@event.image_id}
                  image={@event.cover_image}
                  preferred_type={:optimized}
                  class="w-full h-full object-cover relative z-0"
                />
              <% else %>
                <div class="w-full h-full bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center relative z-0">
                  <div class="text-center text-white">
                    <.icon
                      name="hero-calendar"
                      class="w-16 h-16 mx-auto mb-4 opacity-50"
                    />
                    <p class="text-xl font-semibold">{@event.title}</p>
                  </div>
                </div>
              <% end %>
              <div class="absolute inset-0 bg-gradient-to-t from-black/40 to-transparent flex items-end p-6 z-10">
                <div class="flex items-center justify-between w-full">
                  <h2 class="text-white text-xl font-bold flex items-center gap-2">
                    <.icon name="hero-information-circle" class="w-8 h-8" />
                    Event Details
                  </h2>
                  <% ticket_count = non_donation_ticket_count(@ticket_order.tickets) %>
                  <span
                    id="event-details-ticket-count-badge"
                    class="text-sm font-medium bg-blue-100 text-blue-700 px-3 py-1 rounded-full"
                  >
                    {ticket_count} {if ticket_count == 1,
                      do: "Ticket",
                      else: "Tickets"}
                  </span>
                </div>
              </div>
            </div>
            <div class="p-8 grid grid-cols-1 md:grid-cols-3 gap-8 relative z-0">
              <div>
                <p class="text-xs font-bold text-zinc-400 uppercase mb-1">Event</p>
                <p class="text-xl font-bold text-zinc-900">{@event.title}</p>
              </div>
              <div>
                <p class="text-xs font-bold text-zinc-400 uppercase mb-1">
                  Date & Time
                </p>
                <p class="text-xl font-bold text-zinc-900">
                  <%= if @event.start_date do %>
                    {format_event_date(@event.start_date)}
                  <% else %>
                    TBD
                  <% end %>
                </p>
                <p class="text-sm text-zinc-500">
                  <%= if @event.start_time do %>
                    {Calendar.strftime(@event.start_time, "%I:%M %p")}
                  <% else %>
                    Time TBD
                  <% end %>
                </p>
              </div>
              <div>
                <p class="text-xs font-bold text-zinc-400 uppercase mb-1">
                  Location
                </p>
                <p class="text-xl font-bold text-zinc-900">
                  <%= if @event.location_name do %>
                    {@event.location_name}
                  <% else %>
                    TBD
                  <% end %>
                </p>
                <p :if={@event.address} class="text-sm text-zinc-500">
                  {@event.address}
                </p>
              </div>
            </div>
          </div>
          <!-- Tickets Card -->
          <div
            id="order-confirmation-items-section"
            class="bg-white rounded-lg border border-zinc-200 overflow-hidden"
          >
            <div class="px-6 py-4 border-b border-zinc-200 bg-zinc-50 flex items-center justify-between gap-4">
              <h2
                id="order-items-section-title"
                class="text-lg font-semibold text-zinc-900 flex items-center gap-2"
              >
                <.icon
                  name={
                    if order_has_donations?(@ticket_order.tickets) &&
                         non_donation_ticket_count(@ticket_order.tickets) == 0,
                       do: "hero-heart",
                       else: "hero-ticket"
                  }
                  class="w-5 h-5"
                />
                <span id="order-items-section-title-text">
                  {order_items_section_title(@ticket_order.tickets)}
                </span>
              </h2>
              <%= if @ticket_order.status != :cancelled do %>
                <.link
                  navigate={~p"/tickets/#{@ticket_order.id}/qr" <> "?return_to=/orders/#{@ticket_order.id}/confirmation"}
                  class="inline-flex items-center gap-1.5 text-sm font-semibold text-zinc-700 bg-zinc-100 hover:bg-zinc-200 px-3 py-1.5 rounded transition-colors shrink-0"
                >
                  <.icon name="hero-qr-code" class="w-4 h-4" />
                  View tickets for check-in
                </.link>
              <% end %>
            </div>
            <div class="px-6 py-4">
              <div class="space-y-3">
                <%= for ticket <- @ticket_order.tickets do %>
                  <% is_refunded = ticket.status == :cancelled %>
                  <% is_donation = donation_ticket?(ticket) %>
                  <% requires_registration =
                    ticket.ticket_tier.requires_registration == true %>
                  <% ticket_detail = ticket.registration %>
                  <div class={[
                    "p-4 rounded-lg border",
                    cond do
                      is_refunded -> "bg-red-50 border-red-200 opacity-60"
                      is_donation -> "bg-amber-50 border-amber-200"
                      true -> "bg-zinc-50 border-zinc-200"
                    end
                  ]}>
                    <div class="flex justify-between items-start mb-3">
                      <div class="flex-1">
                        <div class="flex items-center gap-2 flex-wrap">
                          <p class={[
                            "font-semibold",
                            if(is_refunded,
                              do: "text-zinc-500 line-through",
                              else: "text-zinc-900"
                            )
                          ]}>
                            {ticket.ticket_tier.name}
                          </p>
                          <%= if is_donation do %>
                            <span
                              id={"donation-badge-#{ticket.id}"}
                              class="text-xs font-bold text-amber-800 bg-amber-100 px-2 py-0.5 rounded"
                            >
                              Donation
                            </span>
                          <% end %>
                          <%= if is_refunded do %>
                            <span class="text-xs font-bold text-red-600 bg-red-100 px-2 py-0.5 rounded">
                              Refunded
                            </span>
                          <% end %>
                        </div>
                        <%= if is_donation do %>
                          <p
                            id={"donation-not-event-ticket-#{ticket.id}"}
                            class={[
                              "text-sm mt-1",
                              if(is_refunded,
                                do: "text-zinc-400",
                                else: "text-amber-900"
                              )
                            ]}
                          >
                            Not an event ticket — thank you for your support.
                          </p>
                          <p class={[
                            "text-sm font-mono mt-1",
                            if(is_refunded,
                              do: "text-zinc-400",
                              else: "text-zinc-500"
                            )
                          ]}>
                            Reference {ticket.reference_id}
                          </p>
                        <% else %>
                          <p class={[
                            "text-sm font-mono",
                            if(is_refunded,
                              do: "text-zinc-400",
                              else: "text-zinc-500"
                            )
                          ]}>
                            Ticket #{ticket.reference_id}
                          </p>
                        <% end %>
                      </div>
                      <div class="text-right">
                        <% ticket_discount =
                          ticket.discount_amount || Money.new(0, :USD) %>
                        <% has_discount = Money.positive?(ticket_discount) %>
                        <% original_price =
                          ticket.ticket_tier.price || Money.new(0, :USD) %>
                        <% final_price =
                          if has_discount do
                            case Money.sub(original_price, ticket_discount) do
                              {:ok, price} -> price
                              _ -> original_price
                            end
                          else
                            original_price
                          end %>
                        <p class={[
                          "font-bold text-lg",
                          if(is_refunded,
                            do: "text-zinc-400 line-through",
                            else: "text-zinc-900"
                          )
                        ]}>
                          <%= cond do %>
                            <% is_donation -> %>
                              {Map.get(
                                @donation_amounts_by_ticket_id,
                                ticket.id,
                                "Donation"
                              )}
                            <% ticket.ticket_tier.price == nil -> %>
                              Free
                            <% Money.zero?(ticket.ticket_tier.price) -> %>
                              Free
                            <% true -> %>
                              <%= if has_discount && !is_refunded do %>
                                <div class="flex flex-col items-end">
                                  <span class="line-through text-zinc-400 text-sm">
                                    {MoneyHelper.format_money!(original_price)}
                                  </span>
                                  <span>
                                    {MoneyHelper.format_money!(final_price)}
                                  </span>
                                </div>
                              <% else %>
                                {MoneyHelper.format_money!(original_price)}
                              <% end %>
                          <% end %>
                        </p>
                      </div>
                    </div>
                    <% has_ticket_discount =
                      has_discount && !is_refunded && !is_donation %>
                    <%= if has_ticket_discount do %>
                      <% discount_percentage =
                        ticket_discount_percentage(
                          ticket_discount,
                          ticket.ticket_tier.price
                        ) %>
                      <div class="mt-3 pt-3 border-t border-zinc-300">
                        <div class="flex justify-between text-xs text-green-600">
                          <span>
                            Member discount<%= if discount_percentage do %>
                              ({discount_percentage}%)
                            <% end %>
                          </span>
                          <span class="font-medium">
                            -{MoneyHelper.format_money!(ticket_discount)}
                          </span>
                        </div>
                      </div>
                    <% end %>
                    <%= if requires_registration && ticket_detail && !is_donation do %>
                      <div class={[
                        "pt-3 border-t border-zinc-300",
                        if(has_ticket_discount, do: "mt-3", else: "mt-3")
                      ]}>
                        <p class="text-xs font-semibold text-zinc-500 uppercase tracking-wider mb-2">
                          Registration Details
                        </p>
                        <div class="space-y-1 text-sm">
                          <p class="text-zinc-700">
                            <span class="font-medium">Name:</span>
                            {ticket_detail.first_name} {ticket_detail.last_name}
                          </p>
                          <p class="text-zinc-700">
                            <span class="font-medium">Email:</span>
                            <a
                              href={"mailto:#{ticket_detail.email}"}
                              class="text-blue-600 hover:text-blue-500 underline"
                            >
                              {ticket_detail.email}
                            </a>
                          </p>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
            <%= if @ticket_order.status != :cancelled do %>
              <div class="px-6 pb-6">
                <.link
                  navigate={~p"/tickets/#{@ticket_order.id}/qr" <> "?return_to=/orders/#{@ticket_order.id}/confirmation"}
                  class="inline-flex items-center justify-center w-full rounded py-3 px-3 bg-zinc-900 hover:bg-zinc-800 text-zinc-100 active:text-zinc-100/80 active:scale-[0.98] transition duration-150 ease-in-out text-sm font-semibold leading-6"
                >
                  <.icon name="hero-qr-code" class="w-5 h-5 -mt-0.5 me-2" />Open tickets for check-in
                </.link>
              </div>
            <% end %>
          </div>
        </div>
        <!-- Right Column: Sidebar -->
        <aside class="space-y-6">
          <!-- Payment Summary -->
          <div class={[
            "rounded-lg p-8 shadow-xl",
            if(
              @ticket_order.status == :cancelled ||
                (@refund_data && @refund_data.total_refunded),
              do: "bg-red-50 border-2 border-red-200",
              else: "bg-zinc-900 text-white"
            )
          ]}>
            <h3 class={[
              "text-xs font-bold uppercase tracking-widest mb-6",
              if(
                @ticket_order.status == :cancelled ||
                  (@refund_data && @refund_data.total_refunded),
                do: "text-red-700",
                else: "text-zinc-400"
              )
            ]}>
              {if @ticket_order.status == :cancelled ||
                    (@refund_data && @refund_data.total_refunded),
                  do: "Payment & Refund Summary",
                  else: "Payment Summary"}
            </h3>
            <div class={[
              "space-y-4 text-sm",
              if(
                @ticket_order.status == :cancelled ||
                  (@refund_data && @refund_data.total_refunded),
                do: "text-zinc-900",
                else: ""
              )
            ]}>
              <% total_discount =
                @ticket_order.discount_amount || Money.new(0, :USD) %>
              <% has_discount = Money.positive?(total_discount) %>
              <%= if has_discount do %>
                <% gross_total =
                  case Money.add(@ticket_order.total_amount, total_discount) do
                    {:ok, total} -> total
                    _ -> @ticket_order.total_amount
                  end %>
                <div class="flex justify-between">
                  <span class={
                    if(
                      @ticket_order.status == :cancelled ||
                        (@refund_data && @refund_data.total_refunded),
                      do: "text-zinc-600",
                      else: "text-zinc-400"
                    )
                  }>
                    Subtotal
                  </span>
                  <span class={
                    if(
                      @ticket_order.status == :cancelled ||
                        (@refund_data && @refund_data.total_refunded),
                      do: "text-zinc-900",
                      else: "text-zinc-400"
                    )
                  }>
                    {MoneyHelper.format_money!(gross_total)}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class={
                    if(
                      @ticket_order.status == :cancelled ||
                        (@refund_data && @refund_data.total_refunded),
                      do: "text-zinc-600",
                      else: "text-zinc-400"
                    )
                  }>
                    Discount
                  </span>
                  <span class={[
                    "font-medium",
                    if(
                      @ticket_order.status == :cancelled ||
                        (@refund_data && @refund_data.total_refunded),
                      do: "text-green-600",
                      else: "text-green-400"
                    )
                  ]}>
                    -{MoneyHelper.format_money!(total_discount)}
                  </span>
                </div>
              <% end %>
              <div class={[
                "flex justify-between",
                if(has_discount, do: "border-t pt-4", else: "")
              ]}>
                <span class={
                  if(
                    @ticket_order.status == :cancelled ||
                      (@refund_data && @refund_data.total_refunded),
                    do: "text-zinc-600",
                    else: "text-zinc-400"
                  )
                }>
                  Total Paid
                </span>
                <span class={[
                  "font-bold text-xl",
                  if(
                    @ticket_order.status == :cancelled ||
                      (@refund_data && @refund_data.total_refunded),
                    do: "text-zinc-900",
                    else: "text-blue-400"
                  )
                ]}>
                  {MoneyHelper.format_money!(@ticket_order.total_amount)}
                </span>
              </div>
              <%= if @refund_data && @refund_data.total_refunded do %>
                <div class="flex justify-between border-t border-red-200 pt-4">
                  <span class="text-zinc-600">Refunded</span>
                  <span class="font-bold text-green-600 text-xl">
                    {MoneyHelper.format_money!(@refund_data.total_refunded)}
                  </span>
                </div>
                <%= if @refund_data.processed_refunds && length(@refund_data.processed_refunds) > 0 do %>
                  <div class="border-t border-red-200 pt-4 space-y-2">
                    <p class="text-xs font-semibold text-zinc-600 uppercase tracking-wider">
                      Refund Details
                    </p>
                    <%= for refund <- @refund_data.processed_refunds do %>
                      <div class="flex justify-between text-xs">
                        <span class="text-zinc-500">
                          {MoneyHelper.format_money!(refund.amount)}
                          <%= if refund.reason do %>
                            <span class="text-zinc-400">
                              • {String.slice(refund.reason, 0, 30)}{if String.length(
                                                                          refund.reason
                                                                        ) >
                                                                          30,
                                                                        do: "..."}
                            </span>
                          <% end %>
                        </span>
                        <span class={[
                          "font-medium",
                          if(refund.status == :completed,
                            do: "text-green-600",
                            else: "text-amber-600"
                          )
                        ]}>
                          {if refund.status == :completed,
                            do: "Processed",
                            else: String.capitalize(Atom.to_string(refund.status))}
                        </span>
                      </div>
                    <% end %>
                  </div>
                <% end %>
                <%= if @refund_data.refunded_tickets && length(@refund_data.refunded_tickets) > 0 do %>
                  <div class="border-t border-red-200 pt-4 space-y-2">
                    <p class="text-xs font-semibold text-zinc-600 uppercase tracking-wider">
                      Refunded Tickets
                    </p>
                    <%= for ticket <- @refund_data.refunded_tickets do %>
                      <div class="text-xs text-zinc-600">
                        <span class="font-medium">
                          {ticket.ticket_tier.name}
                        </span>
                        <span class="text-zinc-400 font-mono">
                          • #{ticket.reference_id}
                        </span>
                      </div>
                    <% end %>
                  </div>
                <% end %>
                <div class="flex justify-between border-t-2 border-red-300 pt-4 mt-4">
                  <span class="font-semibold text-zinc-900">Net Amount</span>
                  <span class="font-bold text-red-600 text-xl">
                    {case Money.sub(
                            @ticket_order.total_amount,
                            @refund_data.total_refunded
                          ) do
                      {:ok, net} -> MoneyHelper.format_money!(net)
                      _ -> MoneyHelper.format_money!(@ticket_order.total_amount)
                    end}
                  </span>
                </div>
              <% end %>
              <div class={[
                "flex justify-between items-center gap-2",
                if(
                  @ticket_order.status == :cancelled ||
                    (@refund_data && @refund_data.total_refunded),
                  do: "border-t border-red-200 pt-4",
                  else: "border-t border-zinc-800 pt-4"
                )
              ]}>
                <span class={
                  if(
                    @ticket_order.status == :cancelled ||
                      (@refund_data && @refund_data.total_refunded),
                    do: "text-zinc-600",
                    else: "text-zinc-400"
                  )
                }>
                  Method
                </span>
                <span class="inline-flex items-center gap-2 justify-end text-right min-w-0">
                  <%= if @payment_method_logo do %>
                    <img
                      src={@payment_method_logo}
                      alt=""
                      class="h-5 w-auto max-w-[3rem] object-contain shrink-0"
                      loading="lazy"
                      decoding="async"
                    />
                  <% end %>
                  <span id="order-confirmation-payment-method" class="min-w-0">
                    {payment_method_label(
                      @ticket_order,
                      @payment_method_description,
                      @async_data_loaded
                    )}
                  </span>
                </span>
              </div>
              <div class="flex justify-between">
                <span class={
                  if(
                    @ticket_order.status == :cancelled ||
                      (@refund_data && @refund_data.total_refunded),
                    do: "text-zinc-600",
                    else: "text-zinc-400"
                  )
                }>
                  Tickets
                </span>
                <span id="order-confirmation-payment-ticket-count">
                  <span id="order-confirmation-payment-ticket-count-value">
                    {active_non_donation_ticket_count(@ticket_order.tickets)}
                  </span>
                  <%= if @refund_data && @refund_data.refunded_tickets do %>
                    <% refunded_event_ticket_count =
                      @refund_data.refunded_tickets
                      |> Enum.reject(&donation_ticket?/1)
                      |> length() %>
                    <%= if refunded_event_ticket_count > 0 do %>
                      <span class="text-zinc-400">
                        ({refunded_event_ticket_count} refunded)
                      </span>
                    <% end %>
                  <% end %>
                </span>
              </div>
            </div>
          </div>
          <!-- Action Buttons -->
          <div class="space-y-3">
            <%= if @ticket_order.status != :cancelled do %>
              <.button
                navigate={~p"/tickets/#{@ticket_order.id}/qr" <> "?return_to=/orders/#{@ticket_order.id}/confirmation"}
                class="w-full py-3"
                color="zinc"
              >
                <.icon name="hero-qr-code" class="w-5 h-5 -mt-0.5 me-2" />View tickets for check-in
              </.button>
            <% end %>
            <.button phx-click="view-tickets" class="w-full py-3">
              <.icon name="hero-ticket" class="w-5 h-5" />View All My Tickets
            </.button>
            <.button
              phx-click="view-event"
              class="w-full py-3"
              variant="outline"
              color="zinc"
            >
              <.icon name="hero-arrow-left" class="w-5 h-5 -mt-0.5 me-2" />Back to Event
            </.button>
          </div>
        </aside>
      </div>
      <!-- Footer Note -->
      <div class="mt-12 pt-8 border-t border-zinc-100">
        <p class="text-sm text-zinc-500 text-center">
          Need help? Contact us at
          <a
            href="mailto:info@ysc.org"
            class="text-blue-600 hover:text-blue-500 underline"
          >
            info@ysc.org
          </a>
        </p>
      </div>
    </div>
    """
  end

  defp non_donation_ticket_count(tickets) do
    tickets
    |> Enum.reject(&donation_ticket?/1)
    |> length()
  end

  defp active_non_donation_ticket_count(tickets) do
    tickets
    |> Enum.reject(&(donation_ticket?(&1) or &1.status == :cancelled))
    |> length()
  end

  defp order_has_donations?(tickets) do
    Enum.any?(tickets, &donation_ticket?/1)
  end

  defp order_items_section_title(tickets) do
    ticket_count = non_donation_ticket_count(tickets)
    donation_count = length(tickets) - ticket_count

    cond do
      ticket_count > 0 && donation_count > 0 -> "Tickets & Donations"
      donation_count > 0 -> "Your Donations"
      true -> "Your Tickets"
    end
  end

  defp donation_ticket?(ticket) do
    ticket.ticket_tier.type == "donation" ||
      ticket.ticket_tier.type == :donation
  end

  defp ticket_discount_percentage(discount, tier_price) do
    if Money.positive?(tier_price) do
      discount.amount
      |> Decimal.div(tier_price.amount)
      |> Decimal.mult(Decimal.new(100))
      |> Decimal.to_float()
      |> Float.round(2)
    end
  end

  # Label from synced payment method only (no Stripe). Nil when async Stripe lookup is required.
  defp payment_method_description_without_stripe(nil), do: nil

  defp payment_method_description_without_stripe(payment) do
    case payment.payment_method do
      nil ->
        nil

      payment_method ->
        payment_type =
          case payment_method.type do
            nil -> nil
            type -> PaymentMethodFormatter.normalize_payment_type(type)
          end

        case payment_type do
          :card ->
            if payment_method.last_four do
              brand =
                PaymentMethodFormatter.payment_brand_label(
                  payment_method.display_brand || "Card"
                )

              "#{brand} ending in #{payment_method.last_four}"
            else
              "Credit Card"
            end

          :bank_account ->
            if payment_method.last_four do
              bank_name = payment_method.bank_name || "Bank"
              "#{bank_name} Account ending in #{payment_method.last_four}"
            else
              "Bank Account"
            end

          type when not is_nil(type) ->
            PaymentMethodFormatter.format_alternative_payment_method(
              type,
              payment_method
            )

          _ ->
            nil
        end
    end
  end

  # Get payment method label + logo from Stripe when not synced to database
  defp get_payment_method_from_stripe(payment) do
    get_payment_method_from_stripe_id(payment.external_payment_id)
  end

  defp get_payment_method_from_stripe_id(nil),
    do: stripe_payment_method_fallback()

  defp get_payment_method_from_stripe_id(payment_intent_id) do
    stripe_client =
      Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.retrieve_payment_intent(payment_intent_id, %{
           expand: ["payment_method", "latest_charge"]
         }) do
      {:ok, payment_intent} ->
        {payment_method_type, last_four, display_brand} =
          PaymentMethodFormatter.payment_details_from_payment_intent(
            payment_intent,
            stripe_client
          )

        case payment_method_type do
          nil ->
            stripe_payment_method_fallback()

          type ->
            normalized = PaymentMethodFormatter.normalize_payment_type(type)

            %{
              description:
                PaymentMethodFormatter.format_payment_method_with_details(
                  normalized,
                  last_four,
                  display_brand
                ),
              logo_path:
                PaymentMethodLogo.path_for_stripe_summary(
                  normalized,
                  display_brand
                )
            }
        end

      {:error, _} ->
        stripe_payment_method_fallback()
    end
  end

  defp stripe_payment_method_fallback do
    %{description: "Credit Card (Stripe)", logo_path: nil}
  end

  defp payment_method_label(ticket_order, description, async_data_loaded?) do
    cond do
      ticket_order.payment ->
        description ||
          if(async_data_loaded? && ticket_order.payment.external_payment_id,
            do: "Credit Card (Stripe)",
            else: "…"
          )

      free_order?(ticket_order) ->
        "Free"

      async_data_loaded? && ticket_order.payment_intent_id ->
        "Credit Card (Stripe)"

      true ->
        "…"
    end
  end

  defp free_order?(%{total_amount: %Money{} = total_amount}) do
    Money.zero?(total_amount)
  end

  defp free_order?(_ticket_order), do: false

  # Load order data asynchronously after WebSocket connection
  defp load_order_data_async(socket, ticket_order) do
    start_async(socket, :load_order_data, fn ->
      refund_data = get_refund_data_for_order(ticket_order)

      stripe_payment_summary =
        cond do
          ticket_order.payment && is_nil(ticket_order.payment.payment_method) ->
            get_payment_method_from_stripe(ticket_order.payment)

          is_nil(ticket_order.payment) && !free_order?(ticket_order) &&
              ticket_order.payment_intent_id ->
            get_payment_method_from_stripe_id(ticket_order.payment_intent_id)

          true ->
            nil
        end

      %{
        refund_data: refund_data,
        stripe_payment_summary: stripe_payment_summary
      }
    end)
  end

  @impl true
  def handle_async(:load_order_data, {:ok, results}, socket) do
    socket =
      socket
      |> assign(:refund_data, results.refund_data)
      |> assign(:async_data_loaded, true)

    socket =
      case results.stripe_payment_summary do
        %{description: description, logo_path: logo} ->
          socket
          |> assign(:payment_method_description, description)
          |> assign(:payment_method_logo, logo)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_async(:load_order_data, {:exit, reason}, socket) do
    Ysc.Logging.warning("Failed to load order data async: #{inspect(reason)}")
    {:noreply, assign(socket, :async_data_loaded, true)}
  end

  defp get_refund_data_for_order(ticket_order) do
    if ticket_order.payment do
      # Get processed refunds for this payment
      processed_refunds =
        from(r in Refund,
          where: r.payment_id == ^ticket_order.payment.id,
          order_by: [desc: r.inserted_at]
        )
        |> Repo.all()

      # Get refunded tickets (cancelled tickets from this order)
      refunded_tickets =
        from(t in Ysc.Events.Ticket,
          where: t.ticket_order_id == ^ticket_order.id,
          where: t.status == :cancelled,
          preload: [:ticket_tier],
          order_by: [desc: t.updated_at]
        )
        |> Repo.all()

      # Calculate total refunded amount
      processed_total =
        Enum.reduce(processed_refunds, Money.new(0, :USD), fn refund, acc ->
          case Money.add(acc, refund.amount) do
            {:ok, sum} -> sum
            _ -> acc
          end
        end)

      %{
        processed_refunds: processed_refunds,
        refunded_tickets: refunded_tickets,
        total_refunded:
          if(Money.positive?(processed_total), do: processed_total, else: nil)
      }
    else
      nil
    end
  end

  defp event_in_past?(event) do
    today = Date.utc_today()

    case event.start_date do
      %DateTime{} = dt -> Date.compare(DateTime.to_date(dt), today) == :lt
      %Date{} = date -> Date.compare(date, today) == :lt
      _ -> false
    end
  end

  defp format_event_date(%DateTime{} = dt) do
    dt |> DateTime.to_date() |> Calendar.strftime("%B %d, %Y")
  end

  defp format_event_date(%Date{} = date),
    do: Calendar.strftime(date, "%B %d, %Y")

  defp format_event_date(_), do: "TBD"
end
