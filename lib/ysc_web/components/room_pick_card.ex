defmodule YscWeb.Components.RoomPickCard do
  @moduledoc """
  Selectable room card for the booking flow's "Choose your rooms" step.

  Shares its look with the browse-only cards in `YscWeb.Components.RoomBrowser`
  (title, one metadata line, quiet price footer) and adds the selection state:
  a visually hidden radio or checkbox, a check indicator, and a clear "Not available" badge and
  a highlighted notice that explains why a room can't be picked. The photo is never covered.
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
          aria-describedby={if(@disabled, do: "room-#{@room.id}-reason")}
          phx-click={if(!@disabled, do: "room-changed")}
          phx-value-room-id={if(!@disabled, do: @room.id)}
          class="sr-only"
        />
        <div class="relative h-36 w-full shrink-0 overflow-hidden bg-zinc-200">
          <div class={["h-full w-full", @disabled && "grayscale opacity-50"]}>
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
          <span
            :if={@disabled}
            class="absolute left-2 top-2 z-10 inline-flex items-center gap-1.5 rounded-full bg-zinc-900 px-2.5 py-1 text-xs font-semibold text-white shadow-xs"
            aria-hidden="true"
          >
            <.icon name="hero-no-symbol" class="size-3.5" /> Not available
          </span>
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
                class={[
                  "mt-1 text-sm leading-relaxed line-clamp-2",
                  if(@disabled, do: "text-zinc-500", else: "text-zinc-600")
                ]}
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
          <p
            :if={@disabled}
            id={"room-#{@room.id}-reason"}
            class="flex items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2.5 text-sm font-medium text-amber-900 leading-snug"
          >
            <.icon
              name="hero-exclamation-triangle-mini"
              class="mt-0.5 size-4 shrink-0 text-amber-600"
            />
            <span>{@reason || "Not available for your selection."}</span>
          </p>
          <.room_meta room={@room} />
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
              <p class={["text-sm font-semibold", price_tone(@disabled)]}>
                {@prices.minimum} min
                <span class="text-xs font-normal text-zinc-500">
                  {@prices[:minimum_caption]}
                </span>
              </p>
            <% else %>
              <p class={["text-sm font-semibold", price_tone(@disabled)]}>
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

  defp card_state(true, _selected),
    do: "border-dashed border-zinc-300 bg-zinc-50"

  defp card_state(false, true), do: "border-blue-600 ring-1 ring-blue-600"
  defp card_state(false, false), do: "border-zinc-200 hover:border-zinc-400"

  defp price_tone(true), do: "text-zinc-500"
  defp price_tone(false), do: "text-zinc-900"
end
