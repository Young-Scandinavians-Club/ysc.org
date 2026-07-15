defmodule YscWeb.UserTicketsLive do
  use YscWeb, :live_view
  require Ysc.Logging

  import YscWeb.Live.AsyncHelpers

  alias Ysc.Tickets
  alias Ysc.Tickets.DonationDisplay

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-12 bg-zinc-50/50 min-h-screen">
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="flex flex-col md:flex-row md:items-end justify-between gap-6 mb-12">
          <div>
            <p class="text-teal-600 text-xs font-bold uppercase tracking-[0.2em] mb-2">
              Your account
            </p>
            <h1 class="text-4xl lg:text-5xl font-black text-zinc-900 tracking-tight">
              Your Tickets
            </h1>
          </div>
          <.link
            href={~p"/events"}
            class="inline-flex items-center gap-2 px-6 py-3 bg-zinc-900 text-white font-bold rounded-xl hover:bg-zinc-700 transition"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> Find More Events
          </.link>
        </div>

        <div
          :if={@loading_user_tickets}
          id="user-tickets-loading"
          class="grid grid-cols-1 lg:grid-cols-2 gap-8"
          role="status"
          aria-live="polite"
        >
          <span class="sr-only">Loading your tickets…</span>
          <.ticket_order_card_skeleton :for={_ <- 1..2} announce?={false} />
        </div>

        <div
          :if={not @loading_user_tickets}
          class="grid grid-cols-1 lg:grid-cols-2 gap-8"
          id="ticket-orders-list"
          phx-update="stream"
        >
          <%!-- Empty state --%>
          <div
            id="ticket-orders-empty"
            class="only:block hidden lg:col-span-2 text-center py-16"
          >
            <div class="text-zinc-400 mb-4">
              <.icon name="hero-ticket" class="w-16 h-16 mx-auto" />
            </div>
            <h3 class="text-lg font-black text-zinc-900 mb-2">No tickets yet</h3>
            <p class="text-zinc-600 mb-6">
              You haven't purchased any event tickets yet.
            </p>
            <.link
              href={~p"/events"}
              class="inline-flex items-center gap-2 px-6 py-3 bg-zinc-900 text-white font-bold rounded-xl hover:bg-zinc-700 transition"
            >
              <.icon name="hero-plus" class="w-4 h-4" /> Browse Events
            </.link>
          </div>

          <%= for {id, ticket_order} <- @streams.ticket_orders do %>
            <div
              id={id}
              class="relative group bg-white border border-zinc-200 rounded-2xl hover:ring-2 hover:ring-zinc-300 transition-all duration-200"
            >
              <%!-- Event Header Section --%>
              <div class="p-8">
                <div class="flex justify-between items-start mb-6">
                  <.status_badge status={ticket_order.status} />
                  <p
                    class="text-xs font-bold text-zinc-400 uppercase tracking-[0.2em] leading-none text-right"
                    title="Use this order number if you contact us about this purchase"
                  >
                    Order {ticket_order.reference_id}
                  </p>
                </div>

                <.link
                  href={~p"/events/#{ticket_order.event_id}"}
                  class="block group-hover:text-teal-600 transition-colors"
                >
                  <h2 class="text-3xl font-black text-zinc-900 tracking-tighter mb-2">
                    {ticket_order.event.title}
                  </h2>
                </.link>

                <div class="flex flex-wrap gap-4 text-sm text-zinc-500 font-medium">
                  <div class="flex items-center gap-1.5">
                    <.icon name="hero-calendar" class="w-4 h-4 text-teal-600" />
                    {format_date(ticket_order.event.start_date)}
                  </div>
                  <div class="flex items-center gap-1.5">
                    <.icon name="hero-ticket" class="w-4 h-4 text-teal-600" />
                    {length(ticket_order.tickets)} Ticket{if length(
                                                               ticket_order.tickets
                                                             ) !=
                                                               1,
                                                             do: "s",
                                                             else: ""}
                  </div>
                </div>

                <%!-- Pending Order Actions --%>
                <%= if ticket_order.status == :pending do %>
                  <div class="mt-6 pt-6 border-t border-zinc-100">
                    <div class="flex items-center gap-2 mb-4 text-sm text-amber-600">
                      <.icon name="hero-clock" class="w-4 h-4" />
                      <span class="font-semibold">
                        Complete payment within {format_time_remaining(
                          ticket_order.expires_at
                        )}
                      </span>
                    </div>
                    <div class="flex gap-2">
                      <.button
                        phx-click="resume-order"
                        phx-value-order-id={ticket_order.id}
                        class="flex-1"
                      >
                        Finish payment
                      </.button>
                      <.button
                        phx-click="cancel-order"
                        phx-value-order-id={ticket_order.id}
                        color="red"
                        class="flex-1"
                        data-confirm="Cancel this order? You'll lose your held tickets and member price. You can buy tickets again if they're still available."
                      >
                        Cancel order
                      </.button>
                    </div>
                  </div>
                <% end %>
              </div>

              <%!-- Perforation Line (only for completed orders) --%>
              <%= if ticket_order.status == :completed do %>
                <div class="relative h-px border-t-2 border-dashed border-zinc-100 mx-4">
                  <div class="absolute -left-6 -top-3 w-6 h-6 bg-zinc-50 rounded-full border-r border-zinc-200">
                  </div>
                  <div class="absolute -right-6 -top-3 w-6 h-6 bg-zinc-50 rounded-full border-l border-zinc-200">
                  </div>
                </div>

                <%!-- Ticket Manifest Section --%>
                <div class="p-8 bg-zinc-50/50 rounded-b-3xl">
                  <% donation_amounts =
                    DonationDisplay.amounts_by_ticket_id(ticket_order) %>
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <%= for ticket <- ticket_order.tickets do %>
                      <div class="bg-white p-4 rounded-2xl border border-zinc-200">
                        <p class="text-xs font-black text-zinc-900">
                          {ticket.ticket_tier.name}
                        </p>
                        <p class="text-xs font-mono text-zinc-400 mt-1">
                          {ticket.reference_id}
                        </p>
                        <div class="mt-3 pt-3 border-t border-zinc-50 flex justify-between items-center">
                          <span class="text-xs font-bold text-teal-600 uppercase">
                            {Ysc.Tickets.Display.ticket_status_label(ticket.status)}
                          </span>
                          <span class="text-xs font-bold text-zinc-900">
                            <%= case ticket.ticket_tier.type do %>
                              <% :free -> %>
                                Free
                              <% "donation" -> %>
                                {Map.get(donation_amounts, ticket.id, "Donation")}
                              <% :donation -> %>
                                {Map.get(donation_amounts, ticket.id, "Donation")}
                              <% _ -> %>
                                {format_price(ticket.ticket_tier.price)}
                            <% end %>
                          </span>
                        </div>
                      </div>
                    <% end %>
                  </div>

                  <div class="mt-8 flex justify-between items-center">
                    <div class="text-right">
                      <p class="text-xs font-bold text-zinc-400 uppercase tracking-[0.2em] leading-none">
                        Total Paid
                      </p>
                      <p class="text-2xl font-black text-zinc-900">
                        {format_price(ticket_order.total_amount)}
                      </p>
                    </div>
                    <div class="flex items-center gap-2">
                      <.link
                        :if={
                          Enum.any?(
                            ticket_order.tickets,
                            &(&1.status == :confirmed)
                          )
                        }
                        navigate={
                          ~p"/tickets/#{ticket_order.id}/qr?return_to=/users/tickets"
                        }
                        class="inline-flex items-center gap-1.5 px-4 py-2.5 text-sm font-semibold text-zinc-100 bg-zinc-900 hover:bg-zinc-800 rounded transition-colors"
                      >
                        <.icon name="hero-qr-code" class="w-4 h-4" />
                        Show event tickets
                      </.link>
                      <.link
                        navigate={~p"/orders/#{ticket_order.id}/confirmation"}
                        class="px-4 py-2.5 bg-white border border-zinc-200 text-zinc-700 text-sm font-semibold rounded hover:bg-zinc-50 transition"
                      >
                        View Order
                      </.link>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Memory Gallery Section --%>
        <%= if !Enum.empty?(@past_items) do %>
          <section class="mt-24 border-t border-zinc-200 pt-16">
            <div class="flex items-center justify-between mb-10">
              <div>
                <h3 class="text-2xl font-black text-zinc-400 tracking-tight italic">
                  Memory Gallery
                </h3>
                <p class="text-sm text-zinc-400">Your past events with YSC</p>
              </div>
              <span class="px-3 py-1 bg-zinc-100 text-zinc-400 text-xs font-bold rounded-full uppercase tracking-widest">
                Archived
              </span>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              <%= for item <- @past_items do %>
                <div class="relative group bg-zinc-50/50 border border-zinc-200 rounded-2xl p-6 grayscale opacity-60 hover:grayscale-0 hover:opacity-100 transition-all duration-500 hover:bg-white hover:ring-2 hover:ring-zinc-300">
                  <div class="flex justify-between items-start mb-4">
                    <span class="text-xs font-black text-zinc-400 uppercase tracking-widest border border-zinc-200 px-2 py-0.5 rounded">
                      {format_visited_date(item)}
                    </span>
                    <.icon name="hero-check-badge" class="w-5 h-5 text-zinc-300" />
                  </div>

                  <h4 class="text-xl font-black text-zinc-900 tracking-tight mb-1">
                    {item.title}
                  </h4>
                  <p class="text-xs font-medium text-zinc-400 flex items-center gap-1 mb-4">
                    <.icon name="hero-map-pin" class="w-3 h-3" />
                    {item.location}
                  </p>

                  <div class="pt-4 border-t border-zinc-100 flex justify-between items-center">
                    <p class="text-xs font-mono text-zinc-400">
                      #{item.reference_id}
                    </p>
                    <.link
                      navigate={item.receipt_path}
                      class="text-xs font-bold text-zinc-400 hover:text-teal-600 underline uppercase tracking-widest"
                    >
                      View Receipt
                    </.link>
                  </div>
                </div>
              <% end %>
            </div>
          </section>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to ticket order updates
      # Phoenix.PubSub.subscribe(Ysc.PubSub, "ticket_orders:#{socket.assigns.current_user.id}")
      send(self(), :load_user_tickets_data)
    end

    {:ok,
     socket
     |> assign(:page_title, "My Tickets")
     |> assign(
       :meta_description,
       "View and manage your event tickets with Young Scandinavians Club."
     )
     |> assign(:past_items, [])
     |> assign(:loading_user_tickets, true)
     |> stream(:ticket_orders, [], limit: -50)}
  end

  @impl true
  def handle_info(:load_user_tickets_data, socket) do
    user_id = socket.assigns.current_user.id

    socket =
      try do
        parallel =
          [
            {:upcoming,
             fn -> Tickets.list_user_upcoming_ticket_orders(user_id) end},
            {:past, fn -> memory_gallery_items(user_id) end}
          ]
          |> async_stream_with_repo(fn {key, fun} -> {key, fun.()} end,
            max_concurrency: 2,
            timeout: :infinity
          )
          |> Enum.reduce(%{}, fn
            {:ok, {key, value}}, acc -> Map.put(acc, key, value)
            {:exit, _reason}, acc -> acc
          end)

        upcoming = Map.get(parallel, :upcoming, [])
        past_items = Map.get(parallel, :past, [])

        socket
        |> assign(:past_items, past_items)
        |> stream(:ticket_orders, upcoming, reset: true, limit: -50)
      rescue
        error ->
          Ysc.Logging.warning("Failed to load user tickets data",
            error: Exception.message(error)
          )

          socket
      end

    {:noreply, assign(socket, :loading_user_tickets, false)}
  end

  @impl true
  def handle_event("cancel-order", %{"order-id" => order_id}, socket) do
    user = socket.assigns.current_user

    case Tickets.get_user_ticket_order(user.id, order_id) do
      nil ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Order not found",
           title: "Order"
         )}

      ticket_order ->
        case Tickets.cancel_ticket_order(ticket_order, "User cancelled") do
          {:ok, _cancelled_order} ->
            ticket_orders =
              Tickets.list_user_upcoming_ticket_orders(
                socket.assigns.current_user.id
              )

            {:noreply,
             socket
             |> stream(:ticket_orders, ticket_orders, reset: true, limit: -50)
             |> YscWeb.Flash.put_toast(
               :info,
               "Reservation cancelled. Your tickets were released.",
               title: "Order"
             )}

          {:error, reason} ->
            {:noreply,
             YscWeb.Flash.put_toast(
               socket,
               :error,
               cancel_order_error_message(reason),
               title: "Order"
             )}
        end
    end
  end

  @impl true
  def handle_event("resume-order", %{"order-id" => order_id}, socket) do
    user = socket.assigns.current_user

    case Tickets.get_user_ticket_order(user.id, order_id) do
      nil ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Order not found",
           title: "Order"
         )}

      ticket_order ->
        # Verify the order status is pending
        if ticket_order.status == :pending do
          # Redirect to event page with resume_order query parameter
          {:noreply,
           push_navigate(socket,
             to: ~p"/events/#{ticket_order.event_id}?resume_order=#{order_id}"
           )}
        else
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             "This ticket order has expired or was already completed. Browse events to buy tickets again. If you see a charge on your card, email info@ysc.org with the date and amount.",
             title: "Order"
           )}
        end
    end
  end

  @impl true
  def handle_event("view-tickets", %{"order-id" => order_id}, socket) do
    # Redirect to the order confirmation page
    {:noreply, push_navigate(socket, to: ~p"/orders/#{order_id}/confirmation")}
  end

  ## Helper Functions

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "px-3 py-1 text-xs font-black rounded-full uppercase tracking-widest ring-1",
      case @status do
        :pending -> "bg-amber-50 text-amber-700 ring-amber-100"
        :completed -> "bg-green-50 text-green-700 ring-green-100"
        :cancelled -> "bg-red-50 text-red-700 ring-red-100"
        :expired -> "bg-zinc-50 text-zinc-700 ring-zinc-100"
        _ -> "bg-zinc-50 text-zinc-700 ring-zinc-100"
      end
    ]}>
      {order_status_label(@status)}
    </span>
    """
  end

  defp order_status_label(status),
    do: Ysc.Tickets.Display.order_status_label(status)

  defp format_date(datetime) do
    Timex.format!(datetime, "{Mshort} {D}, {YYYY}")
  end

  defp format_price(%Money{} = money) do
    Ysc.MoneyHelper.format_money!(money)
  end

  defp format_price(_), do: "$0.00"

  defp format_time_remaining(expires_at) do
    now = DateTime.utc_now()

    if DateTime.compare(now, expires_at) == :gt do
      "Expired"
    else
      diff_seconds = DateTime.diff(expires_at, now)

      cond do
        diff_seconds < 60 ->
          "in #{diff_seconds} seconds"

        diff_seconds < 3600 ->
          minutes = div(diff_seconds, 60)
          "in #{minutes} minute#{if minutes == 1, do: "", else: "s"}"

        true ->
          hours = div(diff_seconds, 3600)
          "in #{hours} hour#{if hours == 1, do: "", else: "s"}"
      end
    end
  end

  defp memory_gallery_items(user_id) do
    user_id
    |> Tickets.list_user_past_memory_gallery_ticket_orders()
    |> Enum.map(fn ticket_order ->
      %{
        title: ticket_order.event.title,
        location: ticket_order.event.location_name || "YSC Event",
        reference_id: ticket_order.reference_id,
        date: ticket_order.event.start_date,
        receipt_path: ~p"/orders/#{ticket_order.id}/confirmation"
      }
    end)
  end

  defp format_visited_date(%{date: %Date{} = date}) do
    case Timex.format(date, "{Mshort} {YYYY}") do
      {:ok, formatted} -> "Visited #{formatted}"
      _ -> "Visited"
    end
  end

  defp format_visited_date(%{date: %DateTime{} = datetime}) do
    case Timex.format(datetime, "{Mshort} {YYYY}") do
      {:ok, formatted} -> "Visited #{formatted}"
      _ -> "Visited"
    end
  end

  defp format_visited_date(_), do: "Visited"

  defp cancel_order_error_message(:not_found),
    do: "We couldn't find this order. It may have already been cancelled."

  defp cancel_order_error_message(:checkout_payment_in_progress),
    do:
      "Your payment is still processing. If you were charged, your tickets will appear shortly or we'll email you a confirmation."

  defp cancel_order_error_message(_reason),
    do:
      "We couldn't cancel this order. Please try again, or contact info@ysc.org for help."
end
