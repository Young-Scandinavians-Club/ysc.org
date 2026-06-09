defmodule YscWeb.AdminGhostComponents do
  @moduledoc """
  Skeleton / ghost placeholders for admin help preview illustrations.

  Real chrome (titles, buttons, nav labels) stays literal; dynamic content
  becomes shimmering bars so guides stay recognizable without real data.
  """
  use Phoenix.Component

  import YscWeb.CoreComponents

  attr :class, :string, default: nil
  attr :width, :string, default: "w-full", doc: "Tailwind width class"
  attr :height, :string, default: "h-3", doc: "Tailwind height class"
  attr :rounded, :string, default: "rounded", doc: "Tailwind rounded class"

  @doc "A single shimmering bar (title line, table cell, etc.)."
  def admin_ghost_bar(assigns) do
    ~H"""
    <span
      class={[
        "admin-ghost-bar inline-block max-w-full",
        @width,
        @height,
        @rounded,
        @class
      ]}
      aria-hidden="true"
    >
    </span>
    """
  end

  attr :class, :string, default: nil
  attr :size, :string, default: "h-8 w-8"

  @doc "Circular avatar placeholder."
  def admin_ghost_avatar(assigns) do
    ~H"""
    <span
      class={["admin-ghost-bar shrink-0 rounded-full", @size, @class]}
      aria-hidden="true"
    >
    </span>
    """
  end

  attr :class, :string, default: nil
  attr :width, :string, default: "w-16"

  @doc "Status pill placeholder."
  def admin_ghost_pill(assigns) do
    ~H"""
    <span
      class={["admin-ghost-bar inline-block h-6 rounded-full", @width, @class]}
      aria-hidden="true"
    >
    </span>
    """
  end

  attr :class, :string, default: nil
  attr :ratio, :string, default: "aspect-video"

  @doc "Image / cover placeholder block."
  def admin_ghost_image(assigns) do
    ~H"""
    <div
      class={[
        "admin-ghost-block w-full overflow-hidden",
        @ratio,
        @class
      ]}
      aria-hidden="true"
    >
      <div class="admin-ghost-bar h-full w-full rounded-none"></div>
    </div>
    """
  end

  attr :cols, :integer, default: 4
  attr :class, :string, default: nil

  @doc "Table header row with ghost column labels."
  def admin_ghost_table_head(assigns) do
    ~H"""
    <div class={[
      "hidden md:grid gap-4 px-4 py-3 border-b border-zinc-200",
      table_cols(@cols),
      @class
    ]}>
      <.admin_ghost_bar :for={_ <- 1..@cols} width="w-20" height="h-2.5" />
    </div>
    """
  end

  attr :cols, :integer, default: 4
  attr :class, :string, default: nil

  @doc "One ghost table row."
  def admin_ghost_table_row(assigns) do
    ~H"""
    <div class={[
      "grid gap-4 items-center px-4 py-4 border-b border-zinc-100",
      table_cols(@cols),
      @class
    ]}>
      <div class="flex items-center gap-2 min-w-0 col-span-1">
        <.admin_ghost_bar width="w-full" height="h-3.5" />
      </div>
      <.admin_ghost_bar :for={_ <- 2..@cols} width="w-full" height="h-3" />
    </div>
    """
  end

  attr :count, :integer, default: 5
  attr :cols, :integer, default: 4
  attr :class, :string, default: nil

  def admin_ghost_table(assigns) do
    ~H"""
    <div class={[
      "bg-white rounded-lg border border-zinc-200 overflow-hidden",
      @class
    ]}>
      <.admin_ghost_table_head cols={@cols} />
      <.admin_ghost_table_row :for={_ <- 1..@count} cols={@cols} />
    </div>
    """
  end

  attr :class, :string, default: nil

  @doc """
  Right-hand email preview panel in the newsletter editor — matches the sticky
  preview column (header + MJML-style body) rather than the compose form.
  """
  def admin_ghost_newsletter_email_preview(assigns) do
    ~H"""
    <div
      id="ghost-newsletter-email-preview"
      class={[
        "flex flex-col min-h-[420px] rounded-xl border border-zinc-200 overflow-hidden shadow-sm",
        @class
      ]}
    >
      <div class="flex items-center justify-between gap-2 px-4 py-3 border-b border-zinc-100 bg-zinc-50 shrink-0">
        <h3 class="text-sm font-semibold text-zinc-700">Email Preview</h3>
        <div class="flex items-center gap-2 sm:gap-3">
          <span class="hidden sm:inline text-xs text-zinc-400 italic">
            Shown as: Subscriber
          </span>
          <span class="inline-flex items-center gap-1.5 text-xs font-medium text-zinc-600 bg-white border border-zinc-200 rounded-md px-2.5 py-1.5">
            <span
              class="w-3.5 h-3.5 rounded border border-zinc-300 inline-block"
              aria-hidden="true"
            >
            </span>
            Send test
          </span>
        </div>
      </div>
      <div class="flex-1 overflow-hidden bg-zinc-100 px-2 py-3 sm:px-3 sm:py-4">
        <div class="mx-auto bg-white rounded-lg overflow-hidden shadow-sm">
          <.admin_ghost_image ratio="aspect-[2/1]" class="rounded-none" />
          <div class="px-5 sm:px-8 pt-8 pb-4 space-y-2.5">
            <.admin_ghost_bar width="w-4/5" height="h-5" />
            <.admin_ghost_bar width="w-full" height="h-2.5" />
            <.admin_ghost_bar width="w-[92%]" height="h-2.5" />
          </div>
          <div class="px-5 sm:px-8 pt-2 pb-2">
            <p class="text-base sm:text-lg font-bold text-zinc-900">Club Updates</p>
            <div class="mt-2 mb-4 border-t border-zinc-200"></div>
            <div class="flex gap-3 pb-5">
              <.admin_ghost_image
                class="w-[38%] shrink-0 rounded-lg"
                ratio="aspect-[4/3]"
              />
              <div class="flex-1 min-w-0 space-y-2 py-0.5">
                <.admin_ghost_bar width="w-full" height="h-3" />
                <.admin_ghost_bar width="w-full" height="h-2.5" />
                <.admin_ghost_bar width="w-2/3" height="h-2.5" />
                <p class="text-sm font-bold text-blue-700 pt-1">Read more →</p>
              </div>
            </div>
          </div>
          <div class="px-5 sm:px-8 pt-1 pb-5">
            <p class="text-base sm:text-lg font-bold text-zinc-900">
              Upcoming events
            </p>
            <div class="mt-2 mb-4 border-t border-zinc-200"></div>
            <.admin_ghost_image ratio="aspect-[21/9]" class="rounded-lg mb-3" />
            <.admin_ghost_bar width="w-2/3" height="h-3.5" />
            <.admin_ghost_bar width="w-2/5" height="h-2.5" class="mt-2" />
            <span class="inline-block mt-3 rounded-md bg-blue-700 text-white text-xs sm:text-sm font-semibold px-4 py-2">
              View event →
            </span>
          </div>
          <p class="text-center text-[11px] text-zinc-400 pb-5 underline decoration-zinc-300">
            Unsubscribe from newsletters
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :selected, :boolean, default: false
  attr :position, :integer, default: nil
  attr :class, :string, default: nil

  @doc "Square thumbnail in the newsletter post/event picker grid."
  def admin_ghost_newsletter_picker_tile(assigns) do
    ~H"""
    <div class={["text-left rounded-xl", @class]}>
      <div class={[
        "relative aspect-square rounded-lg overflow-hidden bg-zinc-100",
        @selected && "ring-2 ring-blue-500 ring-offset-2"
      ]}>
        <div class="admin-ghost-bar h-full w-full rounded-none"></div>
        <div
          :if={@selected}
          class="absolute inset-0 bg-blue-600/20"
          aria-hidden="true"
        >
        </div>
        <span
          :if={@position}
          class="absolute top-1.5 right-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-blue-600 text-[10px] font-bold text-white shadow-sm"
        >
          {@position}
        </span>
      </div>
      <.admin_ghost_bar width="w-full" height="h-2.5" class="mt-1.5" />
    </div>
    """
  end

  attr :class, :string, default: nil

  attr :event_title, :string, default: "Summer Cabin Weekend"
  attr :state, :atom, default: :draft, values: [:draft, :scheduled, :published]

  attr :active_tab, :atom,
    default: :details,
    values: [:details, :tickets, :updates]

  attr :partiful?, :boolean, default: false
  attr :date_line, :string, default: "Sat, Jun 21 · 5:00 PM – 9:00 PM"

  @doc """
  Sticky-style header from `AdminEventsNewLive`: back link, title, state badge,
  action buttons, and Event Details / Tickets / Updates tabs.
  """
  def admin_ghost_event_editor_header(assigns) do
    ~H"""
    <div id="ghost-event-header-bar" class="mb-4 border-b border-zinc-100 pb-3">
      <span class="inline-flex items-center gap-1 text-sm text-zinc-500">
        <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
      </span>

      <div class="mt-3 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div class="min-w-0 flex-1 space-y-1">
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1.5">
            <h1 class="text-xl font-semibold leading-8 text-zinc-800 sm:text-2xl break-words">
              {@event_title}
            </h1>
            <.badge type={event_state_badge_type(@state)}>
              {event_state_label(@state)}
            </.badge>
            <span
              class="inline-flex shrink-0 items-center justify-center rounded-full text-zinc-300"
              aria-hidden="true"
            >
              <.icon name="hero-question-mark-circle" class="w-5 h-5" />
            </span>
            <span
              :if={@state == :published}
              class="inline-flex shrink-0 items-center text-zinc-400"
              aria-hidden="true"
            >
              <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
            </span>
          </div>
          <div class="flex items-center gap-1 text-sm text-zinc-600">
            <.icon name="hero-calendar-days" class="w-4 h-4 shrink-0 text-zinc-500" />
            {@date_line}
          </div>
        </div>

        <div class="flex flex-shrink-0 flex-row flex-wrap items-center gap-2 sm:justify-end">
          <.button
            :if={@state in [:draft, :scheduled]}
            color="blue"
            class="whitespace-nowrap"
          >
            <.icon name="hero-document-arrow-up" class="w-5 h-5 -mt-0.5 me-1" />
            Publish
          </.button>
          <.button
            :if={@state == :published}
            color="red"
            class="whitespace-nowrap"
          >
            <.icon name="hero-document-arrow-down" class="w-5 h-5 -mt-0.5 me-1" />
            Unpublish
          </.button>
          <.button
            :if={@state in [:published, :scheduled]}
            color="green"
            class="whitespace-nowrap"
          >
            <.icon
              name="hero-clipboard-document-check"
              class="w-4 h-4 -mt-0.5 me-1"
            /> Check In
          </.button>
          <span
            :if={@state in [:draft, :scheduled]}
            class="inline-flex items-center whitespace-nowrap rounded-md bg-blue-700 px-3 py-2 text-sm font-semibold text-zinc-100"
          >
            <.icon name="hero-clock" class="w-5 h-5 me-1" />
            {if @state == :scheduled, do: "Scheduled", else: "Schedule"}
            <.icon name="hero-chevron-down" class="ms-2 w-4 h-4" />
          </span>
          <span class="inline-flex items-center justify-center rounded-md px-2 py-2 text-zinc-800 hover:bg-zinc-100">
            <.icon name="hero-ellipsis-vertical" class="w-6 h-6" />
          </span>
        </div>
      </div>

      <nav
        id="ghost-event-detail-tabs"
        aria-label="Event sections"
        class="event-header-tabs -mb-px mt-3 flex space-x-8 border-b border-zinc-200 text-sm font-medium text-zinc-500"
      >
        <span class={event_tab_class(@active_tab == :details)}>
          Event Details
        </span>
        <span class={[
          event_tab_class(@active_tab == :tickets),
          @partiful? && "opacity-50"
        ]}>
          Tickets{if @partiful?, do: " (Disabled - Using Partiful)"}
        </span>
        <span class={event_tab_class(@active_tab == :updates)}>
          Updates
        </span>
      </nav>
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  @doc "Bordered section card matching the event editor layout."
  def admin_ghost_event_section(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "border border-zinc-200 rounded py-5 px-4 space-y-4 bg-white",
        @class
      ]}
    >
      <div>
        <h2 class="text-lg font-bold text-zinc-900">{@title}</h2>
        <p :if={@subtitle} class="text-sm text-zinc-600 mt-1">{@subtitle}</p>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :string, default: nil

  @doc "Horizontal agenda card from the event editor Agenda section."
  def admin_ghost_agenda_panel(assigns) do
    ~H"""
    <div
      id="ghost-event-agenda-card"
      class={["bg-zinc-100 rounded-lg flex-shrink-0 w-72 flex flex-col", @class]}
    >
      <div class="flex items-center justify-center py-1.5 rounded-t-lg bg-zinc-200/80">
        <div class="flex flex-col gap-0.5">
          <div :for={_ <- 1..2} class="flex gap-0.5">
            <div :for={_ <- 1..3} class="w-1 h-1 rounded-full bg-zinc-500"></div>
          </div>
        </div>
      </div>
      <div class="px-4 pt-3 pb-4 space-y-3">
        <div class="flex items-start justify-between gap-2">
          <p class="text-sm font-semibold text-zinc-800">Saturday programme</p>
          <.icon name="hero-trash" class="w-5 h-5 text-zinc-400 shrink-0" />
        </div>
        <div class="space-y-2">
          <div
            :for={{time, idx} <- [{"17:00", 0}, {"18:30", 1}, {"20:00", 2}]}
            class="flex gap-2 items-start rounded-md bg-white border border-zinc-200 px-2 py-2"
          >
            <span class="text-xs font-semibold text-blue-700 bg-blue-50 px-1.5 py-0.5 rounded shrink-0">
              {time}
            </span>
            <div class="flex-1 min-w-0 space-y-1">
              <.admin_ghost_bar
                width={if(idx == 0, do: "w-24", else: "w-20")}
                height="h-2.5"
              />
              <.admin_ghost_bar
                :if={idx == 0}
                width="w-full"
                height="h-2"
              />
            </div>
          </div>
        </div>
        <span class="inline-flex items-center gap-1 text-xs font-medium text-blue-600">
          <.icon name="hero-plus" class="w-3.5 h-3.5" /> Add item
        </span>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :type_label, :string, required: true
  attr :price, :string, required: true
  attr :status, :string, default: "On sale"

  @doc "Single ticket tier row in the Tickets tab."
  def admin_ghost_ticket_tier_card(assigns) do
    ~H"""
    <div class="border border-zinc-200 rounded-lg p-4 bg-white hover:border-blue-300 transition-colors">
      <div class="flex flex-col lg:flex-row lg:items-center gap-4">
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <h4 class="font-bold text-zinc-900 text-base">{@name}</h4>
            <.badge
              type="green"
              class="text-xs uppercase tracking-wider font-bold rounded-full px-2 py-0.5 me-0"
            >
              {@status}
            </.badge>
          </div>
          <p class="text-zinc-400 text-sm italic mb-2">{@type_label} Tier</p>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
            <div>
              <p class="text-xs uppercase tracking-wide text-zinc-400 font-semibold mb-0.5">
                Price
              </p>
              <p class="font-semibold text-zinc-900">{@price}</p>
            </div>
            <div>
              <p class="text-xs uppercase tracking-wide text-zinc-400 font-semibold mb-0.5">
                Sold
              </p>
              <p class="font-semibold text-zinc-900">12 / 40</p>
            </div>
            <div>
              <p class="text-xs uppercase tracking-wide text-zinc-400 font-semibold mb-0.5">
                Sales window
              </p>
              <.admin_ghost_bar width="w-20" height="h-2.5" />
            </div>
          </div>
        </div>
        <div class="flex items-center gap-1 border-t lg:border-t-0 border-zinc-100 pt-3 lg:pt-0">
          <span class="p-2 text-zinc-400">
            <.icon name="hero-ticket" class="w-5 h-5" />
          </span>
          <span class="p-2 text-zinc-400">
            <.icon name="hero-pencil" class="w-5 h-5" />
          </span>
          <span class="p-2 text-zinc-400">
            <.icon name="hero-trash" class="w-5 h-5" />
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :price, :string, required: true
  attr :availability, :string, default: "28 remaining"
  attr :description, :string, default: nil
  attr :selected, :boolean, default: false
  attr :muted, :boolean, default: false
  attr :quantity, :integer, default: 0
  attr :class, :string, default: nil

  @doc "Ticket tier row inside the public event ticket modal."
  def admin_ghost_public_ticket_tier_card(assigns) do
    ~H"""
    <div class={[
      "border rounded-xl p-4 sm:p-5 transition-colors",
      @selected && !@muted && "border-blue-500 bg-blue-50",
      !@selected && !@muted && "border-zinc-200 bg-white",
      @muted && "border-zinc-200 bg-zinc-50 opacity-70",
      @class
    ]}>
      <div class="flex justify-between items-start gap-4 mb-3">
        <div class="min-w-0">
          <h4 class="font-semibold text-lg text-zinc-900">{@name}</h4>
          <p :if={@description} class="text-sm text-zinc-600 mt-1">
            {@description}
          </p>
        </div>
        <div class="text-right shrink-0">
          <p class="font-semibold text-xl text-zinc-900">{@price}</p>
          <p class={[
            "text-sm mt-0.5",
            @muted && "text-zinc-400",
            !@muted && "text-zinc-500"
          ]}>
            {@availability}
          </p>
        </div>
      </div>
      <div :if={!@muted} class="flex items-center justify-end gap-3">
        <span class="w-9 h-9 rounded-full border border-zinc-300 flex items-center justify-center text-zinc-400">
          <.icon name="hero-minus" class="w-5 h-5" />
        </span>
        <span class="w-8 text-center font-medium text-lg text-zinc-900">
          {@quantity}
        </span>
        <span class={[
          "w-9 h-9 rounded-full border flex items-center justify-center",
          @selected && "border-blue-700 bg-blue-700 text-white",
          !@selected && "border-zinc-300 text-zinc-700"
        ]}>
          <.icon name="hero-plus" class="w-5 h-5" />
        </span>
      </div>
    </div>
    """
  end

  attr :pricing_text, :string, default: "From $20"
  attr :date_line, :string, default: "Sat, Jun 21"
  attr :spots_available, :integer, default: 48
  attr :tickets_tbd?, :boolean, default: false
  attr :class, :string, default: nil

  @doc "Sticky ticket sidebar on the public event details page."
  def admin_ghost_public_ticket_sidebar(assigns) do
    ~H"""
    <aside
      id="ghost-public-ticket-sidebar"
      class={[
        "bg-white rounded-xl border border-zinc-100 overflow-hidden shadow-sm",
        @class
      ]}
    >
      <div class="p-6 sm:p-8 text-center bg-zinc-50/50 shadow-[inset_0_-1px_0_0_rgba(0,0,0,0.06)]">
        <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.3em] mb-2">
          Tickets
        </p>
        <p class="text-3xl sm:text-4xl font-black text-zinc-900 tracking-tighter">
          {if @tickets_tbd?, do: "Tickets coming soon", else: @pricing_text}
        </p>
        <p :if={!@tickets_tbd?} class="text-sm text-zinc-500 mt-2">{@date_line}</p>
      </div>
      <div class="relative h-px border-t border-dashed border-zinc-200 mx-4"></div>
      <div class="p-6 sm:p-8 space-y-5">
        <div
          :if={@tickets_tbd?}
          class="p-4 bg-blue-50 rounded-xl border border-blue-200 text-center"
        >
          <.icon name="hero-ticket" class="w-8 h-8 text-blue-600 mx-auto mb-2" />
          <p class="text-sm font-semibold text-blue-900">Tickets Coming Soon</p>
          <p class="text-xs text-blue-700 mt-1">
            Check back for pricing and availability.
          </p>
          <span class="mt-3 inline-block w-full rounded-lg bg-blue-600 px-3 py-2 text-xs font-semibold text-white">
            Notify me when tickets open
          </span>
        </div>
        <div
          :if={!@tickets_tbd? && @spots_available}
          class="flex items-center gap-3 text-sm text-zinc-600 font-medium"
        >
          <.icon name="hero-users" class="w-5 h-5 text-blue-500 shrink-0" />
          {@spots_available} Spots Available
        </div>
        <.button
          :if={!@tickets_tbd?}
          id="ghost-public-get-tickets"
          class="w-full py-3.5 uppercase tracking-widest text-sm"
        >
          <.icon name="hero-ticket" class="w-5 h-5 me-2 -mt-0.5" /> Get Tickets
        </.button>
      </div>
    </aside>
    """
  end

  attr :event_title, :string, default: "Summer Cabin Weekend"
  attr :class, :string, default: nil

  @doc "Ticket selection modal from `EventDetailsLive` (tier list + order summary)."
  def admin_ghost_public_ticket_modal(assigns) do
    ~H"""
    <div
      id="ghost-public-ticket-modal"
      class={[
        "rounded-xl border border-zinc-200 bg-white shadow-lg overflow-hidden",
        @class
      ]}
    >
      <div class="flex flex-col lg:flex-row min-h-[420px]">
        <div class="lg:w-2/3 p-5 sm:p-6 border-b lg:border-b-0 lg:border-r border-zinc-100 space-y-4">
          <div class="border-b border-zinc-200 pb-3">
            <h2 class="text-xl font-semibold text-zinc-900">{@event_title}</h2>
            <p class="text-sm text-zinc-600 mt-1">Sat, Jun 21</p>
          </div>
          <.admin_ghost_public_ticket_tier_card
            name="Member"
            price="Free"
            description="YSC members only"
            selected={true}
            quantity={1}
          />
          <.admin_ghost_public_ticket_tier_card
            name="Guest"
            price="$20.00"
            description="Non-member ticket"
            quantity={0}
          />
        </div>
        <div class="lg:w-1/3 p-5 sm:p-6 bg-zinc-50/80 flex flex-col justify-between gap-4">
          <div class="space-y-4">
            <.admin_ghost_image
              ratio="aspect-video"
              class="rounded-lg hidden lg:block"
            />
            <h3 class="font-semibold text-zinc-900">Order Summary</h3>
            <div class="bg-white rounded-xl border border-zinc-200 p-4 space-y-3 text-sm">
              <div class="flex justify-between gap-3">
                <span class="text-zinc-700">Member × 1</span>
                <span class="font-medium text-zinc-900">Free</span>
              </div>
              <div class="border-t border-zinc-100 pt-3 flex justify-between font-semibold text-zinc-900">
                <span>Total</span>
                <span>Free</span>
              </div>
            </div>
          </div>
          <.button class="w-full py-3 uppercase tracking-widest text-sm">
            Continue to checkout
          </.button>
        </div>
      </div>
    </div>
    """
  end

  attr :class, :string, default: nil

  @doc "Agenda timeline as shown on the public event details page."
  def admin_ghost_public_agenda_timeline(assigns) do
    items = [
      %{time: "17:00 – 18:00", title: "Doors open"},
      %{time: "18:30 – 20:00", title: "Dinner"},
      %{time: "20:00 – 22:00", title: "Sauna & swimming"}
    ]

    assigns = assign(assigns, :items, items)

    ~H"""
    <section id="ghost-public-event-agenda" class={["space-y-8", @class]}>
      <h3 class="text-xl font-black text-zinc-900 tracking-tight flex items-center gap-3">
        <span class="w-8 h-px bg-zinc-200"></span> Agenda
      </h3>
      <div class="relative pl-8 space-y-10">
        <div
          class="absolute left-3 top-2 bottom-2 w-px bg-zinc-100"
          aria-hidden="true"
        >
        </div>
        <div :for={{item, idx} <- Enum.with_index(@items)} class="relative group">
          <div class={[
            "absolute -left-[25px] w-4 h-4 rounded-full border-4 border-white shadow-sm z-10 mt-1.5",
            idx == 0 && "bg-blue-600",
            idx != 0 && "bg-zinc-200"
          ]}>
          </div>
          <div class="flex flex-col md:flex-row md:items-baseline gap-2 md:gap-8">
            <div class="w-36 shrink-0">
              <span class="text-xs font-black text-blue-600 bg-blue-50 px-2.5 py-1 rounded uppercase tracking-widest whitespace-nowrap">
                {item.time}
              </span>
            </div>
            <div class="flex-1 min-w-0">
              <h4 class="text-lg font-black text-zinc-900 tracking-tight leading-none">
                {item.title}
              </h4>
              <p :if={idx == 0} class="text-sm text-zinc-500 mt-2 leading-relaxed">
                Check in at the front desk and grab a name tag.
              </p>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :class, :string, default: nil

  @doc "Ghost rich-text editor body."
  def admin_ghost_editor_body(assigns) do
    ~H"""
    <div class={["space-y-3 p-4", @class]}>
      <.admin_ghost_bar width="w-full" height="h-3" />
      <.admin_ghost_bar width="w-11/12" height="h-3" />
      <.admin_ghost_bar width="w-10/12" height="h-3" />
      <.admin_ghost_bar width="w-1/3" height="h-4" class="mt-2" />
      <.admin_ghost_bar width="w-full" height="h-3" />
      <.admin_ghost_bar width="w-9/12" height="h-3" />
    </div>
    """
  end

  defp table_cols(4), do: "grid-cols-4"
  defp table_cols(5), do: "grid-cols-5"
  defp table_cols(6), do: "grid-cols-6"
  defp table_cols(_), do: "grid-cols-4"

  defp event_state_badge_type(:draft), do: "sky"
  defp event_state_badge_type(:scheduled), do: "yellow"
  defp event_state_badge_type(:published), do: "green"

  defp event_state_label(:draft), do: "Draft"
  defp event_state_label(:scheduled), do: "Scheduled"
  defp event_state_label(:published), do: "Published"

  defp event_tab_class(true),
    do:
      "shrink-0 whitespace-nowrap py-3 border-b-2 border-blue-500 text-blue-600 font-medium"

  defp event_tab_class(false),
    do:
      "shrink-0 whitespace-nowrap py-3 border-b-2 border-transparent text-zinc-500 font-medium"
end
