defmodule YscWeb.UserTicketsLive do
  use YscWeb, :live_view

  alias Ysc.Tickets
  import Ecto.Query

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-12 bg-zinc-50/50 min-h-screen">
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="flex flex-col md:flex-row md:items-end justify-between gap-6 mb-12">
          <div>
            <p class="text-teal-600 text-xs font-bold uppercase tracking-[0.2em] mb-2">
              Member Portal
            </p>
            <h1 class="text-4xl lg:text-5xl font-black text-zinc-900 tracking-tight">
              Your Tickets
            </h1>
          </div>
          <.link
            navigate={~p"/events"}
            class="inline-flex items-center gap-2 px-6 py-3 bg-zinc-900 text-white font-bold rounded-xl hover:bg-zinc-700 transition shadow-lg shadow-zinc-200"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> Find More Events
          </.link>
        </div>

        <div
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
              navigate={~p"/events"}
              class="inline-flex items-center gap-2 px-6 py-3 bg-zinc-900 text-white font-bold rounded-xl hover:bg-zinc-700 transition shadow-lg"
            >
              <.icon name="hero-plus" class="w-4 h-4" /> Browse Events
            </.link>
          </div>

          <%= for {id, ticket_order} <- @streams.ticket_orders do %>
            <div
              id={id}
              class="relative group bg-white border border-zinc-200 rounded-3xl shadow-sm hover:shadow-xl transition-all duration-300"
            >
              <%!-- Event Header Section --%>
              <div class="p-8">
                <div class="flex justify-between items-start mb-6">
                  <.status_badge status={ticket_order.status} />
                  <p class="text-[10px] font-bold text-zinc-400 uppercase tracking-[0.2em] leading-none">
                    Order #<%= ticket_order.reference_id %>
                  </p>
                </div>

                <.link
                  navigate={~p"/events/#{ticket_order.event_id}"}
                  class="block group-hover:text-teal-600 transition-colors"
                >
                  <h2 class="text-3xl font-black text-zinc-900 tracking-tighter mb-2">
                    <%= ticket_order.event.title %>
                  </h2>
                </.link>

                <div class="flex flex-wrap gap-4 text-sm text-zinc-500 font-medium">
                  <div class="flex items-center gap-1.5">
                    <.icon name="hero-calendar" class="w-4 h-4 text-teal-600" />
                    <%= format_date(ticket_order.event.start_date) %>
                  </div>
                  <div class="flex items-center gap-1.5">
                    <.icon name="hero-ticket" class="w-4 h-4 text-teal-600" />
                    <%= length(ticket_order.tickets) %> Ticket<%= if length(
                                                                       ticket_order.tickets
                                                                     ) !=
                                                                       1,
                                                                     do: "s",
                                                                     else: "" %>
                  </div>
                </div>

                <%!-- Pending Order Actions --%>
                <%= if ticket_order.status == :pending do %>
                  <div class="mt-6 pt-6 border-t border-zinc-100">
                    <div class="flex items-center gap-2 mb-4 text-sm text-amber-600">
                      <.icon name="hero-clock" class="w-4 h-4" />
                      <span class="font-semibold">
                        Expires <%= format_time_remaining(ticket_order.expires_at) %>
                      </span>
                    </div>
                    <div class="flex gap-2">
                      <.button
                        phx-click="resume-order"
                        phx-value-order-id={ticket_order.id}
                        class="flex-1"
                      >
                        Resume Order
                      </.button>
                      <.button
                        phx-click="cancel-order"
                        phx-value-order-id={ticket_order.id}
                        color="red"
                        class="flex-1"
                      >
                        Cancel
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
                  <h4 class="text-[10px] font-bold text-zinc-400 uppercase tracking-[0.2em] mb-4">
                    Manifest
                  </h4>

                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <%= for ticket <- ticket_order.tickets do %>
                      <div class="bg-white p-4 rounded-2xl border border-zinc-200 shadow-sm">
                        <p class="text-xs font-black text-zinc-900">
                          <%= ticket.ticket_tier.name %>
                        </p>
                        <p class="text-[10px] font-mono text-zinc-400 mt-1">
                          #<%= ticket.reference_id %>
                        </p>
                        <div class="mt-3 pt-3 border-t border-zinc-50 flex justify-between items-center">
                          <span class="text-[10px] font-bold text-teal-600 uppercase">
                            <%= String.capitalize(to_string(ticket.status)) %>
                          </span>
                          <span class="text-xs font-bold text-zinc-900">
                            <%= case ticket.ticket_tier.type do %>
                              <% :free -> %>
                                Free
                              <% "donation" -> %>
                                <%= get_donation_amount_for_ticket(
                                  ticket,
                                  ticket_order
                                ) %>
                              <% :donation -> %>
                                <%= get_donation_amount_for_ticket(
                                  ticket,
                                  ticket_order
                                ) %>
                              <% _ -> %>
                                <%= format_price(ticket.ticket_tier.price) %>
                            <% end %>
                          </span>
                        </div>
                      </div>
                    <% end %>
                  </div>

                  <div class="mt-8 flex justify-between items-center">
                    <div class="text-right">
                      <p class="text-[10px] font-bold text-zinc-400 uppercase tracking-[0.2em] leading-none">
                        Total Paid
                      </p>
                      <p class="text-2xl font-black text-zinc-900">
                        <%= format_price(ticket_order.total_amount) %>
                      </p>
                    </div>
                    <.link
                      navigate={~p"/orders/#{ticket_order.id}/confirmation"}
                      class="px-6 py-3 bg-white border border-zinc-200 text-zinc-900 font-bold rounded hover:bg-zinc-50 transition shadow-sm"
                    >
                      View Order
                    </.link>
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
              <span class="px-3 py-1 bg-zinc-100 text-zinc-400 text-[10px] font-bold rounded-full uppercase tracking-widest">
                Archived
              </span>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              <%= for item <- @past_items do %>
                <div class="relative group bg-zinc-50/50 border border-zinc-200 rounded-3xl p-6 grayscale opacity-60 hover:grayscale-0 hover:opacity-100 transition-all duration-500 hover:bg-white hover:shadow-lg">
                  <div class="flex justify-between items-start mb-4">
                    <span class="text-[9px] font-black text-zinc-400 uppercase tracking-widest border border-zinc-200 px-2 py-0.5 rounded">
                      <%= format_visited_date(item) %>
                    </span>
                    <.icon name="hero-check-badge" class="w-5 h-5 text-zinc-300" />
                  </div>

                  <h4 class="text-xl font-black text-zinc-900 tracking-tighter mb-1">
                    <%= item.title %>
                  </h4>
                  <p class="text-xs font-medium text-zinc-400 flex items-center gap-1 mb-4">
                    <.icon name="hero-map-pin" class="w-3 h-3" />
                    <%= item.location %>
                  </p>

                  <div class="pt-4 border-t border-zinc-100 flex justify-between items-center">
                    <p class="text-[10px] font-mono text-zinc-400">
                      #<%= item.reference_id %>
                    </p>
                    <.link
                      navigate={item.receipt_path}
                      class="text-[10px] font-bold text-zinc-400 hover:text-teal-600 underline uppercase tracking-widest"
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
    end

    now = DateTime.utc_now()

    # Get all ticket orders and filter for upcoming events only (excluding cancelled orders)
    all_ticket_orders =
      Tickets.list_user_ticket_orders(socket.assigns.current_user.id)

    upcoming_ticket_orders =
      all_ticket_orders
      |> Enum.filter(fn ticket_order ->
        ticket_order.status != :cancelled &&
          ticket_order.event &&
          DateTime.compare(ticket_order.event.start_date, now) == :gt
      end)

    past_items = get_past_items(socket.assigns.current_user.id)

    {:ok,
     socket
     |> assign(:page_title, "My Tickets")
     |> assign(:past_items, past_items)
     |> stream(:ticket_orders, upcoming_ticket_orders, limit: -50)}
  end

  @impl true
  def handle_event("cancel-order", %{"order-id" => order_id}, socket) do
    user = socket.assigns.current_user

    case Tickets.get_user_ticket_order(user.id, order_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Order not found")}

      ticket_order ->
        case Tickets.cancel_ticket_order(ticket_order, "User cancelled") do
          {:ok, _cancelled_order} ->
            # Refresh the ticket orders list (excluding cancelled orders)
            now = DateTime.utc_now()

            all_ticket_orders =
              Tickets.list_user_ticket_orders(socket.assigns.current_user.id)

            ticket_orders =
              all_ticket_orders
              |> Enum.filter(fn to ->
                to.status != :cancelled &&
                  to.event &&
                  DateTime.compare(to.event.start_date, now) == :gt
              end)

            {:noreply,
             socket
             |> stream(:ticket_orders, ticket_orders, reset: true, limit: -50)
             |> put_flash(:info, "Order cancelled successfully")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to cancel order: #{reason}")}
        end
    end
  end

  @impl true
  def handle_event("resume-order", %{"order-id" => order_id}, socket) do
    user = socket.assigns.current_user

    case Tickets.get_user_ticket_order(user.id, order_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Order not found")}

      ticket_order ->
        # Verify the order status is pending
        if ticket_order.status == :pending do
          # Redirect to event page with resume_order query parameter
          {:noreply,
           redirect(socket,
             to: ~p"/events/#{ticket_order.event_id}?resume_order=#{order_id}"
           )}
        else
          {:noreply, put_flash(socket, :error, "Cannot resume this order")}
        end
    end
  end

  @impl true
  def handle_event("view-tickets", %{"order-id" => order_id}, socket) do
    # Redirect to the order confirmation page
    {:noreply, redirect(socket, to: ~p"/orders/#{order_id}/confirmation")}
  end

  ## Helper Functions

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "px-3 py-1 text-[10px] font-black rounded-full uppercase tracking-widest ring-1",
      case @status do
        :pending -> "bg-amber-50 text-amber-700 ring-amber-100"
        :completed -> "bg-green-50 text-green-700 ring-green-100"
        :cancelled -> "bg-red-50 text-red-700 ring-red-100"
        :expired -> "bg-zinc-50 text-zinc-700 ring-zinc-100"
        _ -> "bg-zinc-50 text-zinc-700 ring-zinc-100"
      end
    ]}>
      <%= String.capitalize(to_string(@status)) %>
    </span>
    """
  end

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

        format_price(per_ticket_amount)
      else
        "Donation"
      end
    else
      "Donation"
    end
  end

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

  defp get_past_items(user_id) do
    now = DateTime.utc_now()

    # Get past ticket orders (completed orders where event.start_date < now)
    from(to in Ysc.Tickets.TicketOrder,
      where: to.user_id == ^user_id,
      where: to.status == :completed,
      join: e in Ysc.Events.Event,
      on: to.event_id == e.id,
      where: e.start_date < ^now,
      order_by: [desc: e.start_date],
      limit: 12,
      preload: [:event]
    )
    |> Ysc.Repo.all()
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
end
