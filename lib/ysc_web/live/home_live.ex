defmodule YscWeb.HomeLive do
  use YscWeb, :live_view

  require Ysc.Logging

  import YscWeb.Live.AsyncHelpers

  alias Ysc.{
    Accounts,
    Bookings,
    Events,
    PublicContentCache
  }

  alias Ysc.Events.EventHelpers

  alias Ysc.Accounts.{FamilyDisplay, UserProfileCache}
  alias Ysc.Bookings.Season
  alias Ysc.Posts.ReadingTime
  alias Ysc.GoogleWallet
  alias Ysc.Tickets.Display, as: TicketDisplay

  alias YscWeb.{
    DateDisplay,
    MembershipQr,
    NewsletterSubscribe,
    PlainText,
    TimeZone,
    WalletPlatform
  }

  @impl true
  def mount(_params, session, socket) do
    user = socket.assigns.current_user

    if user do
      # Logged-in user: use async loading for performance
      socket = mount_minimal_assigns(socket)

      just_logged_in =
        Map.get(session, "just_logged_in", false) ||
          Map.get(session, :just_logged_in, false)

      # Passkey prompt is resolved in `handle_async/3` with the same user load
      # as the rest of the dashboard (no extra mount-time query). Static HTML
      # stays free of passkey round-trips for typical visits.
      socket =
        assign(socket,
          just_logged_in: just_logged_in
        )

      if connected?(socket) do
        PublicContentCache.subscribe()
        {:ok, load_home_data_async(socket)}
      else
        {:ok, socket}
      end
    else
      # Guest user: load data synchronously for SEO
      # Search engines need to see content in the initial HTML response
      socket =
        mount_guest_with_data(
          socket,
          YscWeb.ClientIP.from_socket(socket, session)
        )

      socket =
        if connected?(socket) do
          PublicContentCache.subscribe()
          socket
        else
          socket
        end

      {:ok, socket}
    end
  end

  # Minimal assigns for fast initial static render (logged-in users only)
  defp mount_minimal_assigns(socket) do
    # Logged-in user: show skeleton UI while data loads
    assign(socket,
      page_title: "Home",
      meta_description:
        "Young Scandinavians Club — a social club in the San Francisco Bay Area celebrating Scandinavian heritage through events, cabin trips, and community.",
      # Will be populated after async load
      is_sub_account: false,
      primary_user: nil,
      other_family_members: [],
      upcoming_tickets: [],
      future_bookings: [],
      upcoming_events: [],
      latest_news: [],
      newsletter_email: "",
      newsletter_submitted: false,
      newsletter_error: nil,
      # Track async loading state
      async_data_loaded: false,
      membership_paused_by_board: nil,
      # Membership QR modal
      show_membership_qr: false,
      membership_qr_token: nil,
      membership_qr_details: nil,
      apple_wallet_membership_enabled?:
        Ysc.AppleWallet.configured?(:membership),
      google_wallet_membership_enabled?: GoogleWallet.configured?(:membership),
      google_wallet_membership_url: nil,
      wallet_platform: WalletPlatform.from_socket(socket),
      show_passkey_prompt: false,
      newsletter_subscribed: false
    )
  end

  # Guest user: load data synchronously for SEO-friendly initial render
  # Search engines and social media crawlers need to see actual content
  defp mount_guest_with_data(socket, remote_ip) do
    # Determine hero video and captions based on season (no DB query)
    {hero_video, hero_poster, hero_poster_srcset, hero_captions} =
      case Season.for_date(
             :tahoe,
             DateTime.now!("America/Los_Angeles") |> DateTime.to_date()
           ) do
        %{name: "Summer"} ->
          {~p"/video/clear_lake_hero.mp4",
           ~p"/images/clear_lake_hero_poster.webp",
           "#{~p"/images/clear_lake_hero_poster-1280.webp"} 1280w, #{~p"/images/clear_lake_hero_poster-1920.webp"} 1920w",
           ~p"/video/clear_lake_hero_captions.vtt"}

        _ ->
          {~p"/video/tahoe_hero.mp4", ~p"/images/tahoe_hero_poster.webp",
           "#{~p"/images/tahoe_hero_poster-1280.webp"} 1280w",
           ~p"/video/tahoe_hero_captions.vtt"}
      end

    # Load events and news in parallel for SEO (same HTML; less wall-clock on DB round-trips)
    %{
      guest_events: upcoming_events,
      guest_news: latest_news
    } =
      [
        {:guest_events,
         fn ->
           PublicContentCache.list_upcoming_events(3)
           |> Enum.reject(&(&1.state == :cancelled))
         end},
        {:guest_news, fn -> PublicContentCache.list_recent_posts(3) end}
      ]
      |> async_stream_with_repo(fn {key, fun} -> {key, fun.()} end,
        timeout: :infinity,
        max_concurrency: 2
      )
      |> Enum.reduce(%{}, fn {:ok, {key, value}}, acc ->
        Map.put(acc, key, value)
      end)

    assign(socket,
      page_title: "Home",
      meta_description:
        "Young Scandinavians Club — a social club in the San Francisco Bay Area celebrating Scandinavian heritage through events, cabin trips, and community.",
      upcoming_events: upcoming_events,
      latest_news: latest_news,
      hero_video: hero_video,
      hero_poster: hero_poster,
      hero_poster_srcset: hero_poster_srcset,
      hero_captions: hero_captions,
      newsletter_email: "",
      newsletter_first_name: "",
      newsletter_last_name: "",
      newsletter_submitted: false,
      newsletter_error: nil,
      remote_ip: remote_ip,
      tahoe_rate: cabin_rate_label(:tahoe),
      clear_lake_rate: cabin_rate_label(:clear_lake),
      # Data is already loaded
      async_data_loaded: true
    )
  end

  # Load all home page data asynchronously (logged-in users only)
  defp load_home_data_async(socket) do
    user = socket.assigns.current_user
    just_logged_in = socket.assigns.just_logged_in

    start_async(socket, :load_home_data, fn ->
      load_logged_in_user_data(user.id, user.email, just_logged_in)
    end)
  end

  # Background task to load logged-in user's home page data in parallel
  defp load_logged_in_user_data(user_id, email, just_logged_in) do
    tasks = [
      {:user_data,
       fn -> load_user_with_subscriptions(user_id, just_logged_in) end},
      {:tickets, fn -> get_upcoming_tickets(user_id) end},
      {:bookings,
       fn -> Bookings.list_upcoming_active_bookings_for_user(user_id) end},
      {:newsletter_subscribed, fn -> NewsletterSubscribe.subscribed?(email) end}
    ]

    tasks
    |> async_stream_with_repo(fn {key, fun} -> {key, fun.()} end,
      timeout: :infinity
    )
    |> Enum.reduce(%{}, fn {:ok, {key, value}}, acc ->
      Map.put(acc, key, value)
    end)
  end

  # Load user with subscriptions and virtual fields. When `just_logged_in`,
  # preloads passkeys once so `should_show_passkey_prompt?/1` does not query again.
  defp load_user_with_subscriptions(user_id, just_logged_in) do
    preloads =
      if just_logged_in do
        [:passkeys, subscriptions: :subscription_items]
      else
        [subscriptions: :subscription_items]
      end

    user_with_subs =
      UserProfileCache.get_user!(user_id, preloads)
      |> Accounts.User.populate_virtual_fields()

    is_sub_account = Accounts.sub_account?(user_with_subs)

    household = Accounts.list_household_dashboard_users(user_with_subs)

    membership_paused_by_board =
      Enum.find(household, fn member -> member.board_position != nil end)

    primary_user =
      if is_sub_account do
        Enum.find(household, &(&1.id == user_with_subs.primary_user_id))
      else
        nil
      end

    # MembershipCache already follows sub-accounts to the primary user.
    active_plan_type =
      Ysc.Accounts.MembershipCache.get_membership_plan_type(user_with_subs)

    # Only show family section for primary users with family/lifetime and linked members
    other_family_members =
      if active_plan_type in [:family, :lifetime] and not is_sub_account do
        Enum.reject(household, &(&1.id == user_with_subs.id))
      else
        []
      end

    show_passkey_prompt =
      just_logged_in && Accounts.should_show_passkey_prompt?(user_with_subs)

    {is_sub_account, primary_user, other_family_members,
     membership_paused_by_board, show_passkey_prompt}
  end

  @impl true
  def handle_async(:load_home_data, {:ok, results}, socket) do
    # Handle logged-in user async results
    {is_sub_account, primary_user, other_family_members,
     membership_paused_by_board, show_passkey_prompt} =
      Map.get(results, :user_data, {false, nil, [], nil, false})

    upcoming_tickets = Map.get(results, :tickets, [])
    future_bookings = Map.get(results, :bookings, [])
    newsletter_subscribed = Map.get(results, :newsletter_subscribed, false)

    socket =
      socket
      |> assign(
        is_sub_account: is_sub_account,
        primary_user: primary_user,
        other_family_members: other_family_members,
        membership_paused_by_board: membership_paused_by_board,
        upcoming_tickets: upcoming_tickets,
        future_bookings: future_bookings,
        show_passkey_prompt: show_passkey_prompt,
        newsletter_subscribed: newsletter_subscribed,
        async_data_loaded: true
      )
      |> assign_public_content_slices()

    {:noreply, socket}
  end

  def handle_async(:load_home_data, {:exit, reason}, socket) do
    Ysc.Logging.warning("Failed to load home data async: #{inspect(reason)}")
    # Mark as loaded to avoid infinite loading state
    {:noreply, assign(socket, :async_data_loaded, true)}
  end

  @impl true
  def handle_info({:public_content_cache_invalidated, domain, _version}, socket) do
    {:noreply, refresh_public_content(socket, domain)}
  end

  defp assign_public_content_slices(socket) do
    assign(socket,
      upcoming_events: list_home_upcoming_events(),
      latest_news: PublicContentCache.list_recent_posts(3)
    )
  end

  defp refresh_public_content(socket, :posts) do
    assign(socket, latest_news: PublicContentCache.list_recent_posts(3))
  end

  defp refresh_public_content(socket, :events) do
    assign(socket, upcoming_events: list_home_upcoming_events())
  end

  defp refresh_public_content(socket, _) do
    assign_public_content_slices(socket)
  end

  defp list_home_upcoming_events do
    PublicContentCache.list_upcoming_events(4)
    |> Enum.reject(&(&1.state == :cancelled))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div :if={@current_user == nil}>
      <.hero
        video={@hero_video}
        poster={@hero_poster}
        poster_srcset={@hero_poster_srcset}
        captions={@hero_captions}
        height="85vh"
        overlay_opacity="bg-linear-to-b from-black/30 via-black/40 to-black/60"
      >
        <div class="mt-12 w-full max-w-4xl flex flex-col items-center">
          <span class={[
            "block font-serif italic text-lg sm:text-xl md:text-2xl mb-4 text-white/90 font-light tracking-wide",
            "[@media(max-height:600px)]:hidden"
          ]}>
            Celebrating {div(Date.utc_today().year - 1950, 5) * 5} Years
          </span>

          <h1 class="text-5xl sm:text-6xl md:text-7xl lg:text-8xl text-white drop-shadow-lg type-display">
            Young Scandinavians Club
          </h1>
        </div>

        <p class="mt-6 text-lg sm:text-xl md:text-2xl max-w-2xl mx-auto text-white/90 font-light leading-relaxed drop-shadow-md">
          Your Nordic home in the Bay Area. Connecting generations through nature, tradition, and lifelong friendships.
        </p>

        <div class="mt-10 flex flex-col sm:flex-row gap-4 justify-center items-center w-full max-w-md sm:max-w-none">
          <.link
            navigate={~p"/users/register"}
            class="group flex items-center justify-center px-8 py-4 text-base font-semibold text-zinc-900 bg-white rounded-sm hover:bg-zinc-100 active:bg-zinc-200 active:scale-[0.98] active:transition-none transition duration-200 w-full sm:w-auto shadow-lg focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-white focus-visible:ring-offset-2 focus-visible:ring-offset-transparent"
          >
            Apply for Membership
            <.icon
              name="hero-arrow-right"
              class="ml-2 w-4 h-4 group-hover:translate-x-1 transition-transform duration-300"
            />
          </.link>
          <.link
            navigate={~p"/events"}
            class="flex items-center justify-center px-8 py-4 text-base font-medium text-white border border-white/60 rounded-sm hover:bg-white/10 hover:border-white active:bg-white/20 active:scale-[0.98] active:transition-none transition duration-200 w-full sm:w-auto focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-white focus-visible:ring-offset-2 focus-visible:ring-offset-transparent"
          >
            Explore Our Events
          </.link>
        </div>
      </.hero>
    </div>

    <%!-- Community Narrative Section --%>
    <section
      :if={@current_user == nil}
      class="py-12 sm:py-16 lg:py-32 bg-white overflow-hidden"
    >
      <div class="max-w-(--breakpoint-xl) mx-auto px-4 sm:px-6">
        <div class="grid lg:grid-cols-12 gap-8 sm:gap-12 lg:gap-20 items-center">
          <div class="lg:col-span-5 min-w-0">
            <span
              id="home-community-eyebrow"
              class="text-blue-700 text-sm type-eyebrow"
            >
              Velkommen (Welcome)
            </span>
            <h2 class="mt-4 sm:mt-6 text-3xl sm:text-4xl lg:text-6xl text-zinc-900 wrap-break-word type-display">
              A home for Nordic spirits in the Bay.
            </h2>
            <p class="mt-6 sm:mt-8 text-base sm:text-lg text-zinc-600 leading-relaxed pr-0 sm:pr-4">
              The Young Scandinavians Club (YSC) is a welcoming community for Scandinavians and Scandinavian-Americans of all ages in the San Francisco Bay Area. We host a wide range of events across Northern California, offering members access to our scenic cabins in Clear Lake and Lake Tahoe.
            </p>
            <div class="mt-6 flex items-center gap-3 flex-wrap">
              <.flag country="fi-dk" class="h-8 w-12 rounded-sm shadow-xs" />
              <.flag country="fi-fi" class="h-8 w-12 rounded-sm shadow-xs" />
              <.flag country="fi-is" class="h-8 w-12 rounded-sm shadow-xs" />
              <.flag country="fi-no" class="h-8 w-12 rounded-sm shadow-xs" />
              <.flag country="fi-se" class="h-8 w-12 rounded-sm shadow-xs" />
            </div>
            <p class="mt-4 sm:mt-6 text-zinc-600 text-base">
              Those with <strong class="text-zinc-900">Danish</strong>, <strong class="text-zinc-900">Finnish</strong>, <strong class="text-zinc-900">Icelandic</strong>, <strong class="text-zinc-900">Norwegian</strong>, or
              <strong class="text-zinc-900">Swedish</strong>
              heritage may qualify for membership, with rates starting at just
              <strong class="text-blue-700">
                {YscWeb.MembershipPlanDisplay.price(:single)}
              </strong>
              per year.
            </p>
            <div class="mt-6 sm:mt-8">
              <.link
                navigate={~p"/users/register"}
                class="inline-flex items-center justify-center min-h-[48px] px-6 py-3 text-base font-bold text-white bg-blue-700 rounded-sm hover:bg-blue-800 transition-colors duration-200 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-blue-700 focus-visible:ring-offset-2"
              >
                Apply for Membership
                <.icon name="hero-arrow-right" class="ml-2 w-5 h-5" />
              </.link>
            </div>
          </div>

          <div class="lg:col-span-7 relative mt-10 sm:mt-12 lg:mt-0">
            <div class="relative z-10 rounded-2xl sm:rounded-3xl overflow-hidden shadow-2xl transform lg:rotate-2">
              <img
                src={~p"/images/ysc_75th.webp"}
                srcset={"#{~p"/images/ysc_75th-480.webp"} 480w, #{~p"/images/ysc_75th.webp"} 800w"}
                sizes="(min-width: 1280px) 690px, (min-width: 1024px) 55vw, 100vw"
                alt="YSC 75th Anniversary"
                class="w-full h-64 sm:h-80 lg:h-96 object-cover"
                loading="lazy"
                decoding="async"
              />
            </div>
            <div class="hidden lg:block absolute -bottom-12 -left-20 z-20 w-64 h-64 rounded-3xl overflow-hidden shadow-2xl border-8 border-white transform -rotate-6">
              <picture>
                <source srcset={~p"/images/ysc_group_photo.webp"} type="image/webp" />
                <img
                  src={~p"/images/ysc_group_photo.jpg"}
                  alt="YSC Group Photo"
                  class="w-full h-full object-cover"
                  loading="lazy"
                />
              </picture>
            </div>
          </div>
        </div>
      </div>
    </section>

    <%!-- Nordic Living Bento Grid Section --%>
    <section :if={@current_user == nil} class="py-12 sm:py-16 lg:py-24 bg-zinc-50">
      <div class="max-w-(--breakpoint-xl) mx-auto px-4 sm:px-6">
        <div class="text-center max-w-3xl mx-auto mb-8 sm:mb-12">
          <span class="text-blue-700 text-sm type-eyebrow">
            Nordic Living
          </span>
          <h2 class="mt-3 text-2xl sm:text-3xl lg:text-4xl text-zinc-900 wrap-break-word type-title">
            Don't Let the Name Fool You – All Ages Are Welcome!
          </h2>
          <p class="mt-4 text-base sm:text-lg text-zinc-600">
            We may be called the "Young" Scandinavians Club, but we're a community for all ages! With roughly 500 active members, we're a lively bunch who love to connect and have fun.
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 sm:gap-6">
          <%!-- Large featured cabin image --%>
          <div class="md:col-span-2 md:row-span-2 bg-white rounded-2xl overflow-hidden border border-zinc-100 hover:border-zinc-200 transition-colors duration-200 group">
            <div class="relative h-full min-h-[280px] sm:min-h-[340px] md:min-h-[400px]">
              <img
                src={~p"/images/clear_lake_midsummer.webp"}
                srcset={"#{~p"/images/clear_lake_midsummer-640.webp"} 640w, #{~p"/images/clear_lake_midsummer.webp"} 1024w"}
                sizes="(min-width: 1280px) 604px, (min-width: 768px) 50vw, 100vw"
                loading="lazy"
                decoding="async"
                alt="Midsummer at Clear Lake"
                class="w-full h-full object-cover group-hover:scale-[1.03] transition-transform duration-500"
              />
              <div class="absolute inset-0 bg-linear-to-t from-zinc-900/80 via-zinc-900/40 to-transparent flex flex-col justify-end p-4 sm:p-6">
                <h3 class="text-xl sm:text-2xl text-white mb-1.5 sm:mb-2 type-subhead">
                  All Ages Welcome
                </h3>
                <p class="text-zinc-200 text-sm sm:text-base">
                  Whether chasing toddlers at Midsummer or sharing stories by the fireplace, everyone is welcome.
                </p>
              </div>
            </div>
          </div>

          <%!-- Events card --%>
          <div class="md:col-span-2 bg-white rounded-2xl overflow-hidden border border-zinc-100 hover:border-zinc-200 transition-colors duration-200 group">
            <div class="relative aspect-video">
              <img
                src={~p"/images/ysc_bonfire_2024.webp"}
                srcset={"#{~p"/images/ysc_bonfire_2024-480.webp"} 480w, #{~p"/images/ysc_bonfire_2024.webp"} 800w"}
                sizes="(min-width: 1280px) 604px, (min-width: 768px) 50vw, 100vw"
                loading="lazy"
                decoding="async"
                alt="YSC Bonfire 2024"
                class="w-full h-full object-cover group-hover:scale-[1.03] transition-transform duration-500"
              />
              <div class="absolute inset-0 bg-linear-to-t from-zinc-900/80 via-zinc-900/40 to-transparent flex flex-col justify-end p-4 sm:p-6">
                <h3 class="text-lg sm:text-xl text-white mb-1.5 sm:mb-2 type-subhead">
                  Events Year-Round
                </h3>
                <p class="text-sm text-zinc-200">
                  From casual happy hours to formal dinners and holiday celebrations.
                </p>
              </div>
            </div>
          </div>

          <%!-- Cultural connection card --%>
          <div class="md:col-span-1 bg-white rounded-2xl overflow-hidden border border-zinc-100 hover:border-zinc-200 transition-colors duration-200 group">
            <div class="relative aspect-square">
              <%!-- Square card cropping a ~1.46:1 image, so it renders ~1.46x the card width --%>
              <img
                src={~p"/images/flags.webp"}
                srcset={"#{~p"/images/flags-480.webp"} 480w, #{~p"/images/flags-800.webp"} 800w, #{~p"/images/flags.webp"} 1200w"}
                sizes="(min-width: 1280px) 424px, (min-width: 768px) 36vw, 146vw"
                loading="lazy"
                decoding="async"
                alt="Nordic country flags"
                class="w-full h-full object-cover group-hover:scale-[1.03] transition-transform duration-500"
              />
              <div class="absolute inset-0 bg-linear-to-t from-zinc-900/80 via-zinc-900/40 to-transparent flex flex-col justify-end p-3 sm:p-4">
                <h3 class="text-base sm:text-lg text-white mb-1 type-subhead">
                  Cultural Connection
                </h3>
                <p class="text-sm text-zinc-200">
                  Stay connected to your roots through traditions like Midsummer, Nordic film screenings, and our annual heritage banquets.
                </p>
              </div>
            </div>
          </div>

          <%!-- Community stats card --%>
          <div class="md:col-span-1 bg-blue-900 rounded-2xl p-5 sm:p-6 flex flex-col justify-center items-center text-center shadow-lg min-h-[180px] sm:min-h-0">
            <div class="text-3xl sm:text-4xl text-white mb-1.5 sm:mb-2 type-title">
              500+
            </div>
            <div class="text-sm text-blue-100 type-eyebrow">
              Active Members
            </div>
            <div class="mt-4 pt-4 border-t border-blue-700/30 w-full">
              <div class="text-2xl text-white mb-1 type-title">
                {div(Date.utc_today().year - 1950, 5) * 5}+
              </div>
              <div class="text-xs text-blue-100 type-eyebrow">
                Years of Community
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <%!-- Property Portfolio Section --%>
    <section
      :if={@current_user == nil}
      class="py-12 sm:py-16 lg:py-32 bg-white overflow-hidden"
    >
      <div class="max-w-(--breakpoint-xl) mx-auto px-4 sm:px-6">
        <div class="flex flex-col md:flex-row md:items-end justify-between gap-4 sm:gap-6 mb-12 sm:mb-20">
          <div class="max-w-2xl min-w-0">
            <span class="text-blue-700 text-sm type-eyebrow">
              Exclusive Retreats
            </span>
            <h2 class="mt-4 text-3xl sm:text-4xl lg:text-6xl text-zinc-900 wrap-break-word type-display">
              The Cabin Legacy.
            </h2>
          </div>
          <p class="text-zinc-500 text-base sm:text-lg lg:max-w-xs font-normal leading-relaxed">
            Membership unlocks year-round access to our two historic, member-run sanctuaries.
          </p>
        </div>

        <div class="space-y-20 sm:space-y-24 lg:space-y-32">
          <.cabin_showcase
            id="home-cabin-tahoe"
            location="Lake Tahoe, CA"
            title="The Alpine Retreat"
            navigate={~p"/bookings/tahoe"}
            cta="Learn More About Tahoe"
            image_src={~p"/images/tahoe/tahoe_cabin_main.webp"}
            image_srcset={"#{~p"/images/tahoe/tahoe_cabin_main-480.webp"} 480w, #{~p"/images/tahoe/tahoe_cabin_main-900.webp"} 900w, #{~p"/images/tahoe/tahoe_cabin_main.webp"} 1227w"}
            image_sizes="(min-width: 1280px) 700px, (min-width: 1024px) 55vw, 100vw"
            image_alt="Lake Tahoe Cabin"
          >
            Ski in winter, hike in summer, and relax year-round. Perfectly positioned for alpine adventures and cozy
            <em>hygge</em>
            evenings by the fire.
            <:feature>
              Minutes from world-class ski resorts & hiking trails
            </:feature>
            <:feature :if={@tahoe_rate}>
              Member-only rates: from <strong>{@tahoe_rate}</strong>
              per adult, per night
            </:feature>
          </.cabin_showcase>

          <.cabin_showcase
            id="home-cabin-clear-lake"
            location="Clear Lake, CA"
            title="The Waterfront Sanctuary"
            navigate={~p"/bookings/clear-lake"}
            cta="Learn More About Clear Lake"
            image_src={~p"/images/clear_lake/clear_lake_dock.webp"}
            image_srcset={"#{~p"/images/clear_lake/clear_lake_dock-480.webp"} 480w, #{~p"/images/clear_lake/clear_lake_dock-900.webp"} 900w, #{~p"/images/clear_lake/clear_lake_dock.webp"} 1280w"}
            image_sizes="(min-width: 1280px) 700px, (min-width: 1024px) 55vw, 100vw"
            image_alt="Clear Lake Cabin"
            accent={:emerald}
            image_side={:left}
          >
            Our social heart since 1963. Swim, boat, and unwind at California's largest natural lake. A sun-drenched escape from the city.
            <:feature>Private dock access for swimming & boating</:feature>
            <:feature :if={@clear_lake_rate}>
              Member-only rates: from <strong>{@clear_lake_rate}</strong>
              per guest, per night
            </:feature>
          </.cabin_showcase>
        </div>
      </div>
    </section>

    <%!-- Happening Now Bar --%>
    <div
      :if={@current_user == nil && length(@upcoming_events) > 0}
      id="happening-soon-bar"
      class="bg-blue-900 text-white py-4 border-b border-blue-800/30 overflow-hidden"
    >
      <div class="max-w-(--breakpoint-xl) mx-auto px-4 sm:px-6">
        <div class="flex flex-col sm:flex-row items-center justify-between gap-4">
          <div class="flex items-center gap-3 flex-wrap">
            <div class="flex items-center gap-2">
              <div class="w-2 h-2 bg-green-400 rounded-full"></div>
              <span class="text-sm type-eyebrow">
                Happening Soon
              </span>
            </div>
            <span class="h-4 w-px bg-white/30"></span>
            <.link
              navigate={~p"/events/#{List.first(@upcoming_events).id}"}
              class="text-sm font-bold hover:text-blue-100 transition-colors line-clamp-1"
            >
              {List.first(@upcoming_events).title} →
            </.link>
          </div>
          <div class="flex items-center gap-4">
            <.link
              navigate={~p"/events"}
              class="text-xs hover:text-blue-100 transition-colors type-eyebrow"
            >
              View Events
            </.link>
          </div>
        </div>
      </div>
    </div>

    <%!-- Upcoming Events Section --%>
    <section
      :if={@current_user == nil && length(@upcoming_events) > 0}
      class="py-16 sm:py-20 lg:py-32 bg-zinc-900 relative overflow-hidden"
    >
      <div class="max-w-(--breakpoint-xl) mx-auto px-4 sm:px-6 relative z-10">
        <div class="flex flex-col md:flex-row md:items-end justify-between gap-4 sm:gap-6 mb-10 sm:mb-16">
          <div class="min-w-0">
            <span class="text-blue-300 text-sm type-eyebrow">
              Upcoming Events
            </span>
            <h2 class="mt-4 text-3xl sm:text-4xl lg:text-6xl text-white wrap-break-word type-display">
              The Pulse of the Club.
            </h2>
          </div>
          <.link
            navigate={~p"/events"}
            class="group flex items-center gap-2 text-white font-bold hover:text-blue-300 transition-colors duration-150"
          >
            View full calendar
            <.icon
              name="hero-arrow-right"
              class="w-5 h-5 group-hover:translate-x-1 transition-transform"
            />
          </.link>
        </div>

        <div class="flex flex-wrap justify-center gap-6 sm:gap-8 lg:gap-10">
          <%= for event <- @upcoming_events do %>
            <div class="group flex flex-col bg-white/5 rounded-2xl sm:rounded-[2.5rem] border border-white/10 hover:border-blue-700/40 transition duration-500 overflow-hidden shadow-2xl w-full md:max-w-md lg:max-w-[calc(33.333%-2rem)]">
              <.link
                navigate={~p"/events/#{event.id}"}
                class="block relative aspect-16/11 overflow-hidden"
              >
                <.live_component
                  id={"home-event-image-#{event.id}"}
                  module={YscWeb.Components.Image}
                  image={event.image}
                  aspect_class="h-full"
                  preferred_type={:optimized}
                />
                <div class="absolute top-6 left-6 flex gap-2 z-2 flex-wrap">
                  <%= if days_since_inserted(event.inserted_at) <= 7 do %>
                    <span class="px-3 py-1 bg-zinc-700 text-white text-xs rounded-sm shadow-lg type-eyebrow">
                      Just Added
                    </span>
                  <% end %>
                  <%= if EventHelpers.event_sold_out?(event) do %>
                    <span class="px-3 py-1 bg-zinc-100 text-zinc-600 text-xs rounded-sm shadow-lg type-eyebrow">
                      Sold Out
                    </span>
                  <% end %>
                </div>
                <div class="absolute bottom-4 right-4 z-2">
                  <span class="bg-zinc-900/85 px-4 py-2 rounded-xl text-white text-xs font-semibold ring-1 ring-white/10 tracking-widest">
                    {event.pricing_info.display_text}
                  </span>
                </div>
                <div class="absolute inset-0 bg-linear-to-t from-zinc-900 via-transparent to-transparent opacity-60">
                </div>
              </.link>

              <div class="p-6 sm:p-8 flex flex-col flex-1">
                <div class="flex items-center gap-3 mb-3 sm:mb-4">
                  <span class="text-blue-300 text-sm type-eyebrow">
                    {DateDisplay.format_date_short(event.start_date)}
                  </span>
                  <span class="w-1.5 h-1.5 bg-white/20 rounded-full"></span>
                  <%= if event.start_time && event.start_time != "" do %>
                    <span class="text-zinc-300 text-sm type-eyebrow">
                      {format_event_time(event.start_date, event.start_time)}
                    </span>
                  <% end %>
                </div>
                <.link navigate={~p"/events/#{event.id}"} class="block">
                  <h3 class="text-xl sm:text-2xl text-white group-hover:text-blue-300 transition-colors type-subhead">
                    {event.title}
                  </h3>
                </.link>
                <%= if description_preview = PlainText.normalize_preview(event.description) do %>
                  <p class="text-zinc-400 mt-3 sm:mt-4 line-clamp-2 text-sm leading-relaxed">
                    {description_preview}
                  </p>
                <% end %>

                <div class="mt-auto pt-6 sm:pt-8 flex justify-between items-center border-t border-white/5">
                  <%= if event.location_name do %>
                    <span class="text-sm font-bold text-zinc-400 flex items-center gap-2">
                      <.icon name="hero-map-pin" class="w-4 h-4 text-blue-300" />
                      {event.location_name}
                    </span>
                  <% else %>
                    <span></span>
                  <% end %>
                  <.icon
                    name="hero-arrow-right"
                    class="w-5 h-5 text-zinc-500 group-hover:text-blue-300 group-hover:translate-x-1 transition duration-150"
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
      :if={@current_user == nil && length(@latest_news) > 0}
      class="py-16 sm:py-24 lg:py-32 bg-zinc-50 overflow-hidden"
    >
      <div class="max-w-(--breakpoint-xl) mx-auto px-4 sm:px-6">
        <div class="flex flex-col md:flex-row md:items-end justify-between gap-4 sm:gap-6 mb-12 sm:mb-20 border-b border-zinc-200 pb-8 sm:pb-10">
          <div class="max-w-2xl min-w-0">
            <span class="text-blue-700 text-sm type-eyebrow">
              Club News
            </span>
            <h2 class="mt-4 text-3xl sm:text-4xl lg:text-6xl text-zinc-900 wrap-break-word type-display">
              Stay Informed.
            </h2>
          </div>
          <p class="text-zinc-500 text-base sm:text-lg font-normal lg:max-w-xs">
            Member updates, seasonal news, and club stories.
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-8 sm:gap-12 lg:gap-16">
          <%= for {post, index} <- Enum.with_index(@latest_news) do %>
            <.link
              navigate={~p"/posts/#{post.url_name}"}
              class={[
                "group block transition duration-500",
                if(rem(index, 2) == 1, do: "md:mt-20", else: "")
              ]}
            >
              <div class="relative overflow-hidden rounded-2xl sm:rounded-[2.5rem] mb-6 sm:mb-8 aspect-square border border-zinc-100">
                <.live_component
                  id={"home-news-image-#{post.id}"}
                  module={YscWeb.Components.Image}
                  image={post.featured_image}
                  aspect_class="h-full"
                  preferred_type={:optimized}
                />
              </div>
              <time
                id={"home-news-reading-time-#{post.id}"}
                class="text-xs text-blue-700 type-eyebrow"
              >
                {DateDisplay.format_date_short_in_zone(
                  post.published_on,
                  @timezone
                )} · {ReadingTime.minutes(post)} min read
              </time>
              <h3 class="text-2xl text-zinc-900 mt-3 group-hover:text-blue-700 transition-colors type-subhead">
                {post.title}
              </h3>
              <%= if post.preview_text || post.rendered_body do %>
                <p class="text-zinc-500 mt-4 text-sm leading-relaxed line-clamp-2 whitespace-pre-line italic">
                  {preview_text_for_news(post)}
                </p>
              <% end %>
            </.link>
          <% end %>
        </div>
      </div>
    </section>

    <%!-- Membership Section --%>
    <section
      :if={@current_user == nil}
      id="membership-section"
      class="relative py-16 sm:py-24 bg-blue-900 overflow-hidden isolate"
    >
      <div class="absolute inset-0 -z-10 bg-[radial-gradient(ellipse_at_top_right,var(--tw-gradient-stops))] from-blue-700/30 via-blue-900 to-gray-900">
      </div>

      <div class="max-w-(--breakpoint-xl) mx-auto px-4 sm:px-6 lg:px-8">
        <div class="max-w-2xl mx-auto text-center">
          <h2
            id="membership-heading"
            class="text-3xl sm:text-4xl text-white type-title"
          >
            Membership
          </h2>
          <p class="mt-4 text-lg sm:text-xl text-blue-100 leading-relaxed">
            Cabins, events, and community — same access for everyone. Choose who is covered.
          </p>
        </div>

        <dl class="mt-12 grid gap-6 sm:grid-cols-2 lg:max-w-4xl mx-auto text-left">
          <div
            id="membership-single"
            class="p-8 rounded-lg bg-blue-800 border border-transparent transition duration-300 ease-out hover:-translate-y-0.5 hover:bg-blue-700 hover:shadow-xl hover:border-blue-400/20 cursor-default"
          >
            <dt>
              <span class="block text-lg font-medium text-blue-200">Single</span>
              <span class="block mt-2 text-3xl text-white type-title">
                {YscWeb.MembershipPlanDisplay.price(:single)}<span class="text-lg font-normal text-blue-200">/year</span>
              </span>
            </dt>
            <dd class="mt-4 text-base text-blue-100 leading-relaxed">
              Just you
            </dd>
          </div>

          <div
            id="membership-family"
            class="p-8 rounded-lg bg-blue-800 border border-transparent transition duration-300 ease-out hover:-translate-y-0.5 hover:bg-blue-700 hover:shadow-xl hover:border-blue-400/20 cursor-default"
          >
            <dt>
              <span class="block text-lg font-medium text-blue-200">Family</span>
              <span class="block mt-2 text-3xl text-white type-title">
                {YscWeb.MembershipPlanDisplay.price(:family)}<span class="text-lg font-normal text-blue-200">/year</span>
              </span>
            </dt>
            <dd class="mt-4 text-base text-blue-100 leading-relaxed">
              You, your spouse or partner, and children under 18
            </dd>
          </div>
        </dl>

        <p
          id="membership-apply-note"
          class="mt-8 text-center text-sm text-blue-100"
        >
          You'll check your eligibility on the first step. Nothing is charged until the board approves your application.
        </p>

        <div class="mt-6 flex justify-center">
          <.link
            id="membership-apply-link"
            navigate={~p"/users/register"}
            class="group inline-flex items-center justify-center min-h-[48px] px-8 py-3.5 text-base font-bold text-blue-900 bg-white rounded-sm hover:bg-blue-50 transition-colors duration-200 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-white focus-visible:ring-offset-2 focus-visible:ring-offset-blue-900"
          >
            Apply for Membership
            <.icon
              name="hero-arrow-right"
              class="ml-2 w-5 h-5 group-hover:translate-x-1 transition-transform duration-300"
            />
          </.link>
        </div>
      </div>
    </section>

    <%!-- Heritage Pride Footer --%>
    <div
      :if={@current_user == nil}
      class="flex justify-center gap-6 py-10 opacity-30 grayscale hover:grayscale-0 transition"
    >
      <.flag country="fi-dk" class="h-8 w-12 rounded-xs" />
      <.flag country="fi-fi" class="h-8 w-12 rounded-xs" />
      <.flag country="fi-is" class="h-8 w-12 rounded-xs" />
      <.flag country="fi-no" class="h-8 w-12 rounded-xs" />
      <.flag country="fi-se" class="h-8 w-12 rounded-xs" />
    </div>

    <%!-- Newsletter Section --%>
    <section
      :if={@current_user == nil}
      class="py-12 sm:py-16 lg:py-24 overflow-hidden"
    >
      <div class="max-w-(--breakpoint-xl) mx-auto px-4 sm:px-6">
        <div class="max-w-2xl mx-auto text-center">
          <h2
            id="newsletter-heading"
            class="text-2xl sm:text-3xl lg:text-4xl text-zinc-900 wrap-break-word type-title"
          >
            Stay in the Loop
          </h2>
          <p
            id="newsletter-description"
            class="mt-3 sm:mt-4 text-base sm:text-lg text-zinc-600"
          >
            Sign up for our newsletter to receive updates about YSC and all the fun events we're arranging.
          </p>

          <.newsletter_subscribe_form
            id="home-newsletter-form"
            email={@newsletter_email}
            submitted={@newsletter_submitted}
            error={@newsletter_error}
            class="mt-8 max-w-lg mx-auto"
            labelledby="newsletter-heading"
            describedby="newsletter-description"
          >
            <:footer>
              <p class="mt-4 text-sm text-zinc-600">
                We don't spam! Read our
                <.link
                  navigate={~p"/privacy-policy"}
                  class="font-medium text-blue-700 underline hover:text-blue-800"
                >
                  privacy policy
                </.link>
                for more info.
              </p>
            </:footer>
          </.newsletter_subscribe_form>
        </div>
      </div>
    </section>

    <%!-- Logged-in User Dashboard --%>
    <div
      :if={@current_user != nil}
      id="member-dashboard"
      class="flex-1 w-full bg-zinc-50/40 min-h-screen pb-24 -mb-8"
    >
      <%!-- Passkey Setup Prompt Banner.
           Hidden until the async user load confirms the prompt should be shown,
           then fades in. No placeholder: most reloads never show the prompt. --%>
      <div
        :if={@show_passkey_prompt}
        id="passkey-prompt-banner"
        class="bg-blue-50 border-b border-blue-100 shadow-xs min-h-19 sm:min-h-21"
        phx-mounted={
          JS.transition(
            {"transition ease-out duration-300", "opacity-0", "opacity-100"}
          )
        }
        phx-remove={
          JS.transition(
            {"transition ease-in duration-200", "opacity-100", "opacity-0"}
          )
        }
      >
        <div class="max-w-(--breakpoint-xl) mx-auto px-4 py-3 sm:py-3.5">
          <div class="flex items-start sm:items-center justify-between gap-x-4">
            <div class="flex items-start sm:items-center gap-4 flex-1">
              <div class="hidden sm:flex shrink-0 h-10 w-10 items-center justify-center rounded-full bg-blue-100 ring-4 ring-blue-50">
                <.icon name="hero-bolt" class="h-6 w-6 text-blue-600" />
              </div>

              <div class="flex-1 min-w-0">
                <p class="text-sm font-semibold text-blue-900 leading-none sm:leading-6">
                  Sign in faster with Passkeys
                </p>
                <p class="mt-1 text-sm text-blue-800/80 leading-snug max-w-xl">
                  Use Face ID, Touch ID, or your device passcode instead of a password.
                </p>
              </div>
            </div>

            <div class="flex items-center gap-2 sm:gap-4">
              <.button
                phx-click="setup_passkey"
                class="py-1.5! px-4! whitespace-nowrap shadow-xs"
              >
                Set up passkey
              </.button>

              <.button
                id="home-dismiss-passkey-prompt-later"
                type="button"
                phx-click="dismiss_passkey_prompt"
                variant="outline"
                color="blue"
                class="hidden md:block min-h-0 border-0! bg-transparent! shadow-none! px-0 py-0 whitespace-nowrap text-sm font-medium text-blue-600! hover:bg-transparent! hover:text-blue-700! transition-colors duration-150 focus-visible:ring-1! focus-visible:ring-blue-400! focus-visible:ring-offset-0!"
              >
                Maybe later
              </.button>

              <button
                type="button"
                phx-click="dismiss_passkey_prompt"
                class="p-2 -mr-2 text-blue-400 hover:text-blue-600 transition-colors"
                aria-label="Dismiss"
              >
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Compact header with the quick-action bar on the right --%>
      <div class="bg-white border-b border-zinc-200">
        <div class="max-w-(--breakpoint-xl) mx-auto px-4 sm:px-6 py-8">
          <div class="flex flex-col lg:flex-row lg:items-end justify-between gap-6">
            <div class="space-y-1 min-w-0">
              <p class="text-blue-600 text-xs type-eyebrow">
                Member Dashboard
              </p>
              <h1 class="text-2xl sm:text-3xl lg:text-4xl text-zinc-900 wrap-break-word type-display">
                {greeting_for_country(@current_user.most_connected_country)}, {String.capitalize(
                  @current_user.first_name
                )}
              </h1>
            </div>

            <%!-- Unified quick-action bar: 1px gaps over a zinc backdrop draw the dividers --%>
            <div
              id="home-quick-actions"
              class="grid grid-cols-2 sm:grid-cols-4 gap-px bg-zinc-200 border border-zinc-200 rounded-xl overflow-hidden lg:min-w-xl"
            >
              <.quick_action_card
                id="home-quick-action-tahoe"
                navigate={~p"/bookings/tahoe"}
                icon="hero-home"
                tone={:blue}
                title="Lake Tahoe"
                subtitle="Book a stay"
              />
              <.quick_action_card
                id="home-quick-action-clear-lake"
                navigate={~p"/bookings/clear-lake"}
                icon="hero-sun"
                tone={:emerald}
                title="Clear Lake"
                subtitle="Book a stay"
              />
              <%= if @current_user && @current_user.role in [:admin, :volunteer] do %>
                <.quick_action_card
                  id="home-quick-action-expenses"
                  navigate={~p"/expensereports"}
                  icon="hero-receipt-refund"
                  tone={:yellow}
                  title="Expenses"
                  subtitle="View reports"
                />
              <% else %>
                <.quick_action_card
                  id="home-quick-action-events"
                  navigate={~p"/events"}
                  icon="hero-calendar-days"
                  tone={:blue}
                  title="Events"
                  subtitle="See what's on"
                />
              <% end %>
              <.quick_action_card
                id="home-quick-action-settings"
                navigate={~p"/users/settings"}
                icon="hero-cog-6-tooth"
                tone={:zinc}
                title="Account"
                subtitle="Settings & billing"
              />
            </div>
          </div>
        </div>
      </div>

      <%!-- Dashboard Content --%>
      <div class="max-w-(--breakpoint-xl) mx-auto px-4 sm:px-6 pt-10">
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-10">
          <div class="lg:col-span-8 space-y-10 min-w-0">
            <%!-- Reservations: cabin stays and event tickets in one place --%>
            <section id="home-reservations">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-lg text-zinc-900 type-subhead">
                  Your Reservations
                </h2>
                <.section_link navigate={~p"/users/payments"}>
                  All bookings & payments
                </.section_link>
              </div>

              <%!-- Loading skeleton matches the compact empty bar (avoids CLS) --%>
              <div
                :if={!@async_data_loaded}
                id="home-reservations-loading"
                class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 py-4 px-5 bg-white border border-zinc-200 rounded-lg"
                aria-hidden="true"
              >
                <.skeleton_block class="h-4 w-56 max-w-full rounded-sm" />
                <div class="flex flex-wrap items-center gap-x-5 gap-y-2">
                  <.skeleton_block class="h-4 w-24 rounded-sm" />
                  <.skeleton_block class="h-4 w-24 rounded-sm" />
                  <.skeleton_block class="h-4 w-24 rounded-sm" />
                </div>
              </div>

              <div
                :if={
                  @async_data_loaded && Enum.empty?(@future_bookings) &&
                    Enum.empty?(@upcoming_tickets)
                }
                id="home-reservations-empty"
                class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 py-4 px-5 bg-white border border-zinc-200 rounded-lg"
              >
                <p class="text-sm text-zinc-600">
                  No upcoming cabin stays or event tickets.
                </p>
                <div class="flex flex-wrap items-center gap-x-5 gap-y-1">
                  <.section_link navigate={~p"/bookings/tahoe"}>
                    Book Lake Tahoe
                    <.icon name="hero-arrow-right" class="w-3 h-3" />
                  </.section_link>
                  <.section_link navigate={~p"/bookings/clear-lake"}>
                    Book Clear Lake
                    <.icon name="hero-arrow-right" class="w-3 h-3" />
                  </.section_link>
                  <.section_link navigate={~p"/events"}>
                    Browse Events <.icon name="hero-arrow-right" class="w-3 h-3" />
                  </.section_link>
                </div>
              </div>

              <div
                :if={@async_data_loaded && !Enum.empty?(@future_bookings)}
                id="home-itinerary-list"
                class="space-y-3"
              >
                <.booking_card
                  :for={booking <- @future_bookings}
                  id={"home-itinerary-booking-#{booking.id}"}
                  booking={booking}
                />
              </div>

              <div
                :if={@async_data_loaded && !Enum.empty?(@upcoming_tickets)}
                id="home-tickets-list"
                class={["space-y-3", !Enum.empty?(@future_bookings) && "mt-3"]}
              >
                <%= for {event, grouped_tiers} <- group_tickets_by_event_and_tier(@upcoming_tickets) do %>
                  <% order_ids =
                    grouped_tiers
                    |> Enum.flat_map(fn {_tier_name, tickets} ->
                      Enum.map(tickets, fn t ->
                        t.ticket_order && t.ticket_order.id
                      end)
                    end)
                    |> Enum.filter(& &1)
                    |> Enum.uniq() %>
                  <% days_until_this_event = days_until_event(event) %>
                  <div
                    id={"home-ticket-#{event.id}"}
                    class="flex bg-white border border-zinc-200 rounded-xl overflow-hidden"
                  >
                    <%!-- Ticket stub: soft tint; solid only on the day of the event --%>
                    <div class={[
                      "flex flex-col items-center justify-center w-18 shrink-0 border-r-2 border-dashed px-2 py-4",
                      ticket_stub_class(days_until_this_event == 0)
                    ]}>
                      <span class="text-xs type-eyebrow opacity-80">
                        {ticket_stub_month(event)}
                      </span>
                      <span class="text-3xl type-display leading-none">
                        {ticket_stub_day(event)}
                      </span>
                      <.icon name="hero-ticket" class="w-4 h-4 mt-3 opacity-70" />
                    </div>
                    <div class="flex-1 min-w-0 p-5 flex flex-col md:flex-row md:items-center gap-4 md:gap-6">
                      <div class="flex-1 min-w-0">
                        <span class={[
                          "inline-block px-2 py-1 mb-2 text-xs font-bold rounded-sm",
                          case days_until_this_event do
                            0 -> "bg-amber-50 text-amber-700"
                            _ -> "bg-zinc-100 text-zinc-700"
                          end
                        ]}>
                          {DateDisplay.relative_days_phrase(days_until_this_event)}
                        </span>
                        <.link
                          navigate={~p"/events/#{event.id}"}
                          class="block group"
                        >
                          <h3 class="text-zinc-900 mb-1 group-hover:text-blue-600 transition-colors type-subhead">
                            {event.title}
                          </h3>
                        </.link>
                        <p class="text-xs text-zinc-500 flex items-center gap-1">
                          <.icon name="hero-calendar" class="w-3 h-3 shrink-0" />
                          {DateDisplay.format_datetime_display(event.start_date)}
                        </p>
                        <p
                          :if={event.location_name}
                          class="mt-1 text-xs text-zinc-500 flex items-center gap-1"
                        >
                          <.icon name="hero-map-pin" class="w-3 h-3 shrink-0" />
                          <span class="truncate">{event.location_name}</span>
                        </p>
                        <div class="mt-3 flex flex-wrap gap-1.5">
                          <%= for {tier_name, tickets} <- grouped_tiers do %>
                            <span class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-bold bg-zinc-100 text-zinc-600 rounded-full">
                              <span class="text-zinc-500">{length(tickets)}×</span>{tier_name}
                            </span>
                          <% end %>
                        </div>
                      </div>
                      <div class="flex flex-col items-start md:items-end gap-1 shrink-0 md:pl-6 md:border-l md:border-zinc-100">
                        <.button
                          navigate={~p"/events/#{event.id}/tickets/qr?return_to=/"}
                          color="blue"
                          variant={
                            if(days_until_this_event == 0,
                              do: "solid",
                              else: "outline"
                            )
                          }
                          class="py-1.5! whitespace-nowrap"
                        >
                          <.icon name="hero-qr-code" class="w-4 h-4" /> Show tickets
                        </.button>
                        <%= if length(order_ids) == 1 do %>
                          <.link
                            navigate={
                              ~p"/orders/#{List.first(order_ids)}/confirmation"
                            }
                            class="inline-flex items-center min-h-8 text-xs font-semibold text-zinc-500 hover:text-zinc-900 transition-colors duration-150 whitespace-nowrap"
                          >
                            View order & receipt
                          </.link>
                        <% else %>
                          <%= if length(order_ids) > 1 do %>
                            <.link
                              navigate={~p"/users/tickets"}
                              class="inline-flex items-center min-h-8 text-xs font-semibold text-zinc-500 hover:text-zinc-900 transition-colors duration-150 whitespace-nowrap"
                            >
                              View all tickets
                            </.link>
                          <% end %>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </section>

            <%!-- Upcoming Events --%>
            <section id="home-upcoming-events">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-lg text-zinc-900 type-subhead">
                  Upcoming Events
                </h2>
                <.section_link navigate={~p"/events"}>
                  View All Events
                </.section_link>
              </div>

              <%!-- Loading skeleton: the same card the section loads (up to four) --%>
              <div
                :if={!@async_data_loaded}
                id="home-upcoming-events-loading"
                class="grid grid-cols-1 md:grid-cols-2 gap-6"
                aria-hidden="true"
              >
                <.event_card_skeleton :for={_ <- 1..4} />
              </div>

              <div
                :if={@async_data_loaded && Enum.empty?(@upcoming_events)}
                id="home-upcoming-events-empty"
                class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 py-4 px-5 bg-white border border-zinc-200 rounded-lg"
              >
                <p class="text-sm text-zinc-600">
                  No upcoming events. Check back later for new community events.
                </p>
                <.section_link navigate={~p"/events"}>
                  Browse Events <.icon name="hero-arrow-right" class="w-3 h-3" />
                </.section_link>
              </div>

              <div
                :if={@async_data_loaded && !Enum.empty?(@upcoming_events)}
                class="grid grid-cols-1 md:grid-cols-2 gap-6"
              >
                <%= for event <- @upcoming_events do %>
                  <.event_card
                    event={event}
                    sold_out={EventHelpers.event_sold_out?(event)}
                    selling_fast={Map.get(event, :selling_fast, false)}
                  />
                <% end %>
              </div>
            </section>
          </div>

          <%!-- Sidebar --%>
          <aside class="lg:col-span-4 space-y-8 min-w-0">
            <%!-- Member pass --%>
            <div
              id="home-member-pass"
              class="bg-white border border-zinc-200 rounded-xl p-5 space-y-4"
            >
              <div class="flex items-center justify-between gap-3">
                <div class="inline-flex items-center gap-2 min-w-0">
                  <span
                    class={[
                      "w-2 h-2 rounded-full shrink-0",
                      cond do
                        @active_membership? -> "bg-emerald-500"
                        @current_user.state == :pending_approval -> "bg-sky-500"
                        true -> "bg-amber-500"
                      end
                    ]}
                    aria-hidden="true"
                  ></span>
                  <h2 class="text-xs text-zinc-900 type-eyebrow truncate">
                    <%= cond do %>
                      <% @current_user.state == :pending_approval -> %>
                        Application Under Review
                      <% @active_membership? -> %>
                        {YscWeb.UserAuth.get_membership_plan_display_name(
                          @current_membership
                        )}
                      <% true -> %>
                        Membership Required
                    <% end %>
                  </h2>
                </div>
                <.link
                  :if={@active_membership?}
                  id="home-membership-details-link"
                  navigate={~p"/users/membership"}
                  class="text-xs font-medium text-zinc-500 hover:text-zinc-900 underline underline-offset-4 transition-colors duration-150 shrink-0"
                >
                  Manage membership
                </.link>
              </div>

              <p class="text-sm text-zinc-600 leading-relaxed">
                <%= cond do %>
                  <% @active_membership? -> %>
                    <%= case membership_renewal_note(
                           @current_membership,
                           @is_sub_account || false,
                           @timezone
                         ) do %>
                      <% {:renews, date} -> %>
                        Auto-renews <strong
                          id="home-membership-renewal-date"
                          class="font-medium text-zinc-900"
                        >{date}</strong>.
                      <% {:ends, date} -> %>
                        Won't auto-renew. Active until <strong
                          id="home-membership-renewal-date"
                          class="font-medium text-zinc-900"
                        >{date}</strong>.
                      <% nil -> %>
                        {get_membership_description(
                          @current_membership,
                          @is_sub_account || false,
                          @primary_user,
                          @timezone
                        )}
                    <% end %>
                  <% @current_user.state == :pending_approval -> %>
                    <span class="block mb-1 font-semibold text-zinc-900">
                      Pending Approval
                    </span>
                    Your membership application has been submitted and is being reviewed by the board. We will email you when there is a decision. Cabin bookings and member-only tickets become available after you are approved and your membership dues are paid.
                  <% true -> %>
                    <%= if @current_membership == nil do %>
                      You need an active membership to access YSC events, cabin bookings, and all membership perks. Get started today!
                    <% else %>
                      Your membership has expired. Renew now to continue enjoying all YSC benefits, including cabin stays and exclusive events.
                    <% end %>
                <% end %>
              </p>

              <.button
                :if={@active_membership?}
                id="home-membership-qr-button"
                type="button"
                color="blue"
                phx-click="show_membership_qr"
                loading_text="Opening..."
                class="flex w-full"
              >
                <.icon name="hero-qr-code" class="w-5 h-5 shrink-0" />
                My Membership QR
              </.button>

              <.link
                :if={@current_user.state == :pending_approval}
                navigate={~p"/pending-review"}
                id="home-pending-review-status"
                class="flex w-full items-center justify-center rounded-md px-4 py-2.5 text-sm font-semibold bg-blue-700 text-white hover:bg-blue-800 transition-colors duration-150 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-blue-700 focus-visible:ring-offset-2"
              >
                <.icon name="hero-clock" class="w-4 h-4 mr-2 shrink-0" />
                View application status
              </.link>

              <.link
                :if={
                  !@active_membership? && @current_user.state != :pending_approval
                }
                id="home-membership-cta"
                navigate={~p"/users/membership"}
                class="flex w-full items-center justify-center rounded-md px-4 py-2.5 text-sm font-semibold bg-blue-700 text-white hover:bg-blue-800 transition-colors duration-150 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-blue-700 focus-visible:ring-offset-2"
              >
                <%= if @current_membership == nil do %>
                  Choose a membership
                <% else %>
                  Renew membership
                <% end %>
              </.link>
            </div>

            <.board_pause_notice
              :if={@active_membership? && @membership_paused_by_board != nil}
              board_member={@membership_paused_by_board}
              current_user={@current_user}
            />

            <%!-- Detects platform to show the correct wallet button(s) --%>
            <div
              id="wallet-platform-detector"
              phx-hook="WalletPlatform"
              class="hidden"
            >
            </div>

            <.membership_qr_modal
              :if={@show_membership_qr}
              id="membership-qr-modal"
              token={@membership_qr_token}
              details={@membership_qr_details}
              timezone={@timezone}
              apple_wallet_enabled?={@apple_wallet_membership_enabled?}
              google_wallet_enabled?={@google_wallet_membership_enabled?}
              google_wallet_url={@google_wallet_membership_url}
              wallet_platform={@wallet_platform}
            />

            <%!-- Latest Updates: sits directly beneath the member pass --%>
            <section
              :if={!@async_data_loaded || @latest_news != []}
              id="home-latest-updates"
            >
              <h2 class="text-sm text-zinc-500 mb-4 type-eyebrow">
                Latest Updates
              </h2>

              <%!-- Loading skeleton for news --%>
              <div
                :if={!@async_data_loaded}
                id="home-latest-updates-loading"
                class="space-y-5"
                aria-hidden="true"
              >
                <div :for={_ <- 1..3} class="flex gap-4">
                  <.skeleton_block class="w-20 h-14 rounded-md shrink-0" />
                  <div class="flex-1 space-y-2">
                    <.skeleton_block class="h-3 w-16 rounded-sm" />
                    <.skeleton_block class="h-4 w-full rounded-sm" />
                    <.skeleton_block class="h-4 w-2/3 rounded-sm" />
                  </div>
                </div>
              </div>

              <div
                :if={@async_data_loaded}
                class="space-y-5"
              >
                <%= for post <- Enum.take(@latest_news, 3) do %>
                  <.link
                    navigate={~p"/posts/#{post.url_name}"}
                    class="flex gap-4 group"
                  >
                    <div class="w-20 h-14 rounded-md bg-zinc-200 overflow-hidden shrink-0">
                      <.live_component
                        id={"sidebar-news-image-#{post.id}"}
                        module={YscWeb.Components.Image}
                        image={post.featured_image}
                        aspect_class="h-full"
                        preferred_type={:thumbnail}
                      />
                    </div>
                    <div class="min-w-0">
                      <p class="text-xs font-bold text-blue-600 mb-1">
                        {DateDisplay.format_date_short_in_zone(
                          post.published_on,
                          @timezone
                        )}
                      </p>
                      <h3 class="text-sm text-zinc-900 group-hover:text-blue-600 transition-colors type-subhead">
                        {post.title}
                      </h3>
                    </div>
                  </.link>
                <% end %>
              </div>
            </section>

            <%!-- Your Family Section (family/lifetime members with linked users) --%>
            <section
              :if={
                family_section_pending?(
                  @async_data_loaded,
                  @current_user,
                  @current_membership,
                  @active_membership?
                )
              }
              id="home-family-loading"
              aria-hidden="true"
            >
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-sm text-zinc-500 type-eyebrow">
                  Your Family
                </h2>
                <.skeleton_block class="h-4 w-24 rounded-sm" />
              </div>
              <div class="flex flex-wrap gap-x-3 gap-y-4">
                <div
                  :for={_ <- 1..2}
                  class="flex flex-col items-center w-16 text-center"
                >
                  <.skeleton_block class="w-12 h-12 rounded-full" />
                  <.skeleton_block class="mt-2 h-3 w-10 rounded-sm" />
                  <.skeleton_block class="mt-1 h-2.5 w-12 rounded-sm" />
                </div>
              </div>
            </section>

            <section
              :if={@async_data_loaded && @other_family_members != []}
              id="home-family"
            >
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-sm text-zinc-500 type-eyebrow">
                  Your Family
                </h2>
                <.section_link navigate={~p"/users/settings/family"}>
                  Manage Family
                </.section_link>
              </div>
              <div class="flex flex-wrap gap-x-3 gap-y-4">
                <%= for member <- @other_family_members do %>
                  <div
                    id={"home-family-member-#{member.id}"}
                    class="flex flex-col items-center w-16 text-center"
                    title={"#{member.first_name} #{member.last_name} · #{FamilyDisplay.relationship_label(member.family_relationship)}"}
                  >
                    <.user_avatar_image user={member} class="w-12 h-12" />
                    <span class="mt-1.5 text-xs font-semibold text-zinc-900 truncate w-full">
                      {member.first_name}
                    </span>
                    <span class="text-[11px] text-zinc-500 truncate w-full">
                      {FamilyDisplay.relationship_label(member.family_relationship)}
                    </span>
                  </div>
                <% end %>
              </div>
            </section>

            <%!-- Notification preferences: quiet settings, kept below the news --%>
            <section id="home-notifications">
              <h2 class="text-sm text-zinc-500 mb-4 type-eyebrow">
                Notifications
              </h2>

              <div
                :if={!@async_data_loaded}
                id="home-notifications-loading"
                class="space-y-4"
                aria-hidden="true"
              >
                <div :for={_ <- 1..2} class="flex items-center gap-3">
                  <.skeleton_block class="w-9 h-9 rounded-full shrink-0" />
                  <div class="space-y-2 flex-1">
                    <.skeleton_block class="h-3.5 w-28 rounded-sm" />
                    <.skeleton_block class="h-3 w-full max-w-56 rounded-sm" />
                  </div>
                  <.skeleton_block class="h-4 w-16 rounded-sm shrink-0" />
                </div>
                <.skeleton_block class="h-4 w-44 rounded-sm" />
              </div>

              <div :if={@async_data_loaded} class="space-y-4">
                <.newsletter_member_status
                  id="home-newsletter-member-status"
                  subscribed={@newsletter_subscribed}
                  layout={:compact}
                />

                <div
                  id="home-event-notifications-status"
                  class="flex items-center gap-3"
                >
                  <div class={[
                    "flex items-center justify-center w-9 h-9 rounded-full shrink-0",
                    if(@current_user.event_notifications,
                      do: "bg-emerald-100",
                      else: "bg-zinc-100"
                    )
                  ]}>
                    <.icon
                      name={
                        if(@current_user.event_notifications,
                          do: "hero-bell",
                          else: "hero-bell-slash"
                        )
                      }
                      class={[
                        "w-4 h-4",
                        if(@current_user.event_notifications,
                          do: "text-emerald-600",
                          else: "text-zinc-500"
                        )
                      ]}
                    />
                  </div>
                  <div class="min-w-0 flex-1">
                    <p class="font-semibold text-zinc-900 text-sm">
                      {if @current_user.event_notifications,
                        do: "Event notifications on",
                        else: "Event notifications off"}
                    </p>
                    <p class="text-xs text-zinc-500 mt-0.5">
                      {if @current_user.event_notifications,
                        do: "You'll hear about new events and reminders.",
                        else: "Turn on to hear about new events and reminders."}
                    </p>
                  </div>
                  <.section_link
                    phx-click="toggle_event_notifications"
                    phx-disable-with="Saving..."
                    class="shrink-0"
                  >
                    {if @current_user.event_notifications,
                      do: "Turn off",
                      else: "Turn on"}
                  </.section_link>
                </div>

                <.section_link navigate={~p"/newsletters"}>
                  Browse newsletter archive
                  <.icon name="hero-arrow-right" class="w-3 h-3" />
                </.section_link>
              </div>
            </section>
          </aside>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  # The family strip only loads for primary family members, which is knowable
  # before the async user load; reserve its slot so the notifications card
  # below does not jump when the members arrive.
  defp family_section_pending?(false, user, membership, true) do
    not Accounts.sub_account?(user) and
      YscWeb.UserAuth.get_membership_plan_type(membership) == :family
  end

  defp family_section_pending?(_loaded?, _user, _membership, _active?),
    do: false

  defp get_membership_description(
         nil,
         _is_sub_account,
         _primary_user,
         _timezone
       ) do
    "You need an active membership to access YSC events and benefits."
  end

  defp get_membership_description(
         membership,
         is_sub_account,
         primary_user,
         timezone
       ) do
    plan_type = YscWeb.UserAuth.get_membership_plan_type(membership)
    renewal_date = YscWeb.UserAuth.get_membership_renewal_date(membership)

    scheduled_for_cancellation? =
      membership_scheduled_for_cancellation?(membership)

    case plan_type do
      :lifetime ->
        if is_sub_account do
          "You are a lifetime member through #{if primary_user, do: "#{primary_user.first_name} #{primary_user.last_name}", else: "the member who manages your family account"}. Enjoy full access to our cabins and events forever."
        else
          "You are a lifetime member. Enjoy full access to our cabins and events forever."
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
          "You have access to a #{membership_type} membership through #{if primary_user, do: "#{primary_user.first_name} #{primary_user.last_name}", else: "the member who manages your family account"}. Your membership benefits are shared through their family membership."
        else
          cond do
            scheduled_for_cancellation? && renewal_date ->
              "Your #{membership_type} membership will not automatically renew. You are still an active member until #{format_membership_date(renewal_date, timezone)}."

            renewal_date ->
              "You have an active #{membership_type} membership. It will automatically renew on #{format_membership_date(renewal_date, timezone)} unless you turn off automatic renewal beforehand."

            true ->
              "You have an active #{membership_type} membership."
          end
        end

      _ ->
        "You have an active membership with access to our cabins and events."
    end
  end

  # Scannable renewal line for paid (non-lifetime, non-sub-account) memberships;
  # nil falls back to the full sentence from `get_membership_description/4`.
  defp membership_renewal_note(nil, _is_sub_account, _timezone), do: nil
  defp membership_renewal_note(_membership, true, _timezone), do: nil

  defp membership_renewal_note(membership, false, timezone) do
    plan_type = YscWeb.UserAuth.get_membership_plan_type(membership)
    renewal_date = YscWeb.UserAuth.get_membership_renewal_date(membership)

    if plan_type in [nil, :lifetime] or is_nil(renewal_date) do
      nil
    else
      date = format_membership_date(renewal_date, timezone)

      if membership_scheduled_for_cancellation?(membership),
        do: {:ends, date},
        else: {:renews, date}
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
    user_id
    |> Events.list_upcoming_confirmed_tickets_for_user(
      after_now: true,
      event_limit: event_limit
    )
    |> Enum.group_by(& &1.event.id)
    |> Enum.map(fn {_event_id, event_tickets} ->
      event = List.first(event_tickets).event
      event_datetime = get_event_datetime_for_sorting(event)
      {event_datetime, event_tickets}
    end)
    |> Enum.sort_by(
      fn {event_datetime, _tickets} -> event_datetime end,
      {:asc, DateTime}
    )
    |> Enum.flat_map(fn {_event_datetime, event_tickets} -> event_tickets end)
  end

  defp get_event_datetime_for_sorting(event) do
    DateDisplay.event_start_datetime(event) || TimeZone.now()
  end

  defp group_tickets_by_event_and_tier(tickets) do
    tickets
    |> Enum.group_by(& &1.event.id)
    |> Enum.map(fn {_event_id, event_tickets} ->
      event = List.first(event_tickets).event
      grouped_tiers = TicketDisplay.group_tickets_by_tier(event_tickets)
      {event, grouped_tiers}
    end)
    |> Enum.sort_by(
      fn {event, _tiers} ->
        get_event_datetime_for_sorting(event)
      end,
      {:asc, DateTime}
    )
  end

  # Date stubs stay soft-tinted so colour is reserved for what is happening now.
  defp ticket_stub_class(true), do: "bg-blue-700 border-blue-300/60 text-white"
  defp ticket_stub_class(false), do: "bg-blue-50 border-blue-200 text-blue-700"

  defp ticket_stub_month(event) do
    case DateDisplay.event_start_datetime(event) do
      %DateTime{} = dt -> Calendar.strftime(dt, "%b")
      _ -> ""
    end
  end

  defp ticket_stub_day(event) do
    case DateDisplay.event_start_datetime(event) do
      %DateTime{} = dt -> Calendar.strftime(dt, "%-d")
      _ -> ""
    end
  end

  defp days_until_event(event) do
    DateDisplay.days_until_event(event) || 0
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "show_membership_qr",
        _params,
        %{assigns: %{current_user: %{} = user, active_membership?: true}} =
          socket
      ) do
    {:noreply, MembershipQr.show(socket, user)}
  end

  def handle_event("show_membership_qr", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("hide_membership_qr", _params, socket) do
    {:noreply, MembershipQr.hide(socket)}
  end

  def handle_event(
        "wallet_platform_detected",
        %{"platform" => platform},
        socket
      ) do
    {:noreply, WalletPlatform.assign_from_hook(socket, platform)}
  end

  @impl true
  def handle_event("dismiss_passkey_prompt", _params, socket) do
    user = socket.assigns.current_user

    case Accounts.dismiss_passkey_prompt(user) do
      {:ok, _updated_user} ->
        {:noreply,
         socket
         |> assign(show_passkey_prompt: false)
         |> YscWeb.Flash.put_toast(
           :info,
           "We'll remind you about passkeys in 30 days.",
           title: "Reminder scheduled",
           icon: &YscWeb.CoreComponents.flash_toast_icon_clock/1
         )}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("setup_passkey", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/users/settings/passkeys/new")}
  end

  def handle_event("subscribe_newsletter", params, socket) do
    {:noreply, NewsletterSubscribe.request_guest(socket, params)}
  end

  def handle_event("toggle_newsletter_subscription", _params, socket) do
    {:noreply,
     NewsletterSubscribe.toggle_member(socket, source: "home_dashboard")}
  end

  def handle_event("toggle_event_notifications", _params, socket) do
    user = socket.assigns.current_user
    now_enabled? = !user.event_notifications

    case Accounts.update_notification_preferences(user, %{
           "event_notifications" => now_enabled?
         }) do
      {:ok, _updated_user} ->
        {title, body} = event_notifications_toggle_toast(now_enabled?)

        {:noreply,
         socket
         |> assign(:current_user, %{user | event_notifications: now_enabled?})
         |> YscWeb.Flash.put_toast(:info, body,
           title: title,
           icon: &YscWeb.CoreComponents.flash_toast_icon_success/1
         )}

      {:error, _changeset} ->
        {:noreply,
         Phoenix.LiveView.put_flash(
           socket,
           :error,
           "We couldn't update your event notification preference. Please try again, or email info@ysc.org if this keeps happening."
         )}
    end
  end

  defp format_event_time(_event_start_date, %Time{} = time) do
    Calendar.strftime(time, "%-I:%M %p")
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

  defp event_notifications_toggle_toast(true),
    do:
      {"Event notifications on", "You'll hear about new events and reminders."}

  defp event_notifications_toggle_toast(false),
    do: {"Event notifications off", "You won't receive event notifications."}

  defp format_membership_date(%DateTime{} = dt, timezone) do
    DateDisplay.format_date_in_zone(dt, timezone)
  end

  defp format_membership_date(%Date{} = date, _timezone),
    do: DateDisplay.format_datetime_display(date)

  defp format_membership_date(_, _timezone), do: ""

  # Lowest property-level nightly rate from the live pricing rules, so the
  # public home page never drifts from what the booking pages charge.
  defp cabin_rate_label(property) do
    case Ysc.Bookings.PricingRuleCache.lowest_property_rate(property) do
      %Money{} = rate -> Ysc.MoneyHelper.format_money!(rate)
      _ -> nil
    end
  end

  defp days_since_inserted(%DateTime{} = inserted_at) do
    DateTime.diff(DateTime.utc_now(), inserted_at, :day)
  end

  defp days_since_inserted(_), do: 999

  defp preview_text_for_news(post) do
    post
    |> PlainText.from_post()
    |> truncate_preview(150)
  end

  defp truncate_preview("", _), do: ""

  defp truncate_preview(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

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
