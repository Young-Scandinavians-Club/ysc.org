defmodule YscWeb.EventsLive do
  use YscWeb, :live_view

  require Ysc.Logging

  import YscWeb.Live.AsyncHelpers

  alias Ysc.Events
  alias Ysc.Events.EventListCache
  alias YscWeb.DateDisplay

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-6 md:py-12">
      <%!-- The "Masthead" Header --%>
      <div class="max-w-screen-xl mx-auto px-4 mb-8 md:mb-16">
        <.page_masthead
          eyebrow="Events"
          title={
            if @total_upcoming_count == 0, do: "The Calendar", else: "What's Next"
          }
        />
      </div>

      <%!-- Hero and Event List (handled by component) --%>
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-12">
          <%!-- Events Grid --%>
          <div class="lg:col-span-9 min-h-[50vh] lg:min-h-[70vh] flex flex-col">
            <.live_component
              id={upcoming_events_list_id()}
              module={YscWeb.EventsListLive}
              show_hero={true}
              upcoming={true}
              defer_load={!@async_data_loaded}
              event_list_cache_version={@event_list_cache_version}
            />
          </div>

          <%!-- Sidebar --%>
          <aside class="lg:col-span-3 space-y-4 md:space-y-8">
            <.feature_card title="Upcoming Events">
              <p class="text-base text-zinc-600 leading-relaxed">
                Explore our curated calendar of events. From social gatherings to cultural celebrations, there's always something happening at YSC.
              </p>
            </.feature_card>
            <%!-- Get Involved - Always shown to encourage event hosting --%>
            <.feature_card title="Get Involved" title_tone={:accent}>
              <p class="text-base text-zinc-700 leading-relaxed mb-4">
                Have an idea for an event? We'd love to help you host it! Reach out through our contact page.
              </p>
              <.link
                navigate={
                  ~p"/contact?subject=Events&message=Hi%2C%20I%20have%20an%20idea%20for%20an%20event%20I%27d%20love%20to%20host%20with%20YSC.%20Here%27s%20what%20I%20had%20in%20mind%3A%20"
                }
                class="inline-flex items-center text-sm font-bold text-blue-600 hover:text-blue-700 hover:underline transition-colors"
              >
                Contact Us <.icon name="hero-arrow-right" class="w-4 h-4 ml-1" />
              </.link>
            </.feature_card>
            <div class="p-6 md:p-8 bg-white rounded-xl border border-zinc-100">
              <h4 class="text-sm font-black text-zinc-500 uppercase tracking-[0.2em] mb-3 md:mb-4">
                Stay Connected
              </h4>
              <p class="text-base text-zinc-600 leading-relaxed mb-4">
                Join our community to see what members are planning informally.
              </p>
              <div class="space-y-3">
                <.link
                  navigate={~p"/news"}
                  class="inline-flex items-center text-sm font-bold text-blue-600 hover:text-blue-700 hover:underline transition-colors"
                >
                  Read Club News
                  <.icon name="hero-arrow-right" class="w-4 h-4 ml-1" />
                </.link>
                <div
                  :if={
                    @site_setting_socials_partiful ||
                      (@current_user && @site_setting_socials_whatsapp)
                  }
                  class="border-t border-zinc-100 pt-3"
                >
                  <p class="text-sm text-zinc-500 mb-2 uppercase tracking-wide font-semibold">
                    Events & Community
                  </p>
                  <div class="flex flex-col gap-2">
                    <a
                      :if={@site_setting_socials_partiful}
                      href={@site_setting_socials_partiful}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="inline-flex items-center text-sm font-bold text-blue-600 hover:text-blue-700 hover:underline transition-colors"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        viewBox="0 0 48 48"
                        aria-hidden="true"
                        class="w-4 h-4 me-2 shrink-0"
                      >
                        <path
                          fill="none"
                          stroke="currentColor"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M14.358 43.5c4.39 0 7.755-4.082 7.755-7.965c0-2.35-1.224-3.266-1.224-4.998c0-1.434.916-1.942 1.732-1.942c1.026 0 2.14.816 4.59.816c5.714 0 13.89-4.49 13.89-12.047C41.1 9.299 31.81 4.5 23.028 4.5c-7.248 0-15.004 2.957-15.004 8.065c0 5.516 8.98 5.715 8.98 9.907c0 4.49-10.105 5.108-10.105 12.864c0 4.292 3.166 8.164 7.458 8.164"
                        />
                        <path
                          fill="none"
                          stroke="currentColor"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M12.416 37.896c-1.942 0-2.757-1.322-2.757-3.363c0-6.333 12.145-8.187 12.145-13.892c0-4.899-10.07-2.66-10.07-6.532c0-2.449 2.822-3.067 5.988-3.067c6.63 0 13.78 2.858 13.78 8.683c0 3.265-1.947 7.266-6.647 7.266c-.816 0-1.413-.253-2.44-.253c-8.074 0-3.56 11.169-10.01 11.169h.01z"
                        />
                      </svg>
                      Partiful
                    </a>
                    <a
                      :if={@current_user && @site_setting_socials_whatsapp}
                      href={@site_setting_socials_whatsapp}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="inline-flex items-center text-sm font-bold text-blue-600 hover:text-blue-700 hover:underline transition-colors"
                    >
                      <.icon name="hero-device-phone-mobile" class="w-4 h-4 mr-2" />
                      WhatsApp
                    </a>
                  </div>
                </div>
              </div>
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
              <div class="aspect-video rounded-xl bg-zinc-200 animate-pulse"></div>
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
                {random_past_events_title()}
              </span>
              <span class="absolute left-0 top-0 inline-block transition-all duration-500 ease-in-out translate-y-full opacity-0 group-hover:translate-y-0 group-hover:opacity-100 whitespace-nowrap">
                What Was
              </span>
            </h2>
            <div
              id="past-events"
              phx-update="stream"
              class="grid grid-cols-2 md:grid-cols-4 gap-4"
            >
              <div
                :for={{id, event} <- @streams.past_events}
                id={id}
                class="group relative aspect-video overflow-hidden rounded-xl opacity-80 hover:opacity-100 grayscale hover:grayscale-0 transition-all duration-300 ring-1 ring-zinc-200 hover:ring-2 hover:ring-blue-500 bg-white p-1"
              >
                <.link
                  navigate={~p"/events/#{event.id}"}
                  class="block w-full h-full"
                >
                  <div class="w-full h-full overflow-hidden rounded-xl relative">
                    <.live_component
                      id={"past-event-image-#{event.id}"}
                      module={YscWeb.Components.Image}
                      image={event.image}
                      aspect_class="h-full"
                      preferred_type={:optimized}
                      sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
                    />
                    <%!-- Title overlay — always visible --%>
                    <div class="absolute inset-0 z-[2] bg-gradient-to-t from-zinc-900/70 via-zinc-900/20 to-transparent">
                    </div>
                    <div class="absolute bottom-0 left-0 right-0 z-[3] p-3">
                      <h4 class="text-white text-sm font-black leading-tight line-clamp-2">
                        {event.title}
                      </h4>
                      <p
                        :if={event.start_date}
                        class="text-white/80 text-sm font-medium mt-1"
                      >
                        {DateDisplay.format_event_date_range(event, with_year: true)}
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
      |> assign(
        :meta_description,
        "Browse upcoming and past events hosted by the Young Scandinavians Club. Parties, dances, outdoor adventures, and more."
      )
      |> assign(:total_upcoming_count, 0)
      |> assign(:past_events_exist, false)
      |> assign(:past_events_limit, 10)
      |> assign(:has_more_past_events, false)
      |> assign(:async_data_loaded, false)
      |> assign(:event_list_cache_version, 0)
      |> stream(:past_events, [], reset: true)

    if connected?(socket) do
      # Subscribe to real-time updates only when connected
      Events.subscribe()
      EventListCache.subscribe()

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
      %{past_events_limit: past_events_limit}
    end)
  end

  @impl true
  def handle_async(
        :load_events_data,
        {:ok, %{past_events_limit: past_events_limit}},
        socket
      ) do
    {:noreply, assign_cached_events_data(socket, past_events_limit)}
  end

  def handle_async(:load_events_data, {:exit, reason}, socket) do
    Ysc.Logging.warning("Failed to load events data async: #{inspect(reason)}")
    {:noreply, assign(socket, :async_data_loaded, true)}
  end

  @impl true
  def handle_info({:event_list_cache_invalidated, _version}, socket) do
    {:noreply,
     socket
     |> assign(:event_list_cache_version, System.unique_integer([:positive]))
     |> refresh_events_from_cache()}
  end

  def handle_info({Ysc.Events, %_event{event: _} = base_event}, socket) do
    notify_events_list_update(socket, base_event)
  end

  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketTierAdded{ticket_tier: ticket_tier}},
        socket
      ) do
    refresh_events_list_for_event_id(socket, ticket_tier.event_id)
  end

  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketTierUpdated{ticket_tier: ticket_tier}},
        socket
      ) do
    refresh_events_list_for_event_id(socket, ticket_tier.event_id)
  end

  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketTierDeleted{ticket_tier: ticket_tier}},
        socket
      ) do
    refresh_events_list_for_event_id(socket, ticket_tier.event_id)
  end

  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationCreated{
           ticket_reservation: reservation,
           event_id: event_id
         }},
        socket
      ) do
    refresh_events_list_for_reservation(socket, event_id, reservation)
  end

  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationFulfilled{
           ticket_reservation: reservation,
           event_id: event_id
         }},
        socket
      ) do
    refresh_events_list_for_reservation(socket, event_id, reservation)
  end

  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationCancelled{
           ticket_reservation: reservation,
           event_id: event_id
         }},
        socket
      ) do
    refresh_events_list_for_reservation(socket, event_id, reservation)
  end

  # Catch-all for event messages that do not affect the events index (e.g.
  # EventUpdateCreated from parallel tests or future message types).
  def handle_info({Ysc.Events, _msg}, socket), do: {:noreply, socket}

  defp upcoming_events_list_id, do: "upcoming_events"

  defp refresh_events_from_cache(socket) do
    if socket.assigns.async_data_loaded do
      assign_cached_events_data(socket, socket.assigns.past_events_limit)
    else
      socket
    end
  end

  defp assign_cached_events_data(socket, past_events_limit) do
    past_events = Events.list_past_events(past_events_limit)

    has_more_past_events =
      if length(past_events) == past_events_limit do
        allow_sandbox_access()
        Events.has_more_past_events?(past_events_limit)
      else
        false
      end

    socket
    |> assign(:total_upcoming_count, Events.count_upcoming_events())
    |> assign(:past_events_exist, Enum.any?(past_events))
    |> assign(:has_more_past_events, has_more_past_events)
    |> assign(:async_data_loaded, true)
    |> stream(:past_events, past_events, reset: true)
  end

  defp notify_events_list_update(socket, event_message) do
    send_update(YscWeb.EventsListLive,
      id: upcoming_events_list_id(),
      event: event_message
    )

    {:noreply, socket}
  end

  defp refresh_events_list_for_event_id(socket, event_id) do
    case Events.get_event(event_id) do
      nil ->
        {:noreply, socket}

      event ->
        notify_events_list_update(
          socket,
          %Ysc.MessagePassingEvents.EventUpdated{event: event}
        )
    end
  end

  defp refresh_events_list_for_reservation(socket, event_id, _reservation)
       when not is_nil(event_id) do
    refresh_events_list_for_event_id(socket, event_id)
  end

  defp refresh_events_list_for_reservation(socket, _event_id, reservation) do
    case Events.get_ticket_tier(reservation.ticket_tier_id) do
      nil ->
        {:noreply, socket}

      ticket_tier ->
        refresh_events_list_for_event_id(socket, ticket_tier.event_id)
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
  defp random_past_events_title do
    ["Hvad var", "Det Som Varit", "Hva var", "Mikä oli", "Hvað var"]
    |> Enum.random()
  end
end
