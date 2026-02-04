defmodule YscWeb.OrderConfirmationLive do
  use YscWeb, :live_view

  alias Ysc.Tickets.TicketOrder
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
       |> put_flash(:error, "You must be signed in to view this order.")
       |> redirect(to: ~p"/events")}
    else
      # SECURITY: Filter by user_id in the database query to prevent unauthorized access
      # This ensures we only fetch orders that belong to the current user
      # Show confetti only if confetti=true parameter is present (from checkout redirect)
      show_confetti = Map.get(params, "confetti") == "true"

      # PERFORMANCE: Preload everything in a single query to avoid N+1 and duplicate queries
      # - Include cover_image via event preload
      # - Include registration via tickets preload
      # This eliminates 3 separate queries (event, cover_image, registration)
      case from(to in TicketOrder,
             where: to.id == ^order_id and to.user_id == ^user.id,
             preload: [
               :user,
               event: [:cover_image, agendas: :agenda_items],
               payment: :payment_method,
               tickets: [:ticket_tier, :registration]
             ]
           )
           |> Repo.one() do
        nil ->
          {:ok,
           socket
           |> put_flash(:error, "Order not found")
           |> redirect(to: ~p"/events")}

        ticket_order ->
          # Use the already-preloaded event (no additional query needed)
          event = ticket_order.event

          # Essential assigns for initial render
          socket =
            socket
            |> assign(:ticket_order, ticket_order)
            |> assign(:event, event)
            |> assign(:user_first_name, user.first_name || "Member")
            |> assign(:show_confetti, show_confetti)
            |> assign(:page_title, "Order Confirmation")
            # Placeholder for async-loaded data
            |> assign(:refund_data, nil)
            |> assign(:async_data_loaded, false)

          if connected?(socket) do
            # Load refund data asynchronously (only needed for cancelled orders with payments)
            {:ok, load_order_data_async(socket, ticket_order)}
          else
            {:ok, socket}
          end
      end
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/events/#{socket.assigns.event.id}")}
  end

  @impl true
  def handle_event("view-tickets", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/users/tickets")}
  end

  @impl true
  def handle_event("view-event", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/events/#{socket.assigns.event.id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
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
              Your order for <strong><%= @event.title %></strong>
              has been cancelled.
              <%= if @refund_data && @refund_data.total_refunded do %>
                A refund of
                <strong>
                  <%= MoneyHelper.format_money!(@refund_data.total_refunded) %>
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
              See you at the Event, <%= @user_first_name %>!
            </h1>
            <p class="text-zinc-500 mt-2 text-lg">
              Your tickets for <strong><%= @event.title %></strong> are confirmed.
              We've sent a copy of these details to your email.
            </p>
          <% end %>
        </div>
        <div class="text-left md:text-right">
          <p class="text-xs font-bold text-zinc-400 uppercase tracking-widest">
            Order Reference
          </p>
          <p class="font-mono text-lg font-semibold text-zinc-900 whitespace-nowrap">
            <%= @ticket_order.reference_id %>
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
                    <p class="text-xl font-semibold"><%= @event.title %></p>
                  </div>
                </div>
              <% end %>
              <div class="absolute inset-0 bg-gradient-to-t from-black/40 to-transparent flex items-end p-6 z-10">
                <div class="flex items-center justify-between w-full">
                  <h2 class="text-white text-xl font-bold flex items-center gap-2">
                    <.icon name="hero-information-circle" class="w-8 h-8" />
                    Event Details
                  </h2>
                  <span class="text-sm font-medium bg-blue-100 text-blue-700 px-3 py-1 rounded-full">
                    <%= length(@ticket_order.tickets) %> <%= if length(
                                                                  @ticket_order.tickets
                                                                ) == 1 do
                      "Ticket"
                    else
                      "Tickets"
                    end %>
                  </span>
                </div>
              </div>
            </div>
            <div class="p-8 grid grid-cols-1 md:grid-cols-3 gap-8 relative z-0">
              <div>
                <p class="text-xs font-bold text-zinc-400 uppercase mb-1">Event</p>
                <p class="text-xl font-bold text-zinc-900"><%= @event.title %></p>
                <p class="text-sm text-zinc-500"><%= @event.description %></p>
              </div>
              <div>
                <p class="text-xs font-bold text-zinc-400 uppercase mb-1">
                  Date & Time
                </p>
                <p class="text-xl font-bold text-zinc-900">
                  <%= if @event.start_date do %>
                    <%= Calendar.strftime(@event.start_date, "%B %d, %Y") %>
                  <% else %>
                    TBD
                  <% end %>
                </p>
                <p class="text-sm text-zinc-500">
                  <%= if @event.start_time do %>
                    <%= Calendar.strftime(@event.start_time, "%I:%M %p") %>
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
                    <%= @event.location_name %>
                  <% else %>
                    TBD
                  <% end %>
                </p>
                <p :if={@event.address} class="text-sm text-zinc-500">
                  <%= @event.address %>
                </p>
              </div>
            </div>
          </div>
          <!-- Tickets Card -->
          <div class="bg-white rounded-lg border border-zinc-200 overflow-hidden">
            <div class="px-6 py-4 border-b border-zinc-200 bg-zinc-50">
              <h2 class="text-lg font-semibold text-zinc-900 flex items-center gap-2">
                <.icon name="hero-ticket" class="w-5 h-5" /> Your Tickets
              </h2>
            </div>
            <div class="px-6 py-4">
              <div class="space-y-3">
                <%= for ticket <- @ticket_order.tickets do %>
                  <% is_refunded = ticket.status == :cancelled %>
                  <% requires_registration =
                    ticket.ticket_tier.requires_registration == true %>
                  <% ticket_detail = ticket.registration %>
                  <div class={[
                    "p-4 rounded-lg border",
                    if(is_refunded,
                      do: "bg-red-50 border-red-200 opacity-60",
                      else: "bg-zinc-50 border-zinc-200"
                    )
                  ]}>
                    <div class="flex justify-between items-start mb-3">
                      <div class="flex-1">
                        <div class="flex items-center gap-2">
                          <p class={[
                            "font-semibold",
                            if(is_refunded,
                              do: "text-zinc-500 line-through",
                              else: "text-zinc-900"
                            )
                          ]}>
                            <%= ticket.ticket_tier.name %>
                          </p>
                          <%= if is_refunded do %>
                            <span class="text-xs font-bold text-red-600 bg-red-100 px-2 py-0.5 rounded">
                              Refunded
                            </span>
                          <% end %>
                        </div>
                        <p class={[
                          "text-sm font-mono",
                          if(is_refunded,
                            do: "text-zinc-400",
                            else: "text-zinc-500"
                          )
                        ]}>
                          Ticket #<%= ticket.reference_id %>
                        </p>
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
                            <% ticket.ticket_tier.type == "donation" || ticket.ticket_tier.type == :donation -> %>
                              <%= get_donation_amount_for_ticket(
                                ticket,
                                @ticket_order
                              ) %>
                            <% ticket.ticket_tier.price == nil -> %>
                              Free
                            <% Money.zero?(ticket.ticket_tier.price) -> %>
                              Free
                            <% true -> %>
                              <%= if has_discount && !is_refunded do %>
                                <div class="flex flex-col items-end">
                                  <span class="line-through text-zinc-400 text-sm">
                                    <%= MoneyHelper.format_money!(original_price) %>
                                  </span>
                                  <span>
                                    <%= MoneyHelper.format_money!(final_price) %>
                                  </span>
                                </div>
                              <% else %>
                                <%= MoneyHelper.format_money!(original_price) %>
                              <% end %>
                          <% end %>
                        </p>
                      </div>
                    </div>
                    <% has_ticket_discount = has_discount && !is_refunded %>
                    <%= if has_ticket_discount do %>
                      <% discount_percentage =
                        if ticket.ticket_tier.price &&
                             Money.positive?(ticket.ticket_tier.price) do
                          case Money.div(ticket_discount, ticket.ticket_tier.price) do
                            {:ok, ratio} ->
                              Decimal.mult(ratio.amount, Decimal.new(100))
                              |> Decimal.to_float()
                              |> Float.round(2)

                            _ ->
                              nil
                          end
                        else
                          nil
                        end %>
                      <div class="mt-3 pt-3 border-t border-zinc-300">
                        <div class="flex justify-between text-xs text-green-600">
                          <span>
                            Reserved discount<%= if discount_percentage do %>
                              (<%= discount_percentage %>%)
                            <% end %>
                          </span>
                          <span class="font-medium">
                            -<%= MoneyHelper.format_money!(ticket_discount) %>
                          </span>
                        </div>
                      </div>
                    <% end %>
                    <%= if requires_registration && ticket_detail do %>
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
                            <%= ticket_detail.first_name %> <%= ticket_detail.last_name %>
                          </p>
                          <p class="text-zinc-700">
                            <span class="font-medium">Email:</span>
                            <a
                              href={"mailto:#{ticket_detail.email}"}
                              class="text-blue-600 hover:text-blue-500 underline"
                            >
                              <%= ticket_detail.email %>
                            </a>
                          </p>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
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
              <%= if @ticket_order.status == :cancelled ||
                       (@refund_data && @refund_data.total_refunded),
                     do: "Payment & Refund Summary",
                     else: "Payment Summary" %>
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
                    <%= MoneyHelper.format_money!(gross_total) %>
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
                    -<%= MoneyHelper.format_money!(total_discount) %>
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
                  <%= MoneyHelper.format_money!(@ticket_order.total_amount) %>
                </span>
              </div>
              <%= if @refund_data && @refund_data.total_refunded do %>
                <div class="flex justify-between border-t border-red-200 pt-4">
                  <span class="text-zinc-600">Refunded</span>
                  <span class="font-bold text-green-600 text-xl">
                    <%= MoneyHelper.format_money!(@refund_data.total_refunded) %>
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
                          <%= MoneyHelper.format_money!(refund.amount) %>
                          <%= if refund.reason do %>
                            <span class="text-zinc-400">
                              • <%= String.slice(refund.reason, 0, 30) %><%= if String.length(
                                                                                  refund.reason
                                                                                ) >
                                                                                  30,
                                                                                do:
                                                                                  "..." %>
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
                          <%= if refund.status == :completed,
                            do: "Processed",
                            else: String.capitalize(Atom.to_string(refund.status)) %>
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
                          <%= ticket.ticket_tier.name %>
                        </span>
                        <span class="text-zinc-400 font-mono">
                          • #<%= ticket.reference_id %>
                        </span>
                      </div>
                    <% end %>
                  </div>
                <% end %>
                <div class="flex justify-between border-t-2 border-red-300 pt-4 mt-4">
                  <span class="font-semibold text-zinc-900">Net Amount</span>
                  <span class="font-bold text-red-600 text-xl">
                    <%= case Money.sub(
                               @ticket_order.total_amount,
                               @refund_data.total_refunded
                             ) do
                      {:ok, net} -> MoneyHelper.format_money!(net)
                      _ -> MoneyHelper.format_money!(@ticket_order.total_amount)
                    end %>
                  </span>
                </div>
              <% end %>
              <div class={[
                "flex justify-between",
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
                <span>
                  <%= if @ticket_order.payment do
                    get_payment_method_description(@ticket_order.payment)
                  else
                    "Free"
                  end %>
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
                <span>
                  <%= length(
                    Enum.filter(@ticket_order.tickets, fn t ->
                      t.status != :cancelled
                    end)
                  ) %>
                  <%= if @refund_data && @refund_data.refunded_tickets && length(@refund_data.refunded_tickets) > 0 do %>
                    <span class="text-zinc-400">
                      (<%= length(@refund_data.refunded_tickets) %> refunded)
                    </span>
                  <% end %>
                </span>
              </div>
            </div>
          </div>
          <!-- Action Buttons -->
          <div class="space-y-3">
            <.button phx-click="view-tickets" class="w-full py-3">
              <.icon name="hero-ticket" class="w-5 h-5 -mt-0.5 me-2" />View All My Tickets
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

  # Normalizes payment method type to atom safely
  defp normalize_payment_type(type) when is_atom(type), do: type
  defp normalize_payment_type("card"), do: :card
  defp normalize_payment_type("us_bank_account"), do: :bank_account
  defp normalize_payment_type("bank_account"), do: :bank_account
  defp normalize_payment_type("sepa_debit"), do: :sepa_debit
  defp normalize_payment_type("link"), do: :link
  defp normalize_payment_type("paypal"), do: :paypal
  defp normalize_payment_type("affirm"), do: :affirm
  defp normalize_payment_type("klarna"), do: :klarna
  defp normalize_payment_type("cashapp"), do: :cashapp
  defp normalize_payment_type(_unknown), do: :other

  # Helper function to calculate donation amount for a ticket
  defp get_donation_amount_for_ticket(_ticket, ticket_order) do
    if ticket_order && ticket_order.tickets do
      # Calculate non-donation ticket costs
      non_donation_total =
        ticket_order.tickets
        |> Enum.filter(fn t ->
          t.ticket_tier.type != "donation" && t.ticket_tier.type != :donation
        end)
        |> Enum.reduce(Money.new(0, :USD), fn t, acc ->
          case t.ticket_tier.price do
            nil ->
              acc

            price when is_struct(price, Money) ->
              case Money.add(acc, price) do
                {:ok, new_total} -> new_total
                _ -> acc
              end

            _ ->
              acc
          end
        end)

      # Calculate donation total
      donation_total =
        case Money.sub(ticket_order.total_amount, non_donation_total) do
          {:ok, amount} -> amount
          _ -> Money.new(0, :USD)
        end

      # Count donation tickets
      donation_tickets =
        ticket_order.tickets
        |> Enum.filter(fn t ->
          t.ticket_tier.type == "donation" || t.ticket_tier.type == :donation
        end)

      donation_count = length(donation_tickets)

      if donation_count > 0 && Money.positive?(donation_total) do
        # Calculate per-ticket donation amount
        per_ticket_amount =
          case Money.div(donation_total, donation_count) do
            {:ok, amount} -> amount
            _ -> Money.new(0, :USD)
          end

        # Format and display
        case Money.to_string(per_ticket_amount) do
          {:ok, amount} -> amount
          _ -> "Donation"
        end
      else
        "Donation"
      end
    else
      "Donation"
    end
  end

  # Helper function to get payment method description
  defp get_payment_method_description(payment) do
    case payment.payment_method do
      nil ->
        # Payment method not synced - try to get it from Stripe payment intent
        get_payment_method_from_stripe(payment)

      payment_method ->
        # Normalize type to atom (could be string from database)
        payment_type =
          case payment_method.type do
            nil -> nil
            type -> normalize_payment_type(type)
          end

        case payment_type do
          :card ->
            if payment_method.last_four do
              brand = payment_method.display_brand || "Card"

              "#{String.capitalize(brand)} ending in #{payment_method.last_four}"
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
            # Handle alternative payment methods (klarna, amazon_pay, cashapp, etc.)
            format_alternative_payment_method(type, payment_method)

          _ ->
            # Fallback: try to get from Stripe
            get_payment_method_from_stripe(payment)
        end
    end
  end

  # Get payment method type from Stripe payment intent when not synced to database
  defp get_payment_method_from_stripe(payment) do
    if payment.external_payment_id do
      stripe_client =
        Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

      case stripe_client.retrieve_payment_intent(payment.external_payment_id, %{
             expand: ["payment_method", "charges.data.payment_method"]
           }) do
        {:ok, payment_intent} ->
          # Try to get payment method type from payment intent
          payment_method_type =
            cond do
              # Payment method is expanded as an object
              is_map(payment_intent.payment_method) &&
                  Map.has_key?(payment_intent.payment_method, :type) ->
                payment_intent.payment_method.type

              # Payment method is a string ID - retrieve it
              is_binary(payment_intent.payment_method) ->
                case Stripe.PaymentMethod.retrieve(
                       payment_intent.payment_method
                     ) do
                  {:ok, pm} -> pm.type
                  _ -> nil
                end

              # Try to get from charges
              payment_intent.charges && payment_intent.charges.data &&
                  payment_intent.charges.data != [] ->
                first_charge = List.first(payment_intent.charges.data)

                cond do
                  is_map(first_charge.payment_method) &&
                      Map.has_key?(first_charge.payment_method, :type) ->
                    first_charge.payment_method.type

                  is_binary(first_charge.payment_method) ->
                    case Stripe.PaymentMethod.retrieve(
                           first_charge.payment_method
                         ) do
                      {:ok, pm} -> pm.type
                      _ -> nil
                    end

                  true ->
                    nil
                end

              true ->
                nil
            end

          case payment_method_type do
            nil ->
              "Credit Card (Stripe)"

            type ->
              format_alternative_payment_method(
                normalize_payment_type(type),
                nil
              )
          end

        {:error, _} ->
          "Credit Card (Stripe)"
      end
    else
      "Credit Card (Stripe)"
    end
  end

  # Format alternative payment method names for display
  defp format_alternative_payment_method(type, _payment_method)
       when is_atom(type) do
    case type do
      :klarna ->
        "Klarna"

      :amazon_pay ->
        "Amazon Pay"

      :cashapp ->
        "Cash App"

      :paypal ->
        "PayPal"

      :apple_pay ->
        "Apple Pay"

      :google_pay ->
        "Google Pay"

      :link ->
        "Link"

      :us_bank_account ->
        "Bank Account"

      :card ->
        "Credit Card"

      :bank_account ->
        "Bank Account"

      _ ->
        # Convert atom to human-readable string
        type
        |> Atom.to_string()
        |> String.replace("_", " ")
        |> String.split()
        |> Enum.map_join(" ", &String.capitalize/1)
    end
  end

  defp format_alternative_payment_method(type, _payment_method)
       when is_binary(type) do
    format_alternative_payment_method(normalize_payment_type(type), nil)
  end

  defp format_alternative_payment_method(_, _), do: "Payment Method"

  # Load order data asynchronously after WebSocket connection
  defp load_order_data_async(socket, ticket_order) do
    start_async(socket, :load_order_data, fn ->
      # Only fetch refund data if order has a payment
      # (free orders have no payment and no refunds)
      get_refund_data_for_order(ticket_order)
    end)
  end

  @impl true
  def handle_async(:load_order_data, {:ok, refund_data}, socket) do
    {:noreply,
     socket
     |> assign(:refund_data, refund_data)
     |> assign(:async_data_loaded, true)}
  end

  def handle_async(:load_order_data, {:exit, reason}, socket) do
    require Logger
    Logger.error("Failed to load order data async: #{inspect(reason)}")
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
end
