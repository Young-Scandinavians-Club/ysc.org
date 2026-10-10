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
    <section id={@id} class="space-y-8">
      <div class="prose prose-zinc max-w-none">
        <h2 class="text-3xl font-black tracking-tight text-zinc-900 mb-3">
          Rooms at the {@property_name}
        </h2>
        <p class="text-lg text-zinc-600 leading-relaxed">
          <%= if @intro do %>
            {@intro}
          <% else %>
            Browse the rooms we offer to find the one that suits your group.
            <span :if={@pick_event}>
              Found one you like? Choose it and we'll check whether it's free on your dates.
            </span>
          <% end %>
        </p>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 items-stretch">
        <.room_card
          :for={room <- @rooms}
          room={room}
          accent={@accent}
          pick_event={@pick_event}
        />
      </div>
    </section>
    """
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
          <div class="absolute inset-0 flex items-center justify-center text-zinc-400">
            <.icon name="hero-photo" class="w-16 h-16" />
          </div>
        <% end %>
      </div>
      <div class="p-5 flex-1 flex flex-col gap-3">
        <div>
          <h3 class="font-bold text-zinc-900 text-lg">{@room.name}</h3>
          <p
            :if={@room.room_category}
            class="text-xs font-semibold uppercase tracking-wider text-zinc-500"
          >
            {@room.room_category.name}
          </p>
        </div>
        <p :if={@room.description} class="text-sm text-zinc-600">
          {@room.description}
        </p>
        <div class="flex items-center gap-2 flex-wrap">
          <span class={[
            "px-2 py-1 text-xs font-bold rounded-sm border",
            capacity_badge(@accent)
          ]}>
            Max {@room.capacity_max} {if @room.capacity_max == 1,
              do: "guest",
              else: "guests"}
          </span>
          <span
            :if={@room.min_billable_occupancy > 1}
            class="px-2 py-1 bg-amber-100 text-amber-700 text-xs font-bold rounded-sm border border-amber-200"
          >
            {YscWeb.BookingUserMessages.room_min_charge_badge(
              @room.min_billable_occupancy
            )}
          </span>
        </div>
        <ul
          :if={bed_summary(@room) != []}
          class="flex items-center gap-2 flex-wrap"
          aria-label="Beds"
        >
          <li
            :for={{type, count, label} <- bed_summary(@room)}
            class="inline-flex items-center gap-1 px-2 py-0.5 bg-zinc-100 text-zinc-700 text-xs rounded-sm border border-zinc-200"
            title={label}
          >
            <.bed_icon type={type} />
            <span>{count} {label}</span>
          </li>
        </ul>
        <div :if={@pick_event} class="mt-auto pt-2">
          <button
            type="button"
            id={"browse-room-pick-#{@room.id}"}
            phx-click={@pick_event}
            phx-value-room-id={@room.id}
            class={[
              "w-full inline-flex items-center justify-center gap-2 px-4 py-2 text-sm font-bold rounded-md transition-colors",
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

  defp capacity_badge(:blue), do: "bg-blue-100 text-blue-700 border-blue-200"
  defp capacity_badge(:teal), do: "bg-teal-100 text-teal-700 border-teal-200"

  defp pick_button(:blue), do: "bg-blue-600 text-white hover:bg-blue-700"
  defp pick_button(:teal), do: "bg-teal-600 text-white hover:bg-teal-700"

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
