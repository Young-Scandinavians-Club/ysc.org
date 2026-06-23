defmodule YscWeb.TicketQrLive do
  use YscWeb, :live_view

  require Ysc.Logging

  alias Ysc.Tickets
  alias Ysc.Scanning.QrToken
  alias Ysc.AppleWallet
  alias Ysc.GoogleWallet
  alias YscWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-900 text-white flex flex-col">
      <%!-- Detects platform to show the correct wallet button(s) --%>
      <div id="wallet-platform-detector" phx-hook="WalletPlatform" class="hidden">
      </div>
      <%!-- Header bar --%>
      <div class="flex items-center gap-3 px-4 pt-safe-top py-4 border-b border-white/10">
        <.link
          id="back-link"
          navigate={@return_to}
          class="flex items-center justify-center w-11 h-11 rounded-full bg-white/15 hover:bg-white/25 active:bg-white/30 transition-colors shrink-0"
          aria-label="Go back"
        >
          <.icon name="hero-chevron-left" class="w-5 h-5 text-white" />
        </.link>
        <div class="min-w-0">
          <%= cond do %>
            <% @loading -> %>
              <div class="h-6 w-48 bg-white/10 rounded animate-pulse"></div>
              <div class="h-4 w-24 bg-white/10 rounded animate-pulse mt-1.5"></div>
            <% @load_error -> %>
              <p
                id="event-title"
                class="font-bold text-xl leading-tight truncate text-white"
              >
                Tickets
              </p>
            <% true -> %>
              <p
                id="event-title"
                class="font-bold text-xl leading-tight truncate text-white"
              >
                {@event.title}
              </p>
              <p id="event-ticket-count" class="text-sm text-zinc-300 mt-0.5">
                {@ticket_count} ticket{if @ticket_count != 1, do: "s", else: ""}
              </p>
          <% end %>
        </div>
      </div>

      <%!-- Event details strip --%>
      <%= cond do %>
        <% @loading -> %>
          <div class="px-5 py-4 flex flex-col gap-2 border-b border-white/10">
            <div class="h-4 w-56 bg-white/10 rounded animate-pulse"></div>
            <div class="h-4 w-40 bg-white/10 rounded animate-pulse"></div>
          </div>
        <% @load_error -> %>
          <%!-- no strip on error --%>
        <% true -> %>
          <div class="px-5 py-4 flex items-start justify-between gap-4 border-b border-white/10">
            <div class="flex flex-col gap-2">
              <span
                :if={@event.start_date}
                class="flex items-center gap-2 text-sm font-medium text-zinc-200"
              >
                <.icon name="hero-calendar" class="w-4 h-4 text-zinc-400 shrink-0" />
                {format_event_date(@event.start_date, @event.start_time)}
              </span>
              <span
                :if={@event.location_name}
                class="flex items-center gap-2 text-sm text-zinc-200"
              >
                <.icon name="hero-map-pin" class="w-4 h-4 text-zinc-400 shrink-0" />
                {@event.location_name}
              </span>
              <span
                :if={@event.address}
                class="flex items-center gap-2 text-sm text-zinc-300"
              >
                <.icon
                  name="hero-building-office"
                  class="w-4 h-4 text-zinc-400 shrink-0"
                />
                {@event.address}
              </span>
            </div>
            <add-to-calendar-button
              :if={@event.start_date}
              name={@event.title}
              startDate={date_for_add_to_cal(@event.start_date)}
              {if get_end_date_for_calendar(@event), do: [endDate: date_for_add_to_cal(get_end_date_for_calendar(@event))], else: []}
              options="'Apple','Google','iCal','Outlook.com','Yahoo'"
              startTime={@event.start_time}
              {if get_end_time_for_calendar(@event), do: [endTime: get_end_time_for_calendar(@event)], else: []}
              timeZone="America/Los_Angeles"
              location={@event.location_name}
              size="4"
              lightMode="dark"
            ></add-to-calendar-button>
          </div>
      <% end %>

      <%!-- Main content area --%>
      <div class="flex-1 flex flex-col justify-center py-8">
        <%= cond do %>
          <% @loading -> %>
            <%!-- Loading skeleton --%>
            <div class="px-6 flex flex-col items-center gap-6">
              <div class="w-full max-w-sm rounded-3xl overflow-hidden shadow-2xl shadow-black/60">
                <div class="h-20 bg-emerald-700/50 animate-pulse rounded-t-3xl">
                </div>
                <div class="bg-white/10 px-6 pt-6 pb-4 flex flex-col items-center gap-4">
                  <div class="w-56 h-56 bg-white/5 rounded-xl animate-pulse"></div>
                  <div class="h-3 w-28 bg-white/10 rounded animate-pulse"></div>
                </div>
                <div class="h-8 bg-white/10 animate-pulse"></div>
                <div class="h-20 bg-white/10 animate-pulse rounded-b-3xl"></div>
              </div>
              <p class="text-sm text-zinc-400 animate-pulse">
                Loading your tickets…
              </p>
            </div>
          <% @load_error -> %>
            <%!-- Error state --%>
            <div class="flex flex-col items-center justify-center px-8 text-center">
              <.icon
                name="hero-exclamation-circle"
                class="w-14 h-14 text-red-400 mb-4"
              />
              <p class="text-lg font-semibold text-white mb-1">
                Could not load tickets
              </p>
              <p class="text-sm text-zinc-400">Please go back and try again.</p>
              <.link
                navigate={@return_to}
                class="mt-6 inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-white/10 hover:bg-white/20 text-sm font-medium transition-colors"
              >
                <.icon name="hero-arrow-left" class="w-4 h-4" /> Go back
              </.link>
            </div>
          <% true -> %>
            <%!-- Slider --%>
            <div
              id="ticket-slider"
              phx-hook="TicketSlider"
              phx-update="ignore"
            >
              <%!-- Scroll-snap viewport: browser handles all touch/swipe physics natively --%>
              <%!-- Wider padding (1.5rem) gives the side notch circles room to breathe --%>
              <div
                data-slider-viewport
                class="flex overflow-x-scroll snap-x snap-mandatory max-w-xl mx-auto"
              >
                <%= for ticket <- @tickets do %>
                  <div
                    data-slide
                    class="shrink-0 basis-full snap-start px-6"
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
                        <div
                          id={"ticket-qr-#{ticket.reference_id}"}
                          class="flex items-center justify-center"
                        >
                          <.qr_code
                            data={ticket.qr_token}
                            size={230}
                            class="rounded-xl"
                          />
                        </div>
                        <p class="text-center text-xs font-bold tracking-[0.2em] uppercase text-zinc-400 mt-4">
                          Scan to check in
                        </p>
                        <%= if @apple_wallet_enabled? && @wallet_platform in [:apple_only, :both] do %>
                          <div class="flex justify-center mt-4">
                            <.add_to_wallet_button href={
                              ~p"/wallet/tickets/#{ticket.id}"
                            } />
                          </div>
                        <% end %>
                        <%= if @google_wallet_enabled? &&
                              @wallet_platform in [:google_only, :both] &&
                              Map.get(@google_wallet_ticket_urls, ticket.id) do %>
                          <div class="flex justify-center mt-2">
                            <.add_to_google_wallet_button href={
                              Map.get(@google_wallet_ticket_urls, ticket.id)
                            } />
                          </div>
                        <% end %>
                      </div>

                      <%!-- ③ Perforation tear-line with side notches --%>
                      <div class="bg-white relative flex items-center h-8">
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
                              {if ticket.holder_name,
                                do: ticket.holder_name,
                                else: "—"}
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

                <%!-- Navigation hint: 14px, zinc-300 on zinc-900 (~5.5:1) --%>
                <p class="text-center text-sm text-zinc-300 mt-3">
                  Swipe left or right to switch tickets
                </p>
              <% end %>
            </div>

            <%!-- Order reference: 14px, zinc-300 on zinc-900 (~5.5:1) --%>
            <div class="mt-8 text-center px-4">
              <%= if @order_id do %>
                <p class="text-sm text-zinc-300">
                  Order&nbsp;<span class="font-mono font-semibold text-white">{@order_reference}</span>
                </p>
                <.link
                  id="confirmation-link"
                  navigate={~p"/orders/#{@order_id}/confirmation"}
                  class="mt-2 inline-flex items-center gap-1.5 text-sm text-zinc-300 hover:text-white underline underline-offset-2 transition-colors"
                >
                  View full order details
                  <.icon name="hero-arrow-right" class="w-4 h-4" />
                </.link>
              <% else %>
                <.link
                  id="all-orders-link"
                  navigate={~p"/users/tickets"}
                  class="inline-flex items-center gap-1.5 text-sm text-zinc-300 hover:text-white underline underline-offset-2 transition-colors"
                >
                  View all ticket orders
                  <.icon name="hero-arrow-right" class="w-4 h-4" />
                </.link>
              <% end %>
            </div>
        <% end %>
      </div>

      <%!-- Footer --%>
      <div :if={!@load_error} class="px-5 py-5 border-t border-white/10 text-center">
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

    socket =
      socket
      |> assign(:return_to, return_to)
      |> assign(:page_title, "Your event tickets")
      |> assign(:loading, true)
      |> assign(:load_error, false)
      |> assign(:event, nil)
      |> assign(:tickets, [])
      |> assign(:ticket_count, 0)
      |> assign(:order_id, nil)
      |> assign(:order_reference, nil)
      |> assign(:apple_wallet_enabled?, AppleWallet.configured?(:ticket))
      |> assign(:google_wallet_enabled?, GoogleWallet.configured?(:ticket))
      |> assign(:google_wallet_ticket_urls, %{})
      |> assign(:wallet_platform, wallet_platform_from_params(socket))

    socket =
      if connected?(socket) do
        start_async(socket, :load_ticket_data, fn ->
          load_ticket_data(user.id, order_id)
        end)
      else
        socket
      end

    {:ok, socket}
  end

  def mount(%{"event_id" => event_id} = params, _session, socket) do
    user = socket.assigns.current_user
    return_to = safe_return_to(Map.get(params, "return_to"))

    socket =
      socket
      |> assign(:return_to, return_to)
      |> assign(:page_title, "Your event tickets")
      |> assign(:loading, true)
      |> assign(:load_error, false)
      |> assign(:event, nil)
      |> assign(:tickets, [])
      |> assign(:ticket_count, 0)
      |> assign(:order_id, nil)
      |> assign(:order_reference, nil)
      |> assign(:apple_wallet_enabled?, AppleWallet.configured?(:ticket))
      |> assign(:google_wallet_enabled?, GoogleWallet.configured?(:ticket))
      |> assign(:google_wallet_ticket_urls, %{})
      |> assign(:wallet_platform, wallet_platform_from_params(socket))

    socket =
      if connected?(socket) do
        start_async(socket, :load_ticket_data, fn ->
          load_event_ticket_data(user.id, event_id)
        end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_async(:load_ticket_data, {:ok, :not_found}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Ticket order not found.")
     |> push_navigate(to: socket.assigns.return_to)}
  end

  def handle_async(:load_ticket_data, {:ok, :no_confirmed_tickets}, socket) do
    {:noreply, push_navigate(socket, to: socket.assigns.return_to)}
  end

  def handle_async(:load_ticket_data, {:ok, data}, socket) do
    google_wallet_urls =
      if socket.assigns.google_wallet_enabled? do
        user_id = socket.assigns.current_user.id
        generate_google_wallet_ticket_urls(data.tickets, user_id)
      else
        %{}
      end

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:page_title, "#{data.event.title} · Your tickets")
     |> assign(:event, data.event)
     |> assign(:tickets, data.tickets)
     |> assign(:ticket_count, data.ticket_count)
     |> assign(:order_id, data.order_id)
     |> assign(:order_reference, data.order_reference)
     |> assign(:google_wallet_ticket_urls, google_wallet_urls)}
  end

  def handle_async(:load_ticket_data, {:exit, reason}, socket) do
    Ysc.Logging.warning("Failed to load ticket QR data", error: reason)

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:load_error, true)}
  end

  @impl true
  def handle_event(
        "wallet_platform_detected",
        %{"platform" => platform},
        socket
      ) do
    platform_atom =
      case platform do
        "apple_only" -> :apple_only
        "google_only" -> :google_only
        _ -> :both
      end

    {:noreply, assign(socket, :wallet_platform, platform_atom)}
  end

  # --- Private ---

  defp load_event_ticket_data(user_id, event_id) do
    tickets = Tickets.list_user_tickets_for_event(user_id, event_id)
    confirmed_tickets = tickets_for_qr_display(tickets)

    if confirmed_tickets == [] do
      :no_confirmed_tickets
    else
      event = List.first(tickets).event

      %{
        event: %{
          title: event.title,
          start_date: event.start_date,
          start_time: event.start_time,
          end_time: event.end_time,
          end_date: event.end_date,
          location_name: event.location_name,
          address: event.address
        },
        order_id: nil,
        order_reference: nil,
        tickets: confirmed_tickets,
        ticket_count: length(confirmed_tickets)
      }
    end
  end

  defp load_ticket_data(user_id, order_id) do
    case Tickets.get_user_ticket_order_for_qr(user_id, order_id) do
      nil ->
        :not_found

      order ->
        confirmed_tickets =
          order.tickets
          |> Enum.filter(&(&1.status == :confirmed))
          |> tickets_for_qr_display()

        if confirmed_tickets == [] do
          :no_confirmed_tickets
        else
          event = order.event

          %{
            event: %{
              title: event.title,
              start_date: event.start_date,
              start_time: event.start_time,
              end_time: event.end_time,
              end_date: event.end_date,
              location_name: event.location_name,
              address: event.address
            },
            order_id: order.id,
            order_reference: order.reference_id,
            tickets: confirmed_tickets,
            ticket_count: length(confirmed_tickets)
          }
        end
    end
  end

  defp tickets_for_qr_display(tickets) do
    tickets
    |> Enum.reject(&donation_ticket?/1)
    |> Enum.map(&ticket_to_qr_card/1)
  end

  defp ticket_to_qr_card(ticket) do
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
  end

  defp donation_ticket?(%{ticket_tier: %{type: type}})
       when type in [:donation, "donation"],
       do: true

  defp donation_ticket?(_), do: false

  defp safe_return_to(path)
       when is_binary(path) and byte_size(path) > 0 do
    if UserAuth.valid_internal_redirect?(path),
      do: path,
      else: ~p"/users/tickets"
  end

  defp safe_return_to(_), do: ~p"/users/tickets"

  defp date_for_add_to_cal(nil), do: nil

  defp date_for_add_to_cal(%DateTime{} = dt),
    do: dt |> DateTime.to_date() |> Date.to_iso8601()

  defp date_for_add_to_cal(%NaiveDateTime{} = dt),
    do: dt |> NaiveDateTime.to_date() |> Date.to_iso8601()

  defp date_for_add_to_cal(%Date{} = d), do: Date.to_iso8601(d)

  defp get_end_time_for_calendar(event) do
    case {event.start_time, event.end_time} do
      {start_time, nil} when not is_nil(start_time) ->
        Time.add(start_time, 3 * 60 * 60, :second)

      {_start_time, end_time} ->
        end_time
    end
  end

  defp get_end_date_for_calendar(event) do
    case {event.start_time, event.end_time, event.end_date} do
      {start_time, nil, _end_date} when not is_nil(start_time) ->
        calculated_end_time = Time.add(start_time, 3 * 60 * 60, :second)

        if Time.compare(calculated_end_time, start_time) == :lt do
          Date.add(DateTime.to_date(event.start_date), 1)
        else
          nil
        end

      {_start_time, _end_time, end_date} ->
        if end_date, do: DateTime.to_date(end_date), else: nil
    end
  end

  defp format_event_date(start_date, start_time) do
    date_str = Calendar.strftime(start_date, "%A, %B %-d, %Y")

    if start_time do
      "#{date_str} at #{Calendar.strftime(start_time, "%-I:%M %p")}"
    else
      date_str
    end
  end

  defp generate_google_wallet_ticket_urls(tickets, user_id) do
    tickets
    |> Task.async_stream(
      fn ticket ->
        {ticket.id, GoogleWallet.generate_ticket_save_url(ticket.id, user_id)}
      end,
      max_concurrency: 5,
      ordered: true,
      timeout: :infinity
    )
    |> Enum.reduce(%{}, fn
      {:ok, {ticket_id, {:ok, url}}}, acc ->
        Map.put(acc, ticket_id, url)

      {:ok, {ticket_id, {:error, reason}}}, acc ->
        Ysc.Logging.error(
          "Failed to generate Google Wallet URL for ticket",
          ticket_id: ticket_id,
          error: inspect(reason)
        )

        acc

      {:exit, reason}, acc ->
        Ysc.Logging.error(
          "Google Wallet URL generation task exited",
          error: inspect(reason)
        )

        acc
    end)
  end

  # Reads the wallet platform from LiveView connect_params (populated from
  # localStorage by app.js). Falls back to :both on the disconnected render
  # (no connect_params available) and on unknown values.
  defp wallet_platform_from_params(socket) do
    if connected?(socket) do
      case get_connect_params(socket)["wallet_platform"] do
        "apple_only" -> :apple_only
        "google_only" -> :google_only
        _ -> :both
      end
    else
      :both
    end
  end
end
