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

  alias YscWeb.{DateDisplay, EventBadgeHelpers, PlainText}

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
            "text-2xl font-black tracking-tight leading-tight mb-3 group-hover:text-blue-600 group-hover:underline transition-colors line-clamp-2 min-h-[4rem]",
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
    event
    |> EventBadgeHelpers.exclusive_badge_kinds(
      sold_out: sold_out,
      selling_fast: selling_fast,
      proximity: :labels
    )
    |> EventBadgeHelpers.to_card_badges()
  end

  defp badge_class(%{class: class}), do: class
end
