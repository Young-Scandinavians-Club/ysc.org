defmodule YscWeb.Components.RoomPickCard do
  @moduledoc """
  Selectable room card for the booking flow's "Choose your rooms" step.

  Shares its look with the browse-only cards in `YscWeb.Components.RoomBrowser`
  (title, one metadata line, quiet price footer) and adds the selection state:
  a visually hidden radio or checkbox, a check indicator, and a short note that
  explains why a room can't be picked. The photo is never covered.
  """
  use Phoenix.Component

  import YscWeb.CoreComponents, only: [icon: 1]
  import YscWeb.Components.RoomBrowser, only: [room_meta: 1]

  attr :room, :map, required: true
  attr :selected, :boolean, default: false
  attr :disabled, :boolean, default: false

  attr :reason, :string,
    default: nil,
    doc: "Why the room can't be picked; shown under the photo when disabled"

  attr :multiple, :boolean,
    default: false,
    doc: "Checkbox (several rooms allowed) instead of radio"

  attr :prices, :map,
    required: true,
    doc: """
    Preformatted price lines: `:adult`, `:child`, and optionally `:minimum` with
    `:minimum_caption` for rooms with a minimum charge.
    """

  def room_pick_card(assigns) do
    ~H"""
    <div
      id={"room-card-#{@room.id}"}
      class={[
        "relative flex flex-col h-full overflow-hidden rounded-xl border bg-white transition-colors has-focus-visible:ring-2 has-focus-visible:ring-blue-600 has-focus-visible:ring-offset-2",
        card_state(@disabled, @selected)
      ]}
    >
      <label class={[
        "flex flex-col h-full",
        if(@disabled, do: "cursor-not-allowed", else: "cursor-pointer")
      ]}>
        <input
          type={if @multiple, do: "checkbox", else: "radio"}
          id={if(!@disabled, do: "room-#{@room.id}")}
          name={if @multiple, do: "room_ids", else: "room_id"}
          value={@room.id}
          checked={@selected}
          disabled={@disabled}
          aria-label={"Select #{@room.name}"}
          aria-describedby={if(@disabled && @reason, do: "room-#{@room.id}-reason")}
          phx-click={if(!@disabled, do: "room-changed")}
          phx-value-room-id={if(!@disabled, do: @room.id)}
          class="sr-only"
        />
        <div class="relative h-36 w-full shrink-0 overflow-hidden bg-zinc-200">
          <%= if @room.image && @room.image.id do %>
            <.live_component
              id={"room-image-#{if(@disabled, do: "disabled-")}#{@room.id}"}
              module={YscWeb.Components.Image}
              image={@room.image}
              aspect_class="h-full"
              preferred_type={:thumbnail}
              rounded_class=""
            />
          <% else %>
            <div class="absolute inset-0 flex items-center justify-center text-zinc-500">
              <.icon name="hero-photo" class="w-12 h-12" />
            </div>
          <% end %>
        </div>
        <div class="flex flex-1 flex-col gap-3 p-4">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <h3 class={[
                "type-subhead text-lg",
                if(@disabled, do: "text-zinc-500", else: "text-zinc-900")
              ]}>
                {@room.name}
              </h3>
              <p
                :if={@room.description}
                class="mt-1 text-sm text-zinc-600 leading-relaxed line-clamp-2"
              >
                {@room.description}
              </p>
            </div>
            <span
              class={[
                "mt-0.5 inline-flex size-5 shrink-0 items-center justify-center rounded-full border",
                if(@selected,
                  do: "border-blue-600 bg-blue-600 text-white",
                  else: "border-zinc-300 bg-white"
                )
              ]}
              aria-hidden="true"
            >
              <.icon :if={@selected} name="hero-check-mini" class="size-3.5" />
            </span>
          </div>
          <.room_meta room={@room} />
          <p
            :if={@disabled && @reason}
            id={"room-#{@room.id}-reason"}
            class="flex items-start gap-1.5 text-xs text-zinc-700 leading-relaxed"
          >
            <.icon
              name="hero-no-symbol"
              class="mt-0.5 w-4 h-4 shrink-0 text-zinc-500"
            />
            <span>{@reason}</span>
          </p>
          <p
            :if={@room.min_billable_occupancy > 1}
            id={"room-#{@room.id}-min-charge-badge"}
            class="text-xs text-amber-700"
          >
            {YscWeb.BookingUserMessages.room_min_charge_badge(
              @room.min_billable_occupancy
            )}
          </p>
          <div class="mt-auto border-t border-zinc-100 pt-3">
            <%= if @prices[:minimum] do %>
              <p class="text-sm font-semibold text-zinc-900">
                {@prices.minimum} min
                <span class="text-xs font-normal text-zinc-500">
                  {@prices[:minimum_caption]}
                </span>
              </p>
            <% else %>
              <p class="text-sm font-semibold text-zinc-900">
                {@prices.adult}/adult
              </p>
            <% end %>
            <p class="text-xs text-zinc-500">{@prices.child}/child</p>
          </div>
        </div>
      </label>
    </div>
    """
  end

  defp card_state(true, _selected), do: "border-zinc-200 bg-zinc-50"
  defp card_state(false, true), do: "border-blue-600 ring-1 ring-blue-600"
  defp card_state(false, false), do: "border-zinc-200 hover:border-zinc-400"
end
