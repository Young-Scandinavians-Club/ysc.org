defmodule YscWeb.Components.RoomBrowser do
  @moduledoc """
  Browsable list of a property's individual rooms for the booking pages'
  "Rooms" information tab.

  Lets members see what kinds of rooms a property offers before they start a
  booking. Each card can optionally offer a button that fires an event so the
  host LiveView can check whether that room is free on the member's dates.
  """
  use Phoenix.Component

  import YscWeb.CoreComponents, only: [icon: 1]
  import YscWeb.Components.CabinInfo, only: [info_section: 1]

  alias Ysc.Bookings.RoomsListCache

  @doc """
  Active rooms for `property`, ordered by name.

  An empty list means the property has no individually bookable rooms, in
  which case callers should not show the Rooms tab.
  """
  def browsable_rooms(property) when is_atom(property) do
    property
    |> RoomsListCache.list()
    |> Enum.filter(& &1.is_active)
  end

  attr :id, :string, default: "room-browser"
  attr :rooms, :list, required: true
  attr :property_name, :string, required: true
  attr :accent, :atom, values: [:blue, :teal], default: :blue

  attr :pick_event, :string,
    default: nil,
    doc:
      "LiveView event fired with `room-id` when a member picks a room. " <>
        "When nil, no availability button is shown."

  attr :intro, :string,
    default: nil,
    doc:
      "Optional override for the intro paragraph. When nil, a default " <>
        "browse/pick sentence is used."

  def room_browser(assigns) do
    ~H"""
    <.info_section
      id={@id}
      title={"Rooms at the #{@property_name}"}
      description={browser_intro(@intro, @pick_event)}
    >
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-6 items-stretch">
        <.room_card
          :for={room <- @rooms}
          room={room}
          accent={@accent}
          pick_event={@pick_event}
        />
      </div>
    </.info_section>
    """
  end

  defp browser_intro(intro, _pick_event) when is_binary(intro), do: intro

  defp browser_intro(nil, nil),
    do: "Browse the rooms we offer to find the one that suits your group."

  defp browser_intro(nil, _pick_event) do
    "Browse the rooms we offer to find the one that suits your group. " <>
      "Found one you like? Choose it and we'll check whether it's free on your dates."
  end

  attr :room, :map, required: true
  attr :accent, :atom, required: true
  attr :pick_event, :string, default: nil

  defp room_card(assigns) do
    ~H"""
    <article
      id={"browse-room-#{@room.id}"}
      class="bg-white border border-zinc-200 rounded-xl overflow-hidden shadow-xs flex flex-col h-full"
    >
      <div class="w-full h-48 bg-zinc-200 relative overflow-hidden">
        <%= if @room.image && @room.image.id do %>
          <.live_component
            id={"browse-room-image-#{@room.id}"}
            module={YscWeb.Components.Image}
            image={@room.image}
            aspect_class="h-full"
            preferred_type={:thumbnail}
            rounded_class=""
          />
        <% else %>
          <div class="absolute inset-0 flex items-center justify-center text-zinc-500">
            <.icon name="hero-photo" class="w-16 h-16" />
          </div>
        <% end %>
      </div>
      <div class="p-5 flex-1 flex flex-col gap-3">
        <div>
          <h3 class="type-subhead text-lg text-zinc-900">{@room.name}</h3>
          <p
            :if={@room.room_category}
            class="mt-0.5 text-xs text-zinc-500 type-eyebrow"
          >
            {@room.room_category.name}
          </p>
        </div>
        <p :if={@room.description} class="text-sm text-zinc-600 leading-relaxed">
          {@room.description}
        </p>
        <.room_meta room={@room} />
        <p
          :if={@room.min_billable_occupancy > 1}
          class="text-xs text-amber-700"
        >
          {YscWeb.BookingUserMessages.room_min_charge_badge(
            @room.min_billable_occupancy
          )}
        </p>
        <div :if={@pick_event} class="mt-auto pt-2">
          <button
            type="button"
            id={"browse-room-pick-#{@room.id}"}
            phx-click={@pick_event}
            phx-value-room-id={@room.id}
            class={[
              "w-full inline-flex items-center justify-center gap-2 px-4 py-2 min-h-11 text-sm font-semibold rounded-md border border-zinc-300 bg-white text-zinc-900 transition-colors focus-visible:outline-hidden focus-visible:ring-2",
              pick_button(@accent)
            ]}
          >
            <.icon name="hero-calendar-days" class="w-4 h-4" /> Check availability
          </button>
        </div>
      </div>
    </article>
    """
  end

  @doc """
  One quiet metadata line for a room: capacity, then each bed type with its icon
  (`Up to 2 guests · 1 queen`). Shared by the browse and booking-flow cards.
  """
  attr :room, :map, required: true

  def room_meta(assigns) do
    ~H"""
    <p class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-zinc-500">
      <span>{capacity_label(@room.capacity_max)}</span>
      <span
        :for={{type, count, label} <- bed_summary(@room)}
        class="inline-flex items-center gap-1.5"
      >
        <span aria-hidden="true">·</span>
        <.bed_icon type={type} />
        <span>{count} {label}</span>
      </span>
    </p>
    """
  end

  defp capacity_label(1), do: "Up to 1 guest"
  defp capacity_label(max), do: "Up to #{max} guests"

  defp pick_button(:blue),
    do: "hover:border-blue-600 hover:text-blue-700 focus-visible:ring-blue-600"

  defp pick_button(:teal),
    do: "hover:border-teal-600 hover:text-teal-700 focus-visible:ring-teal-600"

  defp bed_summary(room) do
    [
      {:single, room.single_beds, "twin"},
      {:queen, room.queen_beds, "queen"},
      {:king, room.king_beds, "king"}
    ]
    |> Enum.filter(fn {_type, count, _label} -> count > 0 end)
  end

  attr :type, :atom, values: [:single, :queen, :king], required: true

  defp bed_icon(%{type: :single} = assigns) do
    ~H"""
    <svg
      class="w-3 h-3 text-zinc-600"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M6 9h12" />
      <rect x="6" y="9" width="12" height="8" rx="2" />
      <path d="M8 17v2m8-2v2" />
      <rect x="9.75" y="10.25" width="4.5" height="2.5" rx="1" />
    </svg>
    """
  end

  defp bed_icon(%{type: :queen} = assigns) do
    ~H"""
    <svg
      class="w-3 h-3 text-zinc-600"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M4 9h16" />
      <rect x="4" y="9" width="16" height="8" rx="2" />
      <path d="M7 17v2m10-2v2" />
      <rect x="7.5" y="10.25" width="5" height="2.5" rx="1" />
      <rect x="11.5" y="10.25" width="5" height="2.5" rx="1" />
    </svg>
    """
  end

  defp bed_icon(%{type: :king} = assigns) do
    ~H"""
    <svg
      class="w-3 h-3 text-zinc-600"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M3 9h18" />
      <rect x="3" y="9" width="18" height="8" rx="2" />
      <path d="M6 17v2m12-2v2" />
      <rect x="6.25" y="10.25" width="6" height="2.5" rx="1" />
      <rect x="11.75" y="10.25" width="6" height="2.5" rx="1" />
    </svg>
    """
  end
end
