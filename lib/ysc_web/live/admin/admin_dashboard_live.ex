defmodule YscWeb.AdminDashboardLive do
  use Phoenix.LiveView,
    layout: {YscWeb.Layouts, :admin_app}

  import YscWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  alias Ysc.{Posts, Events, Accounts, Bookings, BuildVersion}

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      email={@current_user.email}
      first_name={@current_user.first_name}
      last_name={@current_user.last_name}
      user_id={@current_user.id}
      most_connected_country={@current_user.most_connected_country}
    >
      <div class="bg-zinc-50/80 min-h-screen -mx-4 lg:-mx-10 px-4 lg:px-10 py-8">
        <!-- Command Center Header -->
        <div class="flex flex-col md:flex-row md:items-center justify-between gap-4 py-8 border-b border-zinc-100 mb-8">
          <div>
            <h1 class="text-3xl font-black text-zinc-900 tracking-tight">
              Overview
            </h1>
            <p class="text-xs text-zinc-500 font-medium mt-1 flex items-center gap-2">
              <span class={[
                "w-2 h-2 rounded-full",
                if(@loading_dashboard,
                  do: "bg-amber-500 animate-pulse",
                  else: "bg-emerald-500"
                )
              ]}>
              </span>
              <%= if @loading_dashboard do %>
                Loading dashboard...
              <% else %>
                Build: <%= @build_version %>
              <% end %>
            </p>
          </div>
          <div class="w-full md:w-96">
            <.live_component module={YscWeb.AdminSearchComponent} id="admin-search" />
          </div>
        </div>
        <!-- Tiered Stats Row -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-12">
          <!-- Applications Card -->
          <div class="bg-white p-6 rounded-lg shadow-sm border border-zinc-100 flex flex-col justify-between">
            <div>
              <p class="text-[10px] font-black text-zinc-400 uppercase tracking-[0.2em] mb-3">
                Applications
              </p>
              <div class="flex items-baseline gap-2">
                <p class="text-3xl font-black text-zinc-900">
                  <%= @pending_reviews_count %>
                </p>
                <span class="text-xs font-bold text-amber-600 bg-amber-50 px-2 py-0.5 rounded italic">
                  Pending
                </span>
              </div>
            </div>
            <div class="mt-6 pt-4 border-t border-zinc-50 grid grid-cols-2 gap-4">
              <div>
                <p class="text-[9px] font-bold text-zinc-400 uppercase">
                  This Month
                </p>
                <p class="text-sm font-black text-zinc-700">
                  <%= @applications_this_month %>
                </p>
                <p class="text-[9px] text-zinc-500 mt-0.5">
                  <%= if @applications_last_month > 0 do %>
                    <span class={
                      if @applications_month_change >= 0,
                        do: "text-emerald-600",
                        else: "text-rose-600"
                    }>
                      <%= if @applications_month_change >= 0, do: "+", else: "" %><%= @applications_month_change %>%
                    </span>
                  <% else %>
                    <span class="text-zinc-400">—</span>
                  <% end %>
                </p>
              </div>
              <div>
                <p class="text-[9px] font-bold text-zinc-400 uppercase">YTD</p>
                <p class="text-sm font-black text-zinc-700">
                  <%= @applications_this_year %>
                </p>
                <p class="text-[9px] text-zinc-500 mt-0.5">
                  <%= if @applications_last_year > 0 do %>
                    <span class={
                      if @applications_year_change >= 0,
                        do: "text-emerald-600",
                        else: "text-rose-600"
                    }>
                      <%= if @applications_year_change >= 0, do: "+", else: "" %><%= @applications_year_change %>%
                    </span>
                  <% else %>
                    <span class="text-zinc-400">—</span>
                  <% end %>
                </p>
              </div>
            </div>
          </div>
          <!-- Total Revenue Card -->
          <div class="bg-white p-6 rounded-lg shadow-sm border border-zinc-100 flex flex-col justify-between">
            <div>
              <p class="text-[10px] font-black text-zinc-400 uppercase tracking-[0.2em] mb-3">
                Total Revenue (<%= Timex.format!(DateTime.utc_now(), "{Mshort}") %>)
              </p>
              <div class="flex items-baseline gap-2">
                <p class="text-3xl font-black text-emerald-600">
                  <%= format_money(@current_month_revenue) %>
                </p>
                <span class={[
                  "text-[10px] font-bold flex items-center",
                  get_revenue_change_color_class(@revenue_change_direction)
                ]}>
                  <.icon
                    name={get_revenue_change_icon(@revenue_change_direction)}
                    class="w-3 h-3 mr-1"
                  />
                  <%= @revenue_change_text %>
                </span>
              </div>
            </div>
            <div class="mt-6 pt-4 border-t border-zinc-50 grid grid-cols-2 gap-4">
              <div>
                <p class="text-[9px] font-bold text-zinc-400 uppercase">
                  vs Last Month
                </p>
                <p class="text-sm font-bold text-zinc-500">
                  <%= format_money(@last_month_revenue) %>
                </p>
              </div>
              <div>
                <p class="text-[9px] font-bold text-zinc-400 uppercase">
                  vs <%= Timex.format!(DateTime.utc_now(), "{Mshort}") %> '23
                </p>
                <p class="text-sm font-bold text-zinc-500">
                  <%= format_money(@last_year_month_revenue) %>
                </p>
              </div>
            </div>
          </div>
          <!-- Revenue Mix Card -->
          <div class="bg-white p-6 rounded-lg shadow-sm border border-zinc-100 flex flex-col justify-between">
            <div>
              <p class="text-[10px] font-black text-zinc-400 uppercase tracking-[0.2em] mb-3">
                Revenue Mix
              </p>
              <div class="w-full bg-zinc-100 h-3 rounded-full overflow-hidden flex mb-2">
                <div
                  class="bg-blue-600 h-full"
                  style={"width: #{@revenue_mix_bookings_percent}%"}
                  title="Bookings"
                >
                </div>
                <div
                  class="bg-purple-500 h-full"
                  style={"width: #{@revenue_mix_events_percent}%"}
                  title="Events"
                >
                </div>
                <div
                  class="bg-emerald-500 h-full"
                  style={"width: #{@revenue_mix_membership_percent}%"}
                  title="Membership"
                >
                </div>
              </div>
            </div>
            <div class="mt-4 space-y-2">
              <div class="flex justify-between items-center">
                <span class="flex items-center text-[9px] font-bold text-zinc-500 uppercase">
                  <span class="w-2 h-2 rounded-full bg-blue-600 mr-2"></span>Bookings
                </span>
                <span class="text-sm font-black text-zinc-700">
                  <%= format_money(@revenue_bookings) %>
                </span>
              </div>
              <div class="flex justify-between items-center">
                <span class="flex items-center text-[9px] font-bold text-zinc-500 uppercase">
                  <span class="w-2 h-2 rounded-full bg-purple-500 mr-2"></span>Events
                </span>
                <span class="text-sm font-black text-zinc-700">
                  <%= format_money(@revenue_events) %>
                </span>
              </div>
              <div class="flex justify-between items-center">
                <span class="flex items-center text-[9px] font-bold text-zinc-500 uppercase">
                  <span class="w-2 h-2 rounded-full bg-emerald-500 mr-2"></span>Membership
                </span>
                <span class="text-sm font-black text-zinc-700">
                  <%= format_money(@revenue_membership) %>
                </span>
              </div>
            </div>
          </div>
          <!-- Active Now Card -->
          <div class="bg-white p-6 rounded-lg shadow-sm border border-zinc-100 flex flex-col justify-between">
            <div>
              <p class="text-[10px] font-black text-zinc-400 uppercase tracking-[0.2em] mb-3">
                Active Now
              </p>
              <p class="text-3xl font-black text-zinc-900">
                <%= @active_guests_count %>
              </p>
              <p class="text-xs text-zinc-500 mt-1 font-medium">
                Guests across properties
              </p>
            </div>
            <div class="mt-6 flex -space-x-2 overflow-hidden">
              <div :for={user <- @active_guests_sample} class="relative">
                <.user_avatar_image
                  email={user.email}
                  user_id={user.id}
                  country={user.most_connected_country}
                  class="inline-block h-6 w-6 rounded-full ring-2 ring-white"
                />
              </div>
              <div
                :if={@active_guests_count > length(@active_guests_sample)}
                class="flex h-6 w-6 items-center justify-center rounded-full bg-zinc-100 text-[8px] font-bold text-zinc-500 ring-2 ring-white"
              >
                +<%= @active_guests_count - length(@active_guests_sample) %>
              </div>
            </div>
          </div>
        </div>
        <!-- Priority Dashboard Layout -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8 pb-20">
          <section class="lg:col-span-2 space-y-6">
            <!-- Review Applications Section -->
            <div class="bg-white rounded shadow-sm border border-zinc-200 p-8">
              <div class="flex items-center justify-between mb-8 border-b border-zinc-50 pb-4">
                <div class="flex items-center gap-3">
                  <div class="w-10 h-10 bg-amber-100 rounded-lg flex items-center justify-center">
                    <.icon name="hero-users" class="w-6 h-6 text-amber-600" />
                  </div>
                  <h2 class="text-2xl font-black text-zinc-900 tracking-tight">
                    Review Applications
                  </h2>
                </div>
                <span
                  :if={@pending_reviews_count > 0}
                  class="px-3 py-1 bg-amber-50 text-amber-700 text-[10px] font-black rounded uppercase ring-1 ring-amber-200"
                >
                  <%= @pending_reviews_count %> PENDING
                </span>
              </div>

              <div
                :if={Enum.empty?(@pending_users)}
                class="text-center py-10 border-2 border-dashed border-zinc-100 rounded"
              >
                <.icon
                  name="hero-check-circle"
                  class="w-8 h-8 text-zinc-200 mx-auto mb-2"
                />
                <p class="text-sm text-zinc-400">No pending applications</p>
              </div>

              <div :if={not Enum.empty?(@pending_users)} class="space-y-4">
                <div
                  :for={user <- @pending_users}
                  class={[
                    "flex items-center gap-5 p-5 bg-white border border-zinc-100 rounded hover:shadow-xl hover:-translate-y-0.5 transition-all group relative overflow-hidden",
                    get_application_card_classes(user)
                  ]}
                >
                  <div class={[
                    "absolute left-0 top-0 bottom-0 w-1 group-hover:w-1.5 transition-all",
                    get_status_pillar_color(user)
                  ]}>
                  </div>

                  <div class="relative flex-shrink-0">
                    <.user_avatar_image
                      email={user.email}
                      user_id={user.id}
                      country={user.most_connected_country}
                      class="w-14 h-14 rounded object-cover ring-2 ring-zinc-50 shadow-sm"
                    />
                  </div>

                  <div class="flex-1 min-w-0">
                    <h4 class="font-bold text-zinc-900 truncate text-lg tracking-tight">
                      <%= "#{user.first_name} #{user.last_name}" %>
                    </h4>
                    <div class="flex items-center gap-3 mt-0.5">
                      <span class={get_status_badge_classes(user)}>
                        <%= get_status_badge_text(user) %>
                      </span>
                      <span class="text-xs text-zinc-400 italic font-medium">
                        <%= get_time_waiting_text(user) %>
                      </span>
                    </div>
                  </div>

                  <div class="flex items-center gap-6">
                    <div class="hidden sm:block text-right border-r border-zinc-100 pr-6">
                      <p class="text-[9px] font-black text-zinc-400 uppercase tracking-widest mb-0.5">
                        Plan Type
                      </p>
                      <p class="text-xs font-bold text-zinc-700">
                        <%= get_membership_type_display(user) %>
                      </p>
                    </div>
                    <.button
                      phx-click="navigate-to-review"
                      phx-value-user-id={user.id}
                    >
                      <%= get_review_button_text(user) %>
                    </.button>
                  </div>
                </div>
              </div>
            </div>
            <!-- Recent Discussions Section -->
            <div class="bg-white rounded shadow-sm border border-zinc-200 p-8">
              <h3 class="text-lg font-black text-zinc-900 tracking-tight mb-6">
                Recent Discussions
              </h3>
              <div
                :if={Enum.empty?(@latest_comments)}
                class="text-center py-10 border-2 border-dashed border-zinc-100 rounded"
              >
                <.icon
                  name="hero-chat-bubble-left-right"
                  class="w-8 h-8 text-zinc-200 mx-auto mb-2"
                />
                <p class="text-sm text-zinc-400">No new comments to moderate</p>
              </div>
              <ul :if={not Enum.empty?(@latest_comments)} class="space-y-4">
                <li
                  :for={comment <- @latest_comments}
                  class="border-b border-zinc-200 pb-4 last:border-0"
                >
                  <div class="flex justify-between items-start mb-2">
                    <div class="flex-1">
                      <.link
                        navigate={
                          ~p"/posts/#{comment.post.url_name || comment.post.id}"
                        }
                        class="text-sm font-semibold text-zinc-800 hover:text-blue-600"
                      >
                        <%= comment.post.title %>
                      </.link>
                      <p class="text-sm text-zinc-600 mt-1 line-clamp-2">
                        <%= comment.text %>
                      </p>
                    </div>
                  </div>
                  <div class="flex items-center justify-between text-xs text-zinc-500 mt-2">
                    <span>
                      By
                      <span class="font-medium text-zinc-700">
                        <%= "#{comment.author.first_name} #{comment.author.last_name}" %>
                      </span>
                    </span>
                    <span>
                      <%= Timex.format!(
                        comment.inserted_at,
                        "{YYYY}-{0M}-{0D} {h12}:{m} {AM}"
                      ) %>
                    </span>
                  </div>
                </li>
              </ul>
            </div>
          </section>
          <!-- Ticket Sales Sidebar -->
          <section class="lg:col-span-1">
            <div class="sticky top-24 bg-white rounded shadow-sm border border-zinc-200 p-8 h-fit">
              <div class="flex items-center justify-between mb-8 border-b border-zinc-50 pb-4">
                <h2 class="text-xl font-black text-zinc-900 tracking-tight">
                  Ticket Sales
                </h2>
                <.link
                  navigate={~p"/admin/events"}
                  class="text-[10px] font-black text-teal-600 underline"
                >
                  VIEW ALL
                </.link>
              </div>

              <div
                :if={Enum.empty?(@events_with_tickets)}
                class="text-center py-10 border-2 border-dashed border-zinc-100 rounded"
              >
                <.icon
                  name="hero-calendar"
                  class="w-8 h-8 text-zinc-200 mx-auto mb-2"
                />
                <p class="text-sm text-zinc-400">No upcoming events</p>
              </div>

              <div :if={not Enum.empty?(@events_with_tickets)} class="space-y-10">
                <div :for={
                  %{event: event, ticket_tiers: tiers} <- @events_with_tickets
                }>
                  <div class="flex justify-between items-start mb-4 group">
                    <.link
                      navigate={~p"/events/#{event.id}"}
                      class="text-sm font-bold text-zinc-900 leading-tight group-hover:text-blue-600 transition-colors flex-1"
                    >
                      <%= event.title %>
                    </.link>
                    <.icon
                      name="hero-arrow-top-right-on-square"
                      class="w-4 h-4 text-zinc-300 flex-shrink-0 ml-2"
                    />
                  </div>

                  <div :if={Enum.empty?(tiers)} class="text-xs text-zinc-500">
                    No ticket tiers configured
                  </div>

                  <div :if={not Enum.empty?(tiers)} class="space-y-4">
                    <div :for={tier <- tiers} class="space-y-1">
                      <div class="flex justify-between text-[10px] font-black text-zinc-400 uppercase tracking-widest">
                        <span><%= tier.name %></span>
                        <span class="text-zinc-900">
                          <%= tier.sold_tickets_count %> / <%= if tier.quantity,
                            do: tier.quantity,
                            else: "∞" %>
                        </span>
                      </div>
                      <div
                        :if={tier.sold_tickets_count > 0}
                        class="w-full bg-zinc-100 h-1.5 rounded-full overflow-hidden"
                      >
                        <div
                          class="bg-zinc-900 h-full rounded-full transition-all duration-1000"
                          style={"width: #{calculate_progress_percentage(tier)}%"}
                        >
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </section>
        </div>
      </div>
    </.side_menu>
    """
  end

  @impl true
  @spec mount(any(), any(), map()) :: {:ok, map()}
  def mount(_params, _session, socket) do
    build_version = get_build_version()

    # Initialize with placeholder values for fast initial render
    socket =
      socket
      |> assign(:active_page, :dashboard)
      |> assign(:build_version, build_version)
      |> assign(:page_title, "Dashboard")
      |> assign(:loading_dashboard, true)
      # Placeholder values - will be populated when connected
      |> assign(:latest_comments, [])
      |> assign(:events_with_tickets, [])
      |> assign(:pending_users, [])
      |> assign(:pending_reviews_count, 0)
      |> assign(:current_month_revenue, Money.new(:USD, 0))
      |> assign(:revenue_change_text, "—")
      |> assign(:revenue_change_direction, :neutral)
      |> assign(:last_month_revenue, Money.new(:USD, 0))
      |> assign(:last_year_month_revenue, Money.new(:USD, 0))
      |> assign(:next_event_date, nil)
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
      |> assign(:active_guests_count, 0)
      |> assign(:active_guests_sample, [])

    # Schedule data loading only when connected (stateful mount)
    if connected?(socket) do
      send(self(), :load_dashboard_data)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_dashboard_data, socket) do
    # Load all data in parallel where possible
    latest_comments = Posts.get_latest_comments(5)
    events_with_tickets = Events.get_upcoming_events_with_ticket_tier_counts()
    pending_users = Accounts.get_pending_approval_users()

    # Optimize revenue calculations by fetching accounts once and combining queries
    {current_revenue, revenue_change_text, revenue_change_direction,
     last_month_revenue, last_year_month_revenue, revenue_bookings,
     revenue_events, revenue_membership, revenue_mix_bookings_percent,
     revenue_mix_events_percent, revenue_mix_membership_percent} =
      calculate_all_revenue_stats()

    next_event_date = get_next_event_date(events_with_tickets)

    {applications_this_month, applications_this_year, applications_last_month,
     applications_last_year, applications_month_change,
     applications_year_change} =
      get_application_statistics()

    {active_guests_count, active_guests_sample} = get_active_guests()

    {:noreply,
     socket
     |> assign(:loading_dashboard, false)
     |> assign(:latest_comments, latest_comments)
     |> assign(:events_with_tickets, events_with_tickets)
     |> assign(:pending_users, pending_users)
     |> assign(:pending_reviews_count, length(pending_users))
     |> assign(:current_month_revenue, current_revenue)
     |> assign(:revenue_change_text, revenue_change_text)
     |> assign(:revenue_change_direction, revenue_change_direction)
     |> assign(:last_month_revenue, last_month_revenue)
     |> assign(:last_year_month_revenue, last_year_month_revenue)
     |> assign(:next_event_date, next_event_date)
     |> assign(:applications_this_month, applications_this_month)
     |> assign(:applications_this_year, applications_this_year)
     |> assign(:applications_last_month, applications_last_month)
     |> assign(:applications_last_year, applications_last_year)
     |> assign(:applications_month_change, applications_month_change)
     |> assign(:applications_year_change, applications_year_change)
     |> assign(:revenue_bookings, revenue_bookings)
     |> assign(:revenue_events, revenue_events)
     |> assign(:revenue_membership, revenue_membership)
     |> assign(:revenue_mix_bookings_percent, revenue_mix_bookings_percent)
     |> assign(:revenue_mix_events_percent, revenue_mix_events_percent)
     |> assign(:revenue_mix_membership_percent, revenue_mix_membership_percent)
     |> assign(:active_guests_count, active_guests_count)
     |> assign(:active_guests_sample, active_guests_sample)}
  end

  defp get_next_event_date(events_with_tickets) do
    events_with_tickets
    |> Enum.map(fn %{event: event} -> event.start_date end)
    |> Enum.filter(&(&1 != nil))
    |> Enum.sort()
    |> List.first()
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

  defp get_status_pillar_color(user) do
    if user.registration_form && user.registration_form.completed do
      submitted_at = user.registration_form.completed
      hours_ago = DateTime.diff(DateTime.utc_now(), submitted_at, :hour)

      cond do
        hours_ago < 24 -> "bg-emerald-500"
        hours_ago >= 24 && hours_ago <= 48 -> "bg-amber-500"
        hours_ago > 48 -> "bg-rose-500"
        true -> "bg-zinc-400"
      end
    else
      "bg-zinc-400"
    end
  end

  defp get_application_card_classes(user) do
    if user.registration_form && user.registration_form.completed do
      submitted_at = user.registration_form.completed
      hours_ago = DateTime.diff(DateTime.utc_now(), submitted_at, :hour)

      base_classes = "bg-white border-zinc-100"

      if hours_ago > 48 do
        "#{base_classes} border-l-4 border-l-rose-500"
      else
        base_classes
      end
    else
      "bg-zinc-50/50 border-zinc-100"
    end
  end

  defp get_time_waiting_text(user) do
    if user.registration_form && user.registration_form.completed do
      submitted_at = user.registration_form.completed
      hours_ago = DateTime.diff(DateTime.utc_now(), submitted_at, :hour)

      cond do
        hours_ago < 1 -> "just now"
        hours_ago == 1 -> "1 hour ago"
        hours_ago < 24 -> "#{hours_ago} hours ago"
        hours_ago < 48 -> "#{div(hours_ago, 24)} day ago"
        true -> "#{div(hours_ago, 24)} days ago"
      end
    else
      "Submission date not available"
    end
  end

  defp get_status_badge_classes(user) do
    if user.registration_form && user.registration_form.completed do
      submitted_at = user.registration_form.completed
      hours_ago = DateTime.diff(DateTime.utc_now(), submitted_at, :hour)

      cond do
        hours_ago < 24 ->
          "text-[9px] font-black text-emerald-600 bg-emerald-50 px-1.5 py-0.5 uppercase tracking-widest"

        hours_ago >= 24 && hours_ago <= 48 ->
          "text-[9px] font-black text-amber-600 bg-amber-50 px-1.5 py-0.5 uppercase tracking-widest"

        hours_ago > 48 ->
          "text-[9px] font-black text-rose-600 bg-rose-50 px-1.5 py-0.5 uppercase tracking-widest"

        true ->
          "text-[9px] font-black text-zinc-600 bg-zinc-50 px-1.5 py-0.5 uppercase tracking-widest"
      end
    else
      "text-[9px] font-black text-zinc-600 bg-zinc-50 px-1.5 py-0.5 uppercase tracking-widest"
    end
  end

  defp get_status_badge_text(user) do
    if user.registration_form && user.registration_form.completed do
      submitted_at = user.registration_form.completed
      hours_ago = DateTime.diff(DateTime.utc_now(), submitted_at, :hour)

      cond do
        hours_ago < 24 -> "New"
        hours_ago >= 24 && hours_ago <= 48 -> "Pending"
        hours_ago > 48 -> "Overdue"
        true -> "Review"
      end
    else
      "Review"
    end
  end

  defp get_review_button_text(user) do
    if user.registration_form && user.registration_form.completed do
      submitted_at = user.registration_form.completed
      hours_ago = DateTime.diff(DateTime.utc_now(), submitted_at, :hour)

      if hours_ago > 48 do
        "Review Now"
      else
        "Review"
      end
    else
      "Review"
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
      # For unlimited tiers, show 0% or a small visual indicator
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

    # Get previous month for comparison
    prev_month_start = Timex.shift(month_start, months: -1)

    # Get same month last year
    last_year_month_start = Timex.shift(month_start, years: -1)

    last_year_month_end =
      Timex.shift(month_start, years: -1) |> Timex.shift(months: 1)

    # Fetch all revenue accounts in a single query
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

    # Build account ID lists for bookings (combined) and individual accounts
    bookings_account_ids =
      [
        accounts["tahoe_booking_revenue"],
        accounts["clear_lake_booking_revenue"]
      ]
      |> Enum.filter(&(&1 != nil))
      |> Enum.map(& &1.id)

    events_account_id =
      if accounts["event_revenue"], do: accounts["event_revenue"].id, else: nil

    membership_account_id =
      if accounts["membership_revenue"],
        do: accounts["membership_revenue"].id,
        else: nil

    all_revenue_account_ids = Map.values(accounts) |> Enum.map(& &1.id)

    # Fetch all entries for all time periods in a single query, then aggregate in Elixir
    # This is more efficient than multiple queries and avoids complex SQL fragments
    all_entries =
      from(e in Ysc.Ledgers.LedgerEntry,
        where: e.account_id in ^all_revenue_account_ids,
        where: e.debit_credit == "credit",
        where:
          (e.inserted_at >= ^month_start and e.inserted_at < ^now) or
            (e.inserted_at >= ^prev_month_start and e.inserted_at < ^month_start) or
            (e.inserted_at >= ^last_year_month_start and
               e.inserted_at < ^last_year_month_end),
        select: %{
          account_id: e.account_id,
          amount: fragment("ABS((?.amount).amount)", e),
          inserted_at: e.inserted_at
        }
      )
      |> Repo.all()

    # Aggregate by account and time period in Elixir
    revenue_data =
      Enum.reduce(
        all_entries,
        %{current: %{}, prev: %{}, last_year: %{}},
        fn entry, acc ->
          account_id = entry.account_id
          amount = entry.amount || Decimal.new(0)
          inserted_at = entry.inserted_at

          acc =
            if DateTime.compare(inserted_at, month_start) != :lt and
                 DateTime.compare(inserted_at, now) == :lt do
              %{
                acc
                | current:
                    Map.update(
                      acc.current || %{},
                      account_id,
                      amount,
                      fn existing ->
                        Decimal.add(existing, amount)
                      end
                    )
              }
            else
              acc
            end

          acc =
            if DateTime.compare(inserted_at, prev_month_start) != :lt and
                 DateTime.compare(inserted_at, month_start) == :lt do
              %{
                acc
                | prev:
                    Map.update(
                      acc.prev || %{},
                      account_id,
                      amount,
                      fn existing ->
                        Decimal.add(existing, amount)
                      end
                    )
              }
            else
              acc
            end

          if DateTime.compare(inserted_at, last_year_month_start) != :lt and
               DateTime.compare(inserted_at, last_year_month_end) == :lt do
            %{
              acc
              | last_year:
                  Map.update(
                    acc.last_year || %{},
                    account_id,
                    amount,
                    fn existing ->
                      Decimal.add(existing, amount)
                    end
                  )
            }
          else
            acc
          end
        end
      )

    # Calculate totals for each period
    current_total =
      revenue_data.current
      |> Map.values()
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    prev_total =
      revenue_data.prev
      |> Map.values()
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    last_year_total =
      revenue_data.last_year
      |> Map.values()
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    current_revenue = Money.new(current_total, :USD)
    prev_revenue = Money.new(prev_total, :USD)
    last_year_revenue = Money.new(last_year_total, :USD)

    # Calculate revenue by category for current month
    bookings_revenue =
      bookings_account_ids
      |> Enum.map(&Map.get(revenue_data.current, &1, Decimal.new(0)))
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
      |> then(&Money.new(&1, :USD))

    events_revenue =
      if events_account_id do
        Map.get(revenue_data.current, events_account_id, Decimal.new(0))
        |> Money.new(:USD)
      else
        Money.new(0, :USD)
      end

    membership_revenue =
      if membership_account_id do
        Map.get(revenue_data.current, membership_account_id, Decimal.new(0))
        |> Money.new(:USD)
      else
        Money.new(0, :USD)
      end

    # Calculate percentages
    {:ok, total} = Money.add(bookings_revenue, events_revenue)
    {:ok, total} = Money.add(total, membership_revenue)

    bookings_percent =
      if Decimal.gt?(total.amount, Decimal.new(0)) do
        bookings_amount = Decimal.to_float(bookings_revenue.amount)
        total_amount = Decimal.to_float(total.amount)
        round(bookings_amount / total_amount * 100)
      else
        0
      end

    events_percent =
      if Decimal.gt?(total.amount, Decimal.new(0)) do
        events_amount = Decimal.to_float(events_revenue.amount)
        total_amount = Decimal.to_float(total.amount)
        round(events_amount / total_amount * 100)
      else
        0
      end

    membership_percent =
      if Decimal.gt?(total.amount, Decimal.new(0)) do
        membership_amount = Decimal.to_float(membership_revenue.amount)
        total_amount = Decimal.to_float(total.amount)
        round(membership_amount / total_amount * 100)
      else
        0
      end

    # Calculate change text and direction
    {revenue_change_text, revenue_change_direction} =
      if Decimal.gt?(prev_revenue.amount, Decimal.new(0)) do
        current_amount = Decimal.to_float(current_revenue.amount)
        prev_amount = Decimal.to_float(prev_revenue.amount)

        change_percent =
          ((current_amount - prev_amount) / prev_amount * 100) |> round()

        month_name = Timex.format!(prev_month_start, "{Mshort}")

        {text, direction} =
          cond do
            change_percent > 0 ->
              {"+#{change_percent}% from #{month_name}", :up}

            change_percent < 0 ->
              {"#{change_percent}% from #{month_name}", :down}

            true ->
              {"0% from #{month_name}", :stable}
          end

        {text, direction}
      else
        {"First month", :stable}
      end

    {current_revenue, revenue_change_text, revenue_change_direction,
     prev_revenue, last_year_revenue, bookings_revenue, events_revenue,
     membership_revenue, bookings_percent, events_percent, membership_percent}
  end

  defp format_money(money) do
    Money.to_string!(money, symbol: true, separator: ",", delimiter: ".")
  end

  defp get_active_guests do
    alias Ysc.Repo
    import Ecto.Query

    today = Date.utc_today()
    checkout_time = ~T[11:00:00]

    # Get all active bookings (checkout_date >= today and status = complete)
    query =
      from(b in Bookings.Booking,
        where: b.status == :complete,
        where: b.checkout_date >= ^today,
        preload: [:user]
      )

    bookings = Repo.all(query)

    # Filter out bookings that are past checkout time today
    active_bookings =
      bookings
      |> Enum.filter(fn booking ->
        if Date.compare(booking.checkout_date, today) == :eq do
          now = DateTime.utc_now()
          checkout_datetime = DateTime.new!(today, checkout_time, "Etc/UTC")
          DateTime.compare(now, checkout_datetime) == :lt
        else
          true
        end
      end)

    # Count unique users
    unique_users =
      active_bookings
      |> Enum.map(& &1.user)
      |> Enum.uniq_by(& &1.id)

    # Get sample of users for avatars (max 3)
    sample_users = Enum.take(unique_users, 3)

    {length(unique_users), sample_users}
  end

  defp get_build_version do
    BuildVersion.version()
  end

  @impl true
  def handle_event("navigate-to-review", %{"user-id" => user_id}, socket) do
    {:noreply, push_navigate(socket, to: build_review_url(user_id))}
  end
end
