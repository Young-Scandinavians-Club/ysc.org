defmodule YscWeb.EventsLive do
  use YscWeb, :live_view

  import YscWeb.Live.AsyncHelpers

  alias Ysc.Events
  alias Ysc.Media.Image

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-6 md:py-12">
      <%!-- The "Masthead" Header --%>
      <div class="max-w-screen-xl mx-auto px-4 mb-8 md:mb-16">
        <div class="text-center py-8 md:py-12 border-y border-zinc-200">
          <p class="text-xs font-black text-blue-400 uppercase tracking-[0.2em] mb-3 md:mb-4">
            Events
          </p>
          <h1 class="text-4xl md:text-7xl font-black text-zinc-900">
            <%= if @total_upcoming_count == 0,
              do: "The Calendar",
              else: "What's Next" %>
          </h1>
        </div>
      </div>

      <%!-- Hero and Event List (handled by component) --%>
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-12">
          <%!-- Events Grid --%>
          <div class="lg:col-span-9 min-h-[50vh] lg:min-h-[70vh] flex flex-col">
            <.live_component
              id="upcoming_events"
              module={YscWeb.EventsListLive}
              show_hero={true}
              upcoming={true}
              defer_load={!@async_data_loaded}
            />
          </div>

          <%!-- Sidebar --%>
          <aside class="lg:col-span-3 space-y-4 md:space-y-8">
            <div class="p-6 md:p-8 bg-zinc-50 rounded-xl border border-zinc-100">
              <h4 class="text-[10px] font-black text-zinc-500 uppercase tracking-[0.2em] mb-4 md:mb-6">
                Upcoming Events
              </h4>
              <p class="text-sm text-zinc-600 leading-relaxed">
                Explore our curated calendar of events. From social gatherings to cultural celebrations, there's always something happening at YSC.
              </p>
            </div>
            <%!-- Get Involved - Always shown to encourage event hosting --%>
            <div class="p-6 md:p-8 bg-gradient-to-br from-blue-50/50 to-slate-50/50 rounded-xl border-2 border-blue-200 backdrop-blur-sm lg:scale-105 shadow-md">
              <h4 class="text-[10px] font-black text-blue-600 uppercase tracking-[0.2em] mb-3 md:mb-4">
                Get Involved
              </h4>
              <p class="text-sm text-zinc-700 leading-relaxed mb-4">
                Have an idea for an event? We'd love to help you host it! Reach out through our contact page.
              </p>
              <.link
                navigate={~p"/contact"}
                class="inline-flex items-center text-sm font-bold text-blue-600 hover:text-blue-700 transition-colors"
              >
                Contact Us <.icon name="hero-arrow-right" class="w-4 h-4 ml-1" />
              </.link>
            </div>
            <div class="p-6 md:p-8 bg-white rounded-xl border border-zinc-100 shadow-sm">
              <h4 class="text-[10px] font-black text-zinc-500 uppercase tracking-[0.2em] mb-3 md:mb-4">
                Stay Connected
              </h4>
              <p class="text-sm text-zinc-600 leading-relaxed mb-4">
                Join our community to see what members are planning informally.
              </p>
              <.link
                navigate={~p"/news"}
                class="inline-flex items-center text-sm font-bold text-zinc-900 hover:text-blue-600 transition-colors"
              >
                Read Club News
                <.icon name="hero-arrow-right" class="w-4 h-4 ml-1" />
              </.link>
            </div>
          </aside>
        </div>
      </div>

      <%!-- Loading skeleton for Past Events --%>
      <section
        :if={!@async_data_loaded}
        class="mt-20 md:mt-32 py-12 md:py-16 border-t border-zinc-100"
      >
        <div class="max-w-screen-xl mx-auto px-4">
          <div class="h-8 w-48 bg-zinc-200 rounded mb-12 animate-pulse"></div>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
            <%= for _i <- 1..4 do %>
              <div class="aspect-video rounded-2xl bg-zinc-200 animate-pulse"></div>
            <% end %>
          </div>
        </div>
      </section>

      <%!-- Memory Gallery - Past Events --%>
      <%= if @async_data_loaded && @past_events_exist do %>
        <section class="mt-20 md:mt-32 py-12 md:py-16 border-t border-zinc-100">
          <div class="max-w-screen-xl mx-auto px-4">
            <h2 class="text-3xl font-black text-zinc-800 tracking-tighter italic mb-12 group relative inline-block">
              <span class="inline-block transition-all duration-500 ease-in-out group-hover:-translate-y-full group-hover:opacity-0">
                <%= random_past_events_title() %>
              </span>
              <span class="absolute left-0 top-0 inline-block transition-all duration-500 ease-in-out translate-y-full opacity-0 group-hover:translate-y-0 group-hover:opacity-100 whitespace-nowrap">
                What Was
              </span>
            </h2>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div
                :for={{id, event} <- @streams.past_events}
                id={id}
                class="group relative aspect-video overflow-hidden rounded-2xl grayscale opacity-60 hover:opacity-100 hover:grayscale-0 transition-all duration-500 hover:scale-105 hover:rotate-1 ring-1 ring-zinc-200 shadow-sm hover:shadow-xl bg-white p-1"
              >
                <.link
                  navigate={~p"/events/#{event.id}"}
                  class="block w-full h-full"
                >
                  <div class="w-full h-full overflow-hidden rounded-xl relative">
                    <canvas
                      id={"blur-hash-past-#{event.id}"}
                      src={get_blur_hash(event.image)}
                      class="absolute inset-0 z-0 w-full h-full object-cover"
                      phx-hook="BlurHashCanvas"
                    >
                    </canvas>
                    <img
                      src={event_image_url(event.image)}
                      id={"image-past-#{event.id}"}
                      phx-hook="BlurHashImage"
                      class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out object-cover w-full h-full group-hover:scale-110 transition-transform duration-700"
                      loading="lazy"
                      alt={
                        if event.image,
                          do:
                            event.image.alt_text || event.image.title || event.title ||
                              "Past event",
                          else: "Past event"
                      }
                    />
                    <%!-- Title overlay --%>
                    <div class="absolute inset-0 z-[2] bg-gradient-to-t from-zinc-900/80 via-zinc-900/40 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300">
                    </div>
                    <div class="absolute bottom-0 left-0 right-0 z-[3] p-3 opacity-0 group-hover:opacity-100 transition-opacity duration-300">
                      <h4 class="text-white text-sm font-black leading-tight line-clamp-2">
                        <%= event.title %>
                      </h4>
                      <p
                        :if={event.start_date}
                        class="text-white/80 text-xs font-medium mt-1"
                      >
                        <%= Timex.format!(event.start_date, "{Mshort} {D}, {YYYY}") %>
                      </p>
                    </div>
                  </div>
                </.link>
              </div>
            </div>

            <%= if @past_events_limit < 50 && @has_more_past_events do %>
              <div class="text-center mt-12">
                <.button phx-click="show_more_past_events" class="px-8 py-3">
                  Show More Past Events
                </.button>
              </div>
            <% end %>
          </div>
        </section>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    # Minimal assigns for fast initial static render
    socket =
      socket
      |> assign(:page_title, "Events")
      |> assign(:total_upcoming_count, 0)
      |> assign(:past_events_exist, false)
      |> assign(:past_events_limit, 10)
      |> assign(:has_more_past_events, false)
      |> assign(:async_data_loaded, false)
      |> stream(:past_events, [], reset: true)

    if connected?(socket) do
      # Subscribe to real-time updates only when connected
      Events.subscribe()

      # Load all data asynchronously after WebSocket connection
      {:ok, load_events_data_async(socket)}
    else
      {:ok, socket}
    end
  end

  # Load events data asynchronously
  defp load_events_data_async(socket) do
    past_events_limit = socket.assigns.past_events_limit

    start_async(socket, :load_events_data, fn ->
      # Run queries in parallel
      tasks = [
        {:upcoming_count, fn -> Events.count_upcoming_events() end},
        {:past_events, fn -> Events.list_past_events(past_events_limit) end}
      ]

      results =
        tasks
        |> async_stream_with_repo(fn {key, fun} -> {key, fun.()} end,
          timeout: :infinity
        )
        |> Enum.reduce(%{}, fn {:ok, {key, value}}, acc ->
          Map.put(acc, key, value)
        end)

      # Compute has_more_past_events based on results
      past_events = Map.get(results, :past_events, [])

      has_more =
        if length(past_events) == past_events_limit do
          # Allow sandbox access for this query
          allow_sandbox_access()
          Events.has_more_past_events?(past_events_limit)
        else
          false
        end

      Map.put(results, :has_more_past_events, has_more)
    end)
  end

  @impl true
  def handle_async(:load_events_data, {:ok, results}, socket) do
    total_upcoming_count = Map.get(results, :upcoming_count, 0)
    past_events = Map.get(results, :past_events, [])
    has_more_past_events = Map.get(results, :has_more_past_events, false)
    past_events_exist = Enum.any?(past_events)

    {:noreply,
     socket
     |> assign(:total_upcoming_count, total_upcoming_count)
     |> assign(:past_events_exist, past_events_exist)
     |> assign(:has_more_past_events, has_more_past_events)
     |> assign(:async_data_loaded, true)
     |> stream(:past_events, past_events, reset: true)}
  end

  def handle_async(:load_events_data, {:exit, reason}, socket) do
    require Logger
    Logger.error("Failed to load events data async: #{inspect(reason)}")
    {:noreply, assign(socket, :async_data_loaded, true)}
  end

  @impl true
  def handle_info({Ysc.Events, %_event{event: _} = base_event}, socket) do
    # Pass event to component - component handles hero logic internally
    send_update(YscWeb.EventsListLive, id: "upcoming_events", event: base_event)

    {:noreply, socket}
  end

  # Handle ticket tier events - refresh the associated event in the list
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketTierAdded{ticket_tier: ticket_tier}},
        socket
      ) do
    # Get the event and send an update to refresh it in the list
    case Events.get_event(ticket_tier.event_id) do
      nil ->
        {:noreply, socket}

      event ->
        event_updated = %Ysc.MessagePassingEvents.EventUpdated{event: event}

        send_update(YscWeb.EventsListLive,
          id: "upcoming_events",
          event: event_updated
        )

        {:noreply, socket}
    end
  end

  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketTierUpdated{ticket_tier: ticket_tier}},
        socket
      ) do
    # Get the event and send an update to refresh it in the list
    case Events.get_event(ticket_tier.event_id) do
      nil ->
        {:noreply, socket}

      event ->
        event_updated = %Ysc.MessagePassingEvents.EventUpdated{event: event}

        send_update(YscWeb.EventsListLive,
          id: "upcoming_events",
          event: event_updated
        )

        {:noreply, socket}
    end
  end

  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketTierDeleted{ticket_tier: ticket_tier}},
        socket
      ) do
    # Get the event and send an update to refresh it in the list
    case Events.get_event(ticket_tier.event_id) do
      nil ->
        {:noreply, socket}

      event ->
        event_updated = %Ysc.MessagePassingEvents.EventUpdated{event: event}

        send_update(YscWeb.EventsListLive,
          id: "upcoming_events",
          event: event_updated
        )

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationCreated{
           ticket_reservation: reservation
         }},
        socket
      ) do
    # Reservations affect availability, refresh the event
    ticket_tier = Events.get_ticket_tier(reservation.ticket_tier_id)

    if ticket_tier do
      case Events.get_event(ticket_tier.event_id) do
        nil ->
          {:noreply, socket}

        event ->
          event_updated = %Ysc.MessagePassingEvents.EventUpdated{event: event}

          send_update(YscWeb.EventsListLive,
            id: "upcoming_events",
            event: event_updated
          )

          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationFulfilled{
           ticket_reservation: reservation
         }},
        socket
      ) do
    # Reservations affect availability, refresh the event
    ticket_tier = Events.get_ticket_tier(reservation.ticket_tier_id)

    if ticket_tier do
      case Events.get_event(ticket_tier.event_id) do
        nil ->
          {:noreply, socket}

        event ->
          event_updated = %Ysc.MessagePassingEvents.EventUpdated{event: event}

          send_update(YscWeb.EventsListLive,
            id: "upcoming_events",
            event: event_updated
          )

          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationCancelled{
           ticket_reservation: reservation
         }},
        socket
      ) do
    # Reservations affect availability, refresh the event
    ticket_tier = Events.get_ticket_tier(reservation.ticket_tier_id)

    if ticket_tier do
      case Events.get_event(ticket_tier.event_id) do
        nil ->
          {:noreply, socket}

        event ->
          event_updated = %Ysc.MessagePassingEvents.EventUpdated{event: event}

          send_update(YscWeb.EventsListLive,
            id: "upcoming_events",
            event: event_updated
          )

          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_more_past_events", _params, socket) do
    current_limit = socket.assigns.past_events_limit
    # Increase by 10, max 50
    new_limit = min(current_limit + 10, 50)
    past_events = Events.list_past_events(new_limit)
    # Check if there are more events beyond the new limit
    has_more_past_events =
      if length(past_events) == new_limit && new_limit < 50 do
        Events.has_more_past_events?(new_limit)
      else
        false
      end

    {:noreply,
     socket
     |> assign(:past_events_limit, new_limit)
     |> assign(:has_more_past_events, has_more_past_events)
     |> stream(:past_events, past_events, reset: true)}
  end

  # Helper functions
  defp get_blur_hash(nil), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: nil}), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: blur_hash}), do: blur_hash

  defp event_image_url(nil), do: "/images/ysc_logo.png"

  defp event_image_url(%Image{optimized_image_path: nil} = image),
    do: image.raw_image_path

  defp event_image_url(%Image{optimized_image_path: optimized_path}),
    do: optimized_path

  defp random_past_events_title do
    ["Hvad var", "Det Som Varit", "Hva var", "Mikä oli", "Hvað var"]
    |> Enum.random()
  end
end
