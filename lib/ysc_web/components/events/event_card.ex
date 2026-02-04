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

  alias Ysc.Media.Image

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

    ~H"""
    <div class={[
      "group flex flex-col rounded-xl border shadow-sm hover:shadow-2xl ring-offset-0 hover:ring-2 hover:ring-blue-500/20 transition-all duration-300 overflow-hidden relative",
      if(@variant == "dark",
        do: "bg-zinc-800 border-zinc-700",
        else: "bg-white border-zinc-100"
      ),
      @class
    ]}>
      <.link navigate={~p"/events/#{@event.id}"} class="block relative">
        <div class={[
          "relative aspect-video overflow-hidden",
          @event.state == :cancelled && "grayscale"
        ]}>
          <canvas
            id={"blur-hash-card-#{@event.id}"}
            src={get_blur_hash(@event.image)}
            class="absolute inset-0 z-0 w-full h-full object-cover"
            phx-hook="BlurHashCanvas"
          >
          </canvas>
          <img
            src={event_image_url(@event.image)}
            id={"image-card-#{@event.id}"}
            phx-hook="BlurHashImage"
            class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out object-cover w-full h-full group-hover:scale-110 transition-transform duration-700"
            loading="lazy"
            alt={
              if @event.image,
                do:
                  @event.image.alt_text || @event.image.title || @event.title ||
                    "Event image",
                else: "Event image"
            }
          />
        </div>
        <div class="absolute top-4 left-4 flex gap-2 z-[2] flex-wrap pointer-events-none">
          <%= for badge <- @badges do %>
            <span class={[
              "px-3 py-1.5 rounded-lg text-xs font-black uppercase tracking-widest shadow-lg pointer-events-auto",
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
              <span class="relative z-10"><%= badge.text %></span>
            </span>
          <% end %>
        </div>
      </.link>

      <div class="p-8 flex flex-col flex-1">
        <div class="flex items-center gap-2 mb-4">
          <span class={[
            "text-xs font-black px-2.5 py-1 rounded uppercase tracking-[0.2em]",
            if(@variant == "dark",
              do: "text-zinc-300 bg-zinc-800",
              else: "text-zinc-900 bg-zinc-100"
            )
          ]}>
            <%= format_event_date(@event) %>
          </span>
          <span
            :if={@event.start_time && @event.start_time != ""}
            class={[
              "text-xs font-bold uppercase tracking-widest",
              if(@variant == "dark", do: "text-zinc-500", else: "text-zinc-600")
            ]}
          >
            <%= format_start_time(@event.start_time) %>
          </span>
        </div>
        <.link navigate={~p"/events/#{@event.id}"} class="block">
          <h3 class={[
            "text-2xl font-black tracking-tighter leading-tight mb-4 group-hover:text-blue-600 transition-colors line-clamp-2 min-h-[4rem]",
            if(@variant == "dark", do: "text-white", else: "text-zinc-900")
          ]}>
            <%= @event.title %>
          </h3>
        </.link>
        <p
          :if={@event.description}
          class={[
            "text-base leading-relaxed mb-6 line-clamp-2",
            if(@variant == "dark", do: "text-zinc-300", else: "text-zinc-500")
          ]}
        >
          <%= @event.description %>
        </p>

        <div class={[
          "mt-auto pt-6 border-t flex items-center justify-between",
          if(@variant == "dark", do: "border-zinc-700", else: "border-zinc-50")
        ]}>
          <div class="flex items-center gap-4 flex-1">
            <span
              :if={@event.location_name}
              class={[
                "text-sm font-bold flex items-center gap-1.5",
                if(@variant == "dark", do: "text-zinc-500", else: "text-zinc-600")
              ]}
            >
              <.icon name="hero-map-pin" class="w-5 h-5" />
              <%= @event.location_name %>
            </span>
            <span class={[
              "backdrop-blur-md px-4 py-2 rounded-xl text-sm font-black shadow-sm ring-1",
              if(@variant == "dark",
                do: "bg-zinc-900/90 text-white ring-white/10",
                else: "bg-white/90 text-zinc-900 ring-black/5"
              ),
              @sold_out && "line-through opacity-60"
            ]}>
              <%= @event.pricing_info.display_text %>
            </span>
          </div>
          <.icon
            name="hero-arrow-right"
            class={[
              "w-5 h-5 group-hover:text-blue-600 group-hover:translate-x-1 transition-all flex-shrink-0",
              if(@variant == "dark", do: "text-zinc-500", else: "text-zinc-200")
            ]}
          />
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
    Timex.format!(event.start_date, "{Mshort} {D}")
  end

  defp get_blur_hash(nil), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: nil}), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: blur_hash}), do: blur_hash
  defp get_blur_hash(_), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

  defp event_image_url(nil), do: "/images/ysc_logo.png"

  defp event_image_url(%Image{optimized_image_path: nil} = image),
    do: image.raw_image_path || "/images/ysc_logo.png"

  defp event_image_url(%Image{optimized_image_path: optimized_path}),
    do: optimized_path

  defp event_image_url(_), do: "/images/ysc_logo.png"

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

      # Add "Just Added" badge if applicable (within 48 hours of publishing)
      just_added_badge =
        if DateTime.diff(DateTime.utc_now(), published_at, :hour) <= 48 do
          [%{text: "Just Added", class: "bg-slate-500 text-white", icon: nil}]
        else
          []
        end

      badges = badges ++ just_added_badge

      # Add "Days Left" badge if applicable (1-3 days remaining)
      days_left = days_until_event_start(event)

      days_left_badge =
        if days_left != nil and days_left >= 1 and days_left <= 3 do
          text =
            "#{days_left} #{if days_left == 1, do: "day", else: "days"} left"

          [%{text: text, class: "bg-sky-500 text-white", icon: nil}]
        else
          []
        end

      badges = badges ++ days_left_badge

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
