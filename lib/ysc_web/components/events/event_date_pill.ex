defmodule YscWeb.Components.Events.EventDatePill do
  @moduledoc """
  Single pill showing an event's start as `Nov 7 · 10:00 AM`.

  Shared by the event card and the featured hero event so the date/time reads
  identically across the events page.
  """
  use Phoenix.Component

  alias Ysc.Events.DateTimeFormatter

  attr :event, :any, required: true

  attr :variant, :string,
    default: "light",
    values: ["light", "dark", "overlay"],
    doc:
      "'light' (grey on white), 'dark' (dark card) or 'overlay' (translucent, over a photo)"

  attr :with_year, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global

  def event_date_pill(assigns) do
    assigns =
      assign(
        assigns,
        :label,
        DateTimeFormatter.format_event_start(assigns.event,
          separator: " · ",
          with_year: assigns.with_year
        )
      )

    ~H"""
    <span
      class={[
        "inline-block text-sm px-2.5 py-1 rounded-sm type-eyebrow",
        variant_class(@variant),
        @class
      ]}
      {@rest}
    >
      {@label}
    </span>
    """
  end

  defp variant_class("dark"), do: "text-zinc-300 bg-zinc-800"
  defp variant_class("overlay"), do: "text-white bg-white/15 backdrop-blur-xs"
  defp variant_class(_light), do: "text-zinc-900 bg-zinc-100"
end
