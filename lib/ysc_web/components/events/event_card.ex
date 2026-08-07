defmodule YscWeb.Components.Events.EventCard do
  @moduledoc """
  Reusable event card component that matches the design used in EventsListLive.
  """
  use Phoenix.Component

  import YscWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  alias YscWeb.DateDisplay
  alias YscWeb.PlainText

  attr :event, :any, required: true
  attr :class, :string, default: nil
  attr :sold_out, :boolean, default: false
  attr :selling_fast, :boolean, default: false

  attr :variant, :string,
    default: "default",
    doc: "Card variant: 'default' or 'dark'"

  def event_card(assigns) do
    assigns =
      assigns
      |> assign(
        :badges,
        get_event_badges_for_card(
          assigns.event,
          assigns.sold_out,
          assigns.selling_fast
        )
      )
      |> assign(
        :description_preview,
        PlainText.normalize_preview(assigns.event.description)
      )

    ~H"""
    <div class={[
      "group flex flex-col rounded-xl border transition-all duration-300 relative hover:ring-2 hover:ring-blue-500 p-2",
      if(@variant == "dark",
        do: "bg-zinc-800 border-zinc-700",
        else: "bg-white border-zinc-100"
      ),
      @class
    ]}>
      <.link navigate={~p"/events/#{@event.id}"} class="block relative">
        <div class={[
          "relative aspect-video overflow-hidden rounded-lg",
          @event.state == :cancelled && "grayscale"
        ]}>
          <.live_component
            id={"event-card-image-#{@event.id}"}
            module={YscWeb.Components.Image}
            image={@event.image}
            aspect_class="h-full"
            preferred_type={:optimized}
            sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
          />
        </div>
        <div class="absolute top-6 left-6 flex gap-2 z-[2] flex-wrap pointer-events-none">
          <%= for badge <- @badges do %>
            <span class={[
              "px-3 py-1.5 rounded text-xs font-black uppercase tracking-widest pointer-events-auto",
              badge_class(badge),
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
              <span class="relative z-10">{badge.text}</span>
            </span>
          <% end %>
        </div>
      </.link>

      <div class="px-4 pb-4 pt-5 flex flex-col flex-1">
        <div class="flex items-center gap-2 mb-4">
          <span class={[
            "text-sm font-black px-2.5 py-1 rounded uppercase tracking-[0.2em]",
            if(@variant == "dark",
              do: "text-zinc-300 bg-zinc-800",
              else: "text-zinc-900 bg-zinc-100"
            )
          ]}>
            {format_event_date(@event)}
          </span>
          <span
            :if={@event.start_time && @event.start_time != ""}
            class={[
              "text-sm font-bold uppercase tracking-widest",
              if(@variant == "dark", do: "text-zinc-500", else: "text-zinc-600")
            ]}
          >
            {format_start_time(@event.start_time)}
          </span>
        </div>
        <.link navigate={~p"/events/#{@event.id}"} class="block">
          <h3 class={[
            "text-2xl font-black tracking-tight leading-tight mb-4 group-hover:text-blue-600 group-hover:underline transition-colors line-clamp-2 min-h-[4rem]",
            if(@variant == "dark", do: "text-white", else: "text-zinc-900")
          ]}>
            {@event.title}
          </h3>
        </.link>
        <p
          :if={@description_preview}
          class={[
            "text-base leading-relaxed mb-6 line-clamp-2",
            if(@variant == "dark", do: "text-zinc-300", else: "text-zinc-500")
          ]}
        >
          {@description_preview}
        </p>

        <div class={[
          "mt-auto pt-5 border-t space-y-3",
          if(@variant == "dark", do: "border-zinc-700", else: "border-zinc-100")
        ]}>
          <div
            :if={@event.location_name}
            class={[
              "flex items-center gap-1.5 text-sm",
              if(@variant == "dark", do: "text-zinc-500", else: "text-zinc-400")
            ]}
          >
            <.icon name="hero-map-pin" class="w-4 h-4 flex-shrink-0" />
            <span class="truncate">{@event.location_name}</span>
          </div>
          <div class="flex items-center justify-between gap-3">
            <span class={[
              "px-3 py-1.5 rounded text-sm font-black border",
              if(@variant == "dark",
                do: "bg-zinc-900 text-zinc-100 border-zinc-700",
                else: "bg-zinc-50 text-zinc-900 border-zinc-200"
              ),
              @sold_out && "line-through opacity-60"
            ]}>
              {@event.pricing_info.display_text}
            </span>
            <.icon
              name="hero-arrow-right"
              class={[
                "w-5 h-5 group-hover:text-blue-600 group-hover:translate-x-1 transition-all flex-shrink-0",
                if(@variant == "dark", do: "text-zinc-500", else: "text-zinc-300")
              ]}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_start_time(time) when is_binary(time) do
    format_start_time(Timex.parse!(time, "{h12}:{m} {AM}"))
  end

  defp format_start_time(time) do
    Timex.format!(time, "{h12}:{m} {AM}")
  end

  defp format_event_date(event) do
    DateDisplay.format_event_date_range(event)
  end

  defp get_event_badges_for_card(event, sold_out, selling_fast) do
    state = Map.get(event, :state) || Map.get(event, "state")

    # If cancelled, only show "Cancelled" badge
    if state == :cancelled or state == "cancelled" do
      [%{text: "Cancelled", class: "bg-red-500 text-white", icon: nil}]
    else
      # If sold out (and not cancelled), only show "Sold Out" badge
      if sold_out do
        [%{text: "Sold Out", class: "bg-red-500 text-white", icon: nil}]
      else
        # Show active badges
        get_active_badges_for_card(event, selling_fast)
      end
    end
  end

  defp get_active_badges_for_card(event, selling_fast) do
    # Check if published_at exists (no badges for unpublished events)
    published_at =
      Map.get(event, :published_at) || Map.get(event, "published_at")

    if published_at != nil do
      badges = []

      # Add "Save the Date" badge if applicable
      tickets_tbd = Map.get(event, :tickets_tbd, false)

      tbd_badge =
        if tickets_tbd do
          [
            %{
              text: "Save the Date",
              class: "bg-blue-500 text-white",
              icon: "hero-ticket"
            }
          ]
        else
          []
        end

      badges = badges ++ tbd_badge

      # Add "Just Added" badge if applicable (within 48 hours of publishing)
      just_added_badge =
        if DateTime.diff(DateTime.utc_now(), published_at, :hour) <= 48 do
          [%{text: "Just Added", class: "bg-zinc-600 text-white", icon: nil}]
        else
          []
        end

      badges = badges ++ just_added_badge

      # Add "Today"/"Tomorrow"/"Days Left" badge based on how soon the event is
      day_label = DateDisplay.event_day_label(event)
      days_left = days_until_event_start(event)

      proximity_badge =
        cond do
          day_label == :today ->
            [
              %{
                text: "Today",
                class: "bg-red-600 text-white animate-pulse",
                icon: "hero-bolt-solid"
              }
            ]

          day_label == :tomorrow ->
            [%{text: "Tomorrow", class: "bg-orange-500 text-white", icon: nil}]

          days_left != nil and days_left >= 2 and days_left <= 3 ->
            [%{text: "#{days_left} days left", class: "bg-sky-500 text-white", icon: nil}]

          true ->
            []
        end

      badges = badges ++ proximity_badge

      # Add "Selling Fast!" badge if applicable
      selling_fast_badge =
        if selling_fast do
          [
            %{
              text: "Going Fast!",
              class: "bg-emerald-600 text-white",
              icon: "hero-bolt-solid"
            }
          ]
        else
          []
        end

      badges ++ selling_fast_badge
    else
      []
    end
  end

  defp badge_class(%{class: class}), do: class

  defp days_until_event_start(event) when is_map(event) do
    start_date = Map.get(event, :start_date)

    if start_date == nil do
      nil
    else
      now = DateTime.utc_now()

      # If event is in the past, return nil
      if DateTime.compare(now, start_date) == :gt do
        nil
      else
        # Calculate days difference using calendar days
        event_date_only = DateTime.to_date(start_date)
        now_date_only = DateTime.to_date(now)
        diff = Date.diff(event_date_only, now_date_only)
        max(0, diff)
      end
    end
  end
end
