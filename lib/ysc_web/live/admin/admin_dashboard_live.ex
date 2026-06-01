defmodule YscWeb.AdminDashboardLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents
  import YscWeb.Live.AsyncHelpers

  alias Ysc.{Posts, Events, Accounts, Bookings, BuildVersion, Newsletter}
  alias Ysc.Scanning
  alias YscWeb.AdminCheckInPaths

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <div class="flex flex-col md:flex-row md:items-center justify-between gap-4 py-6 mb-8">
        <div>
          <.admin_page_title>
            Welcome back, {Ysc.title_case(@current_user.first_name)}
          </.admin_page_title>
          <p class="text-xs text-zinc-500 font-medium mt-1 flex items-center gap-2">
            <span class="relative inline-flex w-2 h-2">
              <span class={[
                "w-2 h-2 rounded-full",
                if(@loading_dashboard, do: "bg-amber-500", else: "bg-emerald-500")
              ]}>
              </span>
              <span class={[
                "absolute top-0 left-0 w-2 h-2 rounded-full [animation-duration:4s]",
                if(@loading_dashboard,
                  do: "bg-amber-500 animate-ping",
                  else: "bg-emerald-500 animate-ping"
                )
              ]}>
              </span>
              <span class={[
                "absolute top-0 left-0 w-2 h-2 rounded-full [animation-duration:5s]",
                if(@loading_dashboard,
                  do: "bg-amber-500 animate-pulse",
                  else: "bg-emerald-500 animate-pulse"
                )
              ]}>
              </span>
            </span>
            <%= if @loading_dashboard do %>
              Loading dashboard...
            <% else %>
              Build: {@build_version}
            <% end %>
          </p>
        </div>
        <div class="w-full md:w-96">
          <.live_component module={YscWeb.AdminSearchComponent} id="admin-search" />
        </div>
      </div>
      <%!-- Admin-only stats row --%>
      <div
        :if={@admin_role == :admin}
        id="admin-stats-row"
        class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8"
      >
        <.link
          navigate={applications_queue_url()}
          class={[
            "p-5 rounded border flex flex-col justify-between transition-all group",
            if(@pending_reviews_count > 0,
              do:
                "bg-white border-amber-300 shadow-sm shadow-amber-50 hover:ring-2 hover:ring-amber-200",
              else: "bg-white border-zinc-200 hover:ring-2 hover:ring-zinc-300"
            )
          ]}
        >
          <div>
            <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-2">
              Applications
            </p>
            <div class="flex items-baseline gap-2">
              <p class={[
                "text-3xl font-black font-mono transition-colors",
                if(@pending_reviews_count > 0,
                  do: "text-amber-600",
                  else: "text-zinc-900 group-hover:text-amber-600"
                )
              ]}>
                {@pending_reviews_count}
              </p>
              <.badge type="yellow">Pending</.badge>
            </div>
          </div>
          <div class="mt-4 pt-3 border-t border-zinc-100 grid grid-cols-2 gap-3">
            <div>
              <p class="text-xs font-bold text-zinc-400 uppercase">This Month</p>
              <p class="text-sm font-black font-mono text-zinc-700">
                {@applications_this_month}
              </p>
              <p class="text-xs text-zinc-500 mt-0.5">
                <%= if @applications_last_month > 0 do %>
                  <span class={
                    if(@applications_month_change >= 0,
                      do: "text-emerald-600",
                      else: "text-rose-600"
                    )
                  }>
                    {if(@applications_month_change >= 0, do: "+", else: "")}{@applications_month_change}%
                  </span>
                <% else %>
                  <span class="text-zinc-400">—</span>
                <% end %>
              </p>
            </div>
            <div>
              <p class="text-xs font-bold text-zinc-400 uppercase">YTD</p>
              <p class="text-sm font-black font-mono text-zinc-700">
                {@applications_this_year}
              </p>
              <p class="text-xs text-zinc-500 mt-0.5">
                <%= if @applications_last_year > 0 do %>
                  <span class={
                    if(@applications_year_change >= 0,
                      do: "text-emerald-600",
                      else: "text-rose-600"
                    )
                  }>
                    {if(@applications_year_change >= 0, do: "+", else: "")}{@applications_year_change}%
                  </span>
                <% else %>
                  <span class="text-zinc-400">—</span>
                <% end %>
              </p>
            </div>
          </div>
          <p class="text-xs text-blue-600 font-medium mt-3 group-hover:underline">
            Review applications →
          </p>
        </.link>
        <.link
          id="dashboard-memberships-card"
          navigate={~p"/admin/memberships"}
          class="bg-white p-5 rounded border border-zinc-200 flex flex-col justify-between hover:ring-2 hover:ring-zinc-300 transition-all group"
        >
          <div>
            <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-2">
              Active memberships
            </p>
            <div class="flex items-baseline gap-2">
              <p class="text-3xl font-black font-mono text-zinc-900 group-hover:text-blue-600 transition-colors">
                {@membership_stats.total}
              </p>
              <span class="text-xs font-bold text-zinc-500">now</span>
            </div>
          </div>
          <div class="mt-3 pt-3 border-t border-zinc-100">
            <p class="text-xs font-bold text-zinc-400 uppercase mb-1">
              New members (YTD)
            </p>
            <div class="flex items-end justify-between gap-2">
              <div>
                <p class="text-xl font-black font-mono text-zinc-900 tabular-nums leading-none">
                  {@membership_joins_current_ytd}
                </p>
                <p class="text-[10px] text-zinc-500 mt-1 leading-snug">
                  {@membership_joins_prior_ytd} in same span · {@membership_joins_prior_year_label}
                </p>
              </div>
              <%= if @membership_joins_ytd_change_percent != nil do %>
                <span class={[
                  "text-xs font-black font-mono shrink-0",
                  membership_joins_ytd_change_class(
                    @membership_joins_ytd_change_percent
                  )
                ]}>
                  {if(@membership_joins_ytd_change_percent >= 0, do: "+", else: "")}{@membership_joins_ytd_change_percent}%
                </span>
              <% else %>
                <span class="text-xs font-bold text-zinc-400 shrink-0">—</span>
              <% end %>
            </div>
          </div>
          <div class="mt-3 pt-3 border-t border-zinc-100 grid grid-cols-3 gap-2 text-center">
            <div>
              <p class="text-xs font-bold text-zinc-400 uppercase">Single</p>
              <p class="text-sm font-black font-mono text-zinc-700">
                {@membership_stats.single}
              </p>
            </div>
            <div>
              <p class="text-xs font-bold text-zinc-400 uppercase">Family</p>
              <p class="text-sm font-black font-mono text-zinc-700">
                {@membership_stats.family}
              </p>
            </div>
            <div>
              <p class="text-xs font-bold text-zinc-400 uppercase">Lifetime</p>
              <p class="text-sm font-black font-mono text-zinc-700">
                {@membership_stats.lifetime}
              </p>
            </div>
          </div>
          <div class="mt-3 pt-3 border-t border-zinc-100 flex items-center justify-between text-xs">
            <span class="font-bold text-zinc-400 uppercase">
              Renewing in 30 days
            </span>
            <span class="font-black font-mono text-zinc-700 tabular-nums">
              {@memberships_renewing_30_days}
            </span>
          </div>
          <p class="text-xs text-blue-600 font-medium mt-3 group-hover:underline">
            View all memberships →
          </p>
        </.link>
        <div
          id="dashboard-pending-refunds"
          class={[
            "p-5 rounded border flex flex-col justify-between transition-all",
            if(@pending_refunds_summary.total > 0,
              do: "bg-rose-50 border-rose-300 shadow-sm shadow-rose-100",
              else: "bg-white border-zinc-200"
            )
          ]}
        >
          <%= if @pending_refunds_summary.total > 0 do %>
            <div>
              <p class="text-xs font-black text-rose-600 uppercase tracking-[0.2em] mb-2">
                Refunds to review
              </p>
              <p class="text-3xl font-black font-mono text-rose-900">
                {@pending_refunds_summary.total}
              </p>
              <p class="text-xs text-rose-700 mt-2 space-x-2">
                <span :if={@pending_refunds_summary.tahoe > 0}>
                  Tahoe {@pending_refunds_summary.tahoe}
                </span>
                <span :if={@pending_refunds_summary.clear_lake > 0}>
                  Clear Lake {@pending_refunds_summary.clear_lake}
                </span>
              </p>
            </div>
            <.link
              navigate={pending_refunds_bookings_path(@pending_refunds_summary)}
              class="text-xs text-rose-800 font-semibold mt-3 hover:underline"
            >
              Open pending refunds →
            </.link>
          <% else %>
            <div>
              <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-2">
                Pending Refunds
              </p>
              <div class="flex items-baseline gap-2 mt-1">
                <p class="text-3xl font-black font-mono text-emerald-600">0</p>
                <.badge type="green">All clear</.badge>
              </div>
              <p class="text-xs text-zinc-400 font-medium mt-2">
                No refunds awaiting review
              </p>
            </div>
            <.link
              navigate={~p"/admin/bookings"}
              class="text-xs text-zinc-400 font-medium mt-3 hover:underline"
            >
              View bookings →
            </.link>
          <% end %>
        </div>
      </div>

      <%!-- Admin-only: Property Status Matrix --%>
      <div
        :if={@admin_role == :admin}
        id="property-matrix"
        class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-8"
      >
        <.link
          navigate={~p"/admin/bookings?property=tahoe"}
          class="bg-white p-5 rounded border border-zinc-200 flex flex-col justify-between hover:ring-2 hover:ring-zinc-300 transition-all group"
        >
          <div>
            <div class="flex items-center justify-between mb-2">
              <p class="text-xs font-black text-sky-600 uppercase tracking-[0.2em]">
                Tahoe
              </p>
              <span class="flex items-center gap-1.5">
                <span class={[
                  "w-1.5 h-1.5 rounded-full",
                  if(@property_stats.tahoe.staying > 0,
                    do: "bg-emerald-500",
                    else: "bg-zinc-300"
                  )
                ]}>
                </span>
                <span class="text-[10px] font-bold text-zinc-400 uppercase">
                  {if(@property_stats.tahoe.staying > 0,
                    do: "Active",
                    else: "Empty"
                  )}
                </span>
              </span>
            </div>
            <div class="flex items-baseline gap-2">
              <p class="text-3xl font-black font-mono text-zinc-900 group-hover:text-sky-600 transition-colors">
                {@property_stats.tahoe.staying}
              </p>
              <span class="text-xs font-bold text-zinc-400">staying now</span>
            </div>
            <div class="mt-3 grid grid-cols-2 gap-2 text-xs">
              <div class="rounded bg-emerald-50 border border-emerald-100 p-2">
                <p class="font-bold text-emerald-700 uppercase text-[10px]">
                  Checking in
                </p>
                <p class="font-black font-mono text-emerald-800 text-lg">
                  {@property_stats.tahoe.checkins_today}
                </p>
              </div>
              <div class="rounded bg-amber-50 border border-amber-100 p-2">
                <p class="font-bold text-amber-700 uppercase text-[10px]">
                  Checking out
                </p>
                <p class="font-black font-mono text-amber-800 text-lg">
                  {@property_stats.tahoe.checkouts_today}
                </p>
              </div>
            </div>
          </div>
          <div class="mt-3 pt-3 border-t border-zinc-100 grid grid-cols-2 gap-3 text-xs">
            <div>
              <p class="font-bold text-zinc-400 uppercase text-[10px]">
                Next 14 days
              </p>
              <p class="font-black font-mono text-zinc-800 mt-0.5">
                {@property_stats.tahoe.upcoming_bookings}
                {if(@property_stats.tahoe.upcoming_bookings == 1,
                  do: "booking",
                  else: "bookings"
                )}
              </p>
            </div>
            <div>
              <p class="font-bold text-zinc-400 uppercase text-[10px]">
                Expected guests
              </p>
              <p class="font-black font-mono text-zinc-800 mt-0.5">
                {@property_stats.tahoe.upcoming_guests}
              </p>
            </div>
          </div>
          <p class="text-xs text-blue-600 font-medium mt-3 group-hover:underline">
            View Tahoe bookings →
          </p>
        </.link>
        <.link
          navigate={~p"/admin/bookings?property=clear_lake"}
          class="bg-white p-5 rounded border border-zinc-200 flex flex-col justify-between hover:ring-2 hover:ring-zinc-300 transition-all group"
        >
          <div>
            <div class="flex items-center justify-between mb-2">
              <p class="text-xs font-black text-teal-600 uppercase tracking-[0.2em]">
                Clear Lake
              </p>
              <span class="flex items-center gap-1.5">
                <span class={[
                  "w-1.5 h-1.5 rounded-full",
                  if(@property_stats.clear_lake.staying > 0,
                    do: "bg-emerald-500",
                    else: "bg-zinc-300"
                  )
                ]}>
                </span>
                <span class="text-[10px] font-bold text-zinc-400 uppercase">
                  {if(@property_stats.clear_lake.staying > 0,
                    do: "Active",
                    else: "Empty"
                  )}
                </span>
              </span>
            </div>
            <div class="flex items-baseline gap-2">
              <p class="text-3xl font-black font-mono text-zinc-900 group-hover:text-teal-600 transition-colors">
                {@property_stats.clear_lake.staying}
              </p>
              <span class="text-xs font-bold text-zinc-400">staying now</span>
            </div>
            <div class="mt-3 grid grid-cols-2 gap-2 text-xs">
              <div class="rounded bg-emerald-50 border border-emerald-100 p-2">
                <p class="font-bold text-emerald-700 uppercase text-[10px]">
                  Checking in
                </p>
                <p class="font-black font-mono text-emerald-800 text-lg">
                  {@property_stats.clear_lake.checkins_today}
                </p>
              </div>
              <div class="rounded bg-amber-50 border border-amber-100 p-2">
                <p class="font-bold text-amber-700 uppercase text-[10px]">
                  Checking out
                </p>
                <p class="font-black font-mono text-amber-800 text-lg">
                  {@property_stats.clear_lake.checkouts_today}
                </p>
              </div>
            </div>
          </div>
          <div class="mt-3 pt-3 border-t border-zinc-100 grid grid-cols-2 gap-3 text-xs">
            <div>
              <p class="font-bold text-zinc-400 uppercase text-[10px]">
                Next 14 days
              </p>
              <p class="font-black font-mono text-zinc-800 mt-0.5">
                {@property_stats.clear_lake.upcoming_bookings}
                {if(@property_stats.clear_lake.upcoming_bookings == 1,
                  do: "booking",
                  else: "bookings"
                )}
              </p>
            </div>
            <div>
              <p class="font-bold text-zinc-400 uppercase text-[10px]">
                Expected guests
              </p>
              <p class="font-black font-mono text-zinc-800 mt-0.5">
                {@property_stats.clear_lake.upcoming_guests}
              </p>
            </div>
          </div>
          <p class="text-xs text-blue-600 font-medium mt-3 group-hover:underline">
            View Clear Lake bookings →
          </p>
        </.link>
      </div>

      <%!-- Volunteer quick stats --%>
      <div
        :if={@admin_role == :volunteer}
        id="volunteer-stats-row"
        class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8"
      >
        <.link
          navigate={~p"/admin/events"}
          class="bg-white p-5 rounded border border-zinc-200 flex flex-col justify-between hover:ring-2 hover:ring-zinc-300 transition-all group"
        >
          <div>
            <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-2">
              Upcoming Events
            </p>
            <p class="text-3xl font-black text-zinc-900 group-hover:text-blue-600 transition-colors">
              {@upcoming_events_count}
            </p>
            <%= if @events_with_tickets != [] do %>
              <p class="text-xs font-semibold text-zinc-700 mt-2 truncate">
                {hd(@events_with_tickets).event.title}
              </p>
              <p class="text-[10px] text-blue-600 font-bold mt-0.5">
                {event_start_pst_label(hd(@events_with_tickets).event)}
              </p>
            <% else %>
              <p class="text-xs text-zinc-400 mt-2">No upcoming events</p>
            <% end %>
          </div>
          <p class="text-xs text-blue-600 font-medium mt-3 group-hover:underline">
            Manage events →
          </p>
        </.link>
        <.link
          navigate={~p"/admin/posts"}
          class="bg-white p-5 rounded border border-zinc-200 flex flex-col justify-between hover:ring-2 hover:ring-zinc-300 transition-all group"
        >
          <div>
            <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-2">
              News &amp; Posts
            </p>
            <p class="text-3xl font-black text-zinc-900 group-hover:text-blue-600 transition-colors">
              {@published_posts_count}
            </p>
            <p class="text-xs text-zinc-500 mt-1 font-medium">
              published
              <span
                :if={@draft_posts_count > 0}
                class="text-amber-600 font-bold ml-1"
              >
                · {@draft_posts_count} draft{if(@draft_posts_count == 1,
                  do: "",
                  else: "s"
                )}
              </span>
            </p>
          </div>
          <p class="text-xs text-blue-600 font-medium mt-3 group-hover:underline">
            Manage posts →
          </p>
        </.link>
        <.link
          navigate={~p"/admin/newsletters"}
          class="bg-white p-5 rounded border border-zinc-200 flex flex-col justify-between hover:ring-2 hover:ring-zinc-300 transition-all group"
        >
          <div>
            <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-2">
              Newsletters
            </p>
            <p class="text-3xl font-black text-zinc-900 group-hover:text-blue-600 transition-colors">
              {@newsletter_editions_count}
            </p>
            <p class="text-xs text-zinc-500 mt-1 font-medium">
              editions sent
              <span
                :if={@draft_newsletter_count > 0}
                class="text-amber-600 font-bold ml-1"
              >
                · {@draft_newsletter_count} draft{if(@draft_newsletter_count == 1,
                  do: "",
                  else: "s"
                )}
              </span>
            </p>
          </div>
          <p class="text-xs text-blue-600 font-medium mt-3 group-hover:underline">
            Manage newsletters →
          </p>
        </.link>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-8 pb-8">
        <div class={[
          "min-w-0",
          if(@admin_role == :admin, do: "lg:col-span-8", else: "lg:col-span-12")
        ]}>
          <div
            id="dashboard-events-timeline"
            class="bg-white rounded border border-zinc-200 p-5 sm:p-6 shadow-sm"
          >
            <div class="flex items-center justify-between mb-6 border-b border-zinc-100 pb-3">
              <h2 class="text-lg font-black text-zinc-900 tracking-tight">
                Upcoming events
              </h2>
              <.link
                navigate={~p"/admin/events"}
                class="text-xs font-black text-blue-600 hover:underline"
              >
                View all
              </.link>
            </div>

            <div
              :if={Enum.empty?(@events_with_tickets)}
              class="text-center py-12 border-2 border-dashed border-zinc-100 rounded-lg"
            >
              <.icon
                name="hero-calendar"
                class="w-8 h-8 text-zinc-200 mx-auto mb-2"
              />
              <p class="text-sm text-zinc-400">No upcoming events</p>
            </div>

            <ul
              :if={not Enum.empty?(@events_with_tickets)}
              class="relative border-l-2 border-zinc-200 ml-2.5 sm:ml-3 space-y-0"
            >
              <li
                :for={%{event: event, ticket_tiers: tiers} <- @events_with_tickets}
                id={"dashboard-event-#{event.id}"}
                class="relative pl-6 sm:pl-8 pb-8 last:pb-0 group"
              >
                <span class={[
                  "absolute -left-[7px] sm:-left-[9px] top-1.5 w-3 h-3 rounded-full border-2 border-white shadow-sm z-10",
                  "bg-blue-600 group-hover:scale-110 transition-transform"
                ]}>
                </span>
                <div class={[
                  "rounded-xl border border-zinc-200 p-4 sm:p-5 bg-zinc-50/40",
                  "group-hover:border-blue-200 group-hover:bg-white group-hover:shadow-md transition-all"
                ]}>
                  <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
                    <div class="min-w-0 flex-1">
                      <p class="text-xs font-bold text-blue-600 uppercase tracking-wide">
                        {event_start_pst_label(event)}
                      </p>
                      <p class="text-base font-black text-zinc-900 mt-1 truncate">
                        {event.title}
                      </p>
                    </div>
                    <div class="flex flex-wrap items-center gap-2 shrink-0">
                      <.button
                        id={"dashboard-event-#{event.id}-public"}
                        variant="outline"
                        color="zinc"
                        navigate={~p"/events/#{event.id}"}
                      >
                        <.icon name="hero-globe-alt" class="w-4 h-4 -mt-0.5" /> View
                      </.button>
                      <.button
                        id={"dashboard-event-#{event.id}-edit"}
                        variant="outline"
                        color="zinc"
                        navigate={~p"/admin/events/#{event.id}/edit"}
                      >
                        <.icon name="hero-pencil-square" class="w-4 h-4 -mt-0.5" />
                        Edit
                      </.button>
                      <.button
                        id={"dashboard-event-#{event.id}-check-in"}
                        color="green"
                        navigate={
                          AdminCheckInPaths.path_for_event(
                            event.id,
                            @open_check_in_sessions
                          )
                        }
                      >
                        <.icon name="hero-qr-code" class="w-4 h-4 -mt-0.5" />
                        Check-in
                      </.button>
                    </div>
                  </div>

                  <div :if={Enum.empty?(tiers)} class="mt-3 text-xs text-zinc-500">
                    No ticket tiers configured
                  </div>

                  <div :if={not Enum.empty?(tiers)} class="mt-4 space-y-3">
                    <div :for={tier <- tiers} class="space-y-1.5">
                      <div class="flex justify-between gap-2 text-xs font-bold text-zinc-600">
                        <span class="truncate">{tier.name}</span>
                        <span class="shrink-0 text-zinc-900 tabular-nums">
                          {tier.sold_tickets_count} / {if(tier.quantity,
                            do: tier.quantity,
                            else: "∞"
                          )}
                          <span class="text-zinc-400 font-medium ml-1">
                            · {format_money(tier_line_revenue(tier))}
                          </span>
                        </span>
                      </div>
                      <div class="w-full bg-zinc-200/80 h-2 rounded-full overflow-hidden">
                        <div
                          class="bg-gradient-to-r from-blue-600 to-indigo-600 h-full rounded-full transition-all duration-700 max-w-full"
                          style={"width: #{calculate_progress_percentage(tier)}%"}
                        >
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </li>
            </ul>
          </div>
        </div>

        <div
          :if={@admin_role == :admin}
          class="lg:col-span-4 space-y-6 min-w-0"
        >
          <div
            id="dashboard-financials"
            class="bg-white rounded border border-zinc-200 p-5 shadow-sm space-y-5"
          >
            <h2 class="text-sm font-black text-zinc-900 uppercase tracking-widest border-b border-zinc-100 pb-2">
              Financials
            </h2>
            <div>
              <div class="flex items-start justify-between gap-3">
                <div class="flex-1 min-w-0">
                  <p class="text-xs font-bold text-zinc-400 uppercase">
                    Total revenue ({@current_period_label})
                  </p>
                  <p class="text-2xl font-black font-mono text-emerald-600 mt-1 tabular-nums">
                    {format_money(@current_month_revenue)}
                  </p>
                </div>
                <svg
                  viewBox="0 0 80 24"
                  width="80"
                  height="24"
                  class="mt-2 overflow-visible shrink-0 opacity-80"
                  aria-hidden="true"
                >
                  <polyline
                    points={sparkline_fill_points(@revenue_sparkline)}
                    fill="rgba(16,185,129,0.1)"
                    stroke="none"
                  />
                  <polyline
                    points={sparkline_line_points(@revenue_sparkline)}
                    fill="none"
                    stroke="#10b981"
                    stroke-width="1.5"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
              </div>
              <div class="flex items-baseline gap-2 mt-1.5 mb-1">
                <p class="text-xs font-bold text-zinc-400 uppercase">
                  YTD {@ytd_revenue_label}
                </p>
                <p class="text-sm font-black font-mono text-zinc-700 tabular-nums">
                  {format_money(@ytd_revenue)}
                </p>
              </div>
              <div class="flex flex-wrap gap-x-4 gap-y-1 mt-2 text-xs font-bold">
                <span class={[
                  "inline-flex items-center",
                  get_revenue_change_color_class(@revenue_change_direction)
                ]}>
                  <.icon
                    name={get_revenue_change_icon(@revenue_change_direction)}
                    class="w-3 h-3 mr-0.5"
                  /> MoM {@revenue_change_text}
                </span>
                <span class={[
                  "inline-flex items-center",
                  get_revenue_change_color_class(@revenue_yoy_change_direction)
                ]}>
                  <.icon
                    name={get_revenue_change_icon(@revenue_yoy_change_direction)}
                    class="w-3 h-3 mr-0.5"
                  /> YoY {@revenue_yoy_change_text}
                </span>
              </div>
              <div class="grid grid-cols-2 gap-3 mt-3 text-xs">
                <div class="rounded bg-zinc-50 p-2 border border-zinc-100">
                  <p class="font-bold text-zinc-400 uppercase">Prev. month</p>
                  <p class="font-black font-mono text-zinc-800 mt-0.5">
                    {format_money(@last_month_revenue)}
                  </p>
                </div>
                <div class="rounded bg-zinc-50 p-2 border border-zinc-100">
                  <p class="font-bold text-zinc-400 uppercase">
                    {@comparison_month_year_pretty}
                  </p>
                  <p class="font-black font-mono text-zinc-800 mt-0.5">
                    {format_money(@last_year_month_revenue)}
                  </p>
                </div>
              </div>
            </div>

            <div>
              <p class="text-xs font-black text-zinc-500 uppercase mb-2">
                Revenue mix · this month
              </p>
              <div class="w-full bg-zinc-100 h-2.5 rounded-full overflow-hidden flex mb-3">
                <div
                  class="bg-blue-600 h-full"
                  style={"width: #{@revenue_mix_bookings_percent}%"}
                >
                </div>
                <div
                  class="bg-purple-500 h-full"
                  style={"width: #{@revenue_mix_events_percent}%"}
                >
                </div>
                <div
                  class="bg-emerald-500 h-full"
                  style={"width: #{@revenue_mix_membership_percent}%"}
                >
                </div>
              </div>
              <p class="text-[10px] font-bold text-zinc-400 uppercase mb-1">
                Last month
              </p>
              <div class="w-full bg-zinc-100 h-1.5 rounded-full overflow-hidden flex mb-3 opacity-90">
                <div
                  class="bg-blue-500 h-full"
                  style={"width: #{@prev_revenue_mix_bookings_percent}%"}
                >
                </div>
                <div
                  class="bg-purple-400 h-full"
                  style={"width: #{@prev_revenue_mix_events_percent}%"}
                >
                </div>
                <div
                  class="bg-emerald-400 h-full"
                  style={"width: #{@prev_revenue_mix_membership_percent}%"}
                >
                </div>
              </div>
              <p class="text-[10px] font-bold text-zinc-400 uppercase mb-1">
                Same month prior year
              </p>
              <div class="w-full bg-zinc-100 h-1.5 rounded-full overflow-hidden flex mb-3 opacity-90">
                <div
                  class="bg-blue-400 h-full"
                  style={"width: #{@last_year_revenue_mix_bookings_percent}%"}
                >
                </div>
                <div
                  class="bg-purple-300 h-full"
                  style={"width: #{@last_year_revenue_mix_events_percent}%"}
                >
                </div>
                <div
                  class="bg-emerald-300 h-full"
                  style={"width: #{@last_year_revenue_mix_membership_percent}%"}
                >
                </div>
              </div>
              <div class="flex items-center gap-3 mb-3">
                <span class="flex items-center gap-1 text-[10px] text-zinc-500">
                  <span class="inline-block w-2 h-2 rounded-sm bg-blue-600 shrink-0">
                  </span>
                  Bookings
                </span>
                <span class="flex items-center gap-1 text-[10px] text-zinc-500">
                  <span class="inline-block w-2 h-2 rounded-sm bg-purple-500 shrink-0">
                  </span>
                  Events
                </span>
                <span class="flex items-center gap-1 text-[10px] text-zinc-500">
                  <span class="inline-block w-2 h-2 rounded-sm bg-emerald-500 shrink-0">
                  </span>
                  Memberships
                </span>
              </div>
              <div class="space-y-1.5 text-xs">
                <div class="flex justify-between">
                  <span class="text-zinc-500">Bookings</span>
                  <span class="font-bold text-zinc-800">
                    {format_money(@revenue_bookings)}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-zinc-500">Events</span>
                  <span class="font-bold text-zinc-800">
                    {format_money(@revenue_events)}
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-zinc-500">Membership</span>
                  <span class="font-bold text-zinc-800">
                    {format_money(@revenue_membership)}
                  </span>
                </div>
              </div>
            </div>

            <div>
              <p class="text-xs font-black text-zinc-500 uppercase mb-2">
                Cabin booking revenue
              </p>
              <div class="w-full bg-zinc-100 h-2.5 rounded-full overflow-hidden flex mb-2">
                <div
                  class="bg-sky-600 h-full"
                  style={"width: #{@cabin_tahoe_percent_of_bookings}%"}
                >
                </div>
                <div
                  class="bg-teal-500 h-full"
                  style={"width: #{@cabin_clear_lake_percent_of_bookings}%"}
                >
                </div>
              </div>
              <div class="flex justify-between text-xs">
                <span class="text-zinc-600">
                  <span class="inline-block w-2 h-2 rounded-full bg-sky-600 align-middle mr-1">
                  </span>
                  Tahoe {format_money(@revenue_tahoe_bookings)}
                </span>
                <span class="text-zinc-600">
                  <span class="inline-block w-2 h-2 rounded-full bg-teal-500 align-middle mr-1">
                  </span>
                  Clear Lake {format_money(@revenue_clear_lake_bookings)}
                </span>
              </div>
            </div>
          </div>

          <div
            id="dashboard-newsletters"
            class="bg-white rounded border border-zinc-200 p-5 shadow-sm"
          >
            <div class="flex items-center justify-between border-b border-zinc-100 pb-2 mb-3">
              <div>
                <h2 class="text-sm font-black text-zinc-900 uppercase tracking-widest">
                  Recent newsletters
                </h2>
                <p class="text-xs text-zinc-500 mt-0.5">
                  <span class="font-bold text-zinc-700">
                    {@newsletter_subscriber_count}
                  </span>
                  active subscribers
                  <span
                    :if={@newsletter_subscribers_this_month > 0}
                    class="text-emerald-600 font-bold ml-1"
                  >
                    +{@newsletter_subscribers_this_month} this month
                  </span>
                </p>
              </div>
              <.link
                navigate={~p"/admin/newsletters"}
                class="text-xs font-bold text-blue-600 hover:underline shrink-0"
              >
                All
              </.link>
            </div>
            <div
              :if={Enum.empty?(@recent_newsletters_with_stats)}
              class="text-center py-8 text-sm text-zinc-400"
            >
              No sent editions yet
            </div>
            <ul
              :if={not Enum.empty?(@recent_newsletters_with_stats)}
              class="space-y-3"
            >
              <li
                :for={row <- @recent_newsletters_with_stats}
                id={"dashboard-newsletter-#{row.edition.id}"}
                class="rounded-lg border border-zinc-100 p-3 hover:border-zinc-200 transition-colors"
              >
                <.link
                  navigate={~p"/admin/newsletters/#{row.edition.id}/edit"}
                  class="text-sm font-bold text-zinc-900 hover:text-blue-600 line-clamp-2"
                >
                  {row.edition.title}
                </.link>
                <p class="text-[10px] text-zinc-400 mt-1">
                  <%= if row.edition.sent_at do %>
                    {format_admin_datetime(row.edition.sent_at)}
                  <% else %>
                    —
                  <% end %>
                </p>
                <div class="flex flex-wrap items-center gap-2 mt-2">
                  <.badge type="zinc" class="me-0">
                    Sent {row.edition.sent_count}
                  </.badge>
                  <.badge type="sky" class="me-0 tabular-nums">
                    {format_newsletter_stat(
                      row.opens,
                      row.edition.sent_count,
                      "opened"
                    )}
                  </.badge>
                  <.badge type="green" class="me-0 tabular-nums">
                    {format_newsletter_stat(
                      row.clicks,
                      row.edition.sent_count,
                      "clicked"
                    )}
                  </.badge>
                </div>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div
        :if={@admin_role == :admin}
        id="review-applications-section"
        class="bg-white rounded border border-zinc-200 p-5 sm:p-6 shadow-sm mb-6"
      >
        <div class="flex flex-wrap items-center justify-between gap-2 mb-4 border-b border-zinc-100 pb-3">
          <div class="flex items-center gap-2">
            <div class="w-8 h-8 bg-amber-100 rounded-lg flex items-center justify-center">
              <.icon name="hero-users" class="w-5 h-5 text-amber-600" />
            </div>
            <h2 class="text-lg font-black text-zinc-900 tracking-tight">
              Review applications
            </h2>
            <.badge :if={@pending_reviews_count > 0} type="yellow">
              {@pending_reviews_count} pending
            </.badge>
          </div>
          <.link
            :if={@pending_reviews_count > 0}
            navigate={applications_queue_url()}
            class="text-xs font-bold text-blue-600 hover:underline"
          >
            View all pending
          </.link>
        </div>

        <div
          :if={Enum.empty?(@pending_users)}
          class="text-center py-8 border-2 border-dashed border-zinc-100 rounded-lg"
        >
          <.icon
            name="hero-check-circle"
            class="w-7 h-7 text-zinc-200 mx-auto mb-2"
          />
          <p class="text-sm text-zinc-400">No pending applications</p>
        </div>

        <div :if={not Enum.empty?(@pending_users)} class="space-y-3">
          <div
            :for={user <- Enum.take(@pending_users, 3)}
            class={[
              "flex flex-col sm:flex-row sm:items-center gap-3 p-4 bg-zinc-50/80 border border-zinc-100 rounded-lg hover:ring-2 hover:ring-zinc-200 transition-all group relative overflow-hidden",
              get_application_card_classes(user)
            ]}
          >
            <div class={[
              "absolute left-0 top-0 bottom-0 w-1 group-hover:w-1.5 transition-all",
              get_status_pillar_color(user)
            ]}>
            </div>
            <div class="relative flex-shrink-0 pl-1">
              <.user_avatar_image
                user={user}
                class="w-11 h-11 rounded-full object-cover ring-2 ring-white shadow-sm"
              />
            </div>
            <div class="flex-1 min-w-0 pl-1">
              <h4 class="font-bold text-zinc-900 truncate text-sm">
                {"#{user.first_name} #{user.last_name}"}
              </h4>
              <div class="flex flex-wrap items-center gap-2 mt-0.5">
                <.badge type={get_status_badge_type(user)}>
                  {get_status_badge_text(user)}
                </.badge>
                <span class="text-xs text-zinc-400 font-medium">
                  {get_time_waiting_text(user)}
                </span>
              </div>
            </div>
            <div class="flex items-center gap-3 pl-1 sm:pl-0">
              <div class="hidden md:block text-right text-xs">
                <p class="font-black text-zinc-400 uppercase tracking-wider">
                  Plan
                </p>
                <p class="font-bold text-zinc-700">
                  {get_membership_type_display(user)}
                </p>
              </div>
              <.button
                phx-click="navigate-to-review"
                phx-value-user-id={user.id}
              >
                {get_review_button_text(user)}
              </.button>
            </div>
          </div>
        </div>
      </div>

      <div
        id="dashboard-recent-discussions"
        class="bg-white rounded border border-zinc-200 p-5 shadow-sm mb-8"
      >
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-sm font-black text-zinc-900 uppercase tracking-widest">
            Recent discussions
          </h3>
          <.link
            navigate={~p"/admin/posts"}
            class="text-xs font-bold text-blue-600 hover:underline"
          >
            View all posts
          </.link>
        </div>
        <p
          :if={Enum.empty?(@latest_comments)}
          class="text-xs text-zinc-400 italic py-1"
        >
          No new comments to moderate
        </p>
        <ul :if={not Enum.empty?(@latest_comments)} class="space-y-3">
          <li
            :for={comment <- @latest_comments}
            class="border-b border-zinc-100 pb-3 last:border-0 last:pb-0"
          >
            <div class="flex justify-between items-start gap-2 mb-1">
              <div class="flex-1 min-w-0">
                <.link
                  navigate={~p"/posts/#{comment.post.url_name || comment.post.id}"}
                  class="text-sm font-semibold text-zinc-800 hover:text-blue-600 line-clamp-1"
                >
                  {comment.post.title}
                </.link>
                <p class="text-xs text-zinc-600 mt-1 line-clamp-2">
                  {comment.text}
                </p>
              </div>
            </div>
            <div class="flex items-center justify-between text-xs text-zinc-500 mt-1">
              <span>
                By
                <span class="font-medium text-zinc-700">
                  {"#{comment.author.first_name} #{comment.author.last_name}"}
                </span>
              </span>
              <span>{format_admin_datetime(comment.inserted_at)}</span>
            </div>
          </li>
        </ul>
      </div>
    </.side_menu>
    """
  end

  @impl true
  @spec mount(any(), any(), map()) :: {:ok, map()}
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:active_page, :dashboard)
      |> assign(:build_version, BuildVersion.version())
      |> assign(:page_title, "Dashboard")
      |> assign(:loading_dashboard, true)
      |> assign(:latest_comments, [])
      |> assign(:events_with_tickets, [])
      |> assign(:open_check_in_sessions, %{})
      # Admin-only placeholders
      |> assign(:pending_users, [])
      |> assign(:pending_reviews_count, 0)
      |> assign(:current_month_revenue, Money.new(:USD, 0))
      |> assign(:revenue_change_text, "—")
      |> assign(:revenue_change_direction, :neutral)
      |> assign(:last_month_revenue, Money.new(:USD, 0))
      |> assign(:last_year_month_revenue, Money.new(:USD, 0))
      |> assign(:applications_this_month, 0)
      |> assign(:applications_this_year, 0)
      |> assign(:applications_last_month, 0)
      |> assign(:applications_last_year, 0)
      |> assign(:applications_month_change, 0)
      |> assign(:applications_year_change, 0)
      |> assign(:revenue_bookings, Money.new(:USD, 0))
      |> assign(:revenue_events, Money.new(:USD, 0))
      |> assign(:revenue_membership, Money.new(:USD, 0))
      |> assign(:revenue_mix_bookings_percent, 0)
      |> assign(:revenue_mix_events_percent, 0)
      |> assign(:revenue_mix_membership_percent, 0)
      |> assign(:prev_revenue_bookings, Money.new(:USD, 0))
      |> assign(:prev_revenue_events, Money.new(:USD, 0))
      |> assign(:prev_revenue_membership, Money.new(:USD, 0))
      |> assign(:prev_revenue_mix_bookings_percent, 0)
      |> assign(:prev_revenue_mix_events_percent, 0)
      |> assign(:prev_revenue_mix_membership_percent, 0)
      |> assign(:last_year_revenue_bookings, Money.new(:USD, 0))
      |> assign(:last_year_revenue_events, Money.new(:USD, 0))
      |> assign(:last_year_revenue_membership, Money.new(:USD, 0))
      |> assign(:last_year_revenue_mix_bookings_percent, 0)
      |> assign(:last_year_revenue_mix_events_percent, 0)
      |> assign(:last_year_revenue_mix_membership_percent, 0)
      |> assign(:revenue_tahoe_bookings, Money.new(:USD, 0))
      |> assign(:revenue_clear_lake_bookings, Money.new(:USD, 0))
      |> assign(:cabin_tahoe_percent_of_bookings, 0)
      |> assign(:cabin_clear_lake_percent_of_bookings, 0)
      |> assign(:current_period_label, "—")
      |> assign(:comparison_month_year_pretty, "—")
      |> assign(:revenue_yoy_change_text, "—")
      |> assign(:revenue_yoy_change_direction, :neutral)
      |> assign(:pending_refunds_summary, %{total: 0, tahoe: 0, clear_lake: 0})
      |> assign(:recent_newsletters_with_stats, [])
      |> assign(:property_stats, %{
        tahoe: %{
          staying: 0,
          checkins_today: 0,
          checkouts_today: 0,
          upcoming_bookings: 0,
          upcoming_guests: 0
        },
        clear_lake: %{
          staying: 0,
          checkins_today: 0,
          checkouts_today: 0,
          upcoming_bookings: 0,
          upcoming_guests: 0
        }
      })
      |> assign(:revenue_sparkline, List.duplicate(Decimal.new(0), 7))
      |> assign(:membership_stats, %{
        total: 0,
        single: 0,
        family: 0,
        lifetime: 0
      })
      |> assign(:membership_joins_current_ytd, 0)
      |> assign(:membership_joins_prior_ytd, 0)
      |> assign(:membership_joins_prior_year_label, "—")
      |> assign(:membership_joins_ytd_change_percent, nil)
      |> assign(:memberships_renewing_30_days, 0)
      |> assign(:ytd_revenue, Money.new(:USD, 0))
      |> assign(:ytd_revenue_label, "—")
      |> assign(:newsletter_subscriber_count, 0)
      |> assign(:newsletter_subscribers_this_month, 0)
      # Volunteer-only placeholders
      |> assign(:upcoming_events_count, 0)
      |> assign(:published_posts_count, 0)
      |> assign(:newsletter_editions_count, 0)
      |> assign(:draft_posts_count, 0)
      |> assign(:draft_newsletter_count, 0)

    if connected?(socket) do
      send(self(), :load_dashboard_data)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(
        :load_dashboard_data,
        %{assigns: %{admin_role: :volunteer}} = socket
      ) do
    data =
      [
        {:latest_comments, fn -> Posts.get_latest_comments(5) end},
        {:events_with_tickets,
         fn -> Events.get_upcoming_events_with_ticket_tier_counts() end},
        {:published_posts_count, fn -> get_published_posts_count() end},
        {:newsletter_editions_count, fn -> get_newsletter_editions_count() end},
        {:draft_posts_count, fn -> get_draft_posts_count() end},
        {:draft_newsletter_count, fn -> get_draft_newsletter_count() end}
      ]
      |> async_stream_with_repo(fn {key, fun} -> {key, fun.()} end,
        timeout: :infinity,
        max_concurrency: 6
      )
      |> Enum.reduce(%{}, fn {:ok, {key, value}}, acc ->
        Map.put(acc, key, value)
      end)

    events_with_tickets = Map.fetch!(data, :events_with_tickets)

    {:noreply,
     socket
     |> assign(:loading_dashboard, false)
     |> assign(:latest_comments, Map.fetch!(data, :latest_comments))
     |> assign(:events_with_tickets, events_with_tickets)
     |> assign_dashboard_check_in_sessions(events_with_tickets)
     |> assign(:upcoming_events_count, length(events_with_tickets))
     |> assign(:published_posts_count, Map.fetch!(data, :published_posts_count))
     |> assign(
       :newsletter_editions_count,
       Map.fetch!(data, :newsletter_editions_count)
     )
     |> assign(:draft_posts_count, Map.fetch!(data, :draft_posts_count))
     |> assign(
       :draft_newsletter_count,
       Map.fetch!(data, :draft_newsletter_count)
     )}
  end

  @impl true
  def handle_info(:load_dashboard_data, socket) do
    data =
      [
        {:latest_comments, fn -> Posts.get_latest_comments(5) end},
        {:events_with_tickets,
         fn -> Events.get_upcoming_events_with_ticket_tier_counts() end},
        {:pending_users, fn -> Accounts.get_pending_approval_users() end},
        {:revenue, fn -> calculate_all_revenue_stats() end},
        {:pending_refunds_summary,
         fn -> Bookings.pending_refunds_dashboard_summary() end},
        {:recent_newsletters,
         fn -> Newsletter.list_recent_sent_editions_with_stats(5) end},
        {:application_statistics, fn -> get_application_statistics() end},
        {:property_stats, fn -> get_property_stats() end},
        {:membership_stats, fn -> Accounts.get_membership_stats() end},
        {:membership_joins_ytd,
         fn -> Accounts.get_membership_joins_ytd_comparison() end},
        {:memberships_renewing_30_days, fn -> get_renewals_in_30_days() end},
        {:ytd_revenue_pair, fn -> calculate_ytd_revenue() end},
        {:revenue_sparkline, fn -> get_last_7_days_revenue() end},
        {:newsletter_subscriber_stats,
         fn -> get_newsletter_subscriber_stats() end}
      ]
      |> async_stream_with_repo(fn {key, fun} -> {key, fun.()} end,
        timeout: :infinity,
        max_concurrency: 10
      )
      |> Enum.reduce(%{}, fn {:ok, {key, value}}, acc ->
        Map.put(acc, key, value)
      end)

    pending_users = Map.fetch!(data, :pending_users)

    {applications_this_month, applications_this_year, applications_last_month,
     applications_last_year, applications_month_change,
     applications_year_change} = Map.fetch!(data, :application_statistics)

    joins_ytd = Map.fetch!(data, :membership_joins_ytd)

    {ytd_revenue, ytd_revenue_label} = Map.fetch!(data, :ytd_revenue_pair)

    {newsletter_subscriber_count, newsletter_subscribers_this_month} =
      Map.fetch!(data, :newsletter_subscriber_stats)

    revenue = Map.fetch!(data, :revenue)
    events_with_tickets = Map.fetch!(data, :events_with_tickets)

    socket =
      socket
      |> assign(:loading_dashboard, false)
      |> assign(:latest_comments, Map.fetch!(data, :latest_comments))
      |> assign(:events_with_tickets, events_with_tickets)
      |> assign_dashboard_check_in_sessions(events_with_tickets)
      |> assign(:pending_users, pending_users)
      |> assign(:pending_reviews_count, length(pending_users))
      |> assign(:applications_this_month, applications_this_month)
      |> assign(:applications_this_year, applications_this_year)
      |> assign(:applications_last_month, applications_last_month)
      |> assign(:applications_last_year, applications_last_year)
      |> assign(:applications_month_change, applications_month_change)
      |> assign(:applications_year_change, applications_year_change)
      |> assign(:property_stats, Map.fetch!(data, :property_stats))
      |> assign(:revenue_sparkline, Map.fetch!(data, :revenue_sparkline))
      |> assign(:membership_stats, Map.fetch!(data, :membership_stats))
      |> assign(:membership_joins_current_ytd, joins_ytd.current_ytd_joins)
      |> assign(:membership_joins_prior_ytd, joins_ytd.prior_ytd_joins)
      |> assign(:membership_joins_prior_year_label, joins_ytd.prior_year_label)
      |> assign(
        :membership_joins_ytd_change_percent,
        joins_ytd.joins_ytd_change_percent
      )
      |> assign(
        :memberships_renewing_30_days,
        Map.fetch!(data, :memberships_renewing_30_days)
      )
      |> assign(:ytd_revenue, ytd_revenue)
      |> assign(:ytd_revenue_label, ytd_revenue_label)
      |> assign(:newsletter_subscriber_count, newsletter_subscriber_count)
      |> assign(
        :newsletter_subscribers_this_month,
        newsletter_subscribers_this_month
      )
      |> assign(
        :recent_newsletters_with_stats,
        Map.fetch!(data, :recent_newsletters)
      )
      |> assign(
        :pending_refunds_summary,
        Map.fetch!(data, :pending_refunds_summary)
      )
      |> then(fn s ->
        Enum.reduce(revenue, s, fn {k, v}, acc -> assign(acc, k, v) end)
      end)

    {:noreply, socket}
  end

  defp assign_dashboard_check_in_sessions(socket, events_with_tickets) do
    event_ids = Enum.map(events_with_tickets, & &1.event.id)

    assign(
      socket,
      :open_check_in_sessions,
      Scanning.get_open_check_in_sessions_by_event_id(event_ids)
    )
  end

  defp build_review_url(user_id) do
    # Build filter parameters for pending_approval state
    # Format matches: filters[0][field]=state&filters[0][op]=in&filters[0][value][]=pending_approval
    params = %{
      "filters" => %{
        "0" => %{
          "field" => "state",
          "op" => "in",
          "value" => ["pending_approval"]
        }
      },
      "search" => ""
    }

    ~p"/admin/users/#{user_id}/review?#{params}"
  end

  defp get_published_posts_count do
    alias Ysc.Repo
    import Ecto.Query

    Repo.one(
      from p in Ysc.Posts.Post,
        where: not is_nil(p.published_on),
        select: count()
    )
  end

  defp get_newsletter_editions_count do
    alias Ysc.Repo
    import Ecto.Query
    Repo.one(from e in Ysc.Newsletter.Edition, select: count())
  end

  defp get_application_statistics do
    alias Ysc.Repo
    import Ecto.Query

    now = DateTime.utc_now()

    # Start of current month
    month_start = %DateTime{
      now
      | day: 1,
        hour: 0,
        minute: 0,
        second: 0,
        microsecond: {0, 0}
    }

    # Start of current year
    year_start = %DateTime{
      now
      | month: 1,
        day: 1,
        hour: 0,
        minute: 0,
        second: 0,
        microsecond: {0, 0}
    }

    # Count all new applications this month (all users created this month)
    applications_this_month =
      Repo.one(
        from u in Ysc.Accounts.User,
          where: u.inserted_at >= ^month_start,
          where: u.inserted_at < ^now,
          select: count(u.id)
      ) || 0

    # Count all new applications this year (all users created this year)
    applications_this_year =
      Repo.one(
        from u in Ysc.Accounts.User,
          where: u.inserted_at >= ^year_start,
          where: u.inserted_at < ^now,
          select: count(u.id)
      ) || 0

    # Start of last month
    last_month_start = Timex.shift(month_start, months: -1)
    last_month_end = month_start

    # Count applications last month
    applications_last_month =
      Repo.one(
        from u in Ysc.Accounts.User,
          where: u.inserted_at >= ^last_month_start,
          where: u.inserted_at < ^last_month_end,
          select: count(u.id)
      ) || 0

    # Start of last year (same month)
    last_year_month_start = Timex.shift(month_start, years: -1)

    last_year_month_end =
      Timex.shift(month_start, years: -1) |> Timex.shift(months: 1)

    # Count applications last year (same month)
    applications_last_year =
      Repo.one(
        from u in Ysc.Accounts.User,
          where: u.inserted_at >= ^last_year_month_start,
          where: u.inserted_at < ^last_year_month_end,
          select: count(u.id)
      ) || 0

    # Calculate percentage changes
    applications_month_change =
      if applications_last_month > 0 do
        round(
          (applications_this_month - applications_last_month) /
            applications_last_month * 100
        )
      else
        0
      end

    applications_year_change =
      if applications_last_year > 0 do
        round(
          (applications_this_year - applications_last_year) /
            applications_last_year * 100
        )
      else
        0
      end

    {applications_this_month, applications_this_year, applications_last_month,
     applications_last_year, applications_month_change,
     applications_year_change}
  end

  defp hours_waiting(user) do
    if user.registration_form && user.registration_form.completed do
      DateTime.diff(DateTime.utc_now(), user.registration_form.completed, :hour)
    else
      nil
    end
  end

  defp get_status_pillar_color(user) do
    case hours_waiting(user) do
      nil -> "bg-zinc-400"
      h when h < 24 -> "bg-emerald-500"
      h when h <= 48 -> "bg-amber-500"
      _ -> "bg-rose-500"
    end
  end

  defp get_application_card_classes(user) do
    case hours_waiting(user) do
      nil -> "bg-zinc-50/50 border-zinc-100"
      h when h > 48 -> "bg-white border-zinc-100 border-l-4 border-l-rose-500"
      _ -> "bg-white border-zinc-100"
    end
  end

  defp get_time_waiting_text(user) do
    case hours_waiting(user) do
      nil -> "Submission date not available"
      0 -> "just now"
      1 -> "1 hour ago"
      h when h < 24 -> "#{h} hours ago"
      h when h < 48 -> "#{div(h, 24)} day ago"
      h -> "#{div(h, 24)} days ago"
    end
  end

  defp get_status_badge_type(user) do
    case hours_waiting(user) do
      nil -> "dark"
      h when h < 24 -> "green"
      h when h <= 48 -> "yellow"
      _ -> "red"
    end
  end

  defp get_status_badge_text(user) do
    case hours_waiting(user) do
      nil -> "Review"
      h when h < 24 -> "New"
      h when h <= 48 -> "Pending"
      _ -> "Overdue"
    end
  end

  defp get_review_button_text(user) do
    case hours_waiting(user) do
      h when is_integer(h) and h > 48 -> "Review Now"
      _ -> "Review"
    end
  end

  defp get_membership_type_display(user) do
    if user.registration_form && user.registration_form.membership_type do
      case user.registration_form.membership_type do
        :family -> "Family"
        :single -> "Single"
        _ -> "N/A"
      end
    else
      "N/A"
    end
  end

  defp membership_joins_ytd_change_class(n) when is_integer(n) and n > 0,
    do: "text-emerald-600"

  defp membership_joins_ytd_change_class(0), do: "text-zinc-600"
  defp membership_joins_ytd_change_class(_), do: "text-rose-600"

  defp get_revenue_change_color_class(direction) do
    case direction do
      :up -> "text-emerald-600"
      :down -> "text-orange-600"
      :stable -> "text-zinc-600"
      _ -> "text-zinc-600"
    end
  end

  defp get_revenue_change_icon(direction) do
    case direction do
      :up -> "hero-arrow-trending-up"
      :down -> "hero-arrow-trending-down"
      :stable -> "hero-minus"
      _ -> "hero-minus"
    end
  end

  defp calculate_progress_percentage(tier) do
    if tier.quantity && tier.quantity > 0 do
      min(100, round(tier.sold_tickets_count / tier.quantity * 100))
    else
      0
    end
  end

  defp calculate_all_revenue_stats do
    alias Ysc.Repo
    import Ecto.Query

    now = DateTime.utc_now()

    month_start = %DateTime{
      now
      | day: 1,
        hour: 0,
        minute: 0,
        second: 0,
        microsecond: {0, 0}
    }

    prev_month_start = Timex.shift(month_start, months: -1)
    last_year_month_start = Timex.shift(month_start, years: -1)

    last_year_month_end =
      Timex.shift(month_start, years: -1) |> Timex.shift(months: 1)

    revenue_account_names = [
      "membership_revenue",
      "event_revenue",
      "tahoe_booking_revenue",
      "clear_lake_booking_revenue",
      "donation_revenue"
    ]

    accounts =
      from(a in Ysc.Ledgers.LedgerAccount,
        where: a.name in ^revenue_account_names
      )
      |> Repo.all()
      |> Map.new(&{&1.name, &1})

    bookings_account_ids =
      [
        accounts["tahoe_booking_revenue"],
        accounts["clear_lake_booking_revenue"]
      ]
      |> Enum.filter(&(&1 != nil))
      |> Enum.map(& &1.id)

    tahoe_account_id =
      if accounts["tahoe_booking_revenue"],
        do: accounts["tahoe_booking_revenue"].id,
        else: nil

    clear_lake_account_id =
      if accounts["clear_lake_booking_revenue"],
        do: accounts["clear_lake_booking_revenue"].id,
        else: nil

    events_account_id =
      if accounts["event_revenue"], do: accounts["event_revenue"].id, else: nil

    membership_account_id =
      if accounts["membership_revenue"],
        do: accounts["membership_revenue"].id,
        else: nil

    all_revenue_account_ids = Map.values(accounts) |> Enum.map(& &1.id)

    all_entries =
      from(e in Ysc.Ledgers.LedgerEntry,
        where: e.account_id in ^all_revenue_account_ids,
        where:
          (e.inserted_at >= ^month_start and e.inserted_at < ^now) or
            (e.inserted_at >= ^prev_month_start and e.inserted_at < ^month_start) or
            (e.inserted_at >= ^last_year_month_start and
               e.inserted_at < ^last_year_month_end),
        select: %{
          account_id: e.account_id,
          amount: fragment("ABS((?.amount).amount)", e),
          debit_credit: e.debit_credit,
          inserted_at: e.inserted_at
        }
      )
      |> Repo.all()

    revenue_data =
      Enum.reduce(
        all_entries,
        %{current: %{}, prev: %{}, last_year: %{}},
        fn entry, acc ->
          account_id = entry.account_id
          amount = entry.amount || Decimal.new(0)

          debit_credit =
            case entry.debit_credit do
              atom when is_atom(atom) -> to_string(atom)
              str when is_binary(str) -> str
              _ -> "debit"
            end

          signed_amount =
            if debit_credit == "credit",
              do: amount,
              else: Decimal.negate(amount)

          inserted_at = entry.inserted_at

          acc =
            if DateTime.compare(inserted_at, month_start) != :lt and
                 DateTime.compare(inserted_at, now) == :lt do
              update_revenue_period(acc, :current, account_id, signed_amount)
            else
              acc
            end

          acc =
            if DateTime.compare(inserted_at, prev_month_start) != :lt and
                 DateTime.compare(inserted_at, month_start) == :lt do
              update_revenue_period(acc, :prev, account_id, signed_amount)
            else
              acc
            end

          if DateTime.compare(inserted_at, last_year_month_start) != :lt and
               DateTime.compare(inserted_at, last_year_month_end) == :lt do
            update_revenue_period(acc, :last_year, account_id, signed_amount)
          else
            acc
          end
        end
      )

    current_total = sum_revenue_map(revenue_data.current)
    prev_total = sum_revenue_map(revenue_data.prev)
    last_year_total = sum_revenue_map(revenue_data.last_year)

    current_revenue = Money.new(current_total, :USD)
    prev_revenue = Money.new(prev_total, :USD)
    last_year_revenue = Money.new(last_year_total, :USD)

    {bookings_revenue, events_revenue, membership_revenue} =
      revenue_three_way_totals(
        revenue_data.current,
        bookings_account_ids,
        events_account_id,
        membership_account_id
      )

    {prev_bookings, prev_events, prev_membership} =
      revenue_three_way_totals(
        revenue_data.prev,
        bookings_account_ids,
        events_account_id,
        membership_account_id
      )

    {ly_bookings, ly_events, ly_membership} =
      revenue_three_way_totals(
        revenue_data.last_year,
        bookings_account_ids,
        events_account_id,
        membership_account_id
      )

    {bookings_percent, events_percent, membership_percent} =
      mix_three_percentages(
        bookings_revenue,
        events_revenue,
        membership_revenue
      )

    {prev_b_pct, prev_e_pct, prev_m_pct} =
      mix_three_percentages(prev_bookings, prev_events, prev_membership)

    {ly_b_pct, ly_e_pct, ly_m_pct} =
      mix_three_percentages(ly_bookings, ly_events, ly_membership)

    revenue_tahoe =
      decimal_to_money(
        Map.get(revenue_data.current, tahoe_account_id, Decimal.new(0))
      )

    revenue_clear_lake =
      decimal_to_money(
        Map.get(revenue_data.current, clear_lake_account_id, Decimal.new(0))
      )

    cabin_sum =
      Decimal.add(
        Map.get(revenue_data.current, tahoe_account_id, Decimal.new(0)),
        Map.get(revenue_data.current, clear_lake_account_id, Decimal.new(0))
      )

    {cabin_tahoe_pct, cabin_clear_pct} =
      if Decimal.gt?(cabin_sum, Decimal.new(0)) do
        t = Map.get(revenue_data.current, tahoe_account_id, Decimal.new(0))
        c = Map.get(revenue_data.current, clear_lake_account_id, Decimal.new(0))

        {
          round(Decimal.to_float(Decimal.div(t, cabin_sum)) * 100),
          round(Decimal.to_float(Decimal.div(c, cabin_sum)) * 100)
        }
      else
        {0, 0}
      end

    {revenue_change_text, revenue_change_direction} =
      month_over_month_change(current_revenue, prev_revenue, prev_month_start)

    {revenue_yoy_change_text, revenue_yoy_change_direction} =
      year_over_year_change(
        current_revenue,
        last_year_revenue,
        last_year_month_start
      )

    current_period_label =
      month_start
      |> DateTime.shift_zone!("America/Los_Angeles")
      |> Timex.format!("{Mshort} {YYYY}")

    comparison_month_year_pretty =
      last_year_month_start
      |> DateTime.shift_zone!("America/Los_Angeles")
      |> Timex.format!("{Mshort} {YYYY}")

    %{
      current_month_revenue: current_revenue,
      revenue_change_text: revenue_change_text,
      revenue_change_direction: revenue_change_direction,
      revenue_yoy_change_text: revenue_yoy_change_text,
      revenue_yoy_change_direction: revenue_yoy_change_direction,
      last_month_revenue: prev_revenue,
      last_year_month_revenue: last_year_revenue,
      revenue_bookings: bookings_revenue,
      revenue_events: events_revenue,
      revenue_membership: membership_revenue,
      revenue_mix_bookings_percent: bookings_percent,
      revenue_mix_events_percent: events_percent,
      revenue_mix_membership_percent: membership_percent,
      prev_revenue_bookings: prev_bookings,
      prev_revenue_events: prev_events,
      prev_revenue_membership: prev_membership,
      prev_revenue_mix_bookings_percent: prev_b_pct,
      prev_revenue_mix_events_percent: prev_e_pct,
      prev_revenue_mix_membership_percent: prev_m_pct,
      last_year_revenue_bookings: ly_bookings,
      last_year_revenue_events: ly_events,
      last_year_revenue_membership: ly_membership,
      last_year_revenue_mix_bookings_percent: ly_b_pct,
      last_year_revenue_mix_events_percent: ly_e_pct,
      last_year_revenue_mix_membership_percent: ly_m_pct,
      revenue_tahoe_bookings: revenue_tahoe,
      revenue_clear_lake_bookings: revenue_clear_lake,
      cabin_tahoe_percent_of_bookings: cabin_tahoe_pct,
      cabin_clear_lake_percent_of_bookings: cabin_clear_pct,
      current_period_label: current_period_label,
      comparison_month_year_pretty: comparison_month_year_pretty
    }
  end

  defp update_revenue_period(acc, period_key, account_id, signed_amount) do
    key = Map.get(acc, period_key) || %{}

    Map.put(
      acc,
      period_key,
      Map.update(key, account_id, signed_amount, fn existing ->
        Decimal.add(existing, signed_amount)
      end)
    )
  end

  defp sum_revenue_map(nil), do: Decimal.new(0)

  defp sum_revenue_map(map) do
    map
    |> Map.values()
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  defp decimal_to_money(decimal) do
    Money.new(decimal, :USD)
  end

  defp revenue_three_way_totals(
         revenue_map,
         bookings_account_ids,
         events_account_id,
         membership_account_id
       ) do
    bookings_dec =
      Enum.reduce(bookings_account_ids, Decimal.new(0), fn id, acc ->
        Decimal.add(acc, Map.get(revenue_map, id, Decimal.new(0)))
      end)

    events_dec =
      if events_account_id do
        Map.get(revenue_map, events_account_id, Decimal.new(0))
      else
        Decimal.new(0)
      end

    membership_dec =
      if membership_account_id do
        Map.get(revenue_map, membership_account_id, Decimal.new(0))
      else
        Decimal.new(0)
      end

    {
      Money.new(bookings_dec, :USD),
      Money.new(events_dec, :USD),
      Money.new(membership_dec, :USD)
    }
  end

  defp mix_three_percentages(bookings_m, events_m, membership_m) do
    {:ok, sub} = Money.add(bookings_m, events_m)
    {:ok, total} = Money.add(sub, membership_m)

    if Decimal.gt?(total.amount, Decimal.new(0)) do
      tf = Decimal.to_float(total.amount)

      bookings_percent =
        round(Decimal.to_float(bookings_m.amount) / tf * 100)

      events_percent =
        round(Decimal.to_float(events_m.amount) / tf * 100)

      membership_percent =
        round(Decimal.to_float(membership_m.amount) / tf * 100)

      {bookings_percent, events_percent, membership_percent}
    else
      {0, 0, 0}
    end
  end

  defp month_over_month_change(current_revenue, prev_revenue, prev_month_start) do
    if Decimal.gt?(prev_revenue.amount, Decimal.new(0)) do
      current_amount = Decimal.to_float(current_revenue.amount)
      prev_amount = Decimal.to_float(prev_revenue.amount)

      change_percent =
        ((current_amount - prev_amount) / prev_amount * 100) |> round()

      month_name =
        prev_month_start
        |> DateTime.shift_zone!("America/Los_Angeles")
        |> Timex.format!("{Mshort}")

      {text, direction} =
        cond do
          change_percent > 0 ->
            {"+#{change_percent}% vs #{month_name}", :up}

          change_percent < 0 ->
            {"#{change_percent}% vs #{month_name}", :down}

          true ->
            {"0% vs #{month_name}", :stable}
        end

      {text, direction}
    else
      {"First month", :stable}
    end
  end

  defp year_over_year_change(
         current_revenue,
         last_year_revenue,
         last_year_month_start
       ) do
    if Decimal.gt?(last_year_revenue.amount, Decimal.new(0)) do
      current_amount = Decimal.to_float(current_revenue.amount)
      ly_amount = Decimal.to_float(last_year_revenue.amount)

      change_percent =
        ((current_amount - ly_amount) / ly_amount * 100) |> round()

      label =
        last_year_month_start
        |> DateTime.shift_zone!("America/Los_Angeles")
        |> Timex.format!("{Mshort} {YYYY}")

      {text, direction} =
        cond do
          change_percent > 0 ->
            {"+#{change_percent}% vs #{label}", :up}

          change_percent < 0 ->
            {"#{change_percent}% vs #{label}", :down}

          true ->
            {"0% vs #{label}", :stable}
        end

      {text, direction}
    else
      {"No prior-year data", :stable}
    end
  end

  defp format_money(money) do
    Money.to_string!(money, symbol: true, separator: ",", delimiter: ".")
  end

  defp format_newsletter_stat(count, sent_count, label)
       when is_integer(sent_count) and sent_count > 0 and is_integer(count) do
    pct = round(count / sent_count * 100)
    "#{pct}% #{label} (#{count})"
  end

  defp format_newsletter_stat(count, _sent_count, label),
    do: "#{count} #{label}"

  defp get_property_stats do
    alias Ysc.Repo
    import Ecto.Query

    today = pst_today()
    checkout_time = ~T[11:00:00]
    now_pst = DateTime.now!("America/Los_Angeles")
    checkout_cutoff = DateTime.new!(today, checkout_time, "America/Los_Angeles")
    two_weeks_out = Date.add(today, 14)

    staying_bookings =
      Repo.all(
        from b in Bookings.Booking,
          where: b.status == :complete,
          where: b.checkin_date <= ^today,
          where: b.checkout_date >= ^today,
          select: %{property: b.property, checkout_date: b.checkout_date}
      )
      |> Enum.filter(fn b ->
        if Date.compare(b.checkout_date, today) == :eq do
          DateTime.compare(now_pst, checkout_cutoff) == :lt
        else
          true
        end
      end)

    checkins_today =
      Repo.all(
        from b in Bookings.Booking,
          where: b.status == :complete,
          where: b.checkin_date == ^today,
          select: %{property: b.property}
      )

    checkouts_today =
      Repo.all(
        from b in Bookings.Booking,
          where: b.status == :complete,
          where: b.checkout_date == ^today,
          select: %{property: b.property}
      )

    upcoming =
      Repo.all(
        from b in Bookings.Booking,
          where: b.status == :complete,
          where:
            fragment(
              "(? <= ? AND ? >= ?)",
              b.checkin_date,
              ^two_weeks_out,
              b.checkout_date,
              ^today
            ),
          select: %{property: b.property, guests_count: b.guests_count}
      )

    build_stats = fn property ->
      prop_upcoming = Enum.filter(upcoming, &(&1.property == property))

      %{
        staying: Enum.count(staying_bookings, &(&1.property == property)),
        checkins_today: Enum.count(checkins_today, &(&1.property == property)),
        checkouts_today:
          Enum.count(checkouts_today, &(&1.property == property)),
        upcoming_bookings: length(prop_upcoming),
        upcoming_guests:
          Enum.sum(Enum.map(prop_upcoming, &(&1.guests_count || 0)))
      }
    end

    %{
      tahoe: build_stats.(:tahoe),
      clear_lake: build_stats.(:clear_lake)
    }
  end

  @impl true
  def handle_event("navigate-to-review", %{"user-id" => user_id}, socket) do
    {:noreply, push_navigate(socket, to: build_review_url(user_id))}
  end

  defp pst_today, do: DateTime.now!("America/Los_Angeles") |> DateTime.to_date()

  defp get_renewals_in_30_days do
    alias Ysc.Repo
    import Ecto.Query

    now = DateTime.utc_now()
    in_30_days = DateTime.add(now, 30, :day)

    Repo.one(
      from s in Ysc.Subscriptions.Subscription,
        where: s.stripe_status in ["active", "trialing"],
        where: not is_nil(s.current_period_end),
        where: s.current_period_end >= ^now,
        where: s.current_period_end <= ^in_30_days,
        select: count()
    ) || 0
  end

  defp calculate_ytd_revenue do
    alias Ysc.Repo
    import Ecto.Query

    now = DateTime.utc_now()

    year_start = %DateTime{
      now
      | month: 1,
        day: 1,
        hour: 0,
        minute: 0,
        second: 0,
        microsecond: {0, 0}
    }

    revenue_account_names = [
      "membership_revenue",
      "event_revenue",
      "tahoe_booking_revenue",
      "clear_lake_booking_revenue",
      "donation_revenue"
    ]

    account_ids =
      from(a in Ysc.Ledgers.LedgerAccount,
        where: a.name in ^revenue_account_names,
        select: a.id
      )
      |> Repo.all()

    entries =
      Repo.all(
        from e in Ysc.Ledgers.LedgerEntry,
          where: e.account_id in ^account_ids,
          where: e.inserted_at >= ^year_start,
          where: e.inserted_at < ^now,
          select: %{
            amount: fragment("ABS((?.amount).amount)", e),
            debit_credit: e.debit_credit
          }
      )

    total =
      Enum.reduce(entries, Decimal.new(0), fn entry, acc ->
        debit_credit =
          case entry.debit_credit do
            atom when is_atom(atom) -> to_string(atom)
            str when is_binary(str) -> str
            _ -> "debit"
          end

        amount = entry.amount || Decimal.new(0)

        signed =
          if debit_credit == "credit", do: amount, else: Decimal.negate(amount)

        Decimal.add(acc, signed)
      end)

    label =
      year_start
      |> DateTime.shift_zone!("America/Los_Angeles")
      |> Timex.format!("Jan–{Mshort} {YYYY}")

    {Money.new(total, :USD), label}
  end

  defp get_newsletter_subscriber_stats do
    alias Ysc.Repo
    import Ecto.Query

    now = DateTime.utc_now()

    month_start = %DateTime{
      now
      | day: 1,
        hour: 0,
        minute: 0,
        second: 0,
        microsecond: {0, 0}
    }

    total =
      Repo.one(
        from s in Ysc.Newsletter.Subscriber,
          where: s.subscribed == true,
          select: count()
      ) || 0

    new_this_month =
      Repo.one(
        from s in Ysc.Newsletter.Subscriber,
          where: s.subscribed == true,
          where: not is_nil(s.subscribed_at),
          where: s.subscribed_at >= ^month_start,
          select: count()
      ) || 0

    {total, new_this_month}
  end

  defp get_draft_posts_count do
    alias Ysc.Repo
    import Ecto.Query

    Repo.one(
      from p in Ysc.Posts.Post,
        where: p.state == "draft",
        select: count()
    ) || 0
  end

  defp get_draft_newsletter_count do
    alias Ysc.Repo
    import Ecto.Query

    Repo.one(
      from e in Ysc.Newsletter.Edition,
        where: e.status in [:draft, :scheduled],
        select: count()
    ) || 0
  end

  defp get_last_7_days_revenue do
    alias Ysc.Repo
    import Ecto.Query

    today_utc = DateTime.utc_now() |> DateTime.to_date()
    days = Enum.map(6..0//-1, &Date.add(today_utc, -&1))
    oldest_day = List.first(days)
    start_dt = DateTime.new!(oldest_day, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.utc_now()

    revenue_account_names = [
      "membership_revenue",
      "event_revenue",
      "tahoe_booking_revenue",
      "clear_lake_booking_revenue",
      "donation_revenue"
    ]

    account_ids =
      from(a in Ysc.Ledgers.LedgerAccount,
        where: a.name in ^revenue_account_names,
        select: a.id
      )
      |> Repo.all()

    entries =
      Repo.all(
        from e in Ysc.Ledgers.LedgerEntry,
          where: e.account_id in ^account_ids,
          where: e.inserted_at >= ^start_dt,
          where: e.inserted_at < ^end_dt,
          select: %{
            amount: fragment("ABS((?.amount).amount)", e),
            debit_credit: e.debit_credit,
            inserted_at: e.inserted_at
          }
      )

    by_date = Enum.group_by(entries, &DateTime.to_date(&1.inserted_at))

    Enum.map(days, fn day ->
      Enum.reduce(Map.get(by_date, day, []), Decimal.new(0), fn entry, acc ->
        dc =
          case entry.debit_credit do
            atom when is_atom(atom) -> to_string(atom)
            str when is_binary(str) -> str
            _ -> "debit"
          end

        amount = entry.amount || Decimal.new(0)
        signed = if dc == "credit", do: amount, else: Decimal.negate(amount)
        Decimal.add(acc, signed)
      end)
    end)
  end

  defp sparkline_line_points(values) when is_list(values) and values != [] do
    w = 80.0
    h = 24.0

    floats =
      Enum.map(values, fn v ->
        f = Decimal.to_float(v)
        max(f, 0.0)
      end)

    max_v = max(Enum.max(floats, fn -> 0.0 end), 0.01)
    count = length(floats)

    floats
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {v, i} ->
      x = if count <= 1, do: 0.0, else: i * w / (count - 1)
      y = (1.0 - v / max_v) * h
      "#{Float.round(x, 1)},#{Float.round(y, 1)}"
    end)
  end

  defp sparkline_line_points(_), do: "0,24 80,24"

  defp sparkline_fill_points(values) when is_list(values) and values != [] do
    "#{sparkline_line_points(values)} 80,24 0,24"
  end

  defp sparkline_fill_points(_), do: ""

  defp format_admin_datetime(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> Timex.format!("{YYYY}-{0M}-{0D} {h12}:{m} {AM}")
  end

  defp format_admin_datetime(_), do: "—"

  defp event_start_pst_label(%{start_date: %DateTime{} = dt} = event) do
    local = DateTime.shift_zone!(dt, "America/Los_Angeles")
    date_part = Timex.format!(local, "{WDshort} {Mshort} {D}")

    if event.start_time do
      t = Calendar.strftime(event.start_time, "%-I:%M %p")
      "#{date_part} · #{t}"
    else
      date_part
    end
  end

  defp event_start_pst_label(_), do: "—"

  defp tier_line_revenue(tier) do
    n = Map.get(tier, :sold_tickets_count) || 0

    if n > 0 && tier.price do
      case Money.mult(tier.price, n) do
        {:ok, m} -> m
        _ -> Money.new(0, :USD)
      end
    else
      Money.new(0, :USD)
    end
  end

  defp pending_refunds_bookings_path(summary) do
    p = refund_property_param(summary)
    "/admin/bookings?property=#{p}&section=pending_refunds"
  end

  defp refund_property_param(%{tahoe: t}) when t > 0, do: "tahoe"
  defp refund_property_param(%{clear_lake: c}) when c > 0, do: "clear_lake"
  defp refund_property_param(_), do: "tahoe"

  defp applications_queue_url do
    "/admin/users?filters[0][_persistent_id]=0&filters[0][field]=state&filters[0][op]=in&filters[0][value][]=pending_approval"
  end
end
