defmodule YscWeb.Components.Bookings.BookingCard do
  @moduledoc """
  Reservation card for an upcoming or in-progress cabin stay.

  A date stub (check-in month and day) sits beside the stay details. The stub
  is softly tinted until the stay is under way, then turns solid so colour
  marks what is happening now. Shared by the member dashboard and the Tahoe and
  Clear Lake booking pages.
  """
  use Phoenix.Component

  import YscWeb.CoreComponents, only: [icon: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  alias Ysc.Bookings.{BookingModeDisplay, PropertyDisplay}
  alias YscWeb.{DateDisplay, TimeZone}

  attr :id, :string, required: true
  attr :booking, :map, required: true

  attr :accent, :atom,
    default: nil,
    values: [nil, :blue, :emerald, :teal],
    doc: "Stub colour; defaults to blue for Tahoe and emerald for Clear Lake"

  attr :detail, :string,
    default: nil,
    doc: "Optional line under the dates, e.g. guest count and rooms"

  attr :class, :any, default: nil

  def booking_card(assigns) do
    days = DateDisplay.days_until_cabin_checkin(assigns.booking)

    assigns =
      assigns
      |> assign(:days, days)
      |> assign(:active?, days in [:started, 0])
      |> assign(:accent, assigns.accent || default_accent(assigns.booking))
      |> assign(:status, status_label(days, assigns.booking))

    ~H"""
    <.link
      id={@id}
      navigate={~p"/bookings/#{@booking.id}/receipt"}
      class={[
        "group flex bg-white rounded-xl overflow-hidden transition-colors duration-150 border border-zinc-200 hover:border-zinc-300",
        @class
      ]}
    >
      <%!-- Stub: soft tint until the stay is active, then solid --%>
      <div class={[
        "flex flex-col items-center justify-center w-18 shrink-0 border-r-2 border-dashed px-2 py-4",
        stub_class(@accent, @active?)
      ]}>
        <span class="text-xs type-eyebrow opacity-80">
          {Calendar.strftime(@booking.checkin_date, "%b")}
        </span>
        <span class="text-3xl type-display leading-none">
          {Calendar.strftime(@booking.checkin_date, "%-d")}
        </span>
        <.icon name="hero-home" class="w-4 h-4 mt-3 opacity-70" />
      </div>
      <div class="flex-1 min-w-0 p-5 flex flex-col md:flex-row md:items-center gap-4 md:gap-6">
        <div class="flex-1 min-w-0">
          <div class="flex flex-wrap items-center gap-1.5 mb-2">
            <span class={[
              "inline-flex items-center px-2 py-1 text-xs font-bold rounded-sm",
              status_class(@status)
            ]}>
              {elem(@status, 1)}
            </span>
            <span
              :if={@booking.booking_mode == :buyout}
              class="inline-flex items-center px-2 py-1 bg-amber-50 text-amber-700 text-xs font-bold rounded-sm"
            >
              {BookingModeDisplay.stay_type_label(:buyout)}
            </span>
          </div>
          <p class="text-zinc-900 type-subhead">
            {PropertyDisplay.medium_name(@booking.property)}
          </p>
          <p class="mt-1 text-xs text-zinc-500 flex items-center gap-1">
            <.icon name="hero-calendar" class="w-3 h-3 shrink-0" />
            {format_date(@booking.checkin_date)} — {format_date(
              @booking.checkout_date
            )}
          </p>
          <p :if={@detail} class="mt-1 text-xs text-zinc-500">
            {@detail}
          </p>
          <p class="mt-1 text-xs font-mono text-zinc-500">
            {@booking.reference_id}
          </p>
        </div>
        <div class="shrink-0 md:pl-6 md:border-l md:border-zinc-100">
          <span class={[
            "inline-flex items-center gap-1 text-sm font-semibold transition-colors duration-150",
            if(@active?,
              do: link_class(@accent),
              else: "text-zinc-600 group-hover:text-zinc-900"
            )
          ]}>
            View details <.icon name="hero-arrow-right" class="w-4 h-4" />
          </span>
        </div>
      </div>
    </.link>
    """
  end

  defp default_accent(%{property: :clear_lake}), do: :emerald
  defp default_accent(_), do: :blue

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d")

  # Returns `{kind, label}`; `kind` drives the badge colour.
  defp status_label(:started, %{checkout_date: %Date{} = checkout}) do
    if Date.compare(checkout, DateTime.to_date(TimeZone.now())) == :eq,
      do: {:checkout_today, "Checking out today"},
      else: {:started, "Currently staying"}
  end

  defp status_label(:started, _), do: {:started, "Currently staying"}
  defp status_label(0, _), do: {:today, "Checking in today"}
  defp status_label(1, _), do: {:soon, "Tomorrow"}

  defp status_label(days, _) when is_integer(days),
    do: {:soon, "In #{days} days"}

  defp status_label(_, _), do: {:soon, ""}

  defp status_class({:started, _}), do: "bg-green-50 text-green-700"
  defp status_class({:today, _}), do: "bg-amber-50 text-amber-700"
  defp status_class({:checkout_today, _}), do: "bg-amber-50 text-amber-700"
  defp status_class(_), do: "bg-zinc-100 text-zinc-700"

  defp stub_class(:blue, true), do: "bg-blue-700 border-blue-300/60 text-white"

  defp stub_class(:emerald, true),
    do: "bg-emerald-700 border-emerald-300/60 text-white"

  defp stub_class(:teal, true), do: "bg-teal-700 border-teal-300/60 text-white"
  defp stub_class(:blue, false), do: "bg-blue-50 border-blue-200 text-blue-700"

  defp stub_class(:emerald, false),
    do: "bg-emerald-50 border-emerald-200 text-emerald-700"

  defp stub_class(:teal, false), do: "bg-teal-50 border-teal-200 text-teal-700"

  defp link_class(:blue), do: "text-blue-700 group-hover:text-blue-800"
  defp link_class(:emerald), do: "text-emerald-700 group-hover:text-emerald-800"
  defp link_class(:teal), do: "text-teal-700 group-hover:text-teal-800"
end
