defmodule YscWeb.TicketQrLive do
  use YscWeb, :live_view

  alias Ysc.Tickets
  alias Ysc.Scanning.QrToken

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-900 text-white flex flex-col">
      <%!-- Header bar --%>
      <div class="flex items-center gap-3 px-4 pt-safe-top py-4 border-b border-white/10">
        <%!-- Back button: returns to wherever the user came from --%>
        <.link
          navigate={@return_to}
          class="flex items-center justify-center w-11 h-11 rounded-full bg-white/15 hover:bg-white/25 active:bg-white/30 transition-colors shrink-0"
          aria-label="Go back"
        >
          <.icon name="hero-chevron-left" class="w-5 h-5 text-white" />
        </.link>
        <div class="min-w-0">
          <p class="font-bold text-xl leading-tight truncate text-white">
            {@event.title}
          </p>
          <p class="text-sm text-zinc-300 mt-0.5">
            {@ticket_count} ticket{if @ticket_count != 1, do: "s", else: ""}
          </p>
        </div>
      </div>

      <%!-- Event details strip --%>
      <div class="px-5 py-4 flex flex-col gap-2 border-b border-white/10">
        <span
          :if={@event.start_date}
          class="flex items-center gap-2 text-sm font-medium text-zinc-200"
        >
          <.icon name="hero-calendar" class="w-4 h-4 text-zinc-400 shrink-0" />
          {format_event_date(@event.start_date, @event.start_time)}
        </span>
        <span :if={@event.location_name} class="flex items-center gap-2 text-sm text-zinc-200">
          <.icon name="hero-map-pin" class="w-4 h-4 text-zinc-400 shrink-0" />
          {@event.location_name}
        </span>
        <span :if={@event.address} class="flex items-center gap-2 text-sm text-zinc-300">
          <.icon name="hero-building-office" class="w-4 h-4 text-zinc-400 shrink-0" />
          {@event.address}
        </span>
      </div>

      <%!-- Slider --%>
      <div class="flex-1 flex flex-col justify-center py-8">
        <div
          id="ticket-slider"
          phx-hook="TicketSlider"
          phx-update="ignore"
        >
          <%!-- Scroll-snap viewport: browser handles all touch/swipe physics natively --%>
          <%!-- Wider padding (1.5rem) gives the side notch circles room to breathe --%>
          <div
            data-slider-viewport
            style="display: flex; overflow-x: scroll; scroll-snap-type: x mandatory; -webkit-overflow-scrolling: touch; scrollbar-width: none; -ms-overflow-style: none;"
          >
            <%= for ticket <- @tickets do %>
              <div
                data-slide
                style="flex: 0 0 100%; scroll-snap-align: start; padding: 0 1.5rem;"
              >
                <%!-- Ticket: three joined sections — header / QR body / info stub --%>
                <div class="shadow-2xl shadow-black/60">

                  <%!-- ① Header band --%>
                  <div class="rounded-t-3xl bg-emerald-700">
                    <div class="px-6 py-4 flex items-center justify-between">
                      <div>
                        <p class="text-white/70 text-xs font-black uppercase tracking-[0.2em] mb-0.5">
                          Event Ticket
                        </p>
                        <p class="text-white font-black text-lg leading-tight drop-shadow">
                          {ticket.tier_name}
                        </p>
                      </div>
                      <div class="w-11 h-11 bg-white/20 rounded-2xl flex items-center justify-center shrink-0">
                        <.icon name="hero-ticket" class="w-6 h-6 text-white" />
                      </div>
                    </div>
                  </div>

                  <%!-- ② QR body — main white section --%>
                  <div class="bg-white px-6 pt-6 pb-4">
                    <div class="flex items-center justify-center">
                      <.qr_code data={ticket.qr_token} size={230} class="rounded-xl" />
                    </div>
                    <p class="text-center text-xs font-bold tracking-[0.2em] uppercase text-zinc-400 mt-4">
                      Scan to check in
                    </p>
                  </div>

                  <%!-- ③ Perforation tear-line with side notches --%>
                  <div class="bg-white relative flex items-center" style="height: 2rem;">
                    <div class="absolute -left-4 top-1/2 -translate-y-1/2 w-8 h-8 rounded-full bg-zinc-900">
                    </div>
                    <div class="absolute inset-x-6 border-t-2 border-dashed border-zinc-300">
                    </div>
                    <div class="absolute -right-4 top-1/2 -translate-y-1/2 w-8 h-8 rounded-full bg-zinc-900">
                    </div>
                  </div>

                  <%!-- ④ Info stub — holder details at the bottom --%>
                  <div class="bg-white rounded-b-3xl px-6 pt-1 pb-6">
                    <div class="flex items-start justify-between gap-4">
                      <div class="min-w-0">
                        <p class="text-zinc-400 text-xs font-bold uppercase tracking-widest mb-1">
                          Ticket Holder
                        </p>
                        <p class="text-zinc-900 font-bold text-base leading-snug truncate">
                          {if ticket.holder_name, do: ticket.holder_name, else: "—"}
                        </p>
                      </div>
                      <div class="shrink-0 text-right">
                        <p class="text-zinc-400 text-xs font-bold uppercase tracking-widest mb-1">
                          Reference
                        </p>
                        <p class="text-zinc-700 text-sm font-mono font-bold">
                          {ticket.reference_id}
                        </p>
                      </div>
                    </div>
                  </div>

                </div>
              </div>
            <% end %>
          </div>

          <%!-- Nav controls (only shown when multiple tickets) --%>
          <%= if @ticket_count > 1 do %>
            <div class="flex items-center justify-center gap-6 mt-8 px-4">
              <%!-- 44px touch targets, more visible background --%>
              <button
                data-slider-prev
                class="w-12 h-12 rounded-full bg-white/20 hover:bg-white/30 active:bg-white/35 disabled:opacity-25 disabled:cursor-not-allowed transition-colors flex items-center justify-center"
                aria-label="Previous ticket"
              >
                <.icon name="hero-chevron-left" class="w-6 h-6 text-white" />
              </button>

              <%!-- Dots: active = white, inactive = zinc-400 (~3:1) — large enough at 10px --%>
              <div data-slider-dots class="flex items-center gap-3">
                <%= for i <- 0..(@ticket_count - 1) do %>
                  <div
                    data-dot
                    class={[
                      "rounded-full transition-all duration-200",
                      if(i == 0,
                        do: "w-3 h-3 bg-white",
                        else: "w-2.5 h-2.5 bg-zinc-400"
                      )
                    ]}
                  >
                  </div>
                <% end %>
              </div>

              <button
                data-slider-next
                class="w-12 h-12 rounded-full bg-white/20 hover:bg-white/30 active:bg-white/35 disabled:opacity-25 disabled:cursor-not-allowed transition-colors flex items-center justify-center"
                aria-label="Next ticket"
              >
                <.icon name="hero-chevron-right" class="w-6 h-6 text-white" />
              </button>
            </div>

            <%!-- Navigation hint: 14px, zinc-300 (~5.5:1) --%>
            <p class="text-center text-sm text-zinc-300 mt-3">
              Swipe left or right to switch tickets
            </p>
          <% end %>
        </div>

        <%!-- Order reference: 14px, zinc-300 on zinc-900 (~5.5:1) --%>
        <div class="mt-8 text-center px-4">
          <p class="text-sm text-zinc-300">
            Order&nbsp;<span class="font-mono font-semibold text-white">{@order_reference}</span>
          </p>
          <.link
            navigate={~p"/orders/#{@order_id}/confirmation"}
            class="mt-2 inline-flex items-center gap-1.5 text-sm text-zinc-300 hover:text-white underline underline-offset-2 transition-colors"
          >
            View full order details
            <.icon name="hero-arrow-right" class="w-4 h-4" />
          </.link>
        </div>
      </div>

      <%!-- Footer --%>
      <div class="px-5 py-5 border-t border-white/10 text-center">
        <p class="text-sm text-zinc-300">
          Show this QR code to event staff for check-in
        </p>
      </div>
    </div>
    """
  end

  @impl true
  def mount(%{"order_id" => order_id} = params, _session, socket) do
    user = socket.assigns.current_user
    return_to = safe_return_to(Map.get(params, "return_to"))

    case Tickets.get_user_ticket_order(user.id, order_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Ticket order not found.")
         |> push_navigate(to: return_to)}

      order ->
        confirmed_tickets =
          order.tickets
          |> Enum.filter(&(&1.status == :confirmed))
          |> Enum.map(fn ticket ->
            holder =
              case ticket do
                %{registration: %{first_name: first, last_name: last}}
                when not is_nil(first) ->
                  "#{first} #{last}"

                _ ->
                  nil
              end

            %{
              id: ticket.id,
              reference_id: ticket.reference_id,
              tier_name: ticket.ticket_tier.name,
              holder_name: holder,
              qr_token: QrToken.sign_ticket(ticket.id)
            }
          end)

        {:ok,
         socket
         |> assign(:page_title, "#{order.event.title} · Ticket QR")
         |> assign(:return_to, return_to)
         |> assign(:event, order.event)
         |> assign(:order_id, order.id)
         |> assign(:order_reference, order.reference_id)
         |> assign(:tickets, confirmed_tickets)
         |> assign(:ticket_count, length(confirmed_tickets))}
    end
  end

  # --- Helpers ---

  # Only allow relative paths to prevent open-redirect abuse.
  defp safe_return_to(path)
       when is_binary(path) and byte_size(path) > 0 do
    if String.starts_with?(path, "/") and not String.contains?(path, "://"),
      do: path,
      else: ~p"/users/tickets"
  end

  defp safe_return_to(_), do: ~p"/users/tickets"

  defp format_event_date(start_date, start_time) do
    date_str = Calendar.strftime(start_date, "%A, %B %-d, %Y")

    if start_time do
      "#{date_str} at #{Calendar.strftime(start_time, "%-I:%M %p")}"
    else
      date_str
    end
  end
end
