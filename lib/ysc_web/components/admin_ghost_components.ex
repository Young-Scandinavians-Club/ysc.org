defmodule YscWeb.AdminGhostComponents do
  @moduledoc """
  Skeleton / ghost placeholders for admin help preview illustrations.

  Real chrome (titles, buttons, nav labels) stays literal; dynamic content
  becomes shimmering bars so guides stay recognizable without real data.
  """
  use Phoenix.Component

  import YscWeb.AdminComponents
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
    ></span>
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
    ></span>
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
    ></span>
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
  attr :first_name, :string, default: "Alex"

  @doc """
  Volunteer-focused dashboard from `AdminDashboardLive` — welcome header, quick
  stats, upcoming events timeline, and recent discussions.
  """
  def admin_ghost_dashboard(assigns) do
    events = [
      %{
        date: "Sat, Jun 21 · 5:00 PM",
        title: "Summer Cabin Weekend",
        tiers: [
          %{name: "Member", sold: 32, total: 50, revenue: "$0"},
          %{name: "Guest", sold: 8, total: 20, revenue: "$160"}
        ]
      },
      %{
        date: "Fri, Jul 18 · 7:00 PM",
        title: "Midsummer Dance",
        tiers: []
      }
    ]

    discussions = [
      %{
        post: "Midsummer 2026 — photos and thanks",
        text: "Great recap! Will the sauna be open again next year?",
        author: "Jamie Member",
        when: "2h ago"
      },
      %{
        post: "Clear Lake cleanup day",
        text: "I can bring extra gloves if helpful.",
        author: "Sam Volunteer",
        when: "Yesterday"
      }
    ]

    assigns =
      assigns
      |> assign(:events, events)
      |> assign(:discussions, discussions)

    ~H"""
    <div id="ghost-admin-dashboard" class={@class}>
      <div class="flex flex-col md:flex-row md:items-center justify-between gap-4 py-6 mb-6">
        <div>
          <.admin_page_title>Welcome back, {@first_name}</.admin_page_title>
          <p class="text-xs text-zinc-500 font-medium mt-1 flex items-center gap-2">
            <span class="w-2 h-2 rounded-full bg-emerald-500 shrink-0"></span>
            Build: 2026.06.09
          </p>
        </div>
        <div id="ghost-admin-search" class="w-full md:w-96 relative">
          <.icon
            name="hero-magnifying-glass"
            class="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-zinc-500 pointer-events-none"
          />
          <input
            type="search"
            readonly
            tabindex="-1"
            placeholder="Search events, posts, tickets, users, bookings..."
            class="block w-full pt-3 pb-3 ps-10 text-sm text-zinc-800 border border-zinc-200 rounded bg-zinc-50 pointer-events-none"
          />
        </div>
      </div>

      <.admin_volunteer_help_banner interactive?={false} />

      <div
        id="volunteer-stats-row"
        class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8"
      >
        <div class="bg-white p-5 rounded border border-zinc-200 flex flex-col justify-between">
          <div>
            <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-2">
              Upcoming Events
            </p>
            <p class="text-3xl font-black text-zinc-900">3</p>
            <p class="text-xs font-semibold text-zinc-700 mt-2 truncate">
              Summer Cabin Weekend
            </p>
            <p class="text-[10px] text-blue-600 font-bold mt-0.5">
              Sat, Jun 21 · 5:00 PM
            </p>
          </div>
          <p class="text-xs text-blue-600 font-medium mt-3">Manage events →</p>
        </div>
        <div class="bg-white p-5 rounded border border-zinc-200 flex flex-col justify-between">
          <div>
            <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-2">
              News &amp; Posts
            </p>
            <p class="text-3xl font-black text-zinc-900">24</p>
            <p class="text-xs text-zinc-500 mt-1 font-medium">
              published
              <span class="text-amber-600 font-bold ml-1">· 2 drafts</span>
            </p>
          </div>
          <p class="text-xs text-blue-600 font-medium mt-3">Manage posts →</p>
        </div>
        <div class="bg-white p-5 rounded border border-zinc-200 flex flex-col justify-between">
          <div>
            <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-2">
              Newsletters
            </p>
            <p class="text-3xl font-black text-zinc-900">18</p>
            <p class="text-xs text-zinc-500 mt-1 font-medium">
              editions sent
              <span class="text-amber-600 font-bold ml-1">· 1 draft</span>
            </p>
          </div>
          <p class="text-xs text-blue-600 font-medium mt-3">Manage newsletters →</p>
        </div>
      </div>

      <div
        id="dashboard-events-timeline"
        class="bg-white rounded border border-zinc-200 p-5 sm:p-6 shadow-sm mb-8"
      >
        <div class="flex items-center justify-between mb-6 border-b border-zinc-100 pb-3">
          <h2 class="text-lg font-black text-zinc-900 tracking-tight">
            Upcoming events
          </h2>
          <span class="text-xs font-black text-blue-600">View all</span>
        </div>
        <ul class="relative border-l-2 border-zinc-200 ml-2.5 sm:ml-3 space-y-0">
          <li
            :for={{event, idx} <- Enum.with_index(@events)}
            id={if(idx == 0, do: "ghost-dashboard-event-primary", else: nil)}
            class="relative pl-6 sm:pl-8 pb-8 last:pb-0"
          >
            <span class="absolute -left-[7px] sm:-left-[9px] top-1.5 w-3 h-3 rounded-full border-2 border-white shadow-sm bg-blue-600 z-10"></span>
            <div class="rounded-xl border border-zinc-200 p-4 sm:p-5 bg-zinc-50/40">
              <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
                <div class="min-w-0 flex-1">
                  <p class="text-xs font-bold text-blue-600 uppercase tracking-wide">
                    {event.date}
                  </p>
                  <p class="text-base font-black text-zinc-900 mt-1">
                    {event.title}
                  </p>
                </div>
                <div class="flex flex-wrap items-center gap-2 shrink-0">
                  <.button variant="outline" color="zinc" class="text-xs">
                    <.icon name="hero-globe-alt" class="w-4 h-4 -mt-0.5" /> View
                  </.button>
                  <.button variant="outline" color="zinc" class="text-xs">
                    <.icon name="hero-pencil-square" class="w-4 h-4 -mt-0.5" /> Edit
                  </.button>
                  <.button color="green" class="text-xs">
                    <.icon name="hero-qr-code" class="w-4 h-4 -mt-0.5" /> Check-in
                  </.button>
                </div>
              </div>
              <p :if={event.tiers == []} class="mt-3 text-xs text-zinc-500">
                No ticket tiers configured
              </p>
              <div :if={event.tiers != []} class="mt-4 space-y-3">
                <div :for={tier <- event.tiers} class="space-y-1.5">
                  <div class="flex justify-between gap-2 text-xs font-bold text-zinc-600">
                    <span>{tier.name}</span>
                    <span class="text-zinc-900 tabular-nums">
                      {tier.sold} / {tier.total}
                      <span class="text-zinc-400 font-medium ml-1">
                        · {tier.revenue}
                      </span>
                    </span>
                  </div>
                  <div class="w-full bg-zinc-200/80 h-2 rounded-full overflow-hidden">
                    <div
                      class="admin-ghost-tier-progress-fill bg-gradient-to-r from-blue-600 to-indigo-600 h-full rounded-full"
                      style={"--admin-ghost-tier-progress: #{tier_progress_pct(tier)}%"}
                    >
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </li>
        </ul>
      </div>

      <div
        id="dashboard-recent-discussions"
        class="bg-white rounded border border-zinc-200 p-5 shadow-sm mb-4"
      >
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-sm font-black text-zinc-900 uppercase tracking-widest">
            Recent discussions
          </h3>
          <span class="text-xs font-bold text-blue-600">View all posts</span>
        </div>
        <ul class="space-y-3">
          <li
            :for={discussion <- @discussions}
            class="border-b border-zinc-100 pb-3 last:border-0 last:pb-0"
          >
            <p class="text-sm font-semibold text-zinc-800 line-clamp-1">
              {discussion.post}
            </p>
            <p class="text-xs text-zinc-600 mt-1 line-clamp-2">{discussion.text}</p>
            <div class="flex items-center justify-between text-xs text-zinc-500 mt-1">
              <span>
                By
                <span class="font-medium text-zinc-700">{discussion.author}</span>
              </span>
              <span>{discussion.when}</span>
            </div>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  attr :class, :string, default: nil

  @doc "Desktop events table from `AdminEventsLive` (title rows, state badges, actions)."
  def admin_ghost_events_table(assigns) do
    rows = [
      %{state: :published, label: "Published"},
      %{state: :draft, label: "Draft"},
      %{state: :published, label: "Published"},
      %{state: :scheduled, label: "Scheduled"},
      %{state: :published, label: "Published"},
      %{state: :draft, label: "Draft"}
    ]

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <div
      id="ghost-events-table"
      class={[
        "hidden md:block bg-white rounded-lg border border-zinc-200 overflow-hidden",
        @class
      ]}
    >
      <div class="grid grid-cols-[2fr_1fr_1fr_1.25fr_0.9fr_1fr_3.5rem] gap-4 px-4 py-3 border-b border-zinc-200 text-xs font-semibold uppercase tracking-wide text-zinc-500">
        <span>Title</span>
        <span>Date</span>
        <span>Registrations</span>
        <span>Author</span>
        <span>State</span>
        <span>Created</span>
        <span class="sr-only">Actions</span>
      </div>
      <div
        :for={{row, idx} <- Enum.with_index(@rows)}
        class={[
          "grid grid-cols-[2fr_1fr_1fr_1.25fr_0.9fr_1fr_3.5rem] gap-4 items-center px-4 py-4 border-b border-zinc-100",
          idx == 0 && "bg-blue-50/40 relative z-10"
        ]}
      >
        <.admin_ghost_bar width="w-full" height="h-3.5" />
        <.admin_ghost_bar width="w-16" height="h-3" />
        <.admin_ghost_bar width="w-12" height="h-3" />
        <.admin_ghost_bar width="w-20" height="h-3" />
        <.badge type={YscWeb.AdminBadgeHelpers.event_state_badge_type(row.state)}>
          {row.label}
        </.badge>
        <.admin_ghost_bar width="w-16" height="h-3" />
        <div class="relative flex justify-end">
          <button
            :if={idx == 0}
            id="ghost-events-actions"
            type="button"
            tabindex="-1"
            class="inline-flex items-center justify-center rounded-md px-1 py-1 text-zinc-700 bg-zinc-100 ring-1 ring-zinc-300"
            aria-label="Event actions"
          >
            <.icon name="hero-ellipsis-vertical" class="h-5 w-5" />
          </button>
          <button
            :if={idx != 0}
            type="button"
            tabindex="-1"
            class="inline-flex items-center justify-center rounded-md px-1 py-1 text-zinc-600"
            aria-hidden="true"
          >
            <.icon name="hero-ellipsis-vertical" class="h-5 w-5" />
          </button>
          <div
            :if={idx == 0}
            id="ghost-events-actions-menu"
            class="absolute right-0 top-full mt-1 z-20 w-44 rounded-md border border-zinc-200 bg-white py-1 text-sm text-zinc-700 shadow-lg pointer-events-none"
          >
            <p class="flex items-center gap-2 px-4 py-2">
              <.icon
                name="hero-document-duplicate"
                class="h-5 w-5 shrink-0 text-zinc-500"
              /> Copy
            </p>
            <p class="flex items-center gap-2 px-4 py-2">
              <.icon
                name="hero-pencil-square"
                class="h-5 w-5 shrink-0 text-zinc-500"
              /> Edit
            </p>
            <p class="flex items-center gap-2 px-4 py-2 text-emerald-700">
              <.icon name="hero-qr-code" class="h-5 w-5 shrink-0" /> Check in
            </p>
            <p class="flex items-center gap-2 px-4 py-2 text-red-600 border-t border-zinc-100">
              <.icon name="hero-trash" class="h-5 w-5 shrink-0" /> Delete
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :class, :string, default: nil

  @doc "Desktop posts table from `AdminPostsLive` (title rows, state badges, ⋮ actions)."
  def admin_ghost_posts_table(assigns) do
    rows = [
      %{state: :published, label: "Published"},
      %{state: :published, label: "Published"},
      %{state: :draft, label: "Draft"},
      %{state: :published, label: "Published"},
      %{state: :published, label: "Published"},
      %{state: :draft, label: "Draft"}
    ]

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <div
      id="ghost-posts-table"
      class={[
        "hidden md:block bg-white rounded-lg border border-zinc-200 overflow-hidden",
        @class
      ]}
    >
      <div class="grid grid-cols-[2fr_1.25fr_0.9fr_1fr_3.5rem] gap-4 px-4 py-3 border-b border-zinc-200 text-xs font-semibold uppercase tracking-wide text-zinc-500">
        <span>Title</span>
        <span>Author</span>
        <span>State</span>
        <span>Created</span>
        <span class="sr-only">Actions</span>
      </div>
      <div
        :for={{row, idx} <- Enum.with_index(@rows)}
        class={[
          "grid grid-cols-[2fr_1.25fr_0.9fr_1fr_3.5rem] gap-4 items-center px-4 py-4 border-b border-zinc-100",
          idx == 0 && "bg-blue-50/40 relative z-10"
        ]}
      >
        <div class="flex items-center gap-1.5 min-w-0">
          <.icon
            :if={idx == 1}
            name="hero-star-solid"
            class="h-4 w-4 shrink-0 text-yellow-500"
          />
          <.admin_ghost_bar width="w-full" height="h-3.5" />
        </div>
        <.admin_ghost_bar width="w-20" height="h-3" />
        <.badge type={YscWeb.AdminBadgeHelpers.post_state_badge_type(row.state)}>
          {row.label}
        </.badge>
        <.admin_ghost_bar width="w-16" height="h-3" />
        <div class="relative flex justify-end">
          <button
            :if={idx == 0}
            id="ghost-posts-actions"
            type="button"
            tabindex="-1"
            class="inline-flex items-center justify-center rounded-md px-1 py-1 text-zinc-700 bg-zinc-100 ring-1 ring-zinc-300"
            aria-label="Post actions"
          >
            <.icon name="hero-ellipsis-vertical" class="h-5 w-5" />
          </button>
          <button
            :if={idx != 0}
            type="button"
            tabindex="-1"
            class="inline-flex items-center justify-center rounded-md px-1 py-1 text-zinc-600"
            aria-hidden="true"
          >
            <.icon name="hero-ellipsis-vertical" class="h-5 w-5" />
          </button>
          <div
            :if={idx == 0}
            id="ghost-posts-actions-menu"
            class="absolute right-0 top-full mt-1 z-20 w-44 rounded-md border border-zinc-200 bg-white py-1 text-sm text-zinc-700 shadow-lg pointer-events-none"
          >
            <p class="flex items-center gap-2 px-4 py-2">
              <.icon
                name="hero-arrow-top-right-on-square"
                class="h-5 w-5 shrink-0 text-zinc-500"
              /> View live
            </p>
            <p class="flex items-center gap-2 px-4 py-2">
              <.icon
                name="hero-pencil-square"
                class="h-5 w-5 shrink-0 text-zinc-500"
              /> Edit
            </p>
            <p class="flex items-center gap-2 px-4 py-2 font-medium text-zinc-900 bg-yellow-50">
              <.icon name="hero-star" class="h-5 w-5 shrink-0 text-zinc-500" />
              Pin post
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :class, :string, default: nil

  @doc "Desktop subscribers table from `AdminNewslettersLive` (email, status, source)."
  def admin_ghost_subscribers_table(assigns) do
    rows = [
      %{
        email: "jamie@example.com",
        name: "Jamie Member",
        active?: true,
        source: "signup",
        subscribed: "Jan 12, 2026"
      },
      %{
        email: "sam.volunteer@example.com",
        name: "Sam Volunteer",
        active?: true,
        source: "admin_added",
        subscribed: "Feb 3, 2026"
      },
      %{
        email: "former@example.com",
        name: "",
        active?: false,
        source: "signup",
        subscribed: "Nov 8, 2025"
      },
      %{
        email: "alex@ysc.org",
        name: "Alex Admin",
        active?: true,
        source: "signup",
        subscribed: "Mar 1, 2024"
      },
      %{
        email: "guest.list@example.com",
        name: "",
        active?: true,
        source: "admin_added",
        subscribed: "Jun 1, 2026"
      }
    ]

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <div
      id="ghost-subscribers-table"
      class={[
        "hidden md:block bg-white rounded-lg border border-zinc-200 overflow-hidden",
        @class
      ]}
    >
      <div class="grid grid-cols-[2fr_1fr_0.9fr_1fr_1fr_3.5rem] gap-4 px-4 py-3 border-b border-zinc-200 text-xs font-semibold uppercase tracking-wide text-zinc-500">
        <span>Email</span>
        <span>Name</span>
        <span>Status</span>
        <span>Source</span>
        <span>Subscribed</span>
        <span class="sr-only">Actions</span>
      </div>
      <div
        :for={row <- @rows}
        class="grid grid-cols-[2fr_1fr_0.9fr_1fr_1fr_3.5rem] gap-4 items-center px-4 py-4 border-b border-zinc-100 last:border-0"
      >
        <span class="font-medium text-zinc-900 truncate">{row.email}</span>
        <span class="text-zinc-600 truncate">{row.name || "—"}</span>
        <.badge type={if(row.active?, do: "green", else: "zinc")}>
          {if row.active?, do: "Active", else: "Inactive"}
        </.badge>
        <span class="text-zinc-600 truncate">{row.source}</span>
        <span class="text-zinc-600 truncate">{row.subscribed}</span>
        <div class="flex justify-end">
          <button
            type="button"
            tabindex="-1"
            class="inline-flex items-center justify-center rounded-md px-1 py-1 text-zinc-600 pointer-events-none"
            aria-hidden="true"
          >
            <.icon name="hero-ellipsis-vertical" class="h-5 w-5" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :class, :string, default: nil
  attr :event_title, :string, default: "Summer Cabin Weekend"
  attr :checked_in_count, :integer, default: 12
  attr :total_count, :integer, default: 48

  @doc """
  Full-width event check-in desk from `AdminEventCheckInLive` — sticky header,
  search, pending tickets grouped by order, and checked-in section.
  """
  def admin_ghost_event_check_in_desk(assigns) do
    pending_groups = [
      %{
        order_ref: "ORD-2026-AB12",
        tickets: [
          %{
            name: "Jamie Member",
            email: "jamie@example.com",
            tier: "Member",
            ticket_ref: "TKT-8F2K1",
            order_ref: "ORD-AB12"
          },
          %{
            name: "Sam Volunteer",
            email: "sam@example.com",
            tier: "Member",
            ticket_ref: "TKT-8F2K2",
            order_ref: "ORD-AB12"
          },
          %{
            name: "Alex Guest",
            email: "alex@example.com",
            tier: "Guest",
            ticket_ref: "TKT-8F2K3",
            order_ref: "ORD-AB12"
          }
        ]
      },
      %{
        order_ref: "ORD-2026-XY34",
        tickets: [
          %{
            name: "Pat Member",
            email: "pat@example.com",
            tier: "Member",
            ticket_ref: "TKT-9M4P2",
            order_ref: "ORD-XY34"
          }
        ]
      }
    ]

    checked_in = [
      %{
        name: "Chris Member",
        email: "chris@example.com",
        tier: "Member",
        ticket_ref: "TKT-7A1B9"
      },
      %{
        name: "Dana Guest",
        email: "dana@example.com",
        tier: "Guest",
        ticket_ref: "TKT-7A1C0"
      }
    ]

    pending_count = assigns.total_count - assigns.checked_in_count

    assigns =
      assigns
      |> assign(:pending_groups, pending_groups)
      |> assign(:checked_in, checked_in)
      |> assign(:pending_count, pending_count)

    ~H"""
    <div id="ghost-event-check-in-desk" class={["min-h-screen bg-zinc-50", @class]}>
      <.admin_check_in_sticky_bar width={:wide}>
        <div class="flex items-center gap-3 min-w-0">
          <span class="inline-flex items-center gap-1 text-sm text-zinc-600 shrink-0">
            <.icon name="hero-arrow-left" class="w-4 h-4" /> Events
          </span>
          <span class="text-zinc-300 select-none hidden sm:inline">/</span>
          <h1 class="text-base font-semibold text-zinc-900 truncate hidden sm:block">
            {@event_title}
          </h1>
        </div>

        <div id="ghost-check-in-counter">
          <.admin_check_in_counter count={@checked_in_count} total={@total_count} />
        </div>

        <div class="shrink-0 flex items-center gap-2">
          <.button class="hidden sm:inline-flex text-sm">
            <.icon name="hero-qr-code" class="w-5 h-5" /> QR Scanner
          </.button>
        </div>
      </.admin_check_in_sticky_bar>

      <.admin_check_in_search_section width={:wide}>
        <div id="ghost-check-in-search-form" class="relative" role="search">
          <div class="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none">
            <.icon name="hero-magnifying-glass" class="w-5 h-5 text-zinc-500" />
          </div>
          <input
            id="ghost-check-in-search-input"
            type="search"
            readonly
            tabindex="-1"
            placeholder="Search by name, email, ORD-xxx, or TKT-xxx…"
            class="block w-full pt-3 pb-3 ps-10 text-sm text-zinc-800 border border-zinc-200 rounded bg-zinc-50 pointer-events-none"
          />
        </div>
        <.admin_check_in_keyboard_hints quick_range="1–8" order_shortcut />
      </.admin_check_in_search_section>

      <.admin_check_in_content width={:wide}>
        <div id="ghost-check-in-pending">
          <div class="flex items-center justify-between mb-3">
            <.admin_section_heading count={@pending_count} badge_tone={:zinc}>
              Pending
            </.admin_section_heading>
          </div>

          <div class="hidden md:block bg-white rounded border border-zinc-200">
            <.admin_event_check_in_table_header />

            <div :for={group <- @pending_groups}>
              <.admin_event_check_in_order_group_header
                order_ref={group.order_ref}
                ticket_count={length(group.tickets)}
                id="ghost-check-in-order-all"
                interactive={false}
              />
              <.admin_event_check_in_pending_row
                :for={ticket <- group.tickets}
                variant={:desktop}
                interactive={false}
                name={ticket.name}
                email={ticket.email}
                tier={ticket.tier}
                ticket_ref={ticket.ticket_ref}
                order_ref={ticket.order_ref}
              />
            </div>
          </div>
        </div>

        <div id="ghost-check-in-checked-in">
          <div class="flex items-center mb-3">
            <.admin_section_heading count={@checked_in_count} badge_tone={:emerald}>
              Checked In
            </.admin_section_heading>
          </div>

          <div class="hidden md:block bg-white rounded border border-zinc-200">
            <.admin_event_check_in_checked_in_row
              :for={ticket <- @checked_in}
              variant={:desktop}
              interactive={false}
              name={ticket.name}
              email={ticket.email}
              tier={ticket.tier}
              ticket_ref={ticket.ticket_ref}
            />
          </div>
        </div>
      </.admin_check_in_content>
    </div>
    """
  end

  attr :class, :string, default: nil
  attr :event_title, :string, default: "Summer Cabin Weekend"
  attr :session_name, :string, default: "Front door scanner"
  attr :scan_count, :integer, default: 12

  @doc """
  QR scanner help preview from `AdminScannerLive` — setup panel beside a
  simplified phone mockup showing the live camera scan UI and success sheet.
  """
  def admin_ghost_scanner(assigns) do
    ~H"""
    <div id="ghost-scanner" class={["min-h-screen bg-zinc-50", @class]}>
      <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-semibold text-zinc-800">Check-in &amp; Scan</h1>
          <span class="inline-flex items-center rounded py-2 px-3 text-sm font-semibold border border-zinc-200 text-zinc-700 bg-white">
            <.icon name="hero-clock" class="w-4 h-4 -mt-0.5 me-1" /> Past Sessions
          </span>
        </div>

        <div class="grid lg:grid-cols-[minmax(0,1fr)_300px] gap-8 items-start">
          <div id="ghost-scanner-setup" class="space-y-4 max-w-lg">
            <div
              id="ghost-scanner-resume"
              class="bg-white rounded-xl border border-green-200 p-4 shadow-sm"
            >
              <h2 class="text-sm font-semibold text-green-800 mb-3 flex items-center gap-1.5">
                <.icon name="hero-arrow-path" class="w-4 h-4" />
                Resume an Active Session
              </h2>
              <div class="flex items-center justify-between bg-green-50 rounded-lg px-3 py-2.5 gap-3">
                <div class="min-w-0">
                  <div class="flex items-center gap-2">
                    <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800 shrink-0">
                      Event
                    </span>
                    <span class="text-sm font-medium text-zinc-800 truncate">
                      {@session_name}
                    </span>
                  </div>
                  <p class="text-xs text-zinc-500 mt-0.5 truncate">
                    {@event_title} · Jun 21 at 4:30 PM UTC
                  </p>
                </div>
                <.button color="green" class="shrink-0 text-sm">Resume</.button>
              </div>
            </div>

            <div class="bg-white rounded-xl border border-zinc-200 p-5 shadow-sm">
              <h2 class="text-lg font-semibold text-zinc-800 mb-4">
                Start a Check-in Session
              </h2>
              <div class="space-y-4">
                <div class="space-y-1">
                  <p class="text-sm font-medium text-zinc-700">Session Name</p>
                  <div class="h-10 rounded-lg border border-zinc-200 bg-zinc-50 px-3 flex items-center text-sm text-zinc-800">
                    {@session_name}
                  </div>
                </div>
                <div>
                  <p class="text-sm font-medium text-zinc-700 mb-1">Mode</p>
                  <p class="text-sm text-zinc-500 mb-3">
                    Choose how attendees will be checked in at this session.
                  </p>
                  <div class="grid grid-cols-3 gap-2">
                    <div class="flex flex-col items-center p-3 rounded-lg border-2 border-zinc-200">
                      <.icon
                        name="hero-identification"
                        class="w-7 h-7 mb-1.5 text-zinc-400"
                      />
                      <span class="text-xs font-medium text-zinc-600">
                        Membership
                      </span>
                    </div>
                    <div class="flex flex-col items-center p-3 rounded-lg border-2 border-blue-500 bg-blue-50">
                      <.icon
                        name="hero-ticket"
                        class="w-7 h-7 mb-1.5 text-blue-600"
                      />
                      <span class="text-xs font-medium text-blue-700">Event</span>
                    </div>
                    <div class="flex flex-col items-center p-3 rounded-lg border-2 border-zinc-200">
                      <.icon
                        name="hero-calendar-days"
                        class="w-7 h-7 mb-1.5 text-zinc-400"
                      />
                      <span class="text-xs font-medium text-zinc-600 text-center leading-tight">
                        Event + Members
                      </span>
                    </div>
                  </div>
                </div>
                <div class="space-y-1">
                  <p class="text-sm font-medium text-zinc-700">Select Event</p>
                  <div class="h-10 rounded-lg border border-zinc-200 bg-zinc-50 px-3 flex items-center text-sm text-zinc-800">
                    {@event_title}
                  </div>
                </div>
                <.button class="w-full">Start Session</.button>
              </div>
            </div>
          </div>

          <div
            id="ghost-scanner-phone"
            class="mx-auto lg:mx-0 lg:pt-4 w-[280px] shrink-0"
          >
            <div class="rounded-[2.25rem] border-[10px] border-zinc-900 bg-zinc-900 shadow-2xl">
              <div class="rounded-[1.65rem] overflow-hidden bg-black aspect-[9/19] relative">
                <div class="absolute top-0 left-1/2 -translate-x-1/2 w-24 h-5 bg-zinc-900 rounded-b-2xl z-30 pointer-events-none">
                </div>

                <div class="absolute inset-0 flex flex-col bg-black">
                  <div class="absolute top-0 inset-x-0 z-20 px-3 pt-8 pb-12 bg-gradient-to-b from-blue-950/95 to-transparent">
                    <div class="flex items-center justify-between gap-2">
                      <div class="flex items-center gap-2 text-white min-w-0">
                        <.icon name="hero-ticket" class="w-4 h-4 shrink-0" />
                        <div class="min-w-0">
                          <p class="font-semibold text-xs leading-tight truncate">
                            {@session_name}
                          </p>
                          <p class="text-[10px] text-white/55 truncate">
                            {@event_title}
                          </p>
                        </div>
                      </div>
                      <div class="flex items-center gap-1.5 shrink-0 text-white text-[10px]">
                        <span>{@scan_count} scans</span>
                        <span class="bg-white/15 border border-white/20 rounded-full px-2 py-0.5 font-semibold">
                          Desk
                        </span>
                        <span class="bg-white/15 border border-white/20 rounded-full px-2 py-0.5 font-semibold">
                          Done
                        </span>
                      </div>
                    </div>
                  </div>

                  <div
                    id="ghost-scanner-viewfinder"
                    class="flex-1 relative bg-zinc-900"
                  >
                    <div class="absolute inset-0 bg-gradient-to-b from-zinc-800 via-zinc-900 to-zinc-950">
                    </div>
                    <div class="absolute inset-0 flex items-center justify-center pointer-events-none">
                      <div class="relative w-40 h-40">
                        <div class="absolute top-0 left-0 w-8 h-8 border-t-4 border-l-4 border-white/80 rounded-tl-xl">
                        </div>
                        <div class="absolute top-0 right-0 w-8 h-8 border-t-4 border-r-4 border-white/80 rounded-tr-xl">
                        </div>
                        <div class="absolute bottom-0 left-0 w-8 h-8 border-b-4 border-l-4 border-white/80 rounded-bl-xl">
                        </div>
                        <div class="absolute bottom-0 right-0 w-8 h-8 border-b-4 border-r-4 border-white/80 rounded-br-xl">
                        </div>
                      </div>
                      <p class="absolute bottom-8 inset-x-0 text-center text-white/50 text-[10px] tracking-wide px-4">
                        Point camera at a QR code
                      </p>
                    </div>
                  </div>

                  <div
                    id="ghost-scanner-result"
                    class="absolute inset-x-0 bottom-0 z-30"
                  >
                    <div class="scanner-result-sheet bg-emerald-600 rounded-t-2xl px-4 pt-3 pb-5 text-white">
                      <div class="w-8 h-1 bg-white/30 rounded-full mx-auto mb-3">
                      </div>
                      <div class="flex items-center gap-3 mb-3">
                        <div class="w-10 h-10 bg-white/20 rounded-xl flex items-center justify-center shrink-0">
                          <.icon
                            name="hero-check-circle"
                            class="w-6 h-6 text-white"
                          />
                        </div>
                        <div class="min-w-0">
                          <p class="text-[10px] font-semibold uppercase tracking-widest text-emerald-200 mb-0.5">
                            Checked In
                          </p>
                          <p class="text-sm font-bold leading-tight truncate">
                            Jamie Member
                          </p>
                        </div>
                      </div>
                      <span class="block w-full text-center bg-white/20 text-white font-semibold py-2 rounded-xl text-xs">
                        Scan Next
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
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
          <span
            id="ghost-newsletter-send-test"
            class="inline-flex items-center gap-1.5 text-xs font-medium text-zinc-600 bg-white border border-zinc-200 rounded-md px-2.5 py-1.5 shrink-0"
          >
            <.icon name="hero-envelope" class="w-3.5 h-3.5" /> Send test
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
            <.badge type={YscWeb.AdminBadgeHelpers.event_state_badge_type(@state)}>
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
          <.dropdown
            :if={@state in [:draft, :scheduled]}
            id="ghost-event-schedule"
            right={true}
            class={
              Enum.join(
                [
                  "text-zinc-100 px-3 leading-6 py-2 text-sm font-semibold transition duration-300 min-h-[44px]",
                  @state == :scheduled && "bg-green-700 hover:bg-green-800",
                  @state != :scheduled && "bg-blue-700 hover:bg-blue-800"
                ],
                " "
              )
            }
          >
            <:button_block>
              <.icon name="hero-clock" class="w-5 h-5 me-1" />
              {if @state == :scheduled, do: "Scheduled", else: "Schedule"}
              <.icon name="hero-chevron-down" class="ms-2" />
            </:button_block>
            <div class="hidden" aria-hidden="true"></div>
          </.dropdown>
          <.dropdown
            id="ghost-event-more"
            right={true}
            class="text-zinc-800 hover:bg-zinc-100 hover:text-black min-h-[44px]"
          >
            <:button_block>
              <.icon name="hero-ellipsis-vertical" class="w-6 h-6" />
            </:button_block>
            <div class="hidden" aria-hidden="true"></div>
          </.dropdown>
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
        <span class={event_tab_class(@active_tab == :tickets)}>
          Tickets
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
        "border border-zinc-200 rounded py-6 px-4 space-y-4 bg-white",
        @class
      ]}
    >
      <div>
        <h2 class="text-xl font-bold text-zinc-900">{@title}</h2>
        <p :if={@subtitle} class="text-sm text-zinc-600">{@subtitle}</p>
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
          <.icon name="hero-ticket" class="w-5 h-5" /> Get Tickets
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

  attr :id, :string, default: "ghost-event-updates-section"
  attr :class, :string, default: nil

  @doc """
  Updates section from the public event details page — titled cards with body
  copy, relative timestamps, and a posted-by line.
  """
  def admin_ghost_public_event_updates_section(assigns) do
    ~H"""
    <section id={@id} class={["space-y-6", @class]}>
      <h3 class="text-2xl font-black text-zinc-900 tracking-tight mb-6 flex items-center gap-3">
        <span class="w-8 h-px bg-zinc-200"></span> Updates
      </h3>
      <div class="space-y-6">
        <div class="rounded-xl border border-zinc-200 bg-zinc-50/50 p-6">
          <div class="flex items-start justify-between gap-4 mb-3">
            <h4 class="text-lg font-bold text-zinc-900">
              Parking entrance has changed
            </h4>
            <span class="shrink-0 text-sm text-zinc-400">2 days ago</span>
          </div>
          <article class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-none text-zinc-600 leading-relaxed">
            <p>
              Please use the <strong>side gate on Oak Ave</strong>
              this weekend — the main clubhouse lot is closed for resurfacing.
            </p>
            <p>Street parking on Birch Lane still works; carpool if you can.</p>
          </article>
          <p class="mt-4 text-sm text-zinc-400">Posted by Alex Volunteer</p>
        </div>
        <div class="rounded-xl border border-zinc-200 bg-zinc-50/50 p-6">
          <div class="flex items-start justify-between gap-4 mb-3">
            <h4 class="text-lg font-bold text-zinc-900">What to bring</h4>
            <span class="shrink-0 text-sm text-zinc-400">1 week ago</span>
          </div>
          <article class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-none text-zinc-600 leading-relaxed">
            <p>A quick reminder before Saturday:</p>
            <ul>
              <li>Swimsuit and towel for the sauna</li>
              <li>Water bottle and sunscreen</li>
              <li>Cash or card for the bar tab</li>
            </ul>
          </article>
          <p class="mt-4 text-sm text-zinc-400">Posted by Alex Volunteer</p>
        </div>
      </div>
    </section>
    """
  end

  attr :id, :string, default: "ghost-public-event-attendees"
  attr :class, :string, default: nil

  @doc """
  Attendees section from the public event details page — hosts appear first
  with an amber ring and a **Host** label under their name.
  """
  def admin_ghost_public_attendees_section(assigns) do
    ~H"""
    <section id={@id} class={["space-y-5", @class]}>
      <h3 class="text-xl font-black text-zinc-900 tracking-tight flex items-center gap-3">
        <span class="w-8 h-px bg-zinc-200"></span> Attendees
      </h3>
      <div class="flex flex-wrap gap-5">
        <div
          id="ghost-public-event-hosts"
          class="flex flex-col items-center gap-2 w-16"
        >
          <div class="relative">
            <.admin_ghost_avatar
              size="h-14 w-14"
              class="ring-2 ring-amber-400"
            />
          </div>
          <div class="text-center w-full">
            <p class="text-xs font-bold text-zinc-900 leading-tight">
              Alex Volunteer
            </p>
            <p class="text-[10px] text-amber-500 font-medium leading-tight">
              Host
            </p>
          </div>
        </div>
        <div :for={_ <- 1..3} class="flex flex-col items-center gap-2 w-16">
          <div class="relative">
            <.admin_ghost_avatar size="h-14 w-14" class="ring-2 ring-zinc-100" />
          </div>
          <div class="text-center w-full">
            <.admin_ghost_bar width="w-12" height="h-2.5" class="mx-auto" />
            <.admin_ghost_bar width="w-10" height="h-2" class="mx-auto mt-1" />
          </div>
        </div>
      </div>
    </section>
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

  attr :title, :string, default: "Midsummer 2026 — photos and thanks"
  attr :url_name, :string, default: "midsummer-2026-photos-and-thanks"
  attr :sample_body?, :boolean, default: false
  attr :class, :string, default: nil

  @doc "Post editor chrome from `AdminPostEditorLive` — title, URL slug, actions, Trix body."
  def admin_ghost_post_editor(assigns) do
    ~H"""
    <div id="ghost-post-editor" class={@class}>
      <div class="mt-4 flex w-full items-start justify-between gap-3">
        <div class="min-w-0 flex-1">
          <div class="inline-flex max-w-full min-w-0 flex-wrap items-center gap-x-3 gap-y-2">
            <div
              id="ghost-post-editor-title"
              class="flex min-w-0 w-max max-w-full items-center"
            >
              <span class="font-extrabold text-2xl leading-7 text-zinc-900 sm:text-3xl sm:leading-8 break-words">
                {@title}
              </span>
            </div>
            <.badge type="sky" class="shrink-0 self-center">Draft</.badge>
          </div>
        </div>

        <div class="flex shrink-0 flex-row items-center gap-2 pt-0.5">
          <.button type="button" class="hidden lg:inline-flex lg:w-28">
            <.icon name="hero-document-arrow-up" class="h-5 w-5 shrink-0" />
            <span>Publish</span>
          </.button>
          <.button
            type="button"
            variant="outline"
            color="zinc"
            class="hidden lg:inline-flex px-3 py-2 text-zinc-800"
          >
            <.icon name="hero-computer-desktop" class="h-5 w-5 shrink-0" />
            <span class="sr-only">Preview post</span>
          </.button>
          <.dropdown
            id="ghost-post-editor-menu"
            right={true}
            class="text-zinc-800 hover:bg-zinc-100 hover:text-black"
          >
            <:button_block>
              <.icon name="hero-ellipsis-vertical" class="w-6 h-6" />
            </:button_block>
            <div class="w-48 py-2 text-sm font-medium text-zinc-800">
              <p class="px-4 py-2 text-zinc-700">Post Settings</p>
              <p class="px-4 py-2 text-red-600">Delete Post</p>
            </div>
          </.dropdown>
        </div>
      </div>

      <div
        id="ghost-post-editor-url"
        class="flex flex-col gap-1 py-1 text-sm leading-6 text-zinc-500 sm:flex-row sm:items-end sm:gap-2"
      >
        <.icon
          name="hero-arrow-top-right-on-square"
          class="w-4 h-4 text-zinc-800 shrink-0"
        />
        <span class="pt-2 mr-1 hidden lg:inline">https://ysc.org/posts/</span>
        <span class="text-blue-600 break-all">{@url_name}</span>
      </div>

      <.admin_ghost_trix_editor
        id="ghost-post-editor-body"
        variant={:post}
        sample?={@sample_body?}
      />
    </div>
    """
  end

  attr :id, :string, default: "ghost-trix-editor"
  attr :class, :string, default: nil
  attr :sample?, :boolean, default: true
  attr :variant, :atom, default: :event, values: [:event, :post]

  @doc """
  Static Trix editor chrome matching `AdminEventsNewLive` overview — toolbar,
  library button, and optional sample rich-text body.
  """
  def admin_ghost_trix_editor(assigns) do
    wrapper_class =
      case assigns.variant do
        :post ->
          "prose prose-zinc prose-base prose-a:text-blue-600 max-w-none mx-auto py-8 not-prose"

        :event ->
          "prose prose-zinc prose-base prose-a:text-blue-600 max-w-none not-prose"
      end

    body_class =
      case assigns.variant do
        :post ->
          "trix-content block mt-8 max-w-2xl mx-auto px-8 py-8 bg-white border-0 text-wrap min-h-[14rem]"

        :event ->
          "trix-content block px-4 py-2 bg-white border-zinc-200 border-l border-b border-r text-wrap min-h-[9rem]"
      end

    assigns =
      assigns
      |> assign(:wrapper_class, wrapper_class)
      |> assign(:body_class, body_class)

    ~H"""
    <div
      id={@id}
      class={[
        @wrapper_class,
        @class
      ]}
    >
      <trix-toolbar
        id={"#{@id}-toolbar"}
        class="pointer-events-none select-none"
        aria-hidden="true"
      >
        <div class="trix-button-row">
          <span class="trix-button-group trix-button-group--text-tools">
            <button
              type="button"
              class="trix-button trix-button--icon trix-button--icon-bold"
              tabindex="-1"
            ></button>
            <button
              type="button"
              class="trix-button trix-button--icon trix-button--icon-italic"
              tabindex="-1"
            ></button>
            <button
              type="button"
              class="trix-button trix-button--icon trix-button--icon-strike"
              tabindex="-1"
            ></button>
            <button
              type="button"
              class="trix-button trix-button--icon trix-button--icon-link"
              tabindex="-1"
            ></button>
          </span>
          <span class="trix-button-group trix-button-group--block-tools">
            <button
              type="button"
              class="trix-button trix-button--icon trix-button--icon-heading-1"
              tabindex="-1"
            ></button>
            <button
              type="button"
              class="trix-button trix-button--icon trix-button--icon-quote"
              tabindex="-1"
            ></button>
            <button
              type="button"
              class="trix-button trix-button--icon trix-button--icon-code"
              tabindex="-1"
            ></button>
            <button
              type="button"
              class="trix-button trix-button--icon trix-button--icon-bullet-list"
              tabindex="-1"
            ></button>
            <button
              type="button"
              class="trix-button trix-button--icon trix-button--icon-number-list"
              tabindex="-1"
            ></button>
            <button
              type="button"
              class="trix-button trix-button--icon trix-button--icon-decrease-nesting-level"
              tabindex="-1"
            ></button>
            <button
              type="button"
              class="trix-button trix-button--icon trix-button--icon-increase-nesting-level"
              tabindex="-1"
            ></button>
          </span>
          <span class="trix-button-group trix-button-group--file-tools">
            <button
              type="button"
              class="trix-button trix-button--icon trix-button--icon-attach"
              tabindex="-1"
            ></button>
            <button
              type="button"
              class="trix-button trix-button--icon trix-button--icon-library"
              tabindex="-1"
            ></button>
          </span>
          <span class="trix-button-group-spacer"></span>
          <span class="trix-button-group trix-button-group--history-tools">
            <button
              type="button"
              class="trix-button trix-button--icon trix-button--icon-undo"
              tabindex="-1"
            ></button>
            <button
              type="button"
              class="trix-button trix-button--icon trix-button--icon-redo"
              tabindex="-1"
            ></button>
          </span>
        </div>
      </trix-toolbar>
      <div id={"#{@id}-body"} class={@body_class}>
        <%= cond do %>
          <% @sample? && @variant == :post -> %>
            <div class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-none text-zinc-700">
              <p>
                What a weekend! Thanks to everyone who helped set up, cook, and
                keep the sauna going until the small hours.
              </p>
              <p>
                Photos are in the gallery — and mark your calendar for the cabin
                cleanup day in September.
              </p>
            </div>
          <% @sample? -> %>
            <div class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-none text-zinc-700">
              <h1>What to expect</h1>
              <p>
                Join us for a relaxing weekend at the lake clubhouse — dinner on
                Saturday, sauna and swimming, and plenty of time to catch up with
                friends.
              </p>
              <ul>
                <li>Dinner included Saturday evening</li>
                <li>Bring a swimsuit, towel, and water bottle</li>
                <li>Guests welcome — see ticket options on the event page</li>
              </ul>
              <.admin_ghost_image
                ratio="aspect-video"
                class="rounded-lg max-w-md my-2"
              />
              <p>
                <a href="#">Parking on Oak Ave</a>
                — street parking fills up by 4pm; carpool if you can.
              </p>
            </div>
          <% true -> %>
            <p class="text-zinc-400 text-sm">
              Write something delightful and nice...
            </p>
        <% end %>
      </div>
    </div>
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

  defp event_state_label(:draft), do: "Draft"
  defp event_state_label(:scheduled), do: "Scheduled"
  defp event_state_label(:published), do: "Published"

  defp event_tab_class(true),
    do:
      "shrink-0 whitespace-nowrap py-3 border-b-2 border-blue-500 text-blue-600 font-medium"

  defp event_tab_class(false),
    do:
      "shrink-0 whitespace-nowrap py-3 border-b-2 border-transparent text-zinc-500 font-medium"

  defp tier_progress_pct(%{sold: sold, total: total}) when total > 0,
    do: div(sold * 100, total)

  defp tier_progress_pct(_), do: 0
end
