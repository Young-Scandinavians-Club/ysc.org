defmodule YscWeb.Components.Events.EventTvPoster do
  @moduledoc """
  16:9 (1920×1080) event poster layout for cabin TV displays (Roku / Google Photos).

  Rendered standalone for browser preview and future ChromicPDF screenshot capture.
  """
  use Phoenix.Component

  import YscWeb.CoreComponents

  alias Ysc.Media.Image

  attr :event, :map, required: true
  attr :sold_out, :boolean, default: false
  attr :selling_fast, :boolean, default: false

  def event_tv_poster(assigns) do
    assigns =
      assigns
      |> assign(
        :badges,
        poster_badges(assigns.event, assigns.sold_out, assigns.selling_fast)
      )

    ~H"""
    <div
      id="event-tv-poster"
      class="relative w-[1920px] h-[1080px] overflow-hidden bg-zinc-900 text-white shrink-0"
    >
      <div class={[
        "absolute inset-0",
        cancelled?(@event) && "grayscale"
      ]}>
        <img
          src={event_image_url(@event.image)}
          alt={event_image_alt(@event)}
          class="absolute inset-0 h-full w-full object-cover"
        />
        <div class="absolute inset-0 bg-gradient-to-t from-zinc-900/95 via-zinc-900/55 to-zinc-900/20">
        </div>
      </div>

      <div class="absolute top-12 left-12 z-10 flex flex-wrap gap-3">
        <%= for badge <- @badges do %>
          <span class={[
            "px-4 py-2 rounded text-sm font-black uppercase tracking-widest",
            badge.class
          ]}>
            <.icon :if={badge.icon} name={badge.icon} class="w-4 h-4 inline me-1" />
            {badge.text}
          </span>
        <% end %>
      </div>

      <div class="absolute inset-x-0 bottom-0 z-10 flex flex-col justify-end p-12 lg:p-16">
        <div class="max-w-[1400px]">
          <div class="flex flex-wrap items-center gap-4 mb-6">
            <span class="text-lg font-black px-4 py-2 rounded bg-white/15 backdrop-blur-sm uppercase tracking-[0.2em]">
              {format_event_date_time(@event)}
            </span>
            <span
              :if={@event.location_name}
              class="text-lg font-bold uppercase tracking-widest text-white/85 flex items-center gap-2"
            >
              <.icon name="hero-map-pin" class="w-5 h-5" />
              {@event.location_name}
            </span>
          </div>

          <h1 class="text-6xl xl:text-7xl font-black leading-[1.05] tracking-tighter mb-6 drop-shadow-lg">
            {@event.title}
          </h1>

          <p
            :if={@event.description}
            class="text-2xl leading-relaxed text-zinc-200 line-clamp-3 mb-10 max-w-5xl drop-shadow"
          >
            {@event.description}
          </p>

          <div class="flex items-center gap-6 pt-8 border-t border-white/25">
            <span class={[
              "text-xl font-black rounded border border-white/35 px-5 py-2.5 backdrop-blur-sm",
              @sold_out && "line-through opacity-70"
            ]}>
              {pricing_display(@event)}
            </span>
            <span class="text-lg font-bold uppercase tracking-widest text-white/80">
              Young Scandinavians Club
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp pricing_display(%{pricing_info: %{display_text: text}})
       when is_binary(text), do: text

  defp pricing_display(_), do: "See event for details"

  defp cancelled?(event) do
    Map.get(event, :state) in [:cancelled, "cancelled"]
  end

  defp format_event_date_time(event) do
    start_date = Map.get(event, :start_date)
    start_time = Map.get(event, :start_time)

    cond do
      start_date && start_time ->
        date_str = Timex.format!(start_date, "{Mshort} {D}, {YYYY}")
        time_str = Timex.format!(start_time, "{h12}:{m} {AM}")
        "#{date_str} · #{time_str}"

      start_date ->
        Timex.format!(start_date, "{Mshort} {D}, {YYYY}")

      true ->
        "Date TBD"
    end
  end

  defp event_image_url(nil), do: "/images/ysc_logo.webp"

  defp event_image_url(%Image{optimized_image_path: nil} = image),
    do: image.raw_image_path || "/images/ysc_logo.webp"

  defp event_image_url(%Image{optimized_image_path: path}), do: path
  defp event_image_url(_), do: "/images/ysc_logo.webp"

  defp event_image_alt(event) do
    case Map.get(event, :image) do
      %Image{alt_text: alt} when is_binary(alt) and alt != "" -> alt
      %Image{title: title} when is_binary(title) and title != "" -> title
      _ -> event.title || "Event image"
    end
  end

  defp poster_badges(event, sold_out, selling_fast) do
    cond do
      cancelled?(event) ->
        [%{text: "Cancelled", class: "bg-red-600 text-white", icon: nil}]

      sold_out ->
        [%{text: "Sold Out", class: "bg-red-600 text-white", icon: nil}]

      true ->
        []
        |> maybe_add_badge(
          Map.get(event, :tickets_tbd),
          %{
            text: "Save the Date",
            class: "bg-blue-600 text-white",
            icon: "hero-ticket"
          }
        )
        |> maybe_add_badge(
          selling_fast,
          %{
            text: "Going Fast!",
            class: "bg-emerald-600 text-white",
            icon: "hero-bolt-solid"
          }
        )
    end
  end

  defp maybe_add_badge(badges, true, badge), do: badges ++ [badge]
  defp maybe_add_badge(badges, _, _), do: badges
end
