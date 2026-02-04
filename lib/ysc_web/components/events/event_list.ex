defmodule YscWeb.EventsListLive do
  use YscWeb, :live_component

  alias Ysc.Events
  alias Money

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Loading skeleton for hero and events --%>
      <div :if={@defer_load} class="max-w-screen-xl mx-auto">
        <%!-- Hero skeleton --%>
        <div :if={@show_hero} class="mb-10 animate-pulse">
          <div class="aspect-[16/10] rounded-xl bg-zinc-200"></div>
        </div>
        <%!-- Events grid skeleton --%>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <%= for _i <- 1..4 do %>
            <div class="bg-white rounded-xl p-4 ring-1 ring-zinc-100 shadow-sm animate-pulse">
              <div class="aspect-[16/10] rounded-lg mb-6 bg-zinc-200"></div>
              <div class="space-y-3">
                <div class="h-4 bg-zinc-200 rounded w-1/4"></div>
                <div class="h-6 bg-zinc-200 rounded w-3/4"></div>
                <div class="h-4 bg-zinc-200 rounded w-1/2"></div>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Hero Event Section (only if show_hero is true) --%>
      <div
        :if={!@defer_load && @show_hero && @hero_event != nil}
        class="max-w-screen-xl mx-auto mb-10"
      >
        <div id="hero-event" class="group">
          <.link
            navigate={~p"/events/#{@hero_event.id}"}
            class="block overflow-hidden rounded-2xl border border-zinc-100 bg-white shadow-xl transition-all duration-300 hover:shadow-2xl sm:border-0 sm:bg-transparent sm:shadow-none"
          >
            <div class="relative flex flex-col sm:block sm:aspect-[16/10] sm:rounded-xl sm:overflow-hidden sm:shadow-2xl">
              <%!-- Image container --%>
              <div class={[
                "relative aspect-[16/9] w-full overflow-hidden sm:absolute sm:inset-0 sm:aspect-auto sm:h-full",
                if(
                  (Map.get(@hero_event, :state) || Map.get(@hero_event, "state")) in [
                    :cancelled,
                    "cancelled"
                  ],
                  do: "grayscale"
                )
              ]}>
                <canvas
                  id={"blur-hash-hero-#{@hero_event.id}"}
                  src={get_blur_hash(@hero_event.image)}
                  class="absolute inset-0 z-0 w-full h-full object-cover"
                  phx-hook="BlurHashCanvas"
                >
                </canvas>
                <img
                  src={event_image_url(@hero_event.image)}
                  id={"image-hero-#{@hero_event.id}"}
                  phx-hook="BlurHashImage"
                  class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out object-cover w-full h-full group-hover:scale-105 transition-transform duration-700"
                  loading="eager"
                  alt={
                    if @hero_event.image,
                      do:
                        @hero_event.image.alt_text || @hero_event.image.title ||
                          @hero_event.title ||
                          "Event image",
                      else: "Event image"
                  }
                />

                <%!-- Overlay gradient for text readability (hidden on mobile, shown on sm+) --%>
                <div class="hidden sm:block absolute inset-0 z-[2] bg-gradient-to-t from-zinc-900/80 via-zinc-900/40 to-transparent">
                </div>
              </div>

              <%!-- Content (stacked on mobile, overlaid on sm+) --%>
              <div class="relative z-[3] flex flex-col p-5 sm:absolute sm:inset-0 sm:justify-end sm:p-8 lg:p-12 transition-all duration-500">
                <div class="max-w-3xl">
                  <div class="flex flex-wrap items-center gap-2 mb-4 grayscale-0">
                    <span class="px-3 py-1.5 bg-slate-600 text-white text-xs font-black uppercase tracking-widest rounded-lg shadow-lg sm:bg-slate-500/90 sm:backdrop-blur-md sm:border sm:border-slate-400 animate-badge-shine-slate">
                      <.icon
                        name="hero-calendar-solid"
                        class="w-3.5 h-3.5 inline me-0.5 relative z-10"
                      />Happening Soon
                    </span>
                    <%= for badge <- get_hero_event_badges(@hero_event) do %>
                      <span class={[
                        "px-3 py-1.5 text-white text-xs font-black uppercase tracking-widest rounded-lg shadow-lg",
                        badge_class_mobile(badge),
                        badge_class_desktop_responsive(badge),
                        if(badge.text == "Going Fast!",
                          do: "animate-badge-shine-emerald",
                          else: ""
                        )
                      ]}>
                        <.icon
                          :if={badge.icon}
                          name={badge.icon}
                          class="w-3.5 h-3.5 inline me-0.5 relative z-10"
                        />
                        <span class="relative z-10"><%= badge.text %></span>
                      </span>
                    <% end %>
                  </div>

                  <h2 class="text-3xl font-black leading-tight tracking-tighter text-zinc-900 sm:text-zinc-50 sm:text-4xl lg:text-5xl xl:text-6xl mb-3 transition-colors duration-300 hero-title-shadow">
                    <%= @hero_event.title %>
                  </h2>

                  <div class="flex flex-wrap items-center gap-x-3 gap-y-1 mb-4 text-zinc-500 sm:text-white/80">
                    <span class="text-xs sm:text-sm font-black uppercase tracking-[0.1em]">
                      <%= format_event_date_time(@hero_event) %>
                    </span>
                    <span
                      :if={@hero_event.location_name}
                      class="h-3 w-px bg-zinc-300 sm:bg-white/40"
                    >
                    </span>
                    <span
                      :if={@hero_event.location_name}
                      class="text-xs sm:text-sm font-bold uppercase tracking-widest flex items-center gap-1"
                    >
                      <.icon name="hero-map-pin" class="w-4 h-4" />
                      <%= @hero_event.location_name %>
                    </span>
                  </div>

                  <p
                    :if={@hero_event.description}
                    class="text-zinc-600 sm:text-zinc-200 text-sm sm:text-base lg:text-lg leading-relaxed line-clamp-2 mb-6 max-w-prose hero-description-shadow"
                  >
                    <%= @hero_event.description %>
                  </p>

                  <div class="flex items-center gap-4 pt-4 border-t border-zinc-100 sm:border-white/20">
                    <span class="text-xs sm:text-sm font-black text-zinc-900 sm:text-white rounded-xl border border-zinc-200 px-4 py-2">
                      <%= @hero_event.pricing_info.display_text %>
                    </span>
                    <span class="hidden sm:inline-flex items-center gap-1 text-sm font-bold text-white/90 hover:text-white transition-colors">
                      View Details <.icon name="hero-arrow-right" class="w-4 h-4" />
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </.link>
        </div>
      </div>

      <%!-- Event List Section --%>
      <div
        :if={!@defer_load && @event_count > 0}
        class="grid grid-cols-1 md:grid-cols-2 gap-8"
      >
        <div :for={{id, event} <- @streams.events} id={id}>
          <.event_card
            event={event}
            sold_out={event_sold_out?(event)}
            selling_fast={Map.get(event, :selling_fast, false)}
          />
        </div>
      </div>

      <div
        :if={!@defer_load && @total_event_count == 0}
        class="flex flex-col items-center justify-center py-10 md:py-20 px-0 md:px-6 flex-grow"
      >
        <div class="flex flex-col items-center justify-center w-full border-2 border-dashed border-zinc-100 rounded-3xl bg-gradient-to-br from-zinc-50/50 via-white to-zinc-50/30 backdrop-blur-sm p-6 md:p-12 shadow-sm">
          <div class="p-4 bg-white rounded-2xl shadow-sm mb-6 ring-1 ring-zinc-100">
            <.icon
              name="hero-calendar-days"
              class="w-10 h-10 md:w-12 md:h-12 text-zinc-300"
            />
          </div>
          <h3 class="text-xl md:text-2xl font-black text-zinc-900 tracking-tight mb-2 text-center">
            The calendar is clear (for now)
          </h3>
          <p class="text-zinc-500 text-center max-w-sm mb-8 text-sm md:text-base leading-relaxed">
            We're currently brewing some new ideas. Check back soon or join our community to see what's happening behind the scenes.
          </p>
          <div class="flex flex-col sm:flex-row gap-3 md:gap-4 w-full sm:w-auto">
            <.link
              navigate={~p"/news"}
              class="inline-flex items-center justify-center px-6 py-3 bg-zinc-900 text-white rounded-xl font-bold hover:bg-zinc-800 transition-all shadow-lg hover:scale-105 active:scale-95 text-sm md:text-base"
            >
              Read Latest News <.icon name="hero-newspaper" class="w-5 h-5 ml-2" />
            </.link>
            <.link
              navigate={~p"/contact"}
              class="inline-flex items-center justify-center px-6 py-3 bg-white border border-zinc-200 text-zinc-600 rounded-xl font-bold hover:bg-zinc-50 transition-all shadow-sm text-sm md:text-base"
            >
              Suggest an Event
              <.icon name="hero-light-bulb-solid" class="w-5 h-5 ml-2" />
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    # Check if this update includes an event message (from send_update in parent)
    event_message = Map.get(assigns, :event)

    # Check if we should defer loading (for initial static render performance)
    defer_load = Map.get(assigns, :defer_load, false)

    socket =
      cond do
        event_message ->
          # Handle event message from parent LiveView
          # This is a real-time update, only modify the stream, don't reload everything
          # Ensure socket has all necessary assigns (send_update only passes what we give it)
          socket = ensure_required_assigns(socket, assigns)

          # Ensure stream is initialized (component might have been just mounted)
          socket = ensure_stream_initialized_for_message(socket)

          handle_event_message(event_message, socket)

        defer_load ->
          # Defer loading - show loading state until parent signals ready
          show_hero = Map.get(assigns, :show_hero, false)
          upcoming = Map.get(assigns, :upcoming, true)
          limit = Map.get(assigns, :limit)

          socket
          |> assign(:show_hero, show_hero)
          |> assign(:upcoming, upcoming)
          |> assign(:limit, limit)
          |> assign(:defer_load, true)
          |> assign(:hero_event, nil)
          |> assign(:event_count, 0)
          |> assign(:total_event_count, 0)
          |> stream(:events, [], reset: true)

        true ->
          # Normal update - load events (this happens on mount or when assigns change)
          socket = load_events(assigns, socket)
          assign(socket, :defer_load, false)
      end

    {:ok, socket}
  end

  # Ensure socket has all required assigns (send_update only passes what we give it)
  # We need to preserve existing assigns from socket
  defp ensure_required_assigns(socket, assigns) do
    # Merge assigns from update with existing socket assigns
    # Prefer new assigns if provided, otherwise keep existing
    show_hero =
      Map.get(assigns, :show_hero) || socket.assigns[:show_hero] || false

    upcoming = Map.get(assigns, :upcoming) || socket.assigns[:upcoming] || true
    limit = Map.get(assigns, :limit) || socket.assigns[:limit]

    socket
    |> assign(:show_hero, show_hero)
    |> assign(:upcoming, upcoming)
    |> assign(:limit, limit)
  end

  # Ensure stream is initialized when handling event messages
  # If stream doesn't exist, we need to load events first
  defp ensure_stream_initialized_for_message(socket) do
    has_stream =
      Map.has_key?(socket.assigns, :streams) &&
        Map.has_key?(socket.assigns.streams, :events)

    if has_stream do
      socket
    else
      # Stream not initialized - load events first
      # This can happen if send_update is called before the component is fully mounted
      show_hero = socket.assigns[:show_hero] || false
      upcoming = socket.assigns[:upcoming] || true
      limit = socket.assigns[:limit]

      load_events(
        %{show_hero: show_hero, upcoming: upcoming, limit: limit},
        socket
      )
    end
  end

  defp load_events(assigns, socket) do
    upcoming = Map.get(assigns, :upcoming, true)
    limit = Map.get(assigns, :limit)
    show_hero = Map.get(assigns, :show_hero, false)

    # Load all events once - avoid duplicate queries
    {events, hero_event} =
      if upcoming do
        all_events =
          if limit,
            do: Events.list_upcoming_events(limit + 1),
            else: Events.list_upcoming_events()

        # Get hero event from the loaded events if show_hero is true
        hero_event = if show_hero, do: List.first(all_events), else: nil

        # Filter out the hero event if we're showing it separately
        filtered_events =
          if show_hero && hero_event do
            Enum.reject(all_events, fn event -> event.id == hero_event.id end)
          else
            all_events
          end

        # Apply limit after filtering
        result_events =
          if limit, do: Enum.take(filtered_events, limit), else: filtered_events

        {result_events, hero_event}
      else
        result_events =
          if limit,
            do: Events.list_past_events(limit),
            else: Events.list_past_events()

        {result_events, nil}
      end

    # Calculate total event count (including hero if shown separately)
    total_event_count =
      if show_hero && hero_event, do: length(events) + 1, else: length(events)

    socket
    |> stream(:events, events, reset: true)
    |> assign(:event_count, length(events))
    |> assign(:total_event_count, total_event_count)
    |> assign(:upcoming, upcoming)
    |> assign(:limit, limit)
    |> assign(:show_hero, show_hero)
    |> assign(:hero_event, hero_event)
  end

  defp handle_event_message(_event_message, socket) do
    # On any event change (add, update, delete), reload everything from DB
    # This is simpler and more reliable than trying to update individual items
    reload_all_events(socket)
  end

  # Reload all events from database and update hero/stream
  defp reload_all_events(socket) do
    upcoming = socket.assigns[:upcoming] || true
    show_hero = socket.assigns[:show_hero] || false
    limit = socket.assigns[:limit]

    # Load all events once - avoid duplicate queries
    {events, hero_event} =
      if upcoming do
        all_events =
          if limit,
            do: Events.list_upcoming_events(limit + 1),
            else: Events.list_upcoming_events()

        # Get hero event from the loaded events if show_hero is true
        hero_event = if show_hero, do: List.first(all_events), else: nil

        # Filter out the hero event if we're showing it separately
        filtered_events =
          if show_hero && hero_event do
            Enum.reject(all_events, fn event -> event.id == hero_event.id end)
          else
            all_events
          end

        # Apply limit after filtering
        result_events =
          if limit, do: Enum.take(filtered_events, limit), else: filtered_events

        {result_events, hero_event}
      else
        result_events =
          if limit,
            do: Events.list_past_events(limit),
            else: Events.list_past_events()

        {result_events, nil}
      end

    # Calculate total event count (including hero if shown separately)
    total_event_count =
      if show_hero && hero_event, do: length(events) + 1, else: length(events)

    socket
    |> stream(:events, events, reset: true)
    |> assign(:event_count, length(events))
    |> assign(:total_event_count, total_event_count)
    |> assign(:hero_event, hero_event)
  end

  defp event_sold_out?(event) do
    # Cache current time to avoid repeated system calls
    now = DateTime.utc_now()

    # Events from list_upcoming_events/list_past_events are preloaded with ticket_tiers
    # via add_pricing_info_batch, so this should always be available
    ticket_tiers = Map.get(event, :ticket_tiers) || []

    # Filter out donation tiers - donations don't count toward "sold out" status
    non_donation_tiers =
      Enum.filter(ticket_tiers, fn tier ->
        tier_type = Map.get(tier, :type) || Map.get(tier, "type")
        tier_type != "donation" && tier_type != :donation
      end)

    # If there are no non-donation tiers, event is not sold out
    if Enum.empty?(non_donation_tiers) do
      false
    else
      # Filter out pre-sale tiers (tiers that haven't started selling yet)
      # We want to check tiers that are on sale OR have ended their sale
      relevant_tiers =
        Enum.filter(non_donation_tiers, fn tier ->
          # Include tiers that are on sale OR have ended their sale
          # Exclude tiers that haven't started their sale yet (pre-sale)
          tier_on_sale?(tier, now) || tier_sale_ended?(tier, now)
        end)

      # If there are no relevant tiers (all are pre-sale), event is not sold out
      if Enum.empty?(relevant_tiers) do
        false
      else
        # Check if all relevant non-donation tiers are sold out
        # A tier is sold out if available == 0 (unlimited tiers never count as sold out)
        all_tiers_sold_out =
          Enum.all?(relevant_tiers, fn tier ->
            available = get_available_quantity(tier)
            available == 0
          end)

        # Also check event capacity if max_attendees is set
        # (Note: This includes all tickets including donations, but if capacity is reached,
        #  all regular tickets are effectively sold out even if some tiers show availability)
        event_at_capacity =
          case Map.get(event, :max_attendees) || Map.get(event, "max_attendees") do
            nil ->
              false

            _ ->
              # Events from list_upcoming_events/list_past_events are preloaded with ticket_count
              # via add_pricing_info_batch, so this should always be available
              ticket_count = Map.get(event, :ticket_count) || 0

              max_attendees =
                Map.get(event, :max_attendees) ||
                  Map.get(event, "max_attendees")

              ticket_count >= max_attendees
          end

        all_tiers_sold_out || event_at_capacity
      end
    end
  end

  defp tier_on_sale?(ticket_tier, now) do
    start_date =
      Map.get(ticket_tier, :start_date) || Map.get(ticket_tier, "start_date")

    end_date =
      Map.get(ticket_tier, :end_date) || Map.get(ticket_tier, "end_date")

    # Check if sale has started
    sale_started =
      case start_date do
        nil -> true
        sd -> DateTime.compare(now, sd) != :lt
      end

    # Check if sale has ended
    sale_ended =
      case end_date do
        nil -> false
        ed -> DateTime.compare(now, ed) == :gt
      end

    sale_started && !sale_ended
  end

  defp tier_sale_ended?(ticket_tier, now) do
    end_date =
      Map.get(ticket_tier, :end_date) || Map.get(ticket_tier, "end_date")

    case end_date do
      nil -> false
      ed -> DateTime.compare(now, ed) == :gt
    end
  end

  defp get_available_quantity(ticket_tier) do
    quantity =
      Map.get(ticket_tier, :quantity) || Map.get(ticket_tier, "quantity")

    sold_count =
      Map.get(ticket_tier, :sold_tickets_count) ||
        Map.get(ticket_tier, "sold_tickets_count") || 0

    case quantity do
      # Unlimited
      nil ->
        :unlimited

      0 ->
        :unlimited

      qty ->
        available = qty - sold_count
        max(0, available)
    end
  end

  # Hero event helper functions (from EventsLive)
  defp get_blur_hash(image) do
    if image && image.blur_hash,
      do: image.blur_hash,
      else: "LKN]Rv%2Tw=w]~RBVZRi};RPxuwH"
  end

  defp event_image_url(image) do
    if image && image.optimized_image_path,
      do: image.optimized_image_path,
      else: "/images/placeholder-event.jpg"
  end

  defp format_event_date_time(event) do
    start_date = Map.get(event, :start_date)
    start_time = Map.get(event, :start_time)

    cond do
      start_date && start_time ->
        date_str = Timex.format!(start_date, "{Mshort} {D}, {YYYY}")
        time_str = Timex.format!(start_time, "{h12}:{m} {AM}")
        "#{date_str} at #{time_str}"

      start_date ->
        Timex.format!(start_date, "{Mshort} {D}, {YYYY}")

      true ->
        "Date TBD"
    end
  end

  defp get_hero_event_badges(event) do
    badges = []

    badges =
      if event_sold_out?(event) do
        [%{text: "Sold Out", icon: "hero-ticket", class: "bg-red-600"} | badges]
      else
        badges
      end

    badges =
      if Map.get(event, :selling_fast, false) do
        [
          %{text: "Going Fast!", icon: "hero-fire", class: "bg-emerald-600"}
          | badges
        ]
      else
        badges
      end

    badges =
      if (Map.get(event, :state) || Map.get(event, "state")) in [
           :cancelled,
           "cancelled"
         ] do
        [
          %{text: "Cancelled", icon: "hero-x-circle", class: "bg-zinc-600"}
          | badges
        ]
      else
        badges
      end

    Enum.reverse(badges)
  end

  defp badge_class_mobile(badge) do
    case badge.text do
      "Sold Out" -> "bg-red-600"
      "Going Fast!" -> "bg-emerald-600"
      "Cancelled" -> "bg-zinc-600"
      _ -> "bg-slate-600"
    end
  end

  defp badge_class_desktop_responsive(badge) do
    case badge.text do
      "Sold Out" ->
        "sm:bg-red-500/90 sm:backdrop-blur-md sm:border sm:border-red-400"

      "Going Fast!" ->
        "sm:bg-emerald-500/90 sm:backdrop-blur-md sm:border sm:border-emerald-400"

      "Cancelled" ->
        "sm:bg-zinc-500/90 sm:backdrop-blur-md sm:border sm:border-zinc-400"

      _ ->
        "sm:bg-slate-500/90 sm:backdrop-blur-md sm:border sm:border-slate-400"
    end
  end
end
