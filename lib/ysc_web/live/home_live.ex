defmodule YscWeb.HomeLive do
  use YscWeb, :live_view
  use YscNative, :live_view

  import YscWeb.Live.AsyncHelpers

  alias Ysc.{Accounts, Events, Posts, Keila, Tickets}
  alias Ysc.Bookings.{Booking, Season}
  alias Ysc.Posts.Post
  alias Ysc.Media.Image
  alias HtmlSanitizeEx.Scrubber
  import Ecto.Query

  @impl true
  def mount(params, session, socket) do
    if Map.get(params, "_format") == "swiftui" do
      # SwiftUI/native format - load minimal data synchronously
      upcoming_events =
        Events.list_upcoming_events(3)
        |> Enum.reject(&(&1.state == :cancelled))

      {:ok,
       assign(socket,
         page_title: "Kiosk",
         upcoming_events: upcoming_events
       )}
    else
      user = socket.assigns.current_user

      if user do
        # Logged-in user: use async loading for performance
        socket = mount_minimal_assigns(socket)

        # Check if user just logged in (from session) and should show passkey prompt
        just_logged_in =
          Map.get(session, "just_logged_in", false) ||
            Map.get(session, :just_logged_in, false)

        user_with_passkeys = Accounts.get_user!(user.id, [:passkeys])

        show_passkey_prompt =
          just_logged_in &&
            Accounts.should_show_passkey_prompt?(user_with_passkeys)

        socket =
          assign(socket,
            show_passkey_prompt: show_passkey_prompt,
            just_logged_in: just_logged_in
          )

        # Note: The just_logged_in session flag will persist for this page load
        # It will be cleared on the next page navigation

        if connected?(socket) do
          {:ok, load_home_data_async(socket)}
        else
          {:ok, socket}
        end
      else
        # Guest user: load data synchronously for SEO
        # Search engines need to see content in the initial HTML response
        socket = mount_guest_with_data(socket)
        {:ok, socket}
      end
    end
  end

  # Minimal assigns for fast initial static render (logged-in users only)
  defp mount_minimal_assigns(socket) do
    # Logged-in user: show skeleton UI while data loads
    assign(socket,
      page_title: "Home",
      # Will be populated after async load
      is_sub_account: false,
      primary_user: nil,
      upcoming_tickets: [],
      future_bookings: [],
      upcoming_events: [],
      latest_news: [],
      newsletter_email: "",
      newsletter_submitted: false,
      newsletter_error: nil,
      # Track async loading state
      async_data_loaded: false
    )
  end

  # Guest user: load data synchronously for SEO-friendly initial render
  # Search engines and social media crawlers need to see actual content
  defp mount_guest_with_data(socket) do
    # Determine hero video based on season (no DB query)
    {hero_video, hero_poster} =
      case Season.for_date(:tahoe, Date.utc_today()) do
        %{name: "Summer"} ->
          {~p"/video/clear_lake_hero.mp4",
           ~p"/images/clear_lake_hero_poster.jpg"}

        _ ->
          {~p"/video/tahoe_hero.mp4", ~p"/images/tahoe_hero_poster.jpg"}
      end

    # Load events and news synchronously for SEO
    # These queries are lightweight and essential for crawlers to index the page
    upcoming_events =
      Events.list_upcoming_events(3)
      |> Enum.reject(&(&1.state == :cancelled))

    latest_news = Posts.list_posts(3)

    # Get remote IP for Turnstile verification
    remote_ip = get_connect_info(socket, :peer_data).address

    assign(socket,
      page_title: "Home",
      upcoming_events: upcoming_events,
      latest_news: latest_news,
      hero_video: hero_video,
      hero_poster: hero_poster,
      newsletter_email: "",
      newsletter_first_name: "",
      newsletter_last_name: "",
      newsletter_submitted: false,
      newsletter_error: nil,
      remote_ip: remote_ip,
      # Data is already loaded
      async_data_loaded: true
    )
  end

  # Load all home page data asynchronously (logged-in users only)
  defp load_home_data_async(socket) do
    user = socket.assigns.current_user

    start_async(socket, :load_home_data, fn ->
      load_logged_in_user_data(user.id)
    end)
  end

  # Background task to load logged-in user's home page data in parallel
  defp load_logged_in_user_data(user_id) do
    tasks = [
      {:user_data, fn -> load_user_with_subscriptions(user_id) end},
      {:tickets, fn -> get_upcoming_tickets(user_id) end},
      {:bookings, fn -> get_future_active_bookings(user_id) end},
      {:events,
       fn ->
         Events.list_upcoming_events(3)
         |> Enum.reject(&(&1.state == :cancelled))
       end},
      {:news, fn -> Posts.list_posts(3) end}
    ]

    tasks
    |> async_stream_with_repo(fn {key, fun} -> {key, fun.()} end,
      timeout: :infinity
    )
    |> Enum.reduce(%{}, fn {:ok, {key, value}}, acc ->
      Map.put(acc, key, value)
    end)
  end

  # Load user with subscriptions and virtual fields
  defp load_user_with_subscriptions(user_id) do
    user_with_subs =
      Accounts.get_user!(user_id)
      |> Ysc.Repo.preload(subscriptions: :subscription_items)
      |> Accounts.User.populate_virtual_fields()

    is_sub_account = Accounts.sub_account?(user_with_subs)

    primary_user =
      if is_sub_account,
        do: Accounts.get_primary_user(user_with_subs),
        else: nil

    {is_sub_account, primary_user}
  end

  @impl true
  def handle_async(:load_home_data, {:ok, results}, socket) do
    # Handle logged-in user async results
    {is_sub_account, primary_user} = Map.get(results, :user_data, {false, nil})
    upcoming_tickets = Map.get(results, :tickets, [])
    future_bookings = Map.get(results, :bookings, [])
    upcoming_events = Map.get(results, :events, [])
    latest_news = Map.get(results, :news, [])

    # Re-check passkey prompt status after data loads (in case user added a passkey)
    user = socket.assigns.current_user
    user_with_passkeys = Accounts.get_user!(user.id, [:passkeys])

    show_passkey_prompt =
      socket.assigns[:just_logged_in] &&
        Accounts.should_show_passkey_prompt?(user_with_passkeys)

    socket =
      assign(socket,
        is_sub_account: is_sub_account,
        primary_user: primary_user,
        upcoming_tickets: upcoming_tickets,
        future_bookings: future_bookings,
        upcoming_events: upcoming_events,
        show_passkey_prompt: show_passkey_prompt,
        latest_news: latest_news,
        async_data_loaded: true
      )

    {:noreply, socket}
  end

  def handle_async(:load_home_data, {:exit, reason}, socket) do
    require Logger
    Logger.error("Failed to load home data async: #{inspect(reason)}")
    # Mark as loaded to avoid infinite loading state
    {:noreply, assign(socket, :async_data_loaded, true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div :if={@current_user == nil}>
      <.hero
        video={@hero_video}
        poster={@hero_poster}
        height="90vh"
        overlay_opacity="bg-black/40"
      >
        <div class="mb-6 pt-6">
          <span class="inline-block px-4 py-1.5 text-sm font-semibold tracking-widest uppercase bg-white/10 backdrop-blur-sm rounded-full border border-white/20 text-white/90">
            Est. 1950 · San Francisco
          </span>
        </div>

        <h1 class="text-6xl md:text-8xl font-black text-white drop-shadow-2xl">
          <span class="block font-serif italic text-2xl md:text-4xl mb-4 text-white/80 font-light tracking-tight">
            Celebrating 75 Years of
          </span>
          Young Scandinavians Club
        </h1>

        <p class="mt-8 text-lg md:text-xl lg:text-2xl max-w-2xl mx-auto text-white/85 font-light leading-relaxed drop-shadow-md">
          A vibrant community for Scandinavians and Scandinavian-Americans in and around the San Francisco Bay Area
        </p>

        <div class="mt-10 flex flex-wrap gap-4 justify-center">
          <.link
            navigate={~p"/users/register"}
            class="group px-8 py-4 text-base font-bold text-zinc-900 bg-white rounded-lg hover:bg-blue-50 transition-all duration-300 shadow-lg hover:shadow-xl hover:scale-105"
          >
            Apply for Membership
            <.icon
              name="hero-arrow-right"
              class="me-2 w-5 h-5 group-hover:translate-x-1 transition-transform duration-300"
            />
          </.link>
          <.link
            navigate={~p"/events"}
            class="px-8 py-4 text-base font-bold text-white border-2 border-white/80 rounded-lg hover:bg-white hover:text-zinc-900 transition-all duration-300 backdrop-blur-sm"
          >
            Explore Our Events
          </.link>
        </div>

        <div class="mt-16 flex items-center justify-center gap-8 text-white/70">
          <div class="text-center">
            <div class="text-3xl font-bold text-white">500+</div>
            <div class="text-sm uppercase tracking-wide">Members</div>
          </div>
          <div class="w-px h-12 bg-white/30"></div>
          <div class="text-center">
            <div class="text-3xl font-bold text-white">2</div>
            <div class="text-sm uppercase tracking-wide">Properties</div>
          </div>
          <div class="w-px h-12 bg-white/30"></div>
          <div class="text-center">
            <div class="text-3xl font-bold text-white">75+</div>
            <div class="text-sm uppercase tracking-wide">Years</div>
          </div>
        </div>
      </.hero>
    </div>

    <%!-- Community Narrative Section --%>
    <section
      :if={@current_user == nil}
      class="py-16 lg:py-32 bg-white overflow-hidden"
    >
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="grid lg:grid-cols-12 gap-12 lg:gap-20 items-center">
          <div class="lg:col-span-5">
            <span class="text-blue-600 font-black text-xs uppercase tracking-[0.3em]">
              Velkommen back
            </span>
            <h2 class="mt-6 text-4xl lg:text-6xl font-black text-zinc-900 tracking-tighter leading-[0.95]">
              A home for Nordic spirits in the Bay.
            </h2>
            <p class="mt-8 text-lg text-zinc-600 leading-relaxed">
              The Young Scandinavians Club (YSC) is a vibrant community for Scandinavians and Scandinavian-Americans of all ages in the San Francisco Bay Area. We host a wide range of events across Northern California, offering members access to our scenic cabins in Clear Lake and Lake Tahoe.
            </p>
            <div class="mt-6 flex items-center gap-3">
              <.flag country="fi-dk" class="h-8 w-12 rounded shadow-sm" />
              <.flag country="fi-fi" class="h-8 w-12 rounded shadow-sm" />
              <.flag country="fi-is" class="h-8 w-12 rounded shadow-sm" />
              <.flag country="fi-no" class="h-8 w-12 rounded shadow-sm" />
              <.flag country="fi-se" class="h-8 w-12 rounded shadow-sm" />
            </div>
            <p class="mt-6 text-zinc-600">
              Those with <strong class="text-zinc-900">Danish</strong>, <strong class="text-zinc-900">Finnish</strong>, <strong class="text-zinc-900">Icelandic</strong>, <strong class="text-zinc-900">Norwegian</strong>, or
              <strong class="text-zinc-900">Swedish</strong>
              heritage may qualify for membership, with rates starting at just
              <strong class="text-blue-600">
                <%= Ysc.MoneyHelper.format_money!(
                  Money.new(
                    :USD,
                    Enum.at(Application.get_env(:ysc, :membership_plans), 0).amount
                  )
                ) %>
              </strong>
              per year.
            </p>
            <div class="mt-8">
              <.link
                navigate={~p"/users/register"}
                class="inline-flex items-center px-6 py-3 text-base font-bold text-white bg-blue-600 rounded-lg hover:bg-blue-700 transition duration-300 shadow-lg hover:shadow-xl"
              >
                Apply for Membership
                <.icon name="hero-arrow-right" class="ml-2 w-5 h-5" />
              </.link>
            </div>
          </div>

          <div class="lg:col-span-7 relative">
            <div class="relative z-10 rounded-3xl overflow-hidden shadow-2xl transform lg:rotate-2">
              <img
                src={~p"/images/ysc_75th.jpg"}
                alt="YSC 75th Anniversary"
                class="w-full h-96 object-cover"
                loading="lazy"
              />
            </div>
            <div class="hidden lg:block absolute -bottom-12 -left-20 z-20 w-64 h-64 rounded-3xl overflow-hidden shadow-2xl border-8 border-white transform -rotate-6">
              <img
                src={~p"/images/ysc_group_photo.jpg"}
                alt="YSC Group Photo"
                class="w-full h-full object-cover"
                loading="lazy"
              />
            </div>
          </div>
        </div>
      </div>
    </section>

    <%!-- Nordic Living Bento Grid Section --%>
    <section :if={@current_user == nil} class="py-16 lg:py-24 bg-zinc-50">
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="text-center max-w-3xl mx-auto mb-12">
          <span class="text-blue-600 font-semibold text-sm uppercase tracking-wider">
            Nordic Living
          </span>
          <h2 class="mt-3 text-3xl lg:text-4xl font-bold text-zinc-900">
            Don't Let the Name Fool You – YSC is for Everyone!
          </h2>
          <p class="mt-4 text-lg text-zinc-600">
            We may be called the "Young" Scandinavians Club, but we're a community for all ages! With roughly 500 active members, we're a lively bunch who love to connect and have fun.
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 lg:gap-6">
          <%!-- Large featured cabin image --%>
          <div class="md:col-span-2 md:row-span-2 bg-white rounded-2xl overflow-hidden shadow-lg hover:shadow-2xl hover:-translate-y-1 transition-all duration-300 group">
            <div class="relative h-full min-h-[400px]">
              <img
                src={~p"/images/clear_lake_midsummer.jpg"}
                alt="Midsummer at Clear Lake"
                class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-700"
              />
              <div class="absolute inset-0 bg-gradient-to-t from-zinc-900/80 via-zinc-900/40 to-transparent flex flex-col justify-end p-6">
                <h3 class="text-2xl font-bold text-white mb-2">All Ages Welcome</h3>
                <p class="text-zinc-200">
                  Whether chasing toddlers at Midsummer or sharing stories by the fireplace, everyone is welcome.
                </p>
              </div>
            </div>
          </div>

          <%!-- Events card --%>
          <div class="md:col-span-2 bg-white rounded-2xl overflow-hidden shadow-lg hover:shadow-2xl hover:-translate-y-1 transition-all duration-300 group">
            <div class="relative aspect-[16/9]">
              <img
                src={~p"/images/ysc_bonfire_2024.jpg"}
                alt="YSC Bonfire 2024"
                class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-700"
              />
              <div class="absolute inset-0 bg-gradient-to-t from-zinc-900/80 via-zinc-900/40 to-transparent flex flex-col justify-end p-6">
                <h3 class="text-xl font-bold text-white mb-2">Events Year-Round</h3>
                <p class="text-sm text-zinc-200">
                  From casual happy hours to formal dinners and holiday celebrations.
                </p>
              </div>
            </div>
          </div>

          <%!-- Cultural connection card --%>
          <div class="md:col-span-1 bg-white rounded-2xl overflow-hidden shadow-lg hover:shadow-2xl hover:-translate-y-1 transition-all duration-300 group">
            <div class="relative aspect-square">
              <img
                src={~p"/images/flags.jpg"}
                alt="Nordic country flags"
                class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-700"
              />
              <div class="absolute inset-0 bg-gradient-to-t from-zinc-900/80 via-zinc-900/40 to-transparent flex flex-col justify-end p-4">
                <h3 class="text-lg font-bold text-white mb-1">
                  Cultural Connection
                </h3>
                <p class="text-xs text-zinc-200">
                  Stay connected to your roots through traditions like Midsummer, Nordic film screenings, and our annual heritage banquets.
                </p>
              </div>
            </div>
          </div>

          <%!-- Community stats card --%>
          <div class="md:col-span-1 bg-gradient-to-br from-blue-600 to-blue-800 rounded-2xl p-6 flex flex-col justify-center items-center text-center shadow-lg">
            <div class="text-4xl font-black text-white mb-2">500+</div>
            <div class="text-sm text-blue-100 uppercase tracking-widest font-bold">
              Active Members
            </div>
            <div class="mt-4 pt-4 border-t border-blue-400/30 w-full">
              <div class="text-2xl font-black text-white mb-1">
                <%= Date.utc_today().year - 1950 %>+
              </div>
              <div class="text-xs text-blue-100 uppercase tracking-widest">
                Years of Community
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <%!-- Property Portfolio Section --%>
    <section :if={@current_user == nil} class="py-16 lg:py-32 bg-white">
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="flex flex-col md:flex-row md:items-end justify-between gap-6 mb-20">
          <div class="max-w-2xl">
            <span class="text-blue-600 font-black text-xs uppercase tracking-[0.3em]">
              Exclusive Retreats
            </span>
            <h2 class="mt-4 text-4xl lg:text-7xl font-black text-zinc-900 tracking-tighter">
              The Cabin Legacy.
            </h2>
          </div>
          <p class="text-zinc-500 text-lg lg:max-w-xs font-light leading-relaxed">
            Membership unlocks year-round access to our two historic, member-run sanctuaries.
          </p>
        </div>

        <div class="space-y-32">
          <%!-- Lake Tahoe --%>
          <div class="grid lg:grid-cols-12 gap-12 items-center">
            <div class="lg:col-span-5 order-2 lg:order-1">
              <div class="inline-flex items-center px-3 py-1 bg-blue-50 text-blue-700 rounded-full text-[10px] font-black uppercase tracking-widest mb-6">
                <.icon name="hero-map-pin" class="w-3 h-3 mr-1" /> Lake Tahoe, CA
              </div>
              <h3 class="text-4xl font-black text-zinc-900 tracking-tight mb-4">
                The Alpine Retreat
              </h3>
              <p class="text-zinc-600 text-lg leading-relaxed mb-6 font-light">
                Ski in winter, hike in summer, and relax year-round. Perfectly positioned for alpine adventures and cozy
                <em>hygge</em>
                evenings by the fire.
              </p>
              <ul class="space-y-4 mb-8">
                <li class="flex items-start gap-3 text-zinc-700 text-sm">
                  <.icon
                    name="hero-check-circle"
                    class="w-5 h-5 text-teal-500 flex-shrink-0"
                  />
                  <span>Minutes from world-class ski resorts & hiking trails</span>
                </li>
                <li class="flex items-start gap-3 text-zinc-700 text-sm">
                  <.icon
                    name="hero-check-circle"
                    class="w-5 h-5 text-teal-500 flex-shrink-0"
                  />
                  <span>
                    Member-only rates: <strong>$45.00 / night</strong>
                  </span>
                </li>
              </ul>
              <.link
                navigate={~p"/bookings/tahoe"}
                class="inline-flex items-center px-8 py-3 bg-zinc-900 text-white rounded-xl font-bold hover:bg-blue-600 transition-all shadow-lg"
              >
                Learn More About Tahoe
              </.link>
            </div>
            <div class="lg:col-span-7 order-1 lg:order-2">
              <div class="relative group overflow-hidden rounded-[2.5rem] shadow-2xl">
                <img
                  src={~p"/images/tahoe/tahoe_cabin_main.webp"}
                  alt="Lake Tahoe Cabin"
                  class="w-full aspect-[4/3] object-cover group-hover:scale-105 transition-transform duration-700"
                />
                <div class="absolute inset-0 bg-gradient-to-t from-black/20 to-transparent">
                </div>
              </div>
            </div>
          </div>

          <%!-- Clear Lake --%>
          <div class="grid lg:grid-cols-12 gap-12 items-center">
            <div class="lg:col-span-7">
              <div class="relative group overflow-hidden rounded-[2.5rem] shadow-2xl">
                <img
                  src={~p"/images/clear_lake/clear_lake_dock.webp"}
                  alt="Clear Lake Cabin"
                  class="w-full aspect-[4/3] object-cover group-hover:scale-105 transition-transform duration-700"
                />
                <div class="absolute inset-0 bg-gradient-to-t from-black/20 to-transparent">
                </div>
              </div>
            </div>
            <div class="lg:col-span-5">
              <div class="inline-flex items-center px-3 py-1 bg-emerald-50 text-emerald-700 rounded-full text-[10px] font-black uppercase tracking-widest mb-6">
                <.icon name="hero-map-pin" class="w-3 h-3 mr-1" /> Clear Lake, CA
              </div>
              <h3 class="text-4xl font-black text-zinc-900 tracking-tight mb-4">
                The Waterfront Sanctuary
              </h3>
              <p class="text-zinc-600 text-lg leading-relaxed mb-6 font-light">
                Our social heart since 1963. Swim, boat, and unwind at California's largest natural lake. A sun-drenched escape from the city.
              </p>
              <ul class="space-y-4 mb-8">
                <li class="flex items-start gap-3 text-zinc-700 text-sm">
                  <.icon
                    name="hero-check-circle"
                    class="w-5 h-5 text-teal-500 flex-shrink-0"
                  />
                  <span>Private dock access for swimming & boating</span>
                </li>
                <li class="flex items-start gap-3 text-zinc-700 text-sm">
                  <.icon
                    name="hero-check-circle"
                    class="w-5 h-5 text-teal-500 flex-shrink-0"
                  />
                  <span>
                    Member-only rates: <strong>$50.00 / night</strong>
                  </span>
                </li>
              </ul>
              <.link
                navigate={~p"/bookings/clear-lake"}
                class="inline-flex items-center px-8 py-3 bg-zinc-900 text-white rounded-xl font-bold hover:bg-emerald-600 transition-all shadow-lg"
              >
                Learn More About Clear Lake
              </.link>
            </div>
          </div>
        </div>
      </div>
    </section>

    <%!-- Happening Now Bar --%>
    <div
      :if={
        @current_user == nil && @async_data_loaded &&
          (length(@upcoming_events) > 0 || length(@latest_news) > 0)
      }
      class="bg-gradient-to-r from-blue-600 to-blue-800 text-white py-4 border-b border-blue-500/20"
    >
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="flex flex-col sm:flex-row items-center justify-between gap-4">
          <div class="flex items-center gap-3 flex-wrap">
            <div class="flex items-center gap-2">
              <div class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
              <span class="text-sm font-black uppercase tracking-widest">
                Happening Now
              </span>
            </div>
            <%= if length(@upcoming_events) > 0 do %>
              <span class="h-4 w-px bg-white/30"></span>
              <.link
                navigate={~p"/events/#{List.first(@upcoming_events).id}"}
                class="text-sm font-bold hover:text-blue-100 transition-colors line-clamp-1"
              >
                <%= List.first(@upcoming_events).title %> →
              </.link>
            <% else %>
              <%= if length(@latest_news) > 0 do %>
                <span class="h-4 w-px bg-white/30"></span>
                <.link
                  navigate={~p"/posts/#{List.first(@latest_news).url_name}"}
                  class="text-sm font-bold hover:text-blue-100 transition-colors line-clamp-1"
                >
                  <%= List.first(@latest_news).title %> →
                </.link>
              <% end %>
            <% end %>
          </div>
          <div class="flex items-center gap-4">
            <%= if length(@upcoming_events) > 0 do %>
              <.link
                navigate={~p"/events"}
                class="text-xs font-bold uppercase tracking-widest hover:text-blue-100 transition-colors"
              >
                View Events
              </.link>
            <% end %>
            <%= if length(@latest_news) > 0 do %>
              <.link
                navigate={~p"/news"}
                class="text-xs font-bold uppercase tracking-widest hover:text-blue-100 transition-colors"
              >
                View News
              </.link>
            <% end %>
          </div>
        </div>
      </div>
    </div>

    <%!-- Upcoming Events Section --%>
    <section
      :if={
        @current_user == nil &&
          (@async_data_loaded == false || length(@upcoming_events) > 0)
      }
      class="py-20 lg:py-32 bg-zinc-900 relative overflow-hidden"
    >
      <div class="absolute top-0 left-1/4 w-96 h-96 bg-blue-600/10 rounded-full blur-[120px] pointer-events-none">
      </div>

      <div class="max-w-screen-xl mx-auto px-4 relative z-10">
        <div class="flex flex-col md:flex-row md:items-end justify-between gap-6 mb-16">
          <div>
            <span class="text-blue-400 font-black text-xs uppercase tracking-[0.3em]">
              Upcoming Events
            </span>
            <h2 class="mt-4 text-4xl lg:text-6xl font-black text-white tracking-tighter leading-none">
              The Pulse of the Club.
            </h2>
          </div>
          <.link
            navigate={~p"/events"}
            class="group flex items-center gap-2 text-white font-bold hover:text-blue-400 transition-all"
          >
            View full calendar
            <.icon
              name="hero-arrow-right"
              class="w-5 h-5 group-hover:translate-x-1 transition-transform"
            />
          </.link>
        </div>

        <%!-- Loading skeleton for guest events --%>
        <div
          :if={!@async_data_loaded}
          class="flex flex-wrap justify-center gap-8 lg:gap-10"
        >
          <%= for _i <- 1..3 do %>
            <div class="flex flex-col bg-white/5 backdrop-blur-sm rounded-[2.5rem] border border-white/10 overflow-hidden shadow-2xl w-full md:max-w-md lg:max-w-[calc(33.333%-2rem)] animate-pulse">
              <div class="aspect-[16/11] bg-zinc-700"></div>
              <div class="p-8 space-y-4">
                <div class="h-4 bg-zinc-700 rounded w-1/3"></div>
                <div class="h-8 bg-zinc-700 rounded w-3/4"></div>
                <div class="h-4 bg-zinc-700 rounded w-full"></div>
                <div class="h-4 bg-zinc-700 rounded w-2/3"></div>
              </div>
            </div>
          <% end %>
        </div>

        <div
          :if={@async_data_loaded}
          class="flex flex-wrap justify-center gap-8 lg:gap-10"
        >
          <%= for event <- @upcoming_events do %>
            <div class="group flex flex-col bg-white/5 backdrop-blur-sm rounded-[2.5rem] border border-white/10 hover:border-blue-500/50 transition-all duration-500 overflow-hidden shadow-2xl w-full md:max-w-md lg:max-w-[calc(33.333%-2rem)]">
              <.link
                navigate={~p"/events/#{event.id}"}
                class="block relative aspect-[16/11] overflow-hidden"
              >
                <canvas
                  id={"blur-hash-event-#{event.id}"}
                  src={get_blur_hash(event.image)}
                  class="absolute inset-0 z-0 w-full h-full object-cover"
                  phx-hook="BlurHashCanvas"
                >
                </canvas>
                <img
                  src={event_image_url(event.image)}
                  id={"image-event-#{event.id}"}
                  phx-hook="BlurHashImage"
                  class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out object-cover w-full h-full group-hover:scale-110 transition-transform duration-700 opacity-80 group-hover:opacity-100"
                  loading="lazy"
                  alt={
                    if event.image,
                      do:
                        event.image.alt_text || event.image.title || event.title ||
                          "Event image",
                      else: "Event image"
                  }
                />
                <div class="absolute top-6 left-6 flex gap-2 z-[2] flex-wrap">
                  <%= if days_since_inserted(event.inserted_at) <= 7 do %>
                    <span class="px-3 py-1 bg-slate-600 text-white text-[10px] font-black uppercase tracking-widest rounded-lg shadow-lg">
                      Just Added
                    </span>
                  <% end %>
                  <%= if event_sold_out?(event) do %>
                    <span class="px-3 py-1 bg-zinc-100 text-zinc-600 text-[10px] font-black uppercase tracking-widest rounded-lg shadow-lg">
                      Sold Out
                    </span>
                  <% end %>
                </div>
                <div class="absolute bottom-4 right-4 z-[2]">
                  <span class="bg-zinc-900/80 backdrop-blur-md px-4 py-2 rounded-xl text-white text-xs font-black ring-1 ring-white/10 tracking-widest">
                    <%= event.pricing_info.display_text %>
                  </span>
                </div>
                <div class="absolute inset-0 bg-gradient-to-t from-zinc-900 via-transparent to-transparent opacity-60">
                </div>
              </.link>

              <div class="p-8 flex flex-col flex-1">
                <div class="flex items-center gap-3 mb-4">
                  <span class="text-blue-400 font-black text-xs tracking-widest uppercase">
                    <%= format_event_date(event.start_date) %>
                  </span>
                  <span class="w-1.5 h-1.5 bg-white/20 rounded-full"></span>
                  <%= if event.start_time && event.start_time != "" do %>
                    <span class="text-zinc-400 text-xs font-bold uppercase tracking-widest text-[10px]">
                      <%= format_event_time(event.start_date, event.start_time) %>
                    </span>
                  <% end %>
                </div>
                <.link navigate={~p"/events/#{event.id}"} class="block">
                  <h3 class="text-2xl font-black text-white tracking-tight group-hover:text-blue-400 transition-colors leading-tight">
                    <%= event.title %>
                  </h3>
                </.link>
                <%= if event.description do %>
                  <p class="text-zinc-400 mt-4 line-clamp-2 text-sm leading-relaxed">
                    <%= event.description %>
                  </p>
                <% end %>

                <div class="mt-auto pt-8 flex justify-between items-center border-t border-white/5">
                  <%= if event.location_name do %>
                    <span class="text-[11px] font-bold text-zinc-500 flex items-center gap-2">
                      <.icon name="hero-map-pin" class="w-4 h-4 text-blue-500" />
                      <%= event.location_name %>
                    </span>
                  <% else %>
                    <span></span>
                  <% end %>
                  <.icon
                    name="hero-arrow-right"
                    class="w-5 h-5 text-zinc-600 group-hover:text-blue-400 group-hover:translate-x-1 transition-all"
                  />
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </section>

    <%!-- Latest News Section --%>
    <section
      :if={
        @current_user == nil &&
          (@async_data_loaded == false || length(@latest_news) > 0)
      }
      class="py-24 lg:py-32 bg-zinc-50"
    >
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="flex flex-col md:flex-row md:items-end justify-between gap-6 mb-20 border-b border-zinc-200 pb-10">
          <div class="max-w-2xl">
            <span class="text-blue-600 font-black text-xs uppercase tracking-[0.3em]">
              Club News
            </span>
            <h2 class="mt-4 text-4xl lg:text-6xl font-black text-zinc-900 tracking-tighter">
              Stay Informed.
            </h2>
          </div>
          <p class="text-zinc-500 text-lg font-light lg:max-w-xs">
            Member updates, seasonal news, and club stories.
          </p>
        </div>

        <%!-- Loading skeleton for guest news --%>
        <div
          :if={!@async_data_loaded}
          class="grid grid-cols-1 md:grid-cols-3 gap-12 lg:gap-16"
        >
          <%= for i <- 0..2 do %>
            <div class={[
              "animate-pulse",
              if(rem(i, 2) == 1, do: "md:mt-20", else: "")
            ]}>
              <div class="rounded-[2.5rem] mb-8 aspect-square bg-zinc-200"></div>
              <div class="h-3 bg-zinc-200 rounded w-1/4 mb-4"></div>
              <div class="h-6 bg-zinc-200 rounded w-3/4 mb-2"></div>
              <div class="h-4 bg-zinc-200 rounded w-full"></div>
            </div>
          <% end %>
        </div>

        <div
          :if={@async_data_loaded}
          class="grid grid-cols-1 md:grid-cols-3 gap-12 lg:gap-16"
        >
          <%= for {post, index} <- Enum.with_index(@latest_news) do %>
            <.link
              navigate={~p"/posts/#{post.url_name}"}
              class={[
                "group block transition-all duration-500",
                if(rem(index, 2) == 1, do: "md:mt-20", else: "")
              ]}
            >
              <div class="relative overflow-hidden rounded-[2.5rem] mb-8 aspect-square shadow-sm group-hover:shadow-2xl transition-all">
                <canvas
                  id={"blur-hash-news-#{post.id}"}
                  src={get_blur_hash(post.featured_image)}
                  class="absolute inset-0 z-0 w-full h-full object-cover"
                  phx-hook="BlurHashCanvas"
                >
                </canvas>
                <img
                  src={featured_image_url_for_news(post.featured_image)}
                  id={"image-news-#{post.id}"}
                  phx-hook="BlurHashImage"
                  class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out object-cover w-full h-full transition-transform duration-700 group-hover:scale-105"
                  loading="lazy"
                  alt={
                    if post.featured_image,
                      do:
                        post.featured_image.alt_text || post.featured_image.title ||
                          post.title ||
                          "News article image",
                      else: "News article image"
                  }
                />
              </div>
              <time class="text-[10px] font-black text-blue-600 uppercase tracking-widest">
                <%= format_post_date(post.published_on) %> · <%= reading_time_for_news(
                  post
                ) %> min read
              </time>
              <h3 class="text-2xl font-black text-zinc-900 tracking-tighter mt-3 group-hover:text-blue-600 transition-colors leading-none">
                <%= post.title %>
              </h3>
              <%= if post.preview_text || post.rendered_body do %>
                <p class="text-zinc-500 mt-4 text-sm leading-relaxed line-clamp-2 italic">
                  <%= preview_text_for_news(post) %>
                </p>
              <% end %>
            </.link>
          <% end %>
        </div>
      </div>
    </section>

    <%!-- Membership Options Section --%>
    <section
      :if={@current_user == nil}
      class="py-16 lg:py-24 bg-gradient-to-br from-blue-600 to-blue-800"
    >
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="text-center max-w-3xl mx-auto mb-12">
          <h2 class="text-3xl lg:text-4xl font-bold text-white">
            Join Our Community Today
          </h2>
          <p class="mt-4 text-lg text-blue-100">
            We offer two membership options to fit your lifestyle.
          </p>
        </div>

        <div class="grid md:grid-cols-2 gap-8 max-w-4xl mx-auto">
          <%!-- Single Membership --%>
          <div class="bg-white rounded-2xl p-8 shadow-xl">
            <h3 class="text-xl font-bold text-zinc-900">Single Membership</h3>
            <div class="mt-4">
              <span class="text-4xl font-bold text-zinc-900">
                <%= Ysc.MoneyHelper.format_money!(
                  Money.new(
                    :USD,
                    Enum.at(Application.get_env(:ysc, :membership_plans), 0).amount
                  )
                ) %>
              </span>
              <span class="text-zinc-500">/year</span>
            </div>
            <p class="mt-4 text-zinc-600">
              Enjoy all the benefits of the YSC for yourself.
            </p>
            <ul class="mt-6 space-y-3">
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check" class="w-5 h-5 text-blue-600 mr-3" />
                Access to both cabins
              </li>
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check" class="w-5 h-5 text-blue-600 mr-3" />
                Member events
              </li>
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check" class="w-5 h-5 text-blue-600 mr-3" />
                Community access
              </li>
            </ul>
          </div>

          <%!-- Family Membership --%>
          <div class="bg-white rounded-2xl p-8 shadow-xl">
            <h3 class="text-xl font-bold text-zinc-900">Family Membership</h3>
            <div class="mt-4">
              <span class="text-4xl font-bold text-zinc-900">
                <%= Ysc.MoneyHelper.format_money!(
                  Money.new(
                    :USD,
                    Enum.at(Application.get_env(:ysc, :membership_plans), 1).amount
                  )
                ) %>
              </span>
              <span class="text-zinc-500">/year</span>
            </div>
            <p class="mt-4 text-zinc-600">
              Share the YSC experience with your loved ones! Covers you, your spouse, and children under 18.
            </p>
            <ul class="mt-6 space-y-3">
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check" class="w-5 h-5 text-blue-600 mr-3" />
                Everything in Single
              </li>
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check" class="w-5 h-5 text-blue-600 mr-3" />
                Spouse included
              </li>
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check" class="w-5 h-5 text-blue-600 mr-3" />
                Children under 18 included
              </li>
            </ul>
          </div>
        </div>

        <div class="text-center mt-12">
          <.link
            navigate={~p"/users/register"}
            class="inline-flex items-center px-8 py-4 text-lg font-bold text-blue-600 bg-white rounded-lg hover:bg-blue-50 transition duration-300 shadow-lg hover:shadow-xl"
          >
            Check Eligibility & Apply
            <.icon name="hero-arrow-right" class="ml-2 w-5 h-5" />
          </.link>
        </div>
      </div>
    </section>

    <%!-- Heritage Pride Footer --%>
    <div
      :if={@current_user == nil}
      class="flex justify-center gap-6 py-10 opacity-30 grayscale hover:grayscale-0 transition-all"
    >
      <.flag country="fi-dk" class="h-8 w-12 rounded-sm" />
      <.flag country="fi-fi" class="h-8 w-12 rounded-sm" />
      <.flag country="fi-is" class="h-8 w-12 rounded-sm" />
      <.flag country="fi-no" class="h-8 w-12 rounded-sm" />
      <.flag country="fi-se" class="h-8 w-12 rounded-sm" />
    </div>

    <%!-- Newsletter Section --%>
    <section :if={@current_user == nil} class="py-16 lg:py-24">
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="max-w-2xl mx-auto text-center">
          <h2 class="text-3xl lg:text-4xl font-bold text-zinc-900">
            Stay in the Loop
          </h2>
          <p class="mt-4 text-lg text-zinc-600">
            Sign up for our newsletter to receive updates about YSC and all the fun events we're arranging.
          </p>

          <form phx-submit="subscribe_newsletter" class="mt-8">
            <div class="max-w-lg mx-auto space-y-4">
              <div class="flex flex-col sm:flex-row gap-4">
                <input
                  type="email"
                  id="newsletter-email"
                  name="email"
                  value={@newsletter_email}
                  class="flex-1 px-4 py-3 border border-zinc-300 rounded-lg text-zinc-900 focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  placeholder="Email address"
                  required
                  disabled={@newsletter_submitted}
                />
                <.button
                  :if={!@newsletter_submitted}
                  type="submit"
                  phx-disable-with="Subscribing..."
                  class="px-6 py-3 whitespace-nowrap"
                >
                  Subscribe
                </.button>
              </div>
              <%!-- Invisible Turnstile verification --%>
              <Turnstile.widget appearance="interaction-only" />
            </div>
            <p :if={@newsletter_error} class="mt-3 text-sm text-red-600">
              <%= @newsletter_error %>
            </p>
            <div
              :if={@newsletter_submitted}
              class="mt-3 flex items-center justify-center text-emerald-600"
            >
              <.icon name="hero-check-circle" class="w-5 h-5 mr-2" />
              <span>Thank you for subscribing!</span>
            </div>
            <p class="mt-4 text-sm text-zinc-500">
              We don't spam! Read our
              <.link
                navigate={~p"/privacy-policy"}
                class="text-blue-600 hover:underline"
              >
                privacy policy
              </.link>
              for more info.
            </p>
          </form>
        </div>
      </div>
    </section>

    <%!-- Logged-in User Dashboard --%>
    <main
      :if={@current_user != nil}
      class="flex-1 w-full bg-zinc-50/50 min-h-screen"
    >
      <%!-- Passkey Setup Prompt Banner --%>
      <div
        :if={@show_passkey_prompt}
        id="passkey-prompt-banner"
        class="bg-blue-50 border-b border-blue-100 shadow-sm"
        phx-mounted={
          JS.transition(
            {"transition ease-out duration-300", "opacity-0 -translate-y-1",
             "opacity-100 translate-y-0"}
          )
        }
        phx-remove={
          JS.transition(
            {"transition ease-in duration-200", "opacity-100", "opacity-0"}
          )
        }
      >
        <div class="max-w-screen-xl mx-auto px-4 py-3 sm:py-3.5">
          <div class="flex items-start sm:items-center justify-between gap-x-4">
            <div class="flex items-start sm:items-center gap-4 flex-1">
              <div class="hidden sm:flex flex-shrink-0 h-10 w-10 items-center justify-center rounded-full bg-blue-100 ring-4 ring-blue-50">
                <.icon name="hero-bolt" class="h-6 w-6 text-blue-600" />
              </div>

              <div class="flex-1 min-w-0">
                <h3 class="text-sm font-semibold text-blue-900 leading-none sm:leading-6">
                  Sign in faster with Passkeys
                </h3>
                <p class="mt-1 text-sm text-blue-800/80 leading-snug max-w-xl">
                  Use FaceID, TouchID, or your device passcode instead of a password.
                </p>
              </div>
            </div>

            <div class="flex items-center gap-2 sm:gap-4">
              <.button
                phx-click="setup_passkey"
                class="!py-1.5 !px-4 whitespace-nowrap shadow-sm"
              >
                Setup
              </.button>

              <button
                phx-click="dismiss_passkey_prompt"
                class="hidden md:block whitespace-nowrap text-sm font-medium text-blue-600 hover:text-blue-800 transition-colors"
              >
                Maybe later
              </button>

              <button
                type="button"
                phx-click="dismiss_passkey_prompt"
                class="p-2 -mr-2 text-blue-400 hover:text-blue-600 transition-colors"
                aria-label="Dismiss"
              >
                <.icon name="hero-x-mark" class="w-5 h-5 -mt-0.5" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Welcome Header with Soft Background --%>
      <div class="bg-white border-b border-zinc-100">
        <div class="max-w-screen-xl mx-auto px-4 py-10 lg:py-16">
          <div class="flex flex-col md:flex-row md:items-center justify-between gap-6">
            <div class="space-y-1">
              <p class="text-blue-600 text-xs font-bold uppercase tracking-[0.2em]">
                Member Dashboard
              </p>
              <h1 class="text-4xl lg:text-5xl font-black text-zinc-900 tracking-tight">
                <%= greeting_for_country(@current_user.most_connected_country) %>, <%= String.capitalize(
                  @current_user.first_name
                ) %>
              </h1>
            </div>
            <div class="hidden md:flex items-center gap-4">
              <div class="text-right hidden md:block">
                <p class="text-sm font-bold text-zinc-900">
                  <%= YscWeb.UserAuth.get_membership_plan_display_name(
                    @current_membership
                  ) %>
                </p>
                <p class="text-xs text-zinc-500">
                  Member since <%= Calendar.strftime(
                    @current_user.inserted_at,
                    "%Y"
                  ) %>
                </p>
              </div>
              <div class="w-16 h-16 rounded-full ring-4 ring-zinc-50 shadow-inner overflow-hidden">
                <.user_avatar_image
                  email={@current_user.email}
                  user_id={@current_user.id}
                  country={@current_user.most_connected_country}
                  class="w-full h-full object-cover"
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Dashboard Content --%>
      <div class="max-w-screen-xl mx-auto px-4 -mt-8 pb-20">
        <%!-- App Launcher Grid --%>
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-12">
          <.link
            navigate={~p"/bookings/tahoe"}
            class="bg-white p-6 rounded shadow-sm border border-zinc-200 hover:border-blue-500 hover:-translate-y-1 hover:shadow-xl transition-all duration-300 group"
          >
            <div class="w-10 h-10 bg-blue-50 rounded-lg flex items-center justify-center mb-4 group-hover:scale-110 transition-transform">
              <.icon name="hero-home" class="w-5 h-5 text-blue-600" />
            </div>
            <p class="font-bold text-zinc-900">Lake Tahoe</p>
            <p class="text-xs text-zinc-500">Reserve Cabin</p>
          </.link>
          <.link
            navigate={~p"/bookings/clear-lake"}
            class="bg-white p-6 rounded shadow-sm border border-zinc-200 hover:border-emerald-500 hover:-translate-y-1 hover:shadow-xl transition-all duration-300 group"
          >
            <div class="w-10 h-10 bg-emerald-50 rounded-lg flex items-center justify-center mb-4 group-hover:scale-110 transition-transform">
              <.icon name="hero-home" class="w-5 h-5 text-emerald-600" />
            </div>
            <p class="font-bold text-zinc-900">Clear Lake</p>
            <p class="text-xs text-zinc-500">Reserve Cabin</p>
          </.link>
          <.link
            navigate={~p"/users/settings"}
            class="bg-white p-6 rounded shadow-sm border border-zinc-200 hover:border-zinc-500 hover:-translate-y-1 hover:shadow-xl transition-all duration-300 group"
          >
            <div class="w-10 h-10 bg-zinc-50 rounded-lg flex items-center justify-center mb-4 group-hover:scale-110 transition-transform">
              <.icon name="hero-cog-6-tooth" class="w-5 h-5 text-zinc-600" />
            </div>
            <p class="font-bold text-zinc-900">Settings</p>
            <p class="text-xs text-zinc-500">Preferences</p>
          </.link>
          <%= if @current_user && @current_user.role == :admin do %>
            <.link
              navigate={~p"/expensereport"}
              class="bg-white p-6 rounded shadow-sm border border-zinc-200 hover:border-yellow-500 hover:-translate-y-1 hover:shadow-xl transition-all duration-300 group"
            >
              <div class="w-10 h-10 bg-orange-50 rounded-lg flex items-center justify-center mb-4 group-hover:scale-110 transition-transform">
                <.icon name="hero-receipt-refund" class="w-5 h-5 text-orange-600" />
              </div>
              <p class="font-bold text-zinc-900">Expenses</p>
              <p class="text-xs text-zinc-500">File Report</p>
            </.link>
          <% else %>
            <div class="bg-white p-6 rounded shadow-sm border border-zinc-200 opacity-50">
              <div class="w-10 h-10 bg-zinc-50 rounded-lg flex items-center justify-center mb-4">
                <.icon name="hero-lock-closed" class="w-5 h-5 text-zinc-400" />
              </div>
              <p class="font-bold text-zinc-400">More</p>
              <p class="text-xs text-zinc-400">Coming soon</p>
            </div>
          <% end %>
        </div>

        <%!-- Main Content Grid --%>
        <div class="grid lg:grid-cols-3 gap-12">
          <div class="lg:col-span-2 space-y-12">
            <%!-- Your Itinerary Section --%>
            <section>
              <div class="flex items-center justify-between mb-6">
                <h3 class="text-lg font-bold text-zinc-900 flex items-center gap-2">
                  <.icon name="hero-map-pin" class="w-5 h-5 text-blue-600" />Your Upcoming Stays
                </h3>
                <.link
                  navigate={~p"/users/payments"}
                  class="text-xs font-bold text-blue-600 hover:underline"
                >
                  View All Trips
                </.link>
              </div>

              <%!-- Loading skeleton for bookings --%>
              <div
                :if={!@async_data_loaded}
                class="bg-white rounded shadow-sm border border-zinc-200 p-6 animate-pulse"
              >
                <div class="flex gap-4">
                  <div class="w-24 h-20 bg-zinc-200 rounded"></div>
                  <div class="flex-1 space-y-3">
                    <div class="h-4 bg-zinc-200 rounded w-1/3"></div>
                    <div class="h-3 bg-zinc-200 rounded w-1/2"></div>
                    <div class="h-3 bg-zinc-200 rounded w-1/4"></div>
                  </div>
                </div>
              </div>

              <div
                :if={@async_data_loaded && Enum.empty?(@future_bookings)}
                class="bg-white rounded shadow-lg border border-zinc-200 p-12 text-center"
              >
                <div class="w-16 h-16 bg-zinc-100 rounded-full flex items-center justify-center mx-auto mb-4">
                  <.icon name="hero-home" class="w-8 h-8 text-zinc-400" />
                </div>
                <h3 class="text-lg font-black text-zinc-900 mb-2">
                  No upcoming bookings
                </h3>
                <p class="text-zinc-500 text-sm mb-6">
                  Plan your next cabin getaway
                </p>
                <div class="flex flex-col sm:flex-row gap-3 justify-center">
                  <.link
                    navigate={~p"/bookings/tahoe"}
                    class="inline-flex items-center justify-center px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white text-sm font-bold rounded transition-colors"
                  >
                    Book Lake Tahoe
                  </.link>
                  <.link
                    navigate={~p"/bookings/clear-lake"}
                    class="inline-flex items-center justify-center px-6 py-3 bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-bold rounded transition-colors"
                  >
                    Book Clear Lake
                  </.link>
                </div>
              </div>

              <div
                :if={@async_data_loaded && !Enum.empty?(@future_bookings)}
                class="space-y-4"
              >
                <%= for booking <- @future_bookings do %>
                  <% is_active =
                    days_until_booking(booking) == :started ||
                      days_until_booking(booking) == 0 %>
                  <.link
                    navigate={~p"/bookings/#{booking.id}/receipt"}
                    class={[
                      "relative bg-white rounded-lg overflow-hidden flex flex-col md:flex-row transition-all duration-300 group hover:-translate-y-1 shadow-sm hover:shadow-lg border border-zinc-100",
                      if is_active do
                        if booking.property == :tahoe do
                          "ring-1 ring-blue-500/10"
                        else
                          "ring-1 ring-emerald-500/10"
                        end
                      else
                        ""
                      end
                    ]}
                  >
                    <div class={[
                      "md:w-1.5 flex-shrink-0",
                      if booking.property == :tahoe do
                        "bg-gradient-to-b from-blue-500 to-blue-700"
                      else
                        "bg-gradient-to-b from-emerald-500 to-emerald-700"
                      end
                    ]}>
                    </div>
                    <div class="p-8 flex-1 grid grid-cols-1 md:grid-cols-3 gap-8 items-center">
                      <div class="space-y-1 md:border-r border-zinc-100 pr-6">
                        <p class="text-[10px] font-bold text-zinc-400 uppercase tracking-[0.2em]">
                          Destination
                        </p>
                        <p class="font-black text-2xl text-zinc-900 tracking-tighter">
                          <%= format_property_name(booking.property) %>
                        </p>
                        <p class="text-[10px] font-mono text-zinc-400">
                          <%= booking.reference_id %>
                        </p>
                      </div>
                      <div class="space-y-2">
                        <p class="text-[10px] font-bold text-zinc-400 uppercase tracking-[0.2em]">
                          Dates
                        </p>
                        <p class="font-bold text-zinc-800">
                          <%= format_booking_date(booking.checkin_date) %> — <%= format_booking_date(
                            booking.checkout_date
                          ) %>
                        </p>
                        <span class={[
                          "inline-flex items-center px-2.5 py-0.5 text-[10px] font-black rounded uppercase tracking-tighter",
                          case days_until_booking(booking) do
                            :started ->
                              "bg-amber-50 text-amber-700 ring-1 ring-amber-200/50 animate-pulse"

                            0 ->
                              "bg-amber-50 text-amber-700 ring-1 ring-amber-200/50 animate-pulse"

                            1 ->
                              "bg-blue-50 text-blue-700 ring-1 ring-blue-200/50"

                            days when days <= 7 ->
                              "bg-emerald-50 text-emerald-700 ring-1 ring-emerald-200/50"

                            _ ->
                              "bg-zinc-50 text-zinc-700 ring-1 ring-zinc-200/50"
                          end
                        ]}>
                          <%= case days_until_booking(booking) do
                            :started -> "Currently Staying"
                            0 -> "Checking in today"
                            1 -> "Tomorrow"
                            days -> "In #{days} days"
                          end %>
                        </span>
                        <%= if booking.booking_mode == :buyout do %>
                          <span class="inline-block mt-1 px-2.5 py-0.5 bg-amber-50 text-amber-700 ring-1 ring-amber-200/50 text-[10px] font-black rounded uppercase tracking-tighter">
                            Full Buyout
                          </span>
                        <% end %>
                      </div>
                      <div class="flex justify-end">
                        <span class="px-5 py-2.5 bg-zinc-900 text-white text-xs font-bold rounded group-hover:bg-blue-600 transition-colors shadow shadow-zinc-200 group-hover:shadow-blue-200">
                          View Details
                        </span>
                      </div>
                    </div>
                  </.link>
                <% end %>
              </div>
            </section>

            <%!-- Event Tickets Section --%>
            <section>
              <h3 class="text-lg font-bold text-zinc-900 mb-6 flex items-center gap-2">
                <.icon name="hero-ticket" class="w-5 h-5 text-purple-600" />
                Event Tickets
              </h3>

              <%!-- Loading skeleton for tickets --%>
              <div
                :if={!@async_data_loaded}
                class="grid grid-cols-1 md:grid-cols-2 gap-6"
              >
                <div class="bg-white/50 border-2 border-dashed border-zinc-200 rounded-lg p-8 animate-pulse">
                  <div class="flex justify-between items-start mb-4">
                    <div class="w-16 h-5 bg-zinc-200 rounded"></div>
                    <div class="w-8 h-8 bg-zinc-200 rounded"></div>
                  </div>
                  <div class="h-5 bg-zinc-200 rounded w-3/4 mb-2"></div>
                  <div class="h-3 bg-zinc-200 rounded w-1/2 mb-4"></div>
                  <div class="h-3 bg-zinc-200 rounded w-2/3"></div>
                </div>
              </div>

              <div
                :if={@async_data_loaded && Enum.empty?(@upcoming_tickets)}
                class="bg-white border border-zinc-200 rounded shadow-lg p-12 text-center"
              >
                <div class="w-16 h-16 bg-zinc-100 rounded-full flex items-center justify-center mx-auto mb-4">
                  <.icon name="hero-calendar-days" class="w-8 h-8 text-zinc-400" />
                </div>
                <h3 class="text-lg font-black text-zinc-900 mb-2">
                  No upcoming event tickets
                </h3>
                <p class="text-zinc-500 text-sm mb-6">
                  Discover what's happening in our community
                </p>
                <.link
                  navigate={~p"/events"}
                  class="inline-flex items-center px-6 py-3 bg-zinc-900 hover:bg-zinc-800 text-white text-sm font-bold rounded transition-colors"
                >
                  Browse Events
                </.link>
              </div>

              <div
                :if={@async_data_loaded && !Enum.empty?(@upcoming_tickets)}
                class="grid grid-cols-1 md:grid-cols-2 gap-6"
              >
                <%= for {event, grouped_tiers} <- group_tickets_by_event_and_tier(@upcoming_tickets) do %>
                  <% order_id =
                    case grouped_tiers do
                      [{_tier_name, [first_ticket | _]} | _]
                      when not is_nil(first_ticket.ticket_order) ->
                        first_ticket.ticket_order.id

                      _ ->
                        nil
                    end %>
                  <div class="bg-white/50 border-2 border-dashed border-zinc-200 rounded-lg p-8 hover:shadow-lg transition-all">
                    <div class="flex justify-between items-start mb-4">
                      <span class={[
                        "px-2 py-1 text-[10px] font-bold rounded",
                        case days_until_event(event) do
                          0 -> "bg-amber-50 text-amber-700"
                          1 -> "bg-blue-50 text-blue-700"
                          days when days <= 7 -> "bg-emerald-50 text-emerald-700"
                          _ -> "bg-purple-50 text-purple-700"
                        end
                      ]}>
                        <%= case days_until_event(event) do
                          0 -> "Today"
                          1 -> "Tomorrow"
                          days -> "In #{days} days"
                        end %>
                      </span>
                      <.icon name="hero-ticket" class="w-8 h-8 text-zinc-300" />
                    </div>
                    <.link navigate={~p"/events/#{event.id}"} class="block group">
                      <h4 class="font-black text-zinc-900 leading-tight mb-2 group-hover:text-blue-600 transition-colors">
                        <%= event.title %>
                      </h4>
                    </.link>
                    <p class="text-xs text-zinc-500 flex items-center gap-1 mb-4">
                      <.icon name="hero-calendar" class="w-3 h-3" />
                      <%= format_event_date_long(event.start_date) %>
                    </p>
                    <div
                      :if={event.location_name}
                      class="text-xs text-zinc-500 flex items-center gap-1 mb-4"
                    >
                      <.icon name="hero-map-pin" class="w-3 h-3" />
                      <span class="truncate"><%= event.location_name %></span>
                    </div>
                    <div class="mt-4 pt-4 border-t-2 border-dashed border-zinc-100 flex items-center justify-between">
                      <.link
                        :if={order_id}
                        navigate={~p"/orders/#{order_id}/confirmation"}
                        class="text-xs font-bold text-zinc-700 hover:text-blue-600 underline transition-colors"
                      >
                        View Order
                      </.link>
                      <span :if={!order_id} class="text-xs font-bold text-zinc-400">
                        No order
                      </span>
                      <div class="flex flex-wrap gap-1">
                        <%= for {tier_name, tickets} <- grouped_tiers do %>
                          <span class="text-[10px] font-bold text-zinc-400">
                            <%= length(tickets) %>× <%= tier_name %>
                          </span>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </section>
          </div>

          <%!-- Sidebar --%>
          <aside class="space-y-10">
            <%!-- Membership Status Card --%>
            <div class={[
              "relative overflow-hidden rounded-lg p-8 text-white shadow-lg",
              if @active_membership? do
                "bg-zinc-900"
              else
                "bg-gradient-to-br from-amber-900 via-orange-900 to-red-900"
              end
            ]}>
              <div class="absolute inset-0 z-0 opacity-40">
                <%= if @active_membership? do %>
                  <div class="absolute -top-[20%] -left-[10%] h-[80%] w-[80%] rounded-full bg-blue-500 blur-[80px]">
                  </div>
                  <div class="absolute top-[20%] -right-[10%] h-[70%] w-[70%] rounded-full bg-blue-600 blur-[80px]">
                  </div>
                  <div class="absolute -bottom-[20%] left-[20%] h-[60%] w-[60%] rounded-full bg-indigo-800 blur-[80px]">
                  </div>
                <% else %>
                  <div class="absolute -top-[20%] -left-[10%] h-[80%] w-[80%] rounded-full bg-amber-500 blur-[80px]">
                  </div>
                  <div class="absolute top-[20%] -right-[10%] h-[70%] w-[70%] rounded-full bg-orange-600 blur-[80px]">
                  </div>
                  <div class="absolute -bottom-[20%] left-[20%] h-[60%] w-[60%] rounded-full bg-red-800 blur-[80px]">
                  </div>
                <% end %>
              </div>

              <div class="relative z-10">
                <div class={[
                  "mb-4 inline-flex h-10 w-10 items-center justify-center rounded backdrop-blur-md",
                  if @active_membership? do
                    "bg-white/10"
                  else
                    "bg-white/20"
                  end
                ]}>
                  <.icon
                    name="hero-identification"
                    class={[
                      "w-6 h-6",
                      if @active_membership? do
                        "text-blue-400"
                      else
                        "text-amber-300"
                      end
                    ]}
                  />
                </div>

                <h3 class="text-2xl font-black tracking-tight mb-2">
                  <%= YscWeb.UserAuth.get_membership_plan_display_name(
                    @current_membership
                  ) %>
                </h3>
                <p class={[
                  "text-sm leading-relaxed mb-8",
                  if @active_membership? do
                    "text-zinc-300"
                  else
                    "text-amber-100 font-semibold"
                  end
                ]}>
                  <%= if @active_membership? do %>
                    <%= get_membership_description(
                      @current_membership,
                      @is_sub_account || false,
                      @primary_user
                    ) %>
                  <% else %>
                    <span class="block mb-2 font-bold text-white">
                      Membership Required
                    </span>
                    <%= if @current_membership == nil do %>
                      You need an active membership to access YSC events, cabin bookings, and all membership perks. Get started today!
                    <% else %>
                      Your membership has expired. Renew now to continue enjoying all YSC benefits including cabin access and exclusive events.
                    <% end %>
                  <% end %>
                </p>

                <.link
                  navigate={~p"/users/membership"}
                  class={[
                    "flex w-full items-center justify-center rounded px-6 py-4 text-sm font-black transition-all hover:scale-[1.02] active:scale-[0.98]",
                    if @active_membership? do
                      "bg-white text-zinc-900 hover:bg-blue-50"
                    else
                      "bg-white text-amber-900 hover:bg-amber-50 shadow-lg animate-pulse"
                    end
                  ]}
                >
                  <%= if @active_membership? do %>
                    Manage Membership
                  <% else %>
                    <%= if @current_membership == nil do %>
                      Get Membership Now
                    <% else %>
                      Renew Membership
                    <% end %>
                  <% end %>
                </.link>
              </div>

              <div class="absolute right-[-10%] bottom-[-10%] z-0 opacity-10 rotate-12">
                <.icon name="hero-identification" class="w-40 h-40" />
              </div>
            </div>

            <%!-- Latest Updates Section --%>
            <section>
              <h3 class="text-sm font-bold text-zinc-400 uppercase tracking-widest mb-6">
                Latest Updates
              </h3>
              <div class="space-y-6">
                <%= for post <- Enum.take(@latest_news, 3) do %>
                  <.link
                    navigate={~p"/posts/#{post.url_name}"}
                    class="flex gap-4 group"
                  >
                    <div class="w-16 h-16 rounded-lg bg-zinc-200 overflow-hidden flex-shrink-0">
                      <div class="relative w-full h-full">
                        <canvas
                          id={"blur-hash-sidebar-#{post.id}"}
                          src={get_blur_hash(post.featured_image)}
                          class="absolute inset-0 z-0 w-full h-full object-cover"
                          phx-hook="BlurHashCanvas"
                        >
                        </canvas>
                        <img
                          src={thumbnail_image_url(post.featured_image)}
                          id={"image-sidebar-#{post.id}"}
                          loading="lazy"
                          phx-hook="BlurHashImage"
                          class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out w-full h-full object-cover group-hover:scale-110 transition-transform"
                          alt={
                            if post.featured_image,
                              do:
                                post.featured_image.alt_text ||
                                  post.featured_image.title ||
                                  post.title ||
                                  "News article image",
                              else: "News article image"
                          }
                        />
                      </div>
                    </div>
                    <div>
                      <p class="text-[10px] font-bold text-blue-600 mb-1">
                        <%= format_post_date(post.published_on) %>
                      </p>
                      <h4 class="text-sm font-bold text-zinc-900 group-hover:text-blue-600 transition-colors">
                        <%= post.title %>
                      </h4>
                      <p class="text-xs text-zinc-500 line-clamp-1">
                        <%= preview_text_plain(post) %>
                      </p>
                    </div>
                  </.link>
                <% end %>
              </div>
            </section>
          </aside>
        </div>

        <%!-- Community Events Section --%>
        <div class="mt-16 space-y-12">
          <%!-- Upcoming Events --%>
          <div>
            <div class="flex items-center justify-between mb-8">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
                  <.icon name="hero-calendar-days" class="w-5 h-5 text-blue-600" />
                </div>
                <h2 class="text-2xl font-black text-zinc-900">Upcoming Events</h2>
              </div>
              <.link
                navigate={~p"/events"}
                class="text-sm font-bold text-blue-600 hover:text-blue-700 transition-colors"
              >
                View all events →
              </.link>
            </div>

            <%!-- Loading skeleton for events --%>
            <div
              :if={!@async_data_loaded}
              class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8"
            >
              <%= for _i <- 1..3 do %>
                <div class="bg-white rounded-xl shadow-sm border border-zinc-100 overflow-hidden animate-pulse">
                  <div class="h-48 bg-zinc-200"></div>
                  <div class="p-6 space-y-3">
                    <div class="h-4 bg-zinc-200 rounded w-1/4"></div>
                    <div class="h-6 bg-zinc-200 rounded w-3/4"></div>
                    <div class="h-4 bg-zinc-200 rounded w-1/2"></div>
                  </div>
                </div>
              <% end %>
            </div>

            <div
              :if={@async_data_loaded && Enum.empty?(@upcoming_events)}
              class="bg-white rounded shadow-lg p-12 text-center border border-zinc-200"
            >
              <div class="w-12 h-12 bg-zinc-100 rounded-full flex items-center justify-center mx-auto mb-3">
                <.icon name="hero-calendar" class="w-6 h-6 text-zinc-400" />
              </div>
              <h3 class="text-sm font-black text-zinc-900 mb-1">
                No upcoming events
              </h3>
              <p class="text-xs text-zinc-500">
                Check back later for new community events
              </p>
            </div>

            <div
              :if={@async_data_loaded && !Enum.empty?(@upcoming_events)}
              class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8"
            >
              <%= for event <- Enum.take(@upcoming_events, 3) do %>
                <.event_card
                  event={event}
                  sold_out={event_sold_out?(event)}
                  selling_fast={Map.get(event, :selling_fast, false)}
                />
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <%!-- White Buffer Zone with Gradient Transition --%>
      <div class="h-32 bg-gradient-to-b from-transparent to-white"></div>
    </main>
    """
  end

  # Helper functions

  defp get_membership_description(nil, _is_sub_account, _primary_user) do
    "You need an active membership to access YSC events and benefits."
  end

  defp get_membership_description(membership, is_sub_account, primary_user) do
    plan_type = YscWeb.UserAuth.get_membership_plan_type(membership)
    renewal_date = YscWeb.UserAuth.get_membership_renewal_date(membership)

    scheduled_for_cancellation? =
      membership_scheduled_for_cancellation?(membership)

    case plan_type do
      :lifetime ->
        if is_sub_account do
          "You are a lifetime member through #{if primary_user, do: "#{primary_user.first_name} #{primary_user.last_name}", else: "the primary account"}. Enjoy full access to all club properties and events forever."
        else
          "You are a lifetime member. Enjoy full access to all club properties and events forever."
        end

      plan_id when not is_nil(plan_id) ->
        # Extract membership type name (e.g., "Single" or "Family" from :single_membership or :family_membership)
        membership_type =
          plan_id
          |> Atom.to_string()
          |> String.split("_")
          |> List.first()
          |> String.capitalize()

        if is_sub_account do
          "You have access to a #{membership_type} membership through #{if primary_user, do: "#{primary_user.first_name} #{primary_user.last_name}", else: "the primary account"}. Your membership benefits are shared from the primary account."
        else
          cond do
            scheduled_for_cancellation? && renewal_date ->
              "Your #{membership_type} membership is scheduled for cancellation. You are still an active member until #{Timex.format!(renewal_date, "{Mshort} {D}, {YYYY}")}. Your membership will not automatically renew."

            renewal_date ->
              "You have an active #{membership_type} membership. Your membership will renew on #{Timex.format!(renewal_date, "{Mshort} {D}, {YYYY}")}."

            true ->
              "You have an active #{membership_type} membership."
          end
        end

      _ ->
        "You have an active membership with access to all club properties and events."
    end
  end

  defp membership_scheduled_for_cancellation?(%{type: :lifetime}), do: false

  defp membership_scheduled_for_cancellation?(%{subscription: subscription})
       when is_map(subscription) do
    Ysc.Subscriptions.scheduled_for_cancellation?(subscription)
  end

  defp membership_scheduled_for_cancellation?(subscription)
       when is_struct(subscription) do
    Ysc.Subscriptions.scheduled_for_cancellation?(subscription)
  end

  defp membership_scheduled_for_cancellation?(_), do: false

  defp get_upcoming_tickets(user_id, event_limit \\ 10) do
    # Get all confirmed tickets for the user
    tickets = Events.list_tickets_for_user(user_id)

    # Filter for upcoming events only and confirmed tickets
    # Use PST timezone for comparison
    now_pst = DateTime.now!("America/Los_Angeles")

    upcoming_tickets =
      tickets
      |> Enum.filter(fn ticket ->
        ticket.status == :confirmed and
          case ticket.event do
            %{start_date: start_date} when not is_nil(start_date) ->
              # Convert event start_date to PST for comparison
              start_date_pst =
                case start_date do
                  %DateTime{} = dt ->
                    DateTime.shift_zone!(dt, "America/Los_Angeles")

                  %Date{} = d ->
                    # For Date-only, create DateTime at midnight PST
                    DateTime.new!(d, ~T[00:00:00], "America/Los_Angeles")

                  _ ->
                    nil
                end

              if start_date_pst do
                DateTime.compare(start_date_pst, now_pst) == :gt
              else
                false
              end

            _ ->
              false
          end
      end)

    # Group by event FIRST to ensure we show all events with tickets
    # Then limit by number of unique events, not number of tickets
    upcoming_tickets
    |> Enum.group_by(& &1.event.id)
    |> Enum.map(fn {_event_id, event_tickets} ->
      # Get the event from the first ticket (all tickets in group have same event)
      event = List.first(event_tickets).event
      # Get combined datetime for proper sorting (date + time)
      event_datetime = get_event_datetime_for_sorting(event)
      {event_datetime, event_tickets}
    end)
    |> Enum.sort_by(
      fn {event_datetime, _tickets} -> event_datetime end,
      {:asc, DateTime}
    )
    |> Enum.take(event_limit)
    |> Enum.flat_map(fn {_event_datetime, event_tickets} -> event_tickets end)
  end

  defp group_tickets_by_tier(tickets) do
    tickets
    |> Enum.group_by(& &1.ticket_tier.name)
    |> Enum.sort_by(fn {_tier_name, tickets} -> length(tickets) end, :desc)
  end

  # Helper function to get event datetime for sorting (combines date and time)
  # Returns a DateTime in PST timezone that can be used for sorting
  defp get_event_datetime_for_sorting(event) do
    case {event.start_date, event.start_time} do
      {%DateTime{} = date, %Time{} = time} ->
        # Convert UTC DateTime to PST, then get date and combine with time
        date_pst = DateTime.shift_zone!(date, "America/Los_Angeles")
        date_part = DateTime.to_date(date_pst)
        naive_datetime = NaiveDateTime.new!(date_part, time)
        DateTime.from_naive!(naive_datetime, "America/Los_Angeles")

      {date, time} when not is_nil(date) and not is_nil(time) ->
        # Handle DateTime or Date with time
        date_part =
          case date do
            %DateTime{} = dt ->
              # Convert UTC DateTime to PST, then get date
              dt_pst = DateTime.shift_zone!(dt, "America/Los_Angeles")
              DateTime.to_date(dt_pst)

            %Date{} = d ->
              d

            _ ->
              nil
          end

        if date_part do
          naive_datetime = NaiveDateTime.new!(date_part, time)
          DateTime.from_naive!(naive_datetime, "America/Los_Angeles")
        else
          # Fallback: use start_date only at midnight
          case event.start_date do
            %DateTime{} = dt ->
              DateTime.shift_zone!(dt, "America/Los_Angeles")

            %Date{} = d ->
              DateTime.new!(d, ~T[00:00:00], "America/Los_Angeles")

            _ ->
              # Ultimate fallback: use current time
              DateTime.now!("America/Los_Angeles")
          end
        end

      _ ->
        # Fallback to just the date if time is nil
        case event.start_date do
          %DateTime{} = dt ->
            # Convert UTC DateTime to PST
            DateTime.shift_zone!(dt, "America/Los_Angeles")

          %Date{} = d ->
            # For Date-only, create a DateTime at midnight PST
            DateTime.new!(d, ~T[00:00:00], "America/Los_Angeles")

          _ ->
            # Ultimate fallback: use current time
            DateTime.now!("America/Los_Angeles")
        end
    end
  end

  defp group_tickets_by_event_and_tier(tickets) do
    tickets
    |> Enum.group_by(& &1.event.id)
    |> Enum.map(fn {_event_id, event_tickets} ->
      event = List.first(event_tickets).event
      grouped_tiers = group_tickets_by_tier(event_tickets)
      {event, grouped_tiers}
    end)
    |> Enum.sort_by(
      fn {event, _tiers} ->
        get_event_datetime_for_sorting(event)
      end,
      {:asc, DateTime}
    )
  end

  defp get_future_active_bookings(user_id, limit \\ 10) do
    # Get today's date in PST timezone
    today_pst = DateTime.now!("America/Los_Angeles") |> DateTime.to_date()
    checkout_time = ~T[11:00:00]

    query =
      from b in Booking,
        where: b.user_id == ^user_id,
        where: b.status == :complete,
        where: b.checkout_date >= ^today_pst,
        order_by: [asc: b.checkin_date],
        limit: ^limit,
        preload: [:rooms]

    bookings = Ysc.Repo.all(query)

    # Filter out bookings that are past checkout time today (in PST)
    bookings
    |> Enum.filter(fn booking ->
      if Date.compare(booking.checkout_date, today_pst) == :eq do
        now_pst = DateTime.now!("America/Los_Angeles")

        checkout_datetime_pst =
          DateTime.new!(today_pst, checkout_time, "America/Los_Angeles")

        DateTime.compare(now_pst, checkout_datetime_pst) == :lt
      else
        true
      end
    end)
    |> Enum.take(limit)
  end

  defp format_property_name(:tahoe), do: "Lake Tahoe"
  defp format_property_name(:clear_lake), do: "Clear Lake"
  defp format_property_name(_), do: "Unknown"

  defp days_until_booking(booking) do
    # Get current time in PST timezone
    now_pst = DateTime.now!("America/Los_Angeles")
    today_pst = DateTime.to_date(now_pst)
    checkin_date = booking.checkin_date

    # Create check-in datetime at 15:00 (3:00 PM) PST on the check-in date
    checkin_datetime_pst =
      checkin_date
      |> DateTime.new!(~T[15:00:00], "America/Los_Angeles")

    case Date.compare(today_pst, checkin_date) do
      # Check-in date is in the past - booking has started
      :gt ->
        :started

      # Check-in is today - need to check if it's before or after 15:00
      :eq ->
        if DateTime.compare(now_pst, checkin_datetime_pst) == :lt do
          # Before 15:00 on check-in date
          0
        else
          # After 15:00 on check-in date - booking has started
          :started
        end

      # Check-in is in the future
      :lt ->
        # Calculate days difference using calendar days
        diff = Date.diff(checkin_date, today_pst)
        diff
    end
  end

  defp days_until_event(event) do
    # Get current time in PST timezone
    now_pst = DateTime.now!("America/Los_Angeles")

    # Combine the date and time properly, converting to PST
    event_datetime_pst =
      case {event.start_date, event.start_time} do
        {%DateTime{} = date, %Time{} = time} ->
          # Convert UTC DateTime to PST, then get date and combine with time
          date_pst = DateTime.shift_zone!(date, "America/Los_Angeles")
          date_part = DateTime.to_date(date_pst)
          naive_datetime = NaiveDateTime.new!(date_part, time)
          DateTime.from_naive!(naive_datetime, "America/Los_Angeles")

        {date, time} when not is_nil(date) and not is_nil(time) ->
          # Handle DateTime or Date with time
          date_part =
            case date do
              %DateTime{} = dt ->
                # Convert UTC DateTime to PST, then get date
                dt_pst = DateTime.shift_zone!(dt, "America/Los_Angeles")
                DateTime.to_date(dt_pst)

              %Date{} = d ->
                d

              _ ->
                nil
            end

          if date_part do
            naive_datetime = NaiveDateTime.new!(date_part, time)
            DateTime.from_naive!(naive_datetime, "America/Los_Angeles")
          else
            nil
          end

        _ ->
          # Fallback to just the date if time is nil
          case event.start_date do
            %DateTime{} = dt ->
              # Convert UTC DateTime to PST
              DateTime.shift_zone!(dt, "America/Los_Angeles")

            %Date{} = d ->
              # For Date-only, create a DateTime at midnight PST
              DateTime.new!(d, ~T[00:00:00], "America/Los_Angeles")

            _ ->
              nil
          end
      end

    case event_datetime_pst do
      nil ->
        0

      event_dt ->
        case DateTime.compare(now_pst, event_dt) do
          # Event is in the past
          :gt ->
            0

          _ ->
            # Calculate days difference using calendar days, not 24-hour periods
            # This ensures that an event tomorrow shows as "1 day left" even if it's less than 24 hours away
            event_date_only = DateTime.to_date(event_dt)
            now_date_only = DateTime.to_date(now_pst)
            diff = Date.diff(event_date_only, now_date_only)
            max(0, diff)
        end
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    # Parse URI to get current path and send to SwiftUI
    parsed_uri = URI.parse(uri)
    current_path = parsed_uri.path || "/"

    # Send current path to SwiftUI via push_event
    socket =
      socket
      |> Phoenix.LiveView.push_event("current_path", %{path: current_path})

    {:noreply, socket}
  end

  @impl true
  def handle_event("native_nav", %{"to" => to}, socket) do
    allowed =
      MapSet.new([
        "/",
        "/property-check-in",
        "/bookings/tahoe",
        "/bookings/tahoe/staying-with",
        "/bookings/clear-lake",
        "/cabin-rules"
      ])

    if MapSet.member?(allowed, to) do
      # Send push_event to notify SwiftUI of navigation
      socket =
        if to != "/" do
          socket
          |> Phoenix.LiveView.push_event("navigate_away_from_home", %{})
        else
          socket
          |> Phoenix.LiveView.push_event("navigate_to_home", %{})
        end

      {:noreply, push_navigate(socket, to: to)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("dismiss_passkey_prompt", _params, socket) do
    user = socket.assigns.current_user

    case Accounts.dismiss_passkey_prompt(user) do
      {:ok, _updated_user} ->
        {:noreply,
         socket
         |> assign(show_passkey_prompt: false)
         |> put_flash(:info, "We'll remind you about passkeys in 30 days.")}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("setup_passkey", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/users/settings/passkeys/new")}
  end

  def handle_event("subscribe_newsletter", params, socket) do
    email = params["email"]

    # Verify Turnstile for spam protection
    case Turnstile.verify(params, socket.assigns.remote_ip) do
      {:ok, _} ->
        subscribe_to_newsletter(email, socket)

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(
           newsletter_email: email,
           newsletter_error: "Please complete the verification to continue."
         )
         |> Turnstile.refresh()}
    end
  end

  defp subscribe_to_newsletter(email, socket) do
    # For unauthenticated users, only collect email with minimal metadata
    metadata = %{
      "source" => "public_signup",
      "signup_date" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    opts = [data: metadata]

    case Keila.subscribe_email(email, opts) do
      :ok ->
        {:noreply,
         socket
         |> assign(
           newsletter_email: email,
           newsletter_submitted: true,
           newsletter_error: nil
         )
         |> put_flash(:info, "Thank you for subscribing to our newsletter!")}

      {:error, :invalid_email} ->
        {:noreply,
         socket
         |> assign(
           newsletter_email: email,
           newsletter_error: "Please enter a valid email address."
         )}

      {:error, :not_configured} ->
        {:noreply,
         socket
         |> assign(
           newsletter_email: email,
           newsletter_error: "Newsletter subscription is currently unavailable."
         )}

      {:error, _error} ->
        {:noreply,
         socket
         |> assign(
           newsletter_email: email,
           newsletter_error: "Something went wrong. Please try again later."
         )}
    end
  end

  defp event_sold_out?(event) do
    # Get event ID (handle both structs and maps)
    event_id = Map.get(event, :id) || Map.get(event, "id")

    # Use preloaded ticket_tiers if available (from batch loading), otherwise fetch
    ticket_tiers =
      case Map.get(event, :ticket_tiers) do
        nil -> Events.list_ticket_tiers_for_event(event_id)
        tiers -> tiers
      end

    # Filter out donation tiers - donations don't count toward "sold out" status
    non_donation_tiers =
      Enum.filter(ticket_tiers, fn tier ->
        tier_type = Map.get(tier, :type) || Map.get(tier, "type")
        tier_type != "donation" && tier_type != :donation
      end)

    # If there are no non-donation tiers, event is not sold out
    if Enum.empty?(non_donation_tiers) do
      false
    else
      # Filter out pre-sale tiers (tiers that haven't started selling yet)
      # We want to check tiers that are on sale OR have ended their sale
      relevant_tiers =
        Enum.filter(non_donation_tiers, fn tier ->
          # Include tiers that are on sale OR have ended their sale
          # Exclude tiers that haven't started their sale yet (pre-sale)
          tier_on_sale?(tier) || tier_sale_ended?(tier)
        end)

      # If there are no relevant tiers (all are pre-sale), event is not sold out
      if Enum.empty?(relevant_tiers) do
        false
      else
        # Check if all relevant non-donation tiers are sold out
        # A tier is sold out if available == 0 (unlimited tiers never count as sold out)
        all_tiers_sold_out =
          Enum.all?(relevant_tiers, fn tier ->
            available = get_available_quantity(tier)
            available == 0
          end)

        # Also check event capacity if max_attendees is set
        # (Note: This includes all tickets including donations, but if capacity is reached,
        #  all regular tickets are effectively sold out even if some tiers show availability)
        event_at_capacity =
          case Map.get(event, :max_attendees) || Map.get(event, "max_attendees") do
            nil ->
              false

            _ ->
              # Use preloaded ticket_count if available, otherwise query
              case Map.get(event, :ticket_count) do
                nil ->
                  Tickets.event_at_capacity?(event)

                ticket_count ->
                  max_attendees =
                    Map.get(event, :max_attendees) ||
                      Map.get(event, "max_attendees")

                  ticket_count >= max_attendees
              end
          end

        all_tiers_sold_out || event_at_capacity
      end
    end
  end

  defp tier_on_sale?(ticket_tier) do
    # Use PST timezone for comparison
    now_pst = DateTime.now!("America/Los_Angeles")

    start_date =
      Map.get(ticket_tier, :start_date) || Map.get(ticket_tier, "start_date")

    end_date =
      Map.get(ticket_tier, :end_date) || Map.get(ticket_tier, "end_date")

    # Check if sale has started (convert to PST if needed)
    sale_started =
      case start_date do
        nil ->
          true

        sd when is_struct(sd, DateTime) ->
          start_date_pst = DateTime.shift_zone!(sd, "America/Los_Angeles")
          DateTime.compare(now_pst, start_date_pst) != :lt

        _ ->
          true
      end

    # Check if sale has ended (convert to PST if needed)
    sale_ended =
      case end_date do
        nil ->
          false

        ed when is_struct(ed, DateTime) ->
          end_date_pst = DateTime.shift_zone!(ed, "America/Los_Angeles")
          DateTime.compare(now_pst, end_date_pst) == :gt

        _ ->
          false
      end

    sale_started && !sale_ended
  end

  defp tier_sale_ended?(ticket_tier) do
    # Use PST timezone for comparison
    now_pst = DateTime.now!("America/Los_Angeles")

    end_date =
      Map.get(ticket_tier, :end_date) || Map.get(ticket_tier, "end_date")

    case end_date do
      nil ->
        false

      ed when is_struct(ed, DateTime) ->
        end_date_pst = DateTime.shift_zone!(ed, "America/Los_Angeles")
        DateTime.compare(now_pst, end_date_pst) == :gt

      _ ->
        false
    end
  end

  defp get_available_quantity(ticket_tier) do
    quantity =
      Map.get(ticket_tier, :quantity) || Map.get(ticket_tier, "quantity")

    sold_count =
      Map.get(ticket_tier, :sold_tickets_count) ||
        Map.get(ticket_tier, "sold_tickets_count") || 0

    case quantity do
      # Unlimited
      nil ->
        :unlimited

      0 ->
        :unlimited

      qty ->
        available = qty - sold_count
        max(0, available)
    end
  end

  # Helper functions for news posts
  defp preview_text_plain(%Post{preview_text: nil} = post) do
    Scrubber.scrub(post.raw_body, YscWeb.Scrubber.StripEverythingExceptText)
    |> String.replace(~r/<[^>]*>/, "")
    |> String.trim()
  end

  defp preview_text_plain(post) do
    post.preview_text
    |> String.replace(~r/<[^>]*>/, "")
    |> String.trim()
  end

  defp get_blur_hash(nil), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: nil}), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: blur_hash}), do: blur_hash

  defp format_event_time(event_start_date, %Time{} = time) do
    # Convert event date and time to PST for display
    date_part =
      case event_start_date do
        %DateTime{} = dt ->
          dt_pst = DateTime.shift_zone!(dt, "America/Los_Angeles")
          DateTime.to_date(dt_pst)

        %Date{} = d ->
          d

        _ ->
          # Get today's date in PST
          DateTime.now!("America/Los_Angeles") |> DateTime.to_date()
      end

    datetime_pst = DateTime.new!(date_part, time, "America/Los_Angeles")
    Timex.format!(datetime_pst, "{h12}:{m} {AM}")
  end

  defp format_event_time(event_start_date, start_time)
       when is_binary(start_time) do
    try do
      # Parse database time format (HH:MM:SS)
      [h, m, _s] = String.split(start_time, ":")
      hour = String.to_integer(h)
      minute = String.to_integer(m)
      time = Time.new!(hour, minute, 0)
      format_event_time(event_start_date, time)
    rescue
      _ -> start_time
    end
  end

  defp format_event_time(_, _), do: ""

  defp format_event_date(%DateTime{} = date) do
    # Convert UTC DateTime to PST, then format
    date_pst = DateTime.shift_zone!(date, "America/Los_Angeles")
    date_only = DateTime.to_date(date_pst)
    Timex.format!(date_only, "{Mshort} {D}")
  end

  defp format_event_date(%Date{} = date) do
    Timex.format!(date, "{Mshort} {D}")
  end

  defp format_event_date(_), do: ""

  defp format_event_date_long(%DateTime{} = date) do
    # Convert UTC DateTime to PST, then format
    date_pst = DateTime.shift_zone!(date, "America/Los_Angeles")
    date_only = DateTime.to_date(date_pst)
    Calendar.strftime(date_only, "%b %d, %Y")
  end

  defp format_event_date_long(%Date{} = date) do
    Calendar.strftime(date, "%b %d, %Y")
  end

  defp format_event_date_long(_), do: ""

  defp format_post_date(%Date{} = date) do
    Timex.format!(date, "{Mshort} {D}")
  end

  defp format_post_date(%DateTime{} = datetime) do
    # Convert UTC DateTime to PST, then format
    datetime_pst = DateTime.shift_zone!(datetime, "America/Los_Angeles")
    date_only = DateTime.to_date(datetime_pst)
    Timex.format!(date_only, "{Mshort} {D}")
  end

  defp format_post_date(_), do: ""

  defp format_booking_date(%Date{} = date) do
    Calendar.strftime(date, "%b %d")
  end

  defp days_since_inserted(%DateTime{} = inserted_at) do
    # Get current time in PST and convert inserted_at to PST
    now_pst = DateTime.now!("America/Los_Angeles")
    inserted_at_pst = DateTime.shift_zone!(inserted_at, "America/Los_Angeles")
    Timex.diff(now_pst, inserted_at_pst, :days)
  end

  defp days_since_inserted(_), do: 999

  defp event_image_url(nil), do: "/images/ysc_logo.png"

  defp event_image_url(%Image{optimized_image_path: nil} = image),
    do: image.raw_image_path || "/images/ysc_logo.png"

  defp event_image_url(%Image{optimized_image_path: optimized_path}),
    do: optimized_path

  defp event_image_url(_), do: "/images/ysc_logo.png"

  defp featured_image_url_for_news(nil), do: "/images/ysc_logo.png"

  defp featured_image_url_for_news(%Image{optimized_image_path: nil} = image),
    do: image.raw_image_path || "/images/ysc_logo.png"

  defp featured_image_url_for_news(%Image{
         optimized_image_path: optimized_path
       }),
       do: optimized_path

  defp featured_image_url_for_news(_), do: "/images/ysc_logo.png"

  defp reading_time_for_news(%Post{rendered_body: nil}), do: 1

  defp reading_time_for_news(%Post{rendered_body: rendered_body}) do
    word_count = String.split(rendered_body, ~r/\s+/, trim: true) |> length()
    # Average reading speed is 200 words per minute
    ceil(word_count / 200) |> max(1)
  end

  defp preview_text_for_news(%Post{preview_text: nil} = post) do
    if post.raw_body do
      post.raw_body
      |> Scrubber.scrub(YscWeb.Scrubber.StripEverythingExceptText)
      |> String.slice(0, 150)
      |> Kernel.<>("...")
    else
      ""
    end
  end

  defp preview_text_for_news(%Post{preview_text: preview_text}),
    do:
      preview_text
      |> Scrubber.scrub(YscWeb.Scrubber.StripEverythingExceptText)
      |> String.slice(0, 150)
      |> Kernel.<>("...")

  defp thumbnail_image_url(nil), do: "/images/ysc_logo.png"

  defp thumbnail_image_url(%Image{thumbnail_path: nil} = image),
    do: image.raw_image_path

  defp thumbnail_image_url(%Image{thumbnail_path: thumbnail_path}),
    do: thumbnail_path

  defp greeting_for_country(nil), do: "Hej"
  defp greeting_for_country("Sweden"), do: "Hej"
  defp greeting_for_country("SE"), do: "Hej"
  defp greeting_for_country("Norway"), do: "Hallo"
  defp greeting_for_country("NO"), do: "Hallo"
  defp greeting_for_country("Finland"), do: "Hei"
  defp greeting_for_country("FI"), do: "Hei"
  defp greeting_for_country("Denmark"), do: "Hej"
  defp greeting_for_country("DK"), do: "Hej"
  defp greeting_for_country("Iceland"), do: "Halló"
  defp greeting_for_country("IS"), do: "Halló"
  defp greeting_for_country(_), do: "Hej"
end
