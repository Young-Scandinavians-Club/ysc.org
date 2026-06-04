defmodule YscWeb.ClearLakeBookingLive do
  use YscWeb, :live_view

  alias Ysc.Bookings

  alias Ysc.Bookings.{
    AvailabilityCache,
    Booking,
    Season,
    SeasonCache,
    SeasonHelpers,
    PricingHelpers,
    BookingLocker
  }

  alias Ysc.MoneyHelper
  alias Ysc.Accounts
  alias Ysc.Subscriptions
  alias Ysc.Repo
  import Ecto.Query

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    timezone = get_timezone_from_socket(socket)
    today = today_in_timezone(timezone)
    seasons = SeasonCache.get_all_for_property(:clear_lake)

    {current_season, season_start_date, season_end_date} =
      SeasonHelpers.get_current_season_info(:clear_lake, today, seasons)

    max_booking_date =
      SeasonHelpers.calculate_max_booking_date(:clear_lake, today, seasons)

    # Parse query parameters, handling malformed/double-encoded URLs
    parsed_params = parse_mount_params(params)

    # Parse dates and guest counts from URL params if present
    {checkin_date, checkout_date} = parse_dates_from_params(parsed_params)
    guests_count = parse_guests_from_params(parsed_params)
    requested_tab = parse_tab_from_params(parsed_params)
    requested_info_tab = parse_info_tab_from_params(parsed_params)
    booking_mode = parse_booking_mode_from_params(parsed_params)

    date_form =
      to_form(
        %{
          "checkin_date" => date_to_datetime_string(checkin_date),
          "checkout_date" => date_to_datetime_string(checkout_date)
        },
        as: "booking_dates"
      )

    # For initial static render, defer heavy operations until socket is connected
    # This ensures fast time-to-paint for the initial HTML response
    {user_with_subs, can_book, booking_error_title, booking_disabled_reason,
     active_tab, membership_type, day_booking_allowed, buyout_booking_allowed,
     booking_mode, active_bookings} =
      if connected?(socket) do
        # Load user with subscriptions and subscription_items FIRST (to avoid multiple fetches)
        # Preloading subscription_items prevents duplicate queries in get_membership_plan_type
        user_with_subs =
          if user,
            do: Accounts.preload_user_subscriptions_for_booking(user),
            else: nil

        # Check if user can book (pass user_with_subs to avoid re-fetching)
        {can_book, booking_error_title, booking_disabled_reason} =
          check_booking_eligibility(user_with_subs)

        # If user can't book, default to information tab
        active_tab =
          if can_book do
            requested_tab
          else
            :information
          end

        # Calculate membership type once and cache it (if user exists)
        # user_with_subs already has subscriptions and subscription_items loaded
        membership_type =
          if user_with_subs do
            get_membership_type(user_with_subs)
          else
            :none
          end

        # Check which booking modes are allowed based on selected dates
        {day_booking_allowed, buyout_booking_allowed} =
          allowed_booking_modes(
            :clear_lake,
            checkin_date,
            checkout_date,
            current_season,
            seasons
          )

        # Resolve booking mode based on allowed modes (handles defaults and invalid selections)
        booking_mode =
          resolve_booking_mode(
            booking_mode,
            day_booking_allowed,
            buyout_booking_allowed
          )

        # Load active bookings for the user
        active_bookings =
          if user_with_subs,
            do: get_active_bookings(user_with_subs.id, today),
            else: []

        {user_with_subs, can_book, booking_error_title, booking_disabled_reason,
         active_tab, membership_type, day_booking_allowed,
         buyout_booking_allowed, booking_mode, active_bookings}
      else
        # Static render: use minimal data for fast initial paint
        user_with_subs = user
        can_book = true
        booking_error_title = nil
        booking_disabled_reason = nil
        active_tab = requested_tab
        membership_type = if user, do: :none, else: :none
        day_booking_allowed = true
        buyout_booking_allowed = true
        booking_mode = booking_mode || :day
        active_bookings = []

        {user_with_subs, can_book, booking_error_title, booking_disabled_reason,
         active_tab, membership_type, day_booking_allowed,
         buyout_booking_allowed, booking_mode, active_bookings}
      end

    # scroll_to_section from URI fragment (handled in handle_params when connected)
    scroll_to_section = nil

    socket =
      assign(socket,
        page_title: "Clear Lake Cabin",
        meta_description:
          "Book a stay at the Young Scandinavians Club Clear Lake cabin. Choose your dates and guests.",
        property: :clear_lake,
        timezone: timezone,
        user: user_with_subs,
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        today: today,
        max_booking_date: max_booking_date,
        current_season: current_season,
        season_start_date: season_start_date,
        season_end_date: season_end_date,
        seasons: seasons,
        selected_booking_mode: booking_mode,
        guests_count: guests_count,
        guests_dropdown_open: false,
        calculated_price: nil,
        price_error: nil,
        availability_error: nil,
        form_errors: %{},
        date_validation_errors: %{},
        date_form: date_form,
        membership_type: membership_type,
        active_tab: active_tab,
        info_tab: requested_info_tab || :general,
        scroll_to_section: scroll_to_section,
        can_book: can_book,
        booking_error_title: booking_error_title,
        booking_disabled_reason: booking_disabled_reason,
        day_booking_allowed: day_booking_allowed,
        buyout_booking_allowed: buyout_booking_allowed,
        active_bookings: active_bookings,
        load_radar: true,
        availability_cache_version: 0
      )

    # Validate all conditions (availability, booking mode, guests, etc.)
    # Only run heavy validation when connected (availability checks run queries)
    socket =
      if connected?(socket) do
        AvailabilityCache.subscribe()

        socket
        |> validate_all_conditions(
          checkin_date,
          checkout_date,
          booking_mode,
          guests_count,
          current_season
        )
        |> then(fn s ->
          # If dates are present and user can book, initialize price calculation
          if checkin_date && checkout_date && can_book do
            s
            |> calculate_price_if_ready()
          else
            s
          end
        end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, uri, socket) do
    # Parse query parameters, handling malformed/double-encoded URLs
    params = parse_query_params(params, uri)

    # Parse dates and guest counts from URL params
    {checkin_date, checkout_date} = parse_dates_from_params(params)
    guests_count = parse_guests_from_params(params)
    requested_tab = parse_tab_from_params(params)
    requested_info_tab = parse_info_tab_from_params(params)
    booking_mode = parse_booking_mode_from_params(params)

    # Reuse eligibility data from mount if already computed (avoid duplicate queries)
    # Use the user with subscriptions preloaded if available
    user_for_check = socket.assigns[:user] || socket.assigns.current_user

    {can_book, booking_error_title, booking_disabled_reason} =
      if socket.assigns[:can_book] != nil do
        # Already computed in mount - reuse it
        {
          socket.assigns.can_book,
          socket.assigns.booking_error_title,
          socket.assigns.booking_disabled_reason
        }
      else
        # First time (shouldn't happen normally since mount runs first)
        check_booking_eligibility(user_for_check)
      end

    # Load active bookings for the user (only if not already loaded in mount)
    active_bookings =
      if user_for_check && !socket.assigns[:active_bookings] do
        get_active_bookings(user_for_check.id, socket.assigns.today)
      else
        socket.assigns[:active_bookings] || []
      end

    # If user can't book and requested booking tab, switch to information tab
    active_tab =
      if requested_tab == :booking && !can_book do
        :information
      else
        requested_tab
      end

    # Check if tab changed (but nothing else)
    tab_changed = active_tab != socket.assigns.active_tab

    # Update if dates, guest counts, or tab have changed
    # Use Date.compare for proper date comparison
    dates_changed =
      case {checkin_date, socket.assigns.checkin_date} do
        {nil, nil} -> false
        {nil, _} -> true
        {_, nil} -> true
        {c1, c2} -> Date.compare(c1, c2) != :eq
      end ||
        case {checkout_date, socket.assigns.checkout_date} do
          {nil, nil} -> false
          {nil, _} -> true
          {_, nil} -> true
          {c1, c2} -> Date.compare(c1, c2) != :eq
        end

    guests_changed = guests_count != socket.assigns.guests_count
    booking_mode_changed = booking_mode != socket.assigns.selected_booking_mode

    # Also check if can_book, booking_error_title, or booking_disabled_reason changed
    can_book_changed =
      can_book != socket.assigns.can_book ||
        booking_error_title != socket.assigns.booking_error_title ||
        booking_disabled_reason != socket.assigns.booking_disabled_reason

    # Update info_tab from URL when present
    info_tab = requested_info_tab || socket.assigns[:info_tab] || :general
    info_tab_changed = info_tab != socket.assigns[:info_tab]

    # Only update if something actually changed
    # This prevents unnecessary updates on initial page load when mount already set everything
    if dates_changed || guests_changed || tab_changed || booking_mode_changed ||
         can_book_changed || info_tab_changed do
      # Only recalculate today and max_booking_date if dates changed
      # This prevents unnecessary component updates
      {today, max_booking_date, current_season, season_start_date,
       season_end_date} =
        if dates_changed do
          timezone = socket.assigns[:timezone] || "America/Los_Angeles"
          today = today_in_timezone(timezone)

          seasons = socket.assigns.seasons

          {current_season, season_start_date, season_end_date} =
            SeasonHelpers.get_current_season_info(:clear_lake, today, seasons)

          max_booking_date =
            SeasonHelpers.calculate_max_booking_date(
              :clear_lake,
              today,
              seasons
            )

          {today, max_booking_date, current_season, season_start_date,
           season_end_date}
        else
          {
            socket.assigns.today,
            socket.assigns.max_booking_date,
            socket.assigns.current_season,
            socket.assigns.season_start_date,
            socket.assigns.season_end_date
          }
        end

      date_form =
        to_form(
          %{
            "checkin_date" => date_to_datetime_string(checkin_date),
            "checkout_date" => date_to_datetime_string(checkout_date)
          },
          as: "booking_dates"
        )

      # Check which booking modes are allowed based on selected dates
      {day_booking_allowed, buyout_booking_allowed} =
        allowed_booking_modes(
          :clear_lake,
          checkin_date,
          checkout_date,
          current_season,
          socket.assigns.seasons
        )

      # Resolve booking mode based on allowed modes
      # This ensures we default to a valid mode if the requested one is not allowed
      # or if no mode was requested (booking_mode is nil)
      resolved_booking_mode =
        resolve_booking_mode(
          booking_mode,
          day_booking_allowed,
          buyout_booking_allowed
        )

      # Validate all conditions (availability, booking mode, guests, etc.)
      # This ensures URL parameters are validated even if user manipulates them
      socket =
        socket
        |> assign(
          page_title: "Clear Lake Cabin",
          meta_description:
            "Book a stay at the Young Scandinavians Club Clear Lake cabin. Choose your dates and guests.",
          checkin_date: checkin_date,
          checkout_date: checkout_date,
          today: today,
          max_booking_date: max_booking_date,
          current_season: current_season,
          season_start_date: season_start_date,
          season_end_date: season_end_date,
          guests_count: guests_count,
          selected_booking_mode: resolved_booking_mode,
          guests_dropdown_open: socket.assigns[:guests_dropdown_open] || false,
          calculated_price: nil,
          price_error: nil,
          availability_error: nil,
          form_errors: %{},
          date_form: date_form,
          date_validation_errors: %{},
          active_tab: active_tab,
          info_tab: info_tab,
          scroll_to_section: scroll_to_section_from_uri(uri),
          can_book: can_book,
          booking_error_title: booking_error_title,
          booking_disabled_reason: booking_disabled_reason,
          day_booking_allowed: day_booking_allowed,
          buyout_booking_allowed: buyout_booking_allowed,
          active_bookings: active_bookings
        )
        |> validate_all_conditions(
          checkin_date,
          checkout_date,
          resolved_booking_mode,
          guests_count,
          current_season
        )
        |> then(fn s ->
          # Update date form with validated/corrected dates
          validated_date_form =
            to_form(
              %{
                "checkin_date" =>
                  date_to_datetime_string(s.assigns.checkin_date),
                "checkout_date" =>
                  date_to_datetime_string(s.assigns.checkout_date)
              },
              as: "booking_dates"
            )

          s
          |> assign(:date_form, validated_date_form)
          |> then(fn updated_s ->
            # Only run price calculation if dates, guests, or booking mode changed, not just tab
            if dates_changed || guests_changed || booking_mode_changed do
              updated_s
              |> calculate_price_if_ready()
            else
              updated_s
            end
          end)
        end)

      {:noreply, socket}
    else
      # Even if nothing changed, update scroll_to_section if hash is present
      socket = update_scroll_section(socket, uri)
      {:noreply, socket}
    end
  end

  defp scroll_to_section_from_uri(uri) do
    if uri do
      parsed_uri = URI.parse(uri)

      if parsed_uri.fragment && parsed_uri.fragment != "",
        do: parsed_uri.fragment,
        else: nil
    else
      nil
    end
  end

  defp update_scroll_section(socket, uri) do
    if uri do
      parsed_uri = URI.parse(uri)

      if parsed_uri.fragment && parsed_uri.fragment != "" do
        assign(socket, scroll_to_section: parsed_uri.fragment)
      else
        assign(socket, scroll_to_section: nil)
      end
    else
      assign(socket, scroll_to_section: nil)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="clear-lake-booking-page"
      class="overflow-x-hidden"
      phx-hook={if assigns[:scroll_to_section], do: "ScrollToSection", else: nil}
      data-section={
        if assigns[:scroll_to_section], do: assigns.scroll_to_section, else: nil
      }
    >
      <%!-- Hero Section with Carousel (For logged-in users) --%>
      <section
        :if={@user}
        id="hero-section"
        class="relative w-full overflow-hidden hero-nav-overlap min-h-[40vh]"
      >
        <div
          id="clear-lake-carousel-wrapper"
          phx-hook="ImageCarouselAutoplay"
          class="absolute inset-0 h-full w-full z-[2]"
        >
          <YscWeb.Components.ImageCarousel.image_carousel
            id="about-the-clear-lake-cabin-carousel-logged-in"
            images={[
              %{
                src: ~p"/images/clear_lake/clear_lake_main.webp",
                alt: "Clear Lake Cabin Exterior"
              },
              %{
                src: ~p"/images/history/clear_lake_from_above.webp",
                alt: "Clear Lake Aerial View"
              },
              %{
                src: ~p"/images/clear_lake/clear_lake_dock.webp",
                alt: "Clear Lake Dock"
              },
              %{
                src: ~p"/images/clear_lake/clear_lake_dock_2.webp",
                alt: "Clear Lake Dock"
              },
              %{
                src: ~p"/images/clear_lake/clear_lake_sweep.webp",
                alt: "Clear Lake"
              },
              %{
                src: ~p"/images/clear_lake/clear_lake_cabin.webp",
                alt: "Clear Lake Cabin"
              }
            ]}
            class="h-full w-full"
          />
          <div
            class="absolute inset-0 z-[5] bg-black/40 pointer-events-none"
            aria-hidden="true"
          >
          </div>
        </div>
        <%!-- Title Text Section --%>
        <div class="absolute bottom-0 left-0 right-0 z-[10] px-4 py-12 md:py-16 pointer-events-none">
          <div class="max-w-screen-xl mx-auto pointer-events-auto">
            <div class="flex items-center gap-4 px-4">
              <h1 class="text-3xl sm:text-4xl md:text-5xl font-black text-white drop-shadow-lg">
                Clear Lake Cabin
              </h1>
              <span class="whitespace-nowrap px-2 py-1 bg-blue-600/90 text-white text-xs font-black uppercase tracking-[0.2em] rounded backdrop-blur-sm">
                Member Access
              </span>
            </div>
          </div>
        </div>
      </section>
      <!-- Booking Dashboard Section -->
      <section :if={@user} class="py-8">
        <div class="max-w-screen-xl mx-auto px-4 space-y-10">
          <!-- Essential Alerts Bar (High-Contrast) -->
          <div class="grid grid-cols-1 md:grid-cols-4 gap-4 bg-zinc-900 text-white p-4 rounded-xl">
            <div class="flex items-center gap-3">
              <span class="text-xl flex-shrink-0">🧺</span>
              <div>
                <p class="text-xs font-black text-teal-400 uppercase">
                  Mandatory
                </p>
                <p class="text-xs font-bold leading-tight">
                  Bring your own bed linens
                </p>
              </div>
            </div>
            <div class="flex items-center gap-3">
              <span class="text-xl flex-shrink-0">🚫</span>
              <div>
                <p class="text-xs font-black text-zinc-400 uppercase">
                  Enforced
                </p>
                <p class="text-xs font-bold leading-tight">No pets or smoking</p>
              </div>
            </div>
            <div class="flex items-center gap-3">
              <span class="text-xl flex-shrink-0">⚓</span>
              <div>
                <p class="text-xs font-black text-amber-400 uppercase">
                  Access
                </p>
                <p class="text-xs font-bold leading-tight">
                  Free boat mooring — email the cabin host before you arrive
                </p>
              </div>
            </div>
            <div class="flex items-center gap-3">
              <span class="text-xl flex-shrink-0">🧹</span>
              <div>
                <p class="text-xs font-black text-zinc-400 uppercase">
                  Community
                </p>
                <p class="text-xs font-bold leading-tight">
                  Shared cabin — please help with chores before you leave
                </p>
              </div>
            </div>
          </div>
          <!-- Active Bookings -->
          <div :if={length(@active_bookings) > 0} class="space-y-4">
            <h2 class="text-sm font-bold text-zinc-400 uppercase tracking-widest">
              <%= if Accounts.sub_account?(@user) || Accounts.primary_user?(@user) do %>
                Family Active Bookings
              <% else %>
                Your Active Bookings
              <% end %>
            </h2>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for booking <- @active_bookings do %>
                <div class="bg-white border-2 border-teal-100 rounded-xl p-5 shadow-sm">
                  <div class="flex justify-between items-start mb-3">
                    <span class="text-xs font-bold text-teal-600 bg-teal-50 px-2 py-0.5 rounded">
                      {booking.reference_id}
                    </span>
                    <%= if Date.compare(booking.checkout_date, @today) == :eq do %>
                      <span class="text-xs font-bold text-amber-600 italic">
                        Today!
                      </span>
                    <% else %>
                      <span class="text-xs font-bold text-teal-600 italic">
                        Active
                      </span>
                    <% end %>
                  </div>
                  <p class="font-bold text-zinc-900 text-lg leading-none">
                    {Calendar.strftime(booking.checkin_date, "%b %d")} — {Calendar.strftime(
                      booking.checkout_date,
                      "%b %d"
                    )}
                  </p>
                  <p class="text-sm text-zinc-500 mt-1">
                    {booking.guests_count} {if booking.guests_count == 1,
                      do: "Guest",
                      else: "Guests"} • {if booking.booking_mode == :buyout,
                      do: "Entire cabin",
                      else: "Shared stay"}
                  </p>
                  <.link
                    navigate={~p"/bookings/#{booking.id}/receipt"}
                    class="inline-block mt-4 text-sm font-semibold text-teal-600 hover:underline"
                  >
                    View Booking →
                  </.link>
                </div>
              <% end %>
            </div>
          </div>
          <!-- Booking Form -->
          <div
            :if={@can_book}
            class="grid grid-cols-1 lg:grid-cols-3 gap-8 items-start"
          >
            <!-- Left Column: Selection Area (2 columns on large screens) -->
            <div class="lg:col-span-2 space-y-8">
              <!-- Step 1: Booking Mode Selection -->
              <section class="bg-zinc-50 p-6 rounded border border-zinc-200">
                <h2 class="text-lg font-bold mb-4 flex items-center gap-2">
                  <span class="w-6 h-6 bg-teal-600 text-white rounded-full flex items-center justify-center text-xs font-semibold">
                    1
                  </span>
                  Choose Booking Type
                </h2>
                <p class="text-base text-zinc-600 mb-6">
                  Select how you'd like to book the Clear Lake cabin:
                </p>
                <fieldset>
                  <form phx-change="booking-mode-changed">
                    <div
                      class="grid grid-cols-1 md:grid-cols-2 gap-4"
                      role="radiogroup"
                    >
                      <label class={[
                        "flex flex-col p-6 border-2 rounded-xl cursor-pointer transition-all",
                        if(
                          @selected_booking_mode == :day ||
                            @selected_booking_mode == nil,
                          do: "border-teal-600 bg-teal-50 shadow-sm",
                          else:
                            "border-zinc-300 hover:border-teal-400 hover:bg-zinc-50"
                        ),
                        if(!@day_booking_allowed,
                          do: "opacity-50 cursor-not-allowed",
                          else: ""
                        )
                      ]}>
                        <input
                          type="radio"
                          id="booking-mode-day"
                          name="booking_mode"
                          value="day"
                          checked={
                            @selected_booking_mode == :day ||
                              @selected_booking_mode == nil
                          }
                          disabled={!@day_booking_allowed}
                          class="sr-only"
                        />
                        <div class="flex items-center gap-3 mb-2">
                          <div class={[
                            "w-6 h-6 rounded-full border-2 flex items-center justify-center",
                            if(
                              @selected_booking_mode == :day ||
                                @selected_booking_mode == nil,
                              do: "border-teal-600 bg-teal-600",
                              else: "border-zinc-300 bg-white"
                            )
                          ]}>
                            <svg
                              :if={
                                @selected_booking_mode == :day ||
                                  @selected_booking_mode == nil
                              }
                              class="w-4 h-4 text-white"
                              fill="currentColor"
                              viewBox="0 0 20 20"
                            >
                              <path
                                fill-rule="evenodd"
                                d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                                clip-rule="evenodd"
                              />
                            </svg>
                          </div>
                          <span class="text-lg font-semibold text-zinc-900">
                            Shared stay
                          </span>
                        </div>
                        <p class="text-sm text-zinc-600 ml-9">
                          Shared cabin stay. Perfect for individuals and small groups.
                        </p>
                      </label>
                      <label class={[
                        "flex flex-col p-6 border-2 rounded-xl cursor-pointer transition-all",
                        if(@selected_booking_mode == :buyout,
                          do: "border-teal-600 bg-teal-50 shadow-sm",
                          else:
                            "border-zinc-300 hover:border-teal-400 hover:bg-zinc-50"
                        ),
                        if(
                          !@buyout_booking_allowed ||
                            (@selected_booking_mode == :buyout &&
                               @availability_error),
                          do: "opacity-50 cursor-not-allowed",
                          else: ""
                        )
                      ]}>
                        <input
                          type="radio"
                          id="booking-mode-buyout"
                          name="booking_mode"
                          value="buyout"
                          checked={@selected_booking_mode == :buyout}
                          disabled={
                            !@buyout_booking_allowed ||
                              (@selected_booking_mode == :buyout &&
                                 @availability_error)
                          }
                          class="sr-only"
                        />
                        <div class="flex items-center gap-3 mb-2">
                          <div class={[
                            "w-6 h-6 rounded-full border-2 flex items-center justify-center",
                            if(@selected_booking_mode == :buyout,
                              do: "border-teal-600 bg-teal-600",
                              else: "border-zinc-300 bg-white"
                            )
                          ]}>
                            <svg
                              :if={@selected_booking_mode == :buyout}
                              class="w-4 h-4 text-white"
                              fill="currentColor"
                              viewBox="0 0 20 20"
                            >
                              <path
                                fill-rule="evenodd"
                                d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                                clip-rule="evenodd"
                              />
                            </svg>
                          </div>
                          <span class="text-lg font-semibold text-zinc-900">
                            Reserve the whole cabin
                          </span>
                        </div>
                        <p class="text-sm text-zinc-600 ml-9">
                          Exclusive use of the property. Great for large families.
                        </p>
                        <p
                          :if={
                            @selected_booking_mode == :buyout && @availability_error &&
                              @checkin_date && @checkout_date
                          }
                          class="text-xs text-amber-600 mt-2 ml-9 font-medium"
                        >
                          Whole-cabin booking unavailable: Other members have already booked spots on these dates.
                        </p>
                      </label>
                    </div>
                  </form>
                </fieldset>
                <div class="mt-4">
                  <p class="text-sm text-zinc-600">
                    <span
                      :if={
                        !@day_booking_allowed && !@buyout_booking_allowed &&
                          (@checkin_date || @checkout_date)
                      }
                      class="text-amber-600 font-medium"
                    >
                      Please select dates to see available booking options for your selected period.
                    </span>
                    <span
                      :if={
                        !@day_booking_allowed && @selected_booking_mode == :day &&
                          @checkin_date
                      }
                      class="text-amber-600 font-medium"
                    >
                      Shared stays are not available for the selected dates. Try different dates or reserve the whole cabin if that option is open.
                    </span>
                    <span
                      :if={
                        !@buyout_booking_allowed &&
                          @selected_booking_mode == :buyout &&
                          @checkin_date
                      }
                      class="text-amber-600 font-medium"
                    >
                      Reserving the whole cabin is not available for the selected dates. Try different dates or choose a shared stay if that option is open.
                    </span>
                  </p>
                </div>
              </section>
              <!-- Step 2a: Day Booking Details (shown when day mode selected) -->
              <div :if={@selected_booking_mode == :day}>
                <!-- Section 1: Stay Details -->
                <section class="bg-zinc-50 p-6 rounded border border-zinc-200">
                  <h2 class="text-lg font-bold mb-4 flex items-center gap-2">
                    <span class="w-6 h-6 bg-teal-600 text-white rounded-full flex items-center justify-center text-xs font-semibold">
                      2
                    </span>
                    Stay Details
                  </h2>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <!-- Guests and Children Selection (Dropdown) -->
                    <div class="py-1">
                      <div
                        id="guests-label"
                        class="block text-sm font-semibold text-zinc-700 mb-2"
                      >
                        Guests
                      </div>
                      <div class="relative">
                        <!-- Dropdown Trigger -->
                        <button
                          type="button"
                          id="guests-dropdown-button"
                          phx-click="toggle-guests-dropdown"
                          aria-labelledby="guests-label"
                          aria-expanded={@guests_dropdown_open}
                          aria-haspopup="true"
                          class="w-full px-3 py-2 border border-zinc-300 rounded focus:ring-2 focus:ring-teal-500 focus:border-teal-500 bg-white text-left flex items-center justify-between disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                          <span class="text-zinc-900">
                            {@guests_count} {if @guests_count == 1,
                              do: "guest",
                              else: "guests"}
                          </span>
                          <.icon
                            name="hero-chevron-down"
                            class={[
                              "w-5 h-5 text-zinc-500 transition-transform duration-200 ease-in-out",
                              if(@guests_dropdown_open, do: "rotate-180", else: "")
                            ]}
                          />
                        </button>
                        <!-- Dropdown Panel -->
                        <div
                          :if={@guests_dropdown_open}
                          phx-click-away="close-guests-dropdown"
                          class="absolute z-50 w-full mt-1 bg-white border border-zinc-300 rounded-md shadow-sm p-4"
                        >
                          <div class="space-y-4" phx-click="ignore">
                            <!-- Guests Counter -->
                            <div>
                              <div
                                id="guests-label"
                                class="block text-sm font-semibold text-zinc-700 mb-2"
                              >
                                Number of Guests
                              </div>
                              <div
                                class="flex items-center space-x-3"
                                role="group"
                                aria-labelledby="guests-label"
                              >
                                <button
                                  type="button"
                                  id="decrease-guests-button"
                                  phx-click="decrease-guests"
                                  phx-click-stop
                                  disabled={@guests_count <= 1}
                                  aria-label="Decrease number of guests"
                                  class={[
                                    "w-10 h-10 rounded-full border flex items-center justify-center transition-colors",
                                    if(@guests_count <= 1,
                                      do:
                                        "border-zinc-200 bg-zinc-100 text-zinc-400 cursor-not-allowed",
                                      else:
                                        "border-zinc-300 hover:bg-zinc-50 text-zinc-700"
                                    )
                                  ]}
                                >
                                  <.icon name="hero-minus" class="w-5 h-5" />
                                </button>
                                <span
                                  id="guests-count-display"
                                  class="w-12 text-center font-medium text-lg text-zinc-900"
                                  aria-live="polite"
                                >
                                  {@guests_count}
                                </span>
                                <button
                                  type="button"
                                  id="increase-guests-button"
                                  phx-click="increase-guests"
                                  phx-click-stop
                                  aria-label="Increase number of guests"
                                  class="w-10 h-10 rounded-full border-2 flex items-center justify-center transition-all duration-200 font-semibold border-teal-600 bg-teal-600 hover:bg-teal-700 hover:border-teal-700 text-white"
                                >
                                  <.icon name="hero-plus" class="w-5 h-5" />
                                </button>
                              </div>
                            </div>
                            <p class="text-sm text-zinc-600 pt-2 border-t border-zinc-200">
                              <strong>Children 5 and under stay free.</strong>
                              Please do not include them when registering attendees.
                            </p>
                            <!-- Done Button -->
                            <div class="pt-2">
                              <button
                                type="button"
                                phx-click="close-guests-dropdown"
                                class="w-full px-4 py-2 bg-teal-700 hover:bg-teal-800 text-white font-semibold rounded transition-colors duration-200"
                              >
                                Done
                              </button>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                  <!-- Error Messages -->
                  <div class="mt-4 space-y-1">
                    <p
                      :if={@form_errors[:guests_count]}
                      class="text-red-600 text-sm"
                    >
                      {@form_errors[:guests_count]}
                    </p>
                  </div>
                </section>
              </div>
              <!-- Step 2b: Buyout Calendar (shown when buyout mode selected) -->
              <div :if={@selected_booking_mode == :buyout}>
                <section class="bg-zinc-50 p-6 rounded border border-zinc-200">
                  <div class="flex items-center justify-between mb-4">
                    <h2 class="text-lg font-bold flex items-center gap-2">
                      <span class="w-6 h-6 bg-teal-600 text-white rounded-full flex items-center justify-center text-xs font-semibold">
                        2
                      </span>
                      Select Dates
                    </h2>
                    <button
                      :if={@checkin_date || @checkout_date}
                      type="button"
                      phx-click="reset-dates"
                      class="text-xs font-semibold text-teal-600 hover:text-teal-800 transition-colors"
                    >
                      Reset Dates
                    </button>
                  </div>
                  <div class="mb-4">
                    <p class="text-sm font-medium text-zinc-800 mb-2">
                      The calendar shows which dates are available for exclusive full cabin rental.
                    </p>
                    <p class="text-xs text-zinc-600">
                      Click on a date to start your selection, then click another date to complete your range.
                    </p>
                  </div>
                  <.live_component
                    module={YscWeb.Components.AvailabilityCalendar}
                    id="1"
                    checkin_date={@checkin_date}
                    checkout_date={@checkout_date}
                    selected_booking_mode={@selected_booking_mode}
                    min={@today}
                    max={@max_booking_date}
                    property={:clear_lake}
                    today={@today}
                    guests_count={@guests_count}
                    availability_cache_version={@availability_cache_version}
                  />
                  <!-- Error Messages -->
                  <div class="mt-4 space-y-1">
                    <p
                      :if={@date_validation_errors[:weekend]}
                      class="text-red-600 text-sm"
                    >
                      {@date_validation_errors[:weekend]}
                    </p>
                    <p
                      :if={@date_validation_errors[:max_nights]}
                      class="text-red-600 text-sm"
                    >
                      {@date_validation_errors[:max_nights]}
                    </p>
                    <p
                      :if={@date_validation_errors[:availability]}
                      class="text-red-600 text-sm"
                    >
                      {@date_validation_errors[:availability]}
                    </p>
                  </div>
                </section>
              </div>
              <!-- Step 3: Select Your Dates (for day mode) -->
              <div :if={@selected_booking_mode == :day}>
                <section class="bg-zinc-50 p-6 rounded border border-zinc-200">
                  <div class="flex items-center justify-between mb-4">
                    <h2 class="text-lg font-bold flex items-center gap-2">
                      <span class="w-6 h-6 bg-teal-600 text-white rounded-full flex items-center justify-center text-xs font-semibold">
                        3
                      </span>
                      Select Your Dates
                    </h2>
                    <button
                      :if={@checkin_date || @checkout_date}
                      type="button"
                      phx-click="reset-dates"
                      class="text-xs font-semibold text-teal-600 hover:text-teal-800 transition-colors"
                    >
                      Reset Dates
                    </button>
                  </div>
                  <div class="mb-4">
                    <p class="text-sm font-medium text-zinc-800 mb-2">
                      The calendar shows how many guests are registered for each day.
                    </p>
                    <p class="text-xs text-zinc-600">
                      Click on a date to start your selection, then click another date to complete your range.
                    </p>
                  </div>
                  <.live_component
                    module={YscWeb.Components.AvailabilityCalendar}
                    id="1"
                    checkin_date={@checkin_date}
                    checkout_date={@checkout_date}
                    selected_booking_mode={@selected_booking_mode}
                    min={@today}
                    max={@max_booking_date}
                    property={:clear_lake}
                    today={@today}
                    guests_count={@guests_count}
                    availability_cache_version={@availability_cache_version}
                  />
                  <!-- Error Messages -->
                  <div class="mt-4 space-y-1">
                    <p
                      :if={@form_errors[:checkin_date]}
                      class="text-red-600 text-sm"
                    >
                      {@form_errors[:checkin_date]}
                    </p>
                    <p
                      :if={@form_errors[:checkout_date]}
                      class="text-red-600 text-sm"
                    >
                      {@form_errors[:checkout_date]}
                    </p>
                    <p
                      :if={@date_validation_errors[:weekend]}
                      class="text-red-600 text-sm"
                    >
                      {@date_validation_errors[:weekend]}
                    </p>
                    <p
                      :if={@date_validation_errors[:max_nights]}
                      class="text-red-600 text-sm"
                    >
                      {@date_validation_errors[:max_nights]}
                    </p>
                    <p
                      :if={@date_validation_errors[:active_booking]}
                      class="text-red-600 text-sm"
                    >
                      {@date_validation_errors[:active_booking]}
                    </p>
                    <p
                      :if={@date_validation_errors[:advance_booking_limit]}
                      class="text-red-600 text-sm"
                    >
                      {@date_validation_errors[:advance_booking_limit]}
                    </p>
                    <p
                      :if={@date_validation_errors[:season_date_range]}
                      class="text-red-600 text-sm"
                    >
                      {@date_validation_errors[:season_date_range]}
                    </p>
                  </div>
                </section>
              </div>
              <!-- Price Error -->
              <div
                :if={@price_error}
                class="bg-red-50 border border-red-200 rounded-xl p-4"
              >
                <div class="flex items-start">
                  <div class="flex-shrink-0">
                    <.icon
                      name="hero-exclamation-circle"
                      class="h-5 w-5 text-red-600 -mt-1"
                    />
                  </div>
                  <div class="ms-3">
                    <p class="text-sm text-red-800">{@price_error}</p>
                  </div>
                </div>
              </div>
            </div>
            <!-- Right Column: Sticky Reservation Summary (1 column on large screens) -->
            <aside class="lg:sticky lg:top-24">
              <div class="bg-white rounded-xl border-2 border-teal-600 overflow-hidden">
                <div class="bg-teal-600 p-4 text-white text-center">
                  <h3 class="text-lg font-bold">Reservation Summary</h3>
                </div>
                <div class="p-6 space-y-4">
                  <!-- Dates -->
                  <div :if={@checkin_date && @checkout_date} class="space-y-3">
                    <div class="flex justify-between items-start text-sm">
                      <span class="text-zinc-500 font-medium">Check-in</span>
                      <span class="font-semibold text-zinc-900 text-right">
                        {Calendar.strftime(@checkin_date, "%b %d, %Y")}
                      </span>
                    </div>
                    <div class="flex justify-between items-start text-sm">
                      <span class="text-zinc-500 font-medium">Check-out</span>
                      <span class="font-semibold text-zinc-900 text-right">
                        {Calendar.strftime(@checkout_date, "%b %d, %Y")}
                      </span>
                    </div>
                    <div class="flex justify-between items-start text-sm">
                      <span class="text-zinc-500 font-medium">Nights</span>
                      <span class="font-semibold text-zinc-900">
                        {Date.diff(@checkout_date, @checkin_date)} {if Date.diff(
                                                                         @checkout_date,
                                                                         @checkin_date
                                                                       ) == 1,
                                                                       do: "night",
                                                                       else:
                                                                         "nights"}
                      </span>
                    </div>
                  </div>
                  <!-- Guests -->
                  <div
                    :if={@guests_count && @selected_booking_mode == :day}
                    class="flex justify-between text-sm"
                  >
                    <span class="text-zinc-500 font-medium">Guests</span>
                    <span class="font-semibold text-zinc-900">
                      {@guests_count} {if @guests_count == 1,
                        do: "guest",
                        else: "guests"}
                    </span>
                  </div>
                  <!-- Booking Mode -->
                  <div
                    :if={
                      @selected_booking_mode == :buyout && @checkin_date &&
                        @checkout_date
                    }
                    class="space-y-2"
                  >
                    <p class="text-xs font-bold text-zinc-400 uppercase">
                      Booking Type
                    </p>
                    <div class="text-sm text-zinc-700 font-medium">
                      Entire cabin
                    </div>
                  </div>
                  <div
                    :if={
                      @selected_booking_mode == :day && @checkin_date &&
                        @checkout_date
                    }
                    class="space-y-2"
                  >
                    <p class="text-xs font-bold text-zinc-400 uppercase">
                      Booking Type
                    </p>
                    <div class="text-sm text-zinc-700 font-medium">Shared stay</div>
                  </div>
                  <!-- Sunday Morning Parking Tip -->
                  <div
                    :if={@checkin_date && @checkout_date}
                    class="mt-4 p-3 bg-amber-50 border border-amber-200 rounded-xl"
                  >
                    <div class="flex items-start gap-2">
                      <.icon
                        name="hero-truck"
                        class="w-4 h-4 text-amber-600 flex-shrink-0 mt-0.5"
                      />
                      <div class="flex-1">
                        <p class="text-xs text-amber-800 leading-relaxed">
                          <strong>Parking Tip:</strong>
                          If you plan to leave early Sunday, don't park in the back or you may find yourself blocked in!
                        </p>
                      </div>
                    </div>
                  </div>
                  <!-- Availability Error Alert -->
                  <div
                    :if={@availability_error}
                    class="bg-amber-50 border border-amber-200 rounded-xl p-3"
                  >
                    <div class="flex items-start gap-2">
                      <div class="flex-shrink-0">
                        <.icon
                          name="hero-exclamation-triangle"
                          class="h-4 w-4 text-amber-600 mt-0.5"
                        />
                      </div>
                      <div class="flex-1">
                        <h4 class="text-xs font-semibold text-amber-800 mb-1">
                          Availability Issue
                        </h4>
                        <p class="text-xs text-amber-700 leading-relaxed">
                          {@availability_error}
                        </p>
                      </div>
                    </div>
                  </div>
                  <!-- Price Display -->
                  <div
                    :if={@calculated_price && @checkin_date && @checkout_date}
                    class="pt-4 border-t border-zinc-200"
                  >
                    <div class="space-y-3">
                      <!-- Price Breakdown -->
                      <div class="space-y-2 text-sm">
                        <span :if={@selected_booking_mode == :day}>
                          <% nights = Date.diff(@checkout_date, @checkin_date) %>
                          <% price_per_guest_per_night =
                            if @price_breakdown &&
                                 @price_breakdown.price_per_guest_per_night do
                              @price_breakdown.price_per_guest_per_night
                            else
                              if nights > 0 && @guests_count > 0 do
                                {:ok, price} =
                                  Money.div(
                                    @calculated_price,
                                    nights * @guests_count
                                  )

                                price
                              else
                                Money.new(0, :USD)
                              end
                            end %>
                          <% total_guest_nights = nights * @guests_count %>
                          <% line_gross =
                            @price_breakdown[:entitlement_subtotal] ||
                              Money.mult(
                                price_per_guest_per_night,
                                total_guest_nights
                              )
                              |> elem(1) %>
                          <div class="flex justify-between items-center text-zinc-600">
                            <span>
                              Spot Rental ({@guests_count} {if @guests_count == 1,
                                do: "adult",
                                else: "adults"} × {nights} {if nights == 1,
                                do: "night",
                                else: "nights"})
                            </span>
                            <span class="font-bold text-zinc-900">
                              {MoneyHelper.format_money!(line_gross)}
                            </span>
                          </div>
                        </span>
                        <span :if={@selected_booking_mode == :buyout}>
                          <% nights = Date.diff(@checkout_date, @checkin_date) %>
                          <% price_per_night =
                            if @price_breakdown && @price_breakdown.price_per_night do
                              @price_breakdown.price_per_night
                            else
                              if nights > 0 do
                                {:ok, price} = Money.div(@calculated_price, nights)
                                price
                              else
                                Money.new(0, :USD)
                              end
                            end %>
                          <% buyout_gross =
                            @price_breakdown[:entitlement_subtotal] ||
                              Money.mult(price_per_night, nights) |> elem(1) %>
                          <div class="flex justify-between items-center text-zinc-600">
                            <span>
                              Entire cabin ({nights} night{if nights != 1,
                                do: "s",
                                else: ""})
                            </span>
                            <span class="font-bold text-zinc-900">
                              {MoneyHelper.format_money!(buyout_gross)}
                            </span>
                          </div>
                        </span>
                      </div>

                      <div
                        :if={
                          @price_breakdown &&
                            @price_breakdown[:entitlement_discount] &&
                            Money.positive?(@price_breakdown[:entitlement_discount])
                        }
                        class="flex justify-between text-sm text-emerald-800"
                      >
                        <span>
                          Member benefit<%= if @price_breakdown[:entitlement_summary] do %>
                            ({@price_breakdown[:entitlement_summary]})
                          <% end %>
                        </span>
                        <span>
                          −{MoneyHelper.format_money!(
                            @price_breakdown[:entitlement_discount]
                          )}
                        </span>
                      </div>

                      <hr class="border-zinc-200 my-3" />

                      <div class="flex justify-between items-end">
                        <span class="text-lg font-bold text-zinc-900">Total</span>
                        <div class="text-right">
                          <span
                            :if={!@availability_error}
                            class="text-2xl font-black text-teal-600"
                          >
                            {MoneyHelper.format_money!(@calculated_price)}
                          </span>
                          <span
                            :if={@availability_error}
                            class="text-2xl font-bold text-zinc-400"
                          >
                            —
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>
                  <!-- Error Messages -->
                  <div :if={@price_error || @availability_error} class="space-y-1">
                    <p :if={@price_error} class="text-red-600 text-xs">
                      {@price_error}
                    </p>
                    <p :if={@availability_error} class="text-red-600 text-xs">
                      {@availability_error}
                    </p>
                  </div>
                  <!-- Missing Info List (Smart Sidebar) -->
                  <div
                    :if={
                      !can_submit_booking?(
                        @selected_booking_mode,
                        @checkin_date,
                        @checkout_date,
                        @guests_count,
                        @availability_error
                      ) && @can_book
                    }
                    class="p-3 bg-amber-50 border border-amber-200 rounded"
                  >
                    <p class="text-xs font-semibold text-amber-900 mb-2">
                      Missing Information:
                    </p>
                    <ul class="text-xs text-amber-800 space-y-1 list-disc list-inside">
                      <li :if={!@checkin_date || !@checkout_date}>
                        Please select check-in and check-out dates
                      </li>
                      <li :if={
                        @checkin_date &&
                          @checkout_date &&
                          @selected_booking_mode == :day &&
                          (!@guests_count || @guests_count < 1)
                      }>
                        Please select number of guests
                      </li>
                      <li :if={@form_errors && map_size(@form_errors) > 0}>
                        Complete the required fields above
                      </li>
                      <li :if={
                        @date_validation_errors &&
                          map_size(@date_validation_errors) > 0
                      }>
                        Review the date messages above
                      </li>
                    </ul>
                  </div>
                  <!-- Empty State -->
                  <div
                    :if={!@checkin_date || !@checkout_date}
                    class="text-center py-8"
                  >
                    <p class="text-sm text-zinc-500">
                      Select dates to see your reservation summary
                    </p>
                  </div>
                  <!-- Submit Button -->
                  <div :if={@checkin_date && @checkout_date}>
                    <.button
                      :if={
                        can_submit_booking?(
                          @selected_booking_mode,
                          @checkin_date,
                          @checkout_date,
                          @guests_count,
                          @availability_error
                        ) &&
                          !@availability_error
                      }
                      phx-click="create-booking"
                      class="w-full text-lg py-4"
                      color="teal"
                    >
                      Continue to Payment
                    </.button>
                    <.button
                      :if={@availability_error}
                      type="button"
                      id="update-selection-btn"
                      phx-hook="BackToTop"
                      class="w-full text-lg py-4"
                      color="amber"
                    >
                      Update Selection
                    </.button>
                  </div>
                </div>
              </div>
            </aside>
          </div>
          <!-- Mobile Sticky Footer (only visible on mobile) -->
          <div class="lg:hidden fixed bottom-0 left-0 right-0 bg-white border-t-2 border-zinc-200 shadow-2xl z-50 p-4">
            <div class="max-w-screen-xl mx-auto flex items-center justify-between gap-4">
              <div class="flex-1">
                <div :if={@calculated_price} class="text-right">
                  <p class="text-xs text-zinc-500 uppercase">Total</p>
                  <p class="text-xl font-black text-teal-600">
                    {MoneyHelper.format_money!(@calculated_price)}
                  </p>
                </div>
                <div :if={!@calculated_price} class="text-sm text-zinc-500">
                  Select dates and guests
                </div>
              </div>
              <.button
                :if={@can_book}
                phx-click="create-booking"
                disabled={
                  !can_submit_booking?(
                    @selected_booking_mode,
                    @checkin_date,
                    @checkout_date,
                    @guests_count,
                    @availability_error
                  ) || !!@availability_error
                }
                class={
                  if can_submit_booking?(
                       @selected_booking_mode,
                       @checkin_date,
                       @checkout_date,
                       @guests_count,
                       @availability_error
                     ) && !@availability_error do
                    "px-6 py-3"
                  else
                    "px-6 py-3 bg-zinc-200 text-zinc-600 hover:bg-zinc-300 opacity-50 cursor-not-allowed"
                  end
                }
              >
                Book Now
              </.button>
            </div>
          </div>
          <!-- Booking Eligibility Banner (shown when user can't book) -->
          <.warning_callout
            :if={!@can_book}
            id="clear-lake-booking-eligibility-banner"
            title={@booking_error_title}
          >
            {raw(@booking_disabled_reason)}
          </.warning_callout>
          <!-- Information Sections (Tab System) -->
          <div id="information-section" class="mt-12 max-w-screen-xl mx-auto">
            <!-- Tab Navigation (Sticky) -->
            <div class="sticky top-0 z-10 bg-white/80 backdrop-blur-md border-b border-zinc-200 mb-8 -mx-4 px-4 py-2">
              <nav class="flex gap-2 overflow-x-auto" role="tablist">
                <button
                  phx-click="switch-info-tab"
                  phx-value-tab="general"
                  class={[
                    "px-4 py-2 text-sm font-bold rounded-md transition-all whitespace-nowrap",
                    if(Map.get(assigns, :info_tab, :general) == :general,
                      do: "bg-teal-50 text-teal-600 border border-teal-100",
                      else: "text-zinc-500 hover:bg-zinc-50 hover:text-zinc-900"
                    )
                  ]}
                >
                  📋 General Information
                </button>
                <button
                  phx-click="switch-info-tab"
                  phx-value-tab="rules"
                  class={[
                    "px-4 py-2 text-sm font-medium rounded-md transition-all whitespace-nowrap",
                    if(Map.get(assigns, :info_tab, :general) == :rules,
                      do: "bg-teal-50 text-teal-600 border border-teal-100",
                      else: "text-zinc-500 hover:bg-zinc-50 hover:text-zinc-900"
                    )
                  ]}
                >
                  📜 Cabin & Booking Rules
                </button>
              </nav>
            </div>
            <!-- Tab Content -->
            <div class="space-y-16">
              <!-- General Information Tab -->
              <div
                :if={Map.get(assigns, :info_tab, :general) == :general}
                class="space-y-16"
              >
                <!-- Welcome Header -->
                <section>
                  <div class="prose prose-zinc max-w-none mb-10">
                    <h1 class="text-3xl font-black tracking-tight text-zinc-900 mb-4">
                      Welcome to the YSC Clear Lake Cabin
                    </h1>
                    <p class="text-lg text-zinc-600 leading-relaxed">
                      Your year-round gateway to North America's oldest natural lake. Since <strong>1963</strong>, the YSC has proudly owned this beautiful cabin, located in the heart of
                      <strong>Kelseyville</strong>
                      on the shores of <strong>Clear Lake</strong>.
                    </p>
                  </div>
                  <!-- Important Notice -->
                  <div class="flex items-center gap-3 p-4 bg-amber-50 border border-amber-100 rounded-xl not-prose mb-10">
                    <span class="text-2xl flex-shrink-0">💡</span>
                    <p class="text-sm text-amber-900 m-0">
                      <strong>Remember:</strong>
                      The Clear Lake Cabin is
                      <strong>your cabin — not a hotel.</strong>
                      To ensure everyone enjoys their stay at a reasonable rate, please follow the guidelines below.
                    </p>
                  </div>
                </section>
                <!-- About the Cabin -->
                <section id="general-info">
                  <h2 class="text-2xl font-bold text-zinc-900 mb-6 flex items-center gap-2">
                    <span>🌲</span>
                    <span>About the Cabin</span>
                  </h2>
                  <p class="mb-8 text-zinc-700">
                    Clear Lake and the surrounding region offer year-round outdoor opportunities:
                  </p>
                  <!-- At-A-Glance Hero Grid -->
                  <div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-12">
                    <div class="bg-white border border-zinc-200 rounded-xl p-5 shadow-sm hover:border-teal-200 transition-colors">
                      <div class="w-10 h-10 bg-teal-50 rounded-full flex items-center justify-center text-xl mb-4 mx-auto">
                        ⚓
                      </div>
                      <div class="text-xs uppercase tracking-widest text-zinc-500 font-bold mb-1 text-center">
                        Dock
                      </div>
                      <div class="text-lg font-bold text-zinc-900 leading-tight text-center">
                        100-Foot Private
                      </div>
                      <div class="text-xs text-zinc-500 text-center mt-1">
                        Boat mooring & swimming
                      </div>
                    </div>
                    <div class="bg-white border border-zinc-200 rounded-xl p-5 shadow-sm hover:border-teal-200 transition-colors">
                      <div class="w-10 h-10 bg-teal-50 rounded-full flex items-center justify-center text-xl mb-4 mx-auto">
                        🎵
                      </div>
                      <div class="text-xs uppercase tracking-widest text-zinc-500 font-bold mb-1 text-center">
                        Social Hall
                      </div>
                      <div class="text-lg font-bold text-zinc-900 leading-tight text-center">
                        Dance Floor
                      </div>
                      <div class="text-xs text-zinc-500 text-center mt-1">
                        Fireplace & games
                      </div>
                    </div>
                    <div class="bg-white border border-zinc-200 rounded-xl p-5 shadow-sm hover:border-teal-200 transition-colors">
                      <div class="w-10 h-10 bg-teal-50 rounded-full flex items-center justify-center text-xl mb-4 mx-auto">
                        🛏️
                      </div>
                      <div class="text-xs uppercase tracking-widest text-zinc-500 font-bold mb-1 text-center">
                        Capacity
                      </div>
                      <div class="text-lg font-bold text-zinc-900 leading-tight text-center">
                        12 Guests
                      </div>
                      <div class="text-xs text-zinc-500 text-center mt-1">
                        Summer lawn & winter beds
                      </div>
                    </div>
                    <div class="bg-white border border-zinc-200 rounded-xl p-5 shadow-sm hover:border-teal-200 transition-colors">
                      <div class="w-10 h-10 bg-teal-50 rounded-full flex items-center justify-center text-xl mb-4 mx-auto">
                        🌅
                      </div>
                      <div class="text-xs uppercase tracking-widest text-zinc-500 font-bold mb-1 text-center">
                        Season
                      </div>
                      <div class="text-lg font-bold text-zinc-900 leading-tight text-center">
                        Year-Round
                      </div>
                      <div class="text-xs text-zinc-500 text-center mt-1">
                        Summer & winter stays
                      </div>
                    </div>
                  </div>

                  <YscWeb.Components.ImageCarousel.image_carousel
                    id="clear-lake-experience-carousel"
                    images={[
                      %{
                        src: ~p"/images/clear_lake/clear_lake_main.webp",
                        alt: "Clear Lake Cabin Exterior"
                      },
                      %{
                        src: ~p"/images/history/clear_lake_from_above.webp",
                        alt: "Clear Lake Aerial View"
                      },
                      %{
                        src: ~p"/images/clear_lake/clear_lake_dock.webp",
                        alt: "Private Dock on Clear Lake"
                      },
                      %{
                        src: ~p"/images/clear_lake/clear_lake_dock_2.webp",
                        alt: "Dock View at Sunset"
                      },
                      %{
                        src: ~p"/images/clear_lake/clear_lake_sweep.webp",
                        alt: "Lake Views"
                      },
                      %{
                        src: ~p"/images/clear_lake/clear_lake_cabin.webp",
                        alt: "Cabin Interior"
                      }
                    ]}
                    class="mb-12 rounded-xl overflow-hidden"
                  />
                  <!-- Nearby Destinations -->
                  <section class="mb-12">
                    <h2 class="text-xl font-bold text-zinc-900 mb-4 flex items-center gap-2">
                      <span>🏔️</span>
                      <span>Nearby Destinations</span>
                    </h2>
                    <div class="bg-white border border-zinc-200 rounded-xl overflow-hidden shadow-sm">
                      <div class="flex items-center justify-between p-4 border-b border-zinc-100">
                        <div class="flex items-center gap-3">
                          <span class="text-xl">🍷</span>
                          <span class="font-semibold">Red Hills Wineries</span>
                        </div>
                        <span class="bg-teal-100 text-teal-700 px-3 py-1 rounded-full text-xs font-bold">
                          10 MINS
                        </span>
                      </div>
                      <div class="flex items-center justify-between p-4 border-b border-zinc-100">
                        <div class="flex items-center gap-3">
                          <span class="text-xl">🥾</span>
                          <span class="font-semibold">Mt. Konocti Trails</span>
                        </div>
                        <span class="bg-teal-100 text-teal-700 px-3 py-1 rounded-full text-xs font-bold">
                          15 MINS
                        </span>
                      </div>
                      <div class="flex items-center justify-between p-4">
                        <div class="flex items-center gap-3">
                          <span class="text-xl">🏘️</span>
                          <span class="font-semibold">Historic Kelseyville</span>
                        </div>
                        <span class="bg-teal-100 text-teal-700 px-3 py-1 rounded-full text-xs font-bold">
                          10 MINS
                        </span>
                      </div>
                    </div>
                    <p class="text-sm text-zinc-600 mt-4">
                      <strong>📍 Location:</strong>
                      Kelseyville, on the shores of Clear Lake.
                    </p>
                  </section>
                </section>
                <!-- How to Book -->
                <section class="bg-white border border-zinc-200 rounded-xl p-6 shadow-sm">
                  <h2 class="text-xl font-bold text-zinc-900 mb-4 flex items-center gap-2">
                    <span>🗓️</span>
                    <span>How to Book</span>
                  </h2>
                  <div>
                    <h3 class="font-semibold text-zinc-900 mb-3">
                      Making a Reservation
                    </h3>
                    <ul class="space-y-2 text-zinc-700">
                      <li>
                        Use the <strong>booking form above</strong>
                        to check availability and select your dates.
                      </li>
                      <li>
                        Choose <strong>Shared stay</strong>
                        or <strong>Reserve the whole cabin</strong>
                        and enter your guest count.
                      </li>
                      <li>
                        Complete your booking and payment <strong>through this website</strong>. You'll receive a confirmation email with your booking details.
                      </li>
                      <li>
                        After booking, you can view and manage your reservation from your booking details page (link in your confirmation email).
                      </li>
                      <li>
                        For cancellation policies and refund information, see the
                        <strong>Cabin & Booking Rules</strong>
                        tab.
                      </li>
                    </ul>
                  </div>
                </section>
                <section id="getting-there">
                  <h2 class="text-2xl font-bold text-zinc-900 mb-4 flex items-center gap-2">
                    <span>🚗</span>
                    <span>Getting There</span>
                  </h2>
                  <div class="grid md:grid-cols-2 gap-8 items-start">
                    <div>
                      <div class="bg-zinc-50 border border-zinc-200 rounded-xl p-6">
                        <p class="text-xs uppercase tracking-widest text-zinc-500 font-bold mb-2">
                          Address
                        </p>
                        <p class="text-xl font-medium text-zinc-900 mb-6">
                          9325 Bass Road<br />Kelseyville, CA 95451
                        </p>
                        <a
                          href="https://www.google.com/maps/dir/?api=1&destination=9325+Bass+Road+Kelseyville+CA+95451"
                          target="_blank"
                          rel="noopener noreferrer"
                          class="inline-flex items-center gap-2 text-teal-600 font-semibold hover:text-teal-800"
                        >
                          <.icon name="hero-map-pin" class="w-4 h-4" /> Open in Maps
                        </a>
                        <h3 class="font-bold text-zinc-900 mb-3 mt-6">
                          From the Bay Area
                        </h3>
                        <p class="text-base text-zinc-600 mb-4">
                          Public transportation is very limited — <strong>driving is essential</strong>. Follow the step-by-step directions below for full details.
                        </p>
                      </div>
                      <details class="group border border-zinc-200 rounded-xl overflow-hidden mt-4">
                        <summary class="p-4 cursor-pointer font-bold text-zinc-700 flex justify-between items-center list-none bg-zinc-50 hover:bg-zinc-100 transition-colors">
                          Step-by-Step Directions from San Francisco
                          <.icon
                            name="hero-chevron-down"
                            class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
                          />
                        </summary>
                        <div class="p-4 border-t border-zinc-100 bg-white">
                          <p class="text-base text-zinc-600 mb-4">
                            Public transportation options are very limited — <strong>driving is essential</strong>. See the map in the Getting There section (right column) for location.
                          </p>
                          <!-- Vertical Trail Directions -->
                          <div class="relative pl-8 space-y-6 mt-6">
                            <!-- Trail line -->
                            <div class="absolute left-3 top-0 bottom-0 w-0.5 bg-teal-300">
                            </div>
                            <!-- Direction steps -->
                            <div class="relative flex gap-4">
                              <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-sm flex items-center justify-center z-10">
                                <span class="text-white text-xs font-bold">1</span>
                              </div>
                              <div class="flex-1 pb-6">
                                <p class="text-sm font-semibold text-zinc-900">
                                  Take HWY 101 North
                                </p>
                                <p class="text-xs text-zinc-600 mt-1">
                                  Past Santa Rosa
                                </p>
                              </div>
                            </div>
                            <div class="relative flex gap-4">
                              <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-sm flex items-center justify-center z-10">
                                <span class="text-white text-xs font-bold">2</span>
                              </div>
                              <div class="flex-1 pb-6">
                                <p class="text-sm font-semibold text-zinc-900">
                                  Exit at River Road / Guerneville
                                </p>
                                <p class="text-xs text-zinc-600 mt-1">Exit 494</p>
                              </div>
                            </div>
                            <div class="relative flex gap-4">
                              <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-sm flex items-center justify-center z-10">
                                <span class="text-white text-xs font-bold">3</span>
                              </div>
                              <div class="flex-1 pb-6">
                                <p class="text-sm font-semibold text-zinc-900">
                                  Turn right onto Mark West Springs Rd
                                </p>
                                <p class="text-xs text-zinc-600 mt-1">
                                  Becomes Porter Creek Rd — go 10.5 miles until it ends
                                </p>
                              </div>
                            </div>
                            <div class="relative flex gap-4">
                              <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-sm flex items-center justify-center z-10">
                                <span class="text-white text-xs font-bold">4</span>
                              </div>
                              <div class="flex-1 pb-6">
                                <p class="text-sm font-semibold text-zinc-900">
                                  Turn left at stop sign onto Petrified Forest Rd
                                </p>
                                <p class="text-xs text-zinc-600 mt-1">
                                  Toward Calistoga — continue 4.6 miles
                                </p>
                              </div>
                            </div>
                            <div class="relative flex gap-4">
                              <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-sm flex items-center justify-center z-10">
                                <span class="text-white text-xs font-bold">5</span>
                              </div>
                              <div class="flex-1 pb-6">
                                <p class="text-sm font-semibold text-zinc-900">
                                  Turn left at stop sign onto Foothill Blvd / HWY 128
                                </p>
                                <p class="text-xs text-zinc-600 mt-1">
                                  Go 0.8 miles
                                </p>
                              </div>
                            </div>
                            <div class="relative flex gap-4">
                              <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-sm flex items-center justify-center z-10">
                                <span class="text-white text-xs font-bold">6</span>
                              </div>
                              <div class="flex-1 pb-6">
                                <p class="text-sm font-semibold text-zinc-900">
                                  Turn right onto Tubbs Lane
                                </p>
                                <p class="text-xs text-zinc-600 mt-1">
                                  Go 1.3 miles to the end
                                </p>
                              </div>
                            </div>
                            <div class="relative flex gap-4">
                              <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-sm flex items-center justify-center z-10">
                                <span class="text-white text-xs font-bold">7</span>
                              </div>
                              <div class="flex-1 pb-6">
                                <p class="text-sm font-semibold text-zinc-900">
                                  Turn left onto HWY 29
                                </p>
                                <p class="text-xs text-zinc-600 mt-1">
                                  Go 28 miles over Mt. St. Helena through Middletown to Lower Lake
                                </p>
                              </div>
                            </div>
                            <div class="relative flex gap-4">
                              <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-sm flex items-center justify-center z-10">
                                <span class="text-white text-xs font-bold">8</span>
                              </div>
                              <div class="flex-1 pb-6">
                                <p class="text-sm font-semibold text-zinc-900">
                                  Turn left onto HWY 29 at Lower Lake
                                </p>
                                <p class="text-xs text-zinc-600 mt-1">
                                  Shell Station on left — go 7.5 miles
                                </p>
                              </div>
                            </div>
                            <div class="relative flex gap-4">
                              <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-sm flex items-center justify-center z-10">
                                <span class="text-white text-xs font-bold">9</span>
                              </div>
                              <div class="flex-1 pb-6">
                                <p class="text-sm font-semibold text-zinc-900">
                                  Turn right onto Soda Bay Road / HWY 281
                                </p>
                                <p class="text-xs text-zinc-600 mt-1">
                                  Kits Corner Store on right — go 4.3 miles
                                </p>
                              </div>
                            </div>
                            <div class="relative flex gap-4">
                              <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-sm flex items-center justify-center z-10">
                                <span class="text-white text-xs font-bold">10</span>
                              </div>
                              <div class="flex-1 pb-6">
                                <p class="text-sm font-semibold text-zinc-900">
                                  Turn right onto Bass Road
                                </p>
                                <p class="text-xs text-zinc-600 mt-1">
                                  Just after Montezuma Way and a church — go 0.3 miles
                                </p>
                              </div>
                            </div>
                            <div class="relative flex gap-4">
                              <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-700 border-4 border-white shadow-sm flex items-center justify-center z-10">
                                <.icon name="hero-flag" class="w-4 h-4 text-white" />
                              </div>
                              <div class="flex-1">
                                <p class="text-sm font-bold text-teal-700">
                                  Turn right at the third driveway with the YSC sign
                                </p>
                                <p class="text-xs text-zinc-600 mt-1">
                                  You've arrived!
                                </p>
                              </div>
                            </div>
                          </div>
                          <div class="mt-4 p-3 bg-amber-50 border border-amber-200 rounded-xl">
                            <p class="text-sm text-amber-800">
                              <strong>Note:</strong>
                              If you reach Konocti Harbor Inn, you've gone too far — turn around.
                            </p>
                          </div>
                          <!-- Parking Strategy Tip -->
                          <div class="mt-6 p-4 bg-zinc-900 text-white rounded-xl">
                            <div class="flex items-center gap-3 mb-2">
                              <.icon
                                name="hero-truck"
                                class="w-5 h-5 text-teal-400"
                              />
                              <h4 class="font-bold text-base">Parking Strategy</h4>
                            </div>
                            <p class="text-sm text-zinc-300 leading-relaxed">
                              Parking is limited. Please park as close to the next car as possible and choose a spot based on your departure time.
                            </p>
                            <p class="text-sm text-zinc-300 leading-relaxed mt-2">
                              <strong>Pro Tip:</strong>
                              If you plan to leave early Sunday, don't park in the back or you may find yourself blocked in!
                            </p>
                          </div>
                        </div>
                      </details>
                    </div>

                    <div class="space-y-4">
                      <div class="rounded-xl overflow-hidden border border-zinc-200 shadow-sm h-80">
                        <.live_component
                          id="clear-lake-cabin-map"
                          module={YscWeb.Components.MapComponent}
                          latitude={38.98087180833886}
                          longitude={-122.73563627025182}
                          locked={true}
                          class="w-full h-full"
                        />
                      </div>
                      <YscWeb.Components.MapNavigationButtons.map_navigation_buttons
                        latitude={38.98087180833886}
                        longitude={-122.73563627025182}
                        class="w-full"
                      />
                    </div>
                  </div>
                </section>
                <!-- Pre-Arrival Checklist & Door Code -->
                <section class="grid md:grid-cols-2 gap-6">
                  <div
                    id="door-code-access"
                    class="bg-teal-600 rounded-xl p-8 text-white shadow-sm"
                  >
                    <div class="flex items-center gap-3 mb-6">
                      <div class="p-2 bg-white/20 rounded-md">🔑</div>
                      <h2 class="text-xl font-bold text-white">
                        Door Code & Access
                      </h2>
                    </div>
                    <p class="text-teal-100 mb-6 leading-relaxed">
                      Sent via email <strong>24 hours before check-in</strong>. Unique to your booking. The code is also displayed on your booking confirmation page when your stay is within 48 hours of check-in or currently active.
                    </p>
                    <div class="bg-teal-700/50 border border-white/10 rounded-xl p-4 text-sm">
                      <p class="font-semibold text-teal-50 mb-2">Important:</p>
                      <ul class="list-disc list-inside space-y-1 text-teal-100 text-xs">
                        <li>
                          Save the door code before you arrive — cell service can be limited in the area
                        </li>
                        <li>The door code is unique to your booking period</li>
                        <li>
                          If you don't receive the code, check your spam folder or contact the Cabin Master
                        </li>
                      </ul>
                    </div>
                  </div>
                  <div class="bg-zinc-900 rounded-xl p-8 text-white">
                    <h2 class="text-xl font-bold mb-6">Pre-Arrival Checklist</h2>
                    <ul class="space-y-4">
                      <li class="flex items-center gap-3">
                        <input
                          type="checkbox"
                          class="w-5 h-5 rounded border-zinc-700 bg-zinc-800 text-teal-500 focus:ring-0"
                        />
                        <div>
                          <span class="font-semibold">Screenshot Door Code</span>
                          <p class="text-xs text-zinc-400 mt-1">
                            Cell service can be limited at the cabin
                          </p>
                        </div>
                      </li>
                      <li class="flex items-center gap-3">
                        <input
                          type="checkbox"
                          class="w-5 h-5 rounded border-zinc-700 bg-zinc-800 text-teal-500 focus:ring-0"
                        />
                        <div>
                          <span class="font-semibold">Download Offline Maps</span>
                          <p class="text-xs text-zinc-400 mt-1">
                            Kelseyville / Clear Lake area
                          </p>
                        </div>
                      </li>
                      <li class="flex items-center gap-3">
                        <input
                          type="checkbox"
                          class="w-5 h-5 rounded border-zinc-700 bg-zinc-800 text-teal-500 focus:ring-0"
                        />
                        <div>
                          <span class="font-semibold">Pack Linens & Bedding</span>
                          <p class="text-xs text-zinc-400 mt-1">
                            Sheets, pillowcases, comforter or sleeping bag, and towels
                          </p>
                        </div>
                      </li>
                      <li class="flex items-center gap-3">
                        <input
                          type="checkbox"
                          class="w-5 h-5 rounded border-zinc-700 bg-zinc-800 text-teal-500 focus:ring-0"
                        />
                        <div>
                          <span class="font-semibold">Review Parking Tip</span>
                          <p class="text-xs text-zinc-400 mt-1">
                            Leave early Sunday? Don't park in the back
                          </p>
                        </div>
                      </li>
                    </ul>
                  </div>
                </section>
                <!-- Parking & Transportation -->
                <section
                  id="parking-transportation"
                  class="bg-white border border-zinc-200 rounded-xl p-6 shadow-sm"
                >
                  <h2 class="text-xl font-bold text-zinc-900 mb-4 flex items-center gap-2">
                    <span>🚙</span>
                    <span>Parking & Transportation</span>
                  </h2>
                  <div class="grid md:grid-cols-2 gap-6">
                    <div>
                      <p class="font-semibold mb-2 text-zinc-900">Parking Rules:</p>
                      <ul class="list-disc list-inside space-y-1 text-zinc-700">
                        <li>
                          Parking is limited — park as close to the next car as possible.
                        </li>
                        <li>Choose a spot based on your departure time.</li>
                        <li>
                          <strong>Pro Tip:</strong>
                          If you plan to leave early Sunday, don't park in the back or you may find yourself blocked in.
                        </li>
                        <li>Do not block driveways or neighbors' access.</li>
                      </ul>
                    </div>
                    <div>
                      <p class="font-semibold mb-2 text-zinc-900">Getting Here:</p>
                      <p class="text-sm text-zinc-700">
                        Public transportation is very limited.
                        <strong>Driving is essential.</strong>
                        See the step-by-step directions in the Getting There section above.
                      </p>
                    </div>
                  </div>
                </section>
                <!-- CTA Card when booking is unavailable -->
                <div
                  :if={!@can_book}
                  class="p-8 rounded-xl bg-teal-50 border border-teal-100 flex flex-col md:flex-row items-center justify-between gap-6"
                >
                  <div>
                    <h4 class="text-xl font-bold text-teal-900">
                      Ready to reserve?
                    </h4>
                    <p class="text-teal-700">{raw(@booking_disabled_reason)}</p>
                    <p
                      :if={@booking_error_title == "Membership Required"}
                      class="text-teal-600 text-sm mt-2"
                    >
                      Pay or renew your membership to book a cabin.
                    </p>
                  </div>
                  <.link
                    :if={@booking_error_title == "Sign In Required"}
                    navigate={
                      ~p"/users/log-in?#{%{redirect_to: ~p"/bookings/clear-lake"}}"
                    }
                    class="px-8 py-3 bg-teal-600 text-white font-bold rounded-lg hover:bg-teal-700 transition shadow-sm"
                  >
                    Sign In to Book
                  </.link>
                  <.link
                    :if={@booking_error_title == "Application under review"}
                    navigate={~p"/pending-review"}
                    class="px-8 py-3 bg-teal-600 text-white font-bold rounded-lg hover:bg-teal-700 transition shadow-sm"
                  >
                    View application status
                  </.link>
                  <.link
                    :if={@booking_error_title == "Membership Required"}
                    navigate={~p"/users/membership"}
                    class="px-8 py-3 bg-teal-600 text-white font-bold rounded-lg hover:bg-teal-700 transition shadow-sm"
                  >
                    Pay or renew membership
                  </.link>
                </div>
                <!-- What to Bring -->
                <section class="bg-teal-900 rounded-xl p-8 text-white">
                  <h2 class="text-lg font-bold mb-6">The Packing List</h2>
                  <ul class="space-y-4 text-sm text-teal-100">
                    <li class="flex items-start gap-3">
                      <span class="text-teal-400 mt-0.5">●</span>
                      <div>
                        <span class="block">Linens & Bedding</span>
                        <span class="text-xs text-teal-300">
                          Requirements differ by season. Summer: camping setup on the lawn — sheets, pillowcases, comforter/sleeping bag. Winter: indoor bed setup — see Winter Season card below.
                        </span>
                      </div>
                    </li>
                    <li class="flex items-start gap-3">
                      <span class="text-teal-400 mt-0.5">●</span>
                      <div>
                        <span class="block">Towels</span>
                        <span class="text-xs text-teal-300">
                          Bath & beach towels
                        </span>
                      </div>
                    </li>
                    <li class="flex items-center gap-3">
                      <span class="text-teal-400">●</span> Reusable Water Bottle
                    </li>
                    <li class="flex items-center gap-3">
                      <span class="text-teal-400">●</span> Sunscreen & Swimsuit
                    </li>
                  </ul>
                </section>
                <!-- Lake Lore -->
                <section class="bg-zinc-900 rounded-xl p-8 text-white">
                  <h2 class="text-lg font-bold mb-4 flex items-center gap-2">
                    <.icon
                      name="hero-information-circle"
                      class="w-6 h-6 text-teal-400"
                    /> Lake Lore
                  </h2>
                  <div class="space-y-4 text-base text-zinc-300">
                    <p>
                      <strong class="text-white">2.5 Million Years:</strong>
                      Clear Lake is the oldest lake in North America, offering a unique ecosystem for bird watching and fishing year-round.
                    </p>
                    <p>
                      <strong class="text-white">A Member Sanctuary:</strong>
                      Everything you see was built and is maintained by our community. We don't just stay here; we preserve and cherish it together.
                    </p>
                  </div>
                </section>
                <!-- Winter Season -->
                <section class="bg-amber-50 border-2 border-amber-200 rounded-xl p-6 shadow-sm">
                  <h2 class="text-lg font-bold mb-3 flex items-center gap-2 text-amber-900">
                    <span class="text-xl">❄️</span> Winter Season (Oct–April)
                  </h2>
                  <div class="space-y-3">
                    <p class="text-base text-amber-900 leading-relaxed font-semibold">
                      <span class="inline-block mr-1">🛏️</span>
                      Indoor beds are set up in the cabin during winter months!
                    </p>
                    <p class="text-sm text-amber-800 leading-relaxed">
                      Please bring your own linens: sheets, pillowcases, comforter or sleeping bag, and towels. We also recommend an extra wool blanket and indoor slippers to keep cozy in the Social Hall.
                    </p>
                  </div>
                </section>
                <!-- Amenities -->
                <section
                  id="amenities"
                  class="bg-white border border-zinc-200 rounded-xl p-6 shadow-sm"
                >
                  <h2 class="text-xl font-bold text-zinc-900 mb-4 flex items-center gap-2">
                    <span>🏠</span>
                    <span>Everything You Need for a Perfect Stay</span>
                  </h2>
                  <ul class="space-y-3 text-zinc-700">
                    <li class="flex gap-3">
                      <span class="text-teal-600 font-bold">•</span>
                      <span>
                        <strong>The Iconic Private Dock</strong>
                        — Deep-water swimming, sunbathing, boat mooring.
                      </span>
                    </li>
                    <li class="flex gap-3">
                      <span class="text-teal-600 font-bold">•</span>
                      <span>
                        <strong>Social Hall & Dance Floor</strong>
                        — Cedar hall with wood-burning fireplace.
                      </span>
                    </li>
                    <li class="flex gap-3">
                      <span class="text-teal-600 font-bold">•</span>
                      <span>
                        <strong>Gourmet Group Kitchen</strong>
                        — Industrial stoves, ample fridge space.
                      </span>
                    </li>
                    <li class="flex gap-3">
                      <span class="text-teal-600 font-bold">•</span>
                      <span>
                        <strong>Sleeping</strong>
                        — Summer: sleeping lawn (bring sleeping bags). Winter: indoor beds (bring linens & comforter).
                      </span>
                    </li>
                  </ul>
                </section>
                <!-- Stewards of the Lake Section -->
                <section class="bg-amber-50 rounded-xl p-8 lg:p-12 border border-amber-100 mb-20">
                  <div class="grid grid-cols-1 lg:grid-cols-3 gap-12 items-start">
                    <div class="lg:col-span-2">
                      <h2 class="text-3xl font-bold text-zinc-900 mb-4">
                        The Dock Revival Project
                      </h2>
                      <p class="text-zinc-700 mb-6 leading-relaxed">
                        The heart of the cabin is its dock. In 2023, after brutal winter storms, our members rallied together to rebuild our private mooring. We are currently raising $45,000 to ensure this landmark outlasts the next 20 years.
                      </p>

                      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-8">
                        <div class="p-4 bg-white border border-amber-200 rounded-xl shadow-sm">
                          <p class="text-base font-bold text-amber-900">
                            $150 — Legacy Tier
                          </p>
                          <p class="text-sm text-zinc-600">
                            Your name inscribed on a tile on the cabin fireplace mantle for eternity.
                          </p>
                        </div>
                        <div class="p-4 bg-white border border-amber-200 rounded-xl shadow-sm">
                          <p class="text-base font-bold text-amber-900">
                            $100 — Captain's Tier
                          </p>
                          <p class="text-sm text-zinc-600">
                            Includes a $15 coupon for any Clear Lake summer event.
                          </p>
                        </div>
                      </div>

                      <div class="bg-white border-2 border-amber-200 rounded-xl p-6 shadow-sm">
                        <p class="text-base text-amber-900 leading-relaxed mb-2">
                          <strong>
                            Interested in contributing to the Dock Revival Project?
                          </strong>
                        </p>
                        <p class="text-sm text-zinc-600 leading-relaxed mb-3">
                          Reach out to the club through our contact page to learn more about donation options and legacy tiers.
                        </p>
                      </div>
                    </div>

                    <div class="space-y-6">
                      <div class="bg-white p-6 rounded-xl shadow-sm border border-amber-200">
                        <h4 class="font-bold text-zinc-900 mb-3 text-base uppercase tracking-wider">
                          Honorary Stewards
                        </h4>
                        <p class="text-sm text-zinc-500 leading-relaxed">
                          Special thanks to
                          <strong>
                            Allen Hinkelman, Solveig Barnes, and Dave Conroy
                          </strong>
                          for taking the lead in 2019 to turn this dream into a reality.
                        </p>
                      </div>
                    </div>
                  </div>
                </section>
                <!-- Footer -->
                <div class="mt-12 pt-8 border-t border-zinc-100 text-center">
                  <p class="text-sm text-zinc-600 italic">
                    The Clear Lake cabin has been a member-run treasure since 1963. Thank you for doing your part to keep it clean for the next family.
                  </p>
                </div>
              </div>
              <!-- Tab Content: Cabin & Booking Rules -->
              <div
                :if={Map.get(assigns, :info_tab, :general) == :rules}
                id="cabin-rules"
                class="space-y-16"
              >
                <!-- Golden Rules Banner -->
                <section class="bg-zinc-100 rounded-xl p-6 mb-12">
                  <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <div class="bg-white rounded-xl p-5 text-center border border-zinc-200 shadow-sm">
                      <div class="text-4xl mb-3">🚫</div>
                      <div class="font-bold text-red-900 text-lg mb-1">No Pets</div>
                      <div class="text-sm text-red-700">No exceptions</div>
                    </div>
                    <div class="bg-white rounded-xl p-5 text-center border border-zinc-200 shadow-sm">
                      <div class="text-4xl mb-3">🧺</div>
                      <div class="font-bold text-amber-900 text-lg mb-1">
                        Bring Own Linens
                      </div>
                      <div class="text-sm text-amber-700">
                        Sheets, Pillowcases, Comforters or Sleeping Bags & Towels Required
                      </div>
                    </div>
                    <div class="bg-white rounded-xl p-5 text-center border border-zinc-200 shadow-sm">
                      <div class="text-4xl mb-3">🚭</div>
                      <div class="font-bold text-red-900 text-lg mb-1">
                        No Smoking
                      </div>
                      <div class="text-sm text-red-700">Indoors or on decks</div>
                    </div>
                  </div>
                </section>
                <!-- Your Stay, Your Way - Accordions -->
                <section class="bg-zinc-50 rounded-xl p-8 lg:p-12 mb-4">
                  <div class="max-w-3xl">
                    <h2 class="text-3xl font-bold text-zinc-900 mb-4">
                      Your Stay, Your Way
                    </h2>
                    <p class="text-zinc-600 mb-10 leading-relaxed">
                      Since 1963, our cabin has been a place of relaxation and connection. Here's what you need to know for the perfect getaway.
                    </p>

                    <div class="space-y-4">
                      <details class="group bg-white border border-zinc-200 rounded-xl transition-all">
                        <summary class="p-5 cursor-pointer font-bold flex justify-between items-center list-none hover:text-teal-700">
                          <span class="flex items-center gap-3">
                            <span class="text-xl">🌊</span>
                            <span>Lake Life & Activities</span>
                          </span>
                          <.icon
                            name="hero-chevron-down"
                            class="w-5 h-5 text-zinc-400 chevron-icon transition-transform"
                          />
                        </summary>
                        <div class="px-5 pb-5 text-base text-zinc-600 space-y-3 border-t border-zinc-50 pt-4">
                          <p>
                            <strong>Private Dock Access:</strong>
                            Enjoy swimming, boating, and fishing from our exclusive 100-foot dock. Perfect for morning coffee on the water or sunset views.
                          </p>
                          <p>
                            <strong>Peaceful Atmosphere:</strong>
                            We maintain quiet hours starting at midnight to ensure everyone can enjoy restful nights by the lake.
                          </p>
                          <p>
                            <strong>Family-Friendly:</strong>
                            Most weekends welcome families and guests of all ages. Check specific event descriptions for any age restrictions.
                          </p>
                          <p>
                            <strong>Bring Your Guests:</strong>
                            Non-member guests are welcome! All guests must be included in your reservation. Check event details for any specific restrictions.
                          </p>
                        </div>
                      </details>

                      <details class="group bg-white border border-zinc-200 rounded-xl transition-all">
                        <summary class="p-5 cursor-pointer font-bold flex justify-between items-center list-none hover:text-teal-700">
                          <span class="flex items-center gap-3">
                            <span class="text-xl">⚓</span>
                            <span>Property & Water Access</span>
                          </span>
                          <.icon
                            name="hero-chevron-down"
                            class="w-5 h-5 text-zinc-400 chevron-icon transition-transform"
                          />
                        </summary>
                        <div class="px-5 pb-5 text-sm text-zinc-600 space-y-4 border-t border-zinc-50 pt-4">
                          <p>
                            <strong>No Pets Policy:</strong>
                            To protect local wildlife and maintain a pristine environment, pets are not permitted on the property.
                          </p>
                          <p>
                            <strong>Boating & Dock Access:</strong>
                            Members enjoy free mooring at our private dock. Please notify the Cabin Master in advance.
                            <em>Note: trailers must be parked off-site.</em>
                          </p>
                          <div class="p-4 bg-rose-50 border border-rose-100 rounded-lg text-rose-800 text-xs">
                            <strong>⚠️ Quagga Mussel Warning:</strong>
                            Mandatory boat inspection required. Violations result in a $1,000 fine from Lake County.
                          </div>
                        </div>
                      </details>

                      <.link
                        navigate={~p"/code-of-conduct"}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="flex items-center justify-between p-5 bg-white border border-zinc-200 rounded-xl font-bold hover:bg-zinc-100 transition-colors"
                      >
                        <span class="flex items-center gap-3">
                          <span class="text-xl">📜</span>
                          <span>Code of Conduct</span>
                        </span>
                        <.icon
                          name="hero-arrow-top-right-on-square"
                          class="w-5 h-5 text-zinc-400"
                        />
                      </.link>
                    </div>
                  </div>
                </section>
                <!-- Booking Policies -->
                <section class="bg-white border border-zinc-200 rounded-xl p-6 shadow-sm mb-12">
                  <h2 class="text-xl font-bold text-zinc-900 mb-6 flex items-center gap-2">
                    <.icon name="hero-document-text" class="w-6 h-6" />
                    <span>Booking Policies</span>
                  </h2>
                  <div class="space-y-4">
                    <div class="p-5 bg-zinc-50 rounded-xl border border-zinc-200">
                      <h3 class="font-semibold text-zinc-900 mb-2">
                        Reservation Requirements
                      </h3>
                      <ul class="list-disc list-inside space-y-2 text-zinc-700">
                        <li>
                          All reservations must be made and paid in advance on the website
                        </li>
                        <li>
                          Check event or season details for any limits on active reservations per membership
                        </li>
                      </ul>
                    </div>
                    <p class="text-sm text-zinc-600">
                      Cancellation and refund policies depend on booking type and season. See your confirmation email and the cabin rules for full details.
                    </p>
                  </div>
                </section>
              </div>
            </div>
          </div>
        </div>
      </section>
      <%!-- Hero Section with Carousel (For non-logged-in users) --%>
      <section
        :if={!@user}
        id="hero-section"
        class="relative w-full overflow-hidden hero-nav-overlap min-h-[60vh] md:min-h-[75vh]"
      >
        <div
          id="clear-lake-carousel-wrapper-nonuser"
          phx-hook="ImageCarouselAutoplay"
          class="absolute inset-0 h-full w-full z-[2]"
        >
          <YscWeb.Components.ImageCarousel.image_carousel
            id="about-the-clear-lake-cabin-carousel"
            images={[
              %{
                src: ~p"/images/clear_lake/clear_lake_main.webp",
                alt: "Clear Lake Cabin Exterior"
              },
              %{
                src: ~p"/images/history/clear_lake_from_above.webp",
                alt: "Clear Lake Aerial View"
              },
              %{
                src: ~p"/images/clear_lake/clear_lake_dock.webp",
                alt: "Clear Lake Dock"
              },
              %{
                src: ~p"/images/clear_lake/clear_lake_dock_2.webp",
                alt: "Clear Lake Dock"
              },
              %{
                src: ~p"/images/clear_lake/clear_lake_sweep.webp",
                alt: "Clear Lake"
              },
              %{
                src: ~p"/images/clear_lake/clear_lake_cabin.webp",
                alt: "Clear Lake Cabin"
              }
            ]}
            class="h-full w-full"
          />
          <div
            class="absolute inset-0 z-[5] bg-black/40 pointer-events-none"
            aria-hidden="true"
          >
          </div>
        </div>
        <%!-- Title Text Section --%>
        <div class="absolute bottom-0 left-0 right-0 z-[10] px-4 py-12 md:py-20 pointer-events-none">
          <div class="max-w-screen-xl mx-auto pointer-events-auto">
            <p class="text-sm font-black text-blue-400 uppercase tracking-[0.2em] mb-3 md:mb-4 drop-shadow-md">
              A Legacy for All Seasons
            </p>
            <h1 class="text-4xl md:text-7xl font-black text-white drop-shadow-lg mb-4">
              Clear Lake Cabin
            </h1>
            <p class="text-base md:text-xl text-zinc-100 max-w-2xl font-normal drop-shadow-md">
              Owned and operated by our community since 1963. A year-round gateway to California's oldest natural lake.
            </p>
          </div>
        </div>
      </section>
      <%!-- Main Content for Non-Logged-In Users --%>
      <section :if={!@user} class="bg-white py-6 md:py-12">
        <%!-- Section Header --%>
        <div class="max-w-screen-xl mx-auto px-4 mb-8 md:mb-16">
          <div class="text-center py-8 md:py-12 border-y border-zinc-200">
            <p class="text-sm font-black text-blue-600 uppercase tracking-[0.2em] mb-3 md:mb-4">
              Since 1963
            </p>
            <h2 class="text-4xl md:text-7xl font-black text-zinc-900">
              Experience Clear Lake
            </h2>
          </div>
        </div>
        <%!-- Feature Grid --%>
        <div class="max-w-screen-xl mx-auto px-4">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6 lg:gap-8 max-w-5xl mx-auto">
            <%!-- Private Dock --%>
            <div class="p-6 md:p-8 bg-zinc-50 rounded-xl border border-zinc-100">
              <h4 class="text-sm font-black text-zinc-500 uppercase tracking-[0.2em] mb-4 md:mb-6">
                Private Dock Access
              </h4>
              <p class="text-sm md:text-base text-zinc-600 leading-relaxed">
                Swim, boat, and unwind at our private dock. Perfect for mooring your boat, enjoying morning coffee over the water, or taking a refreshing dip in California's largest natural lake.
              </p>
            </div>
            <%!-- Year-Round Access --%>
            <div class="p-6 md:p-8 bg-zinc-50 rounded-xl border border-zinc-100">
              <h4 class="text-sm font-black text-zinc-500 uppercase tracking-[0.2em] mb-4 md:mb-6">
                Year-Round Access
              </h4>
              <p class="text-sm md:text-base text-zinc-600 leading-relaxed">
                <strong class="text-zinc-900">Summer (May–Sept):</strong>
                Legendary dock parties and sleeping under the stars on our lawn.<br />
                <strong class="text-zinc-900">Winter (Oct–April):</strong>
                Cozy indoor beds set up in the cabin for warm, comfortable lakeside retreats.
              </p>
            </div>
            <%!-- Community Treasure --%>
            <div class="p-6 md:p-8 bg-zinc-50 rounded-xl border border-zinc-100">
              <h4 class="text-sm font-black text-zinc-500 uppercase tracking-[0.2em] mb-4 md:mb-6">
                A Community Treasure
              </h4>
              <p class="text-sm md:text-base text-zinc-600 leading-relaxed">
                Owned and operated by our members since 1963. <strong class="text-zinc-900">Your cabin, your getaway</strong>. Low rates and authentic experiences made possible through our cooperative spirit.
              </p>
            </div>
            <%!-- California's Oldest Lake --%>
            <div class="p-6 md:p-8 bg-zinc-50 rounded-xl border border-zinc-100">
              <h4 class="text-sm font-black text-zinc-500 uppercase tracking-[0.2em] mb-4 md:mb-6">
                California's Oldest Lake
              </h4>
              <p class="text-sm md:text-base text-zinc-600 leading-relaxed">
                Clear Lake is
                <strong class="text-zinc-900">2.5 million years old</strong>
                — the oldest natural lake in North America. Experience a unique ecosystem perfect for bird watching, fishing, and connecting with nature year-round.
              </p>
            </div>
          </div>
          <%!-- CTA Card --%>
          <div class="mt-12 md:mt-16 max-w-2xl mx-auto">
            <div class="p-8 md:p-12 bg-blue-50/40 rounded-xl border border-blue-200 text-center flex flex-col items-center">
              <h4 class="text-sm font-black text-blue-600 uppercase tracking-[0.2em] mb-3 md:mb-4">
                Ready to Book?
              </h4>
              <p class="text-base text-zinc-700 leading-relaxed mb-6">
                Sign in to view the cabin calendar, check availability, and reserve your dates.
              </p>
              <.link
                navigate={
                  ~p"/users/log-in?#{%{redirect_to: ~p"/bookings/clear-lake"}}"
                }
                class="px-8 py-3 bg-blue-600 text-white text-sm font-bold rounded hover:bg-blue-700 transition-colors duration-150"
              >
                Sign In to Book
              </.link>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end

  @impl true
  def handle_event(
        "date-changed",
        %{
          "checkin_date" => checkin_date_str,
          "checkout_date" => checkout_date_str
        },
        socket
      ) do
    checkin_date = parse_date(checkin_date_str)
    checkout_date = parse_date(checkout_date_str)

    date_form =
      to_form(
        %{
          "checkin_date" => date_to_datetime_string(checkin_date),
          "checkout_date" => date_to_datetime_string(checkout_date)
        },
        as: "booking_dates"
      )

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        calculated_price: nil,
        price_error: nil,
        form_errors: %{},
        date_form: date_form
      )
      |> calculate_price_if_ready()
      |> update_url_with_dates(checkin_date, checkout_date)

    {:noreply, socket}
  end

  def handle_event(
        "date-changed",
        %{"checkin_date" => checkin_date_str},
        socket
      ) do
    checkin_date = parse_date(checkin_date_str)
    # Preserve existing checkout_date
    checkout_date = socket.assigns.checkout_date

    date_form =
      to_form(
        %{
          "checkin_date" => date_to_datetime_string(checkin_date),
          "checkout_date" => date_to_datetime_string(checkout_date)
        },
        as: "booking_dates"
      )

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        calculated_price: nil,
        price_error: nil,
        form_errors: %{},
        date_form: date_form
      )
      |> calculate_price_if_ready()
      |> update_url_with_dates(checkin_date, checkout_date)

    {:noreply, socket}
  end

  def handle_event(
        "date-changed",
        %{"checkout_date" => checkout_date_str},
        socket
      ) do
    checkout_date = parse_date(checkout_date_str)
    # Preserve existing checkin_date
    checkin_date = socket.assigns.checkin_date

    date_form =
      to_form(
        %{
          "checkin_date" => date_to_datetime_string(checkin_date),
          "checkout_date" => date_to_datetime_string(checkout_date)
        },
        as: "booking_dates"
      )

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        calculated_price: nil,
        price_error: nil,
        form_errors: %{},
        date_form: date_form
      )
      |> calculate_price_if_ready()
      |> update_url_with_dates(checkin_date, checkout_date)

    {:noreply, socket}
  end

  def handle_event("booking-mode-changed", %{"booking_mode" => "day"}, socket) do
    # Re-check allowed booking modes based on current dates
    {day_booking_allowed, buyout_booking_allowed} =
      allowed_booking_modes(
        socket.assigns.property,
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        socket.assigns.current_season,
        socket.assigns.seasons
      )

    # Validate availability for the new booking mode if dates are selected
    availability_error =
      if socket.assigns.checkin_date && socket.assigns.checkout_date do
        validate_date_range_for_booking_mode(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date,
          :day,
          socket.assigns.guests_count,
          socket.assigns
        )
      else
        nil
      end

    socket =
      socket
      |> assign(
        selected_booking_mode: :day,
        calculated_price: nil,
        price_error: nil,
        availability_error: availability_error,
        day_booking_allowed: day_booking_allowed,
        buyout_booking_allowed: buyout_booking_allowed
      )
      |> calculate_price_if_ready()
      |> then(fn updated_socket ->
        # Update URL with new booking mode
        update_url_with_booking_mode(updated_socket)
      end)

    {:noreply, socket}
  end

  def handle_event(
        "booking-mode-changed",
        %{"booking_mode" => "buyout"},
        socket
      ) do
    # Re-check allowed booking modes based on current dates
    {day_booking_allowed, buyout_booking_allowed} =
      allowed_booking_modes(
        socket.assigns.property,
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        socket.assigns.current_season,
        socket.assigns.seasons
      )

    # Validate availability for the new booking mode if dates are selected
    availability_error =
      if socket.assigns.checkin_date && socket.assigns.checkout_date do
        validate_date_range_for_booking_mode(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date,
          :buyout,
          socket.assigns.guests_count,
          socket.assigns
        )
      else
        nil
      end

    socket =
      socket
      |> assign(
        selected_booking_mode: :buyout,
        calculated_price: nil,
        price_error: nil,
        availability_error: availability_error,
        day_booking_allowed: day_booking_allowed,
        buyout_booking_allowed: buyout_booking_allowed
      )
      |> calculate_price_if_ready()
      |> then(fn updated_socket ->
        # Update URL with new booking mode
        update_url_with_booking_mode(updated_socket)
      end)

    {:noreply, socket}
  end

  def handle_event("guests-changed", %{"guests_count" => guests_str}, socket) do
    guests_count = parse_integer(guests_str) || 1

    # Ensure guests_count is at least 1
    guests_count = max(guests_count, 1)

    # Check if the selected dates still have enough spots available
    availability_error =
      if socket.assigns.selected_booking_mode == :day &&
           socket.assigns.checkin_date &&
           socket.assigns.checkout_date do
        validate_guests_against_availability(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date,
          guests_count,
          socket.assigns
        )
      else
        nil
      end

    socket =
      socket
      |> assign(
        guests_count: guests_count,
        calculated_price: nil,
        price_error: nil,
        availability_error: availability_error,
        guests_dropdown_open: socket.assigns.guests_dropdown_open
      )
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("increase-guests", _params, socket) do
    current_count = socket.assigns.guests_count || 1
    new_count = current_count + 1

    # Check if the selected dates still have enough spots available
    availability_error =
      if socket.assigns.selected_booking_mode == :day &&
           socket.assigns.checkin_date &&
           socket.assigns.checkout_date do
        validate_guests_against_availability(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date,
          new_count,
          socket.assigns
        )
      else
        nil
      end

    socket =
      socket
      |> assign(
        guests_count: new_count,
        calculated_price: nil,
        price_error: nil,
        availability_error: availability_error,
        guests_dropdown_open: socket.assigns.guests_dropdown_open
      )
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("decrease-guests", _params, socket) do
    current_count = socket.assigns.guests_count || 1
    new_count = max(current_count - 1, 1)

    # Check if the selected dates still have enough spots available
    availability_error =
      if socket.assigns.selected_booking_mode == :day &&
           socket.assigns.checkin_date &&
           socket.assigns.checkout_date do
        validate_guests_against_availability(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date,
          new_count,
          socket.assigns
        )
      else
        nil
      end

    socket =
      socket
      |> assign(
        guests_count: new_count,
        calculated_price: nil,
        price_error: nil,
        availability_error: availability_error,
        guests_dropdown_open: socket.assigns.guests_dropdown_open
      )
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("toggle-guests-dropdown", _params, socket) do
    {:noreply,
     assign(socket, guests_dropdown_open: !socket.assigns.guests_dropdown_open)}
  end

  def handle_event("close-guests-dropdown", _params, socket) do
    socket =
      socket
      |> assign(guests_dropdown_open: false)
      |> then(fn updated_socket ->
        update_url_with_guests(updated_socket)
      end)

    {:noreply, socket}
  end

  def handle_event("ignore", _params, socket) do
    # Handler to prevent click-away from closing dropdown when clicking inside
    {:noreply, socket}
  end

  def handle_event("payment-redirect-started", _params, socket) do
    # Acknowledge that the payment redirect has started (no action needed)
    {:noreply, socket}
  end

  def handle_event("reset-dates", _params, socket) do
    date_form =
      to_form(
        %{
          "checkin_date" => "",
          "checkout_date" => ""
        },
        as: "booking_dates"
      )

    socket =
      socket
      |> assign(
        checkin_date: nil,
        checkout_date: nil,
        calculated_price: nil,
        price_error: nil,
        availability_error: nil,
        date_form: date_form
      )
      |> update_url_with_dates(nil, nil)

    {:noreply, socket}
  end

  def handle_event("create-booking", _params, socket) do
    case validate_and_create_booking(socket) do
      {:ok, booking} ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/bookings/checkout/#{booking.id}")}

      {:error, :insufficient_capacity} ->
        # Re-validate to get specific error message about which dates are unavailable
        availability_error =
          if socket.assigns.selected_booking_mode == :day &&
               socket.assigns.checkin_date &&
               socket.assigns.checkout_date do
            validate_guests_against_availability(
              socket.assigns.checkin_date,
              socket.assigns.checkout_date,
              socket.assigns.guests_count,
              socket.assigns
            )
          else
            "Sorry, there is not enough capacity for your requested dates and number of guests."
          end

        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           availability_error ||
             "Sorry, there is not enough capacity for your requested dates and number of guests.",
           title: "Booking"
         )
         |> assign(
           form_errors: %{
             general:
               availability_error ||
                 "Sorry, there is not enough capacity for your requested dates and number of guests."
           },
           calculated_price: socket.assigns.calculated_price,
           availability_error:
             availability_error || "Not enough capacity available"
         )}

      {:error, :property_unavailable} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Sorry, the property is not available for your requested dates.",
           title: "Booking"
         )
         |> assign(
           form_errors: %{
             general:
               "Sorry, the property is not available for your requested dates."
           },
           calculated_price: socket.assigns.calculated_price,
           availability_error: "Property unavailable"
         )}

      {:error, reason} when is_atom(reason) ->
        error_message = format_booking_error(reason)

        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, error_message, title: "Booking")
         |> assign(
           form_errors: %{general: error_message},
           calculated_price: socket.assigns.calculated_price
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        form_errors = format_errors(changeset)
        error_message = "Please fix the errors above and try again."

        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, error_message, title: "Booking")
         |> assign(
           form_errors: form_errors,
           calculated_price: nil,
           price_error: "Please fix the errors above"
         )}

      {:error, {:error, %Ecto.Changeset{} = changeset}} ->
        # Handle nested error from Repo.rollback({:error, changeset})
        form_errors = format_errors(changeset)
        error_message = "Please fix the errors above and try again."

        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, error_message, title: "Booking")
         |> assign(
           form_errors: form_errors,
           calculated_price: nil,
           price_error: "Please fix the errors above"
         )}

      {:error, {:error, reason}} when is_atom(reason) ->
        # Handle nested error from Repo.rollback({:error, reason})
        error_message = format_booking_error(reason)

        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, error_message, title: "Booking")
         |> assign(
           form_errors: %{general: error_message},
           calculated_price: socket.assigns.calculated_price
         )}
    end
  end

  def handle_event("switch-info-tab", %{"tab" => tab}, socket) do
    info_tab =
      case tab do
        "general" -> :general
        "rules" -> :rules
        _ -> :general
      end

    query_params =
      build_query_params(
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        socket.assigns.guests_count,
        socket.assigns.active_tab,
        socket.assigns.selected_booking_mode,
        info_tab
      )

    socket =
      socket
      |> assign(info_tab: info_tab)
      |> then(fn s ->
        if map_size(query_params) > 0 do
          push_patch(s,
            to: ~p"/bookings/clear-lake?#{URI.encode_query(query_params)}"
          )
        else
          push_patch(s, to: ~p"/bookings/clear-lake")
        end
      end)

    {:noreply, socket}
  end

  def handle_event("switch-tab", %{"tab" => tab}, socket) do
    active_tab =
      case tab do
        "information" ->
          :information

        "booking" ->
          # Prevent switching to booking tab if user can't book
          if socket.assigns.can_book do
            :booking
          else
            socket.assigns.active_tab
          end

        _ ->
          socket.assigns.active_tab
      end

    # Only update if tab actually changed
    if active_tab != socket.assigns.active_tab do
      # Update URL with the new tab
      query_params =
        build_query_params(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date,
          socket.assigns.guests_count,
          active_tab,
          socket.assigns.selected_booking_mode || :day,
          socket.assigns[:info_tab]
        )

      socket =
        socket
        |> assign(active_tab: active_tab)
        |> push_patch(
          to: ~p"/bookings/clear-lake?#{URI.encode_query(query_params)}"
        )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {:availability_calendar_date_changed,
         %{checkin_date: checkin_date, checkout_date: checkout_date}},
        socket
      ) do
    date_form =
      to_form(
        %{
          "checkin_date" => date_to_datetime_string(checkin_date),
          "checkout_date" => date_to_datetime_string(checkout_date)
        },
        as: "booking_dates"
      )

    # Validate availability when dates change
    availability_error =
      if socket.assigns.selected_booking_mode == :day &&
           checkin_date &&
           checkout_date &&
           socket.assigns.guests_count do
        validate_guests_against_availability(
          checkin_date,
          checkout_date,
          socket.assigns.guests_count,
          socket.assigns
        )
      else
        nil
      end

    # Re-check allowed booking modes based on new dates
    {day_booking_allowed, buyout_booking_allowed} =
      allowed_booking_modes(
        socket.assigns.property,
        checkin_date,
        checkout_date,
        socket.assigns.current_season,
        socket.assigns.seasons
      )

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        calculated_price: nil,
        price_error: nil,
        availability_error: availability_error,
        form_errors: %{},
        date_form: date_form,
        day_booking_allowed: day_booking_allowed,
        buyout_booking_allowed: buyout_booking_allowed
      )
      |> calculate_price_if_ready()
      |> update_url_with_dates(checkin_date, checkout_date)

    {:noreply, socket}
  end

  def handle_info({:availability_calendar_date_changed, _}, socket) do
    {:noreply, socket}
  end

  def handle_info(:availability_cache_invalidated, socket) do
    socket =
      socket
      |> assign(:availability_cache_version, System.unique_integer([:positive]))
      |> refresh_selection_after_availability_change()

    {:noreply, socket}
  end

  # Helper functions

  defp parse_date(""), do: nil

  defp parse_date(date_str) when is_binary(date_str),
    do: Date.from_iso8601!(date_str)

  defp parse_date(_), do: nil

  defp parse_integer(""), do: nil

  defp parse_integer(int_str) when is_binary(int_str),
    do: String.to_integer(int_str)

  defp parse_integer(_), do: nil

  defp calculate_price_if_ready(socket) do
    PricingHelpers.calculate_price_if_ready(socket, :clear_lake)
  end

  defp can_submit_booking?(
         booking_mode,
         checkin_date,
         checkout_date,
         guests_count,
         availability_error
       ) do
    checkin_date && checkout_date &&
      is_nil(availability_error) &&
      (booking_mode == :buyout || (booking_mode == :day && guests_count > 0))
  end

  defp validate_and_create_booking(socket) do
    property = socket.assigns.property
    checkin_date = socket.assigns.checkin_date
    checkout_date = socket.assigns.checkout_date
    booking_mode = socket.assigns.selected_booking_mode
    guests_count = socket.assigns.guests_count
    user_id = socket.assigns.user.id

    # Validate required fields
    if is_nil(checkin_date) || is_nil(checkout_date) || is_nil(guests_count) ||
         guests_count <= 0 do
      {:error, :invalid_parameters}
    else
      # Use BookingLocker to create booking with inventory locking
      case booking_mode do
        :buyout ->
          BookingLocker.create_buyout_booking(
            user_id,
            property,
            checkin_date,
            checkout_date,
            guests_count
          )

        :day ->
          BookingLocker.create_per_guest_booking(
            user_id,
            property,
            checkin_date,
            checkout_date,
            guests_count
          )

        _ ->
          {:error, :invalid_booking_mode}
      end
    end
  end

  defp format_booking_error(:insufficient_capacity),
    do:
      "Sorry, there is not enough capacity for your requested dates and number of guests."

  defp format_booking_error(:property_unavailable),
    do: "Sorry, the property is not available for your requested dates."

  defp format_booking_error(:stale_inventory),
    do:
      "The availability changed while you were booking. Please refresh the calendar and try again."

  defp format_booking_error(:rooms_already_booked),
    do: "Sorry, some rooms are already booked for your requested dates."

  defp format_booking_error(:invalid_parameters),
    do: "Please fill in all required fields."

  defp format_booking_error(:invalid_booking_mode),
    do: "Invalid booking mode selected."

  defp format_booking_error(_),
    do: "An error occurred while creating your booking. Please try again."

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp check_booking_eligibility(nil) do
    sign_in_path = ~p"/users/log-in?#{%{redirect_to: ~p"/bookings/clear-lake"}}"

    sign_in_link =
      ~s(<a href="#{sign_in_path}" class="font-semibold text-white hover:text-blue-200 underline">sign in</a>)

    {
      false,
      "Sign In Required",
      "You must be signed in to make a booking. Please #{sign_in_link} to continue."
    }
  end

  defp check_booking_eligibility(user) do
    # Check if user account is approved
    if user.state != :active do
      {
        false,
        "Application under review",
        "Your membership application is still being reviewed by the board. You'll be able to make bookings after your application is approved and your membership is active."
      }
    else
      # Check if user has active membership
      # user should already have subscriptions preloaded (with subscription_items)
      # to avoid duplicate queries
      if Accounts.has_active_membership?(user) do
        {true, nil, nil}
      else
        membership_path = ~p"/users/membership"

        membership_link =
          ~s(<a href="#{membership_path}" class="font-semibold text-amber-900 hover:text-amber-950 underline">go to Membership</a>)

        {
          false,
          "Membership Required",
          "You need an active YSC membership to book a cabin. #{membership_link} to pay dues or renew."
        }
      end
    end
  end

  defp get_membership_type(user) do
    if Ysc.Accounts.has_lifetime_membership?(user) do
      :lifetime
    else
      subscriptions =
        case user.subscriptions do
          %Ecto.Association.NotLoaded{} ->
            Subscriptions.list_subscriptions(user)

          subscriptions when is_list(subscriptions) ->
            subscriptions

          _ ->
            []
        end

      active_subscriptions =
        Enum.filter(subscriptions, fn sub ->
          Subscriptions.valid?(sub)
        end)

      case active_subscriptions do
        [] ->
          :none

        [subscription | _] ->
          get_membership_type_from_subscription(subscription)
      end
    end
  end

  defp get_membership_type_from_subscription(subscription) do
    case YscWeb.UserAuth.get_membership_plan_type(subscription) do
      nil -> :none
      plan_id -> plan_id
    end
  end

  defp date_to_datetime_string(nil), do: ""

  defp date_to_datetime_string(date) when is_struct(date, Date) do
    date
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp parse_query_params(params, _uri) when is_map(params) do
    # Check if params are malformed (single key with entire query string as key)
    case find_malformed_query_key(params) do
      nil ->
        # Params are already correctly parsed
        params

      malformed_key ->
        # Params are malformed - the entire query string is the key
        parsed = parse_query_string(malformed_key)
        # Remove the malformed key from params before merging
        clean_params = Map.delete(params, malformed_key)
        Map.merge(parsed, clean_params)
    end
  end

  defp parse_query_params(_params, uri) do
    # If params is not a map, try to parse from URI
    case URI.parse(uri) do
      %URI{query: nil} -> %{}
      %URI{query: query} -> parse_query_string(query)
    end
  end

  defp find_malformed_query_key(params) when is_map(params) do
    Enum.find_value(params, fn {key, _value} ->
      if is_binary(key) and String.contains?(key, "=") do
        key
      else
        nil
      end
    end)
  end

  defp parse_query_string(""), do: %{}

  defp parse_query_string(query_string) when is_binary(query_string) do
    query_string
    |> URI.decode_query()
  end

  defp parse_query_string(_), do: %{}

  # Parse params in mount - handle malformed query strings
  defp parse_mount_params(params) when is_map(params) do
    # Check if params are malformed (single key with entire query string as key)
    case find_malformed_query_key(params) do
      nil ->
        # Params are already correctly parsed
        params

      malformed_key ->
        # Params are malformed - the entire query string is the key
        parsed = parse_query_string(malformed_key)
        # Remove the malformed key from params before merging
        clean_params = Map.delete(params, malformed_key)
        Map.merge(parsed, clean_params)
    end
  end

  defp parse_mount_params(_), do: %{}

  defp parse_dates_from_params(params) do
    checkin_date =
      case params["checkin_date"] || params[:checkin_date] do
        nil ->
          nil

        date_str when is_binary(date_str) ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> date
            _ -> nil
          end

        _ ->
          nil
      end

    checkout_date =
      case params["checkout_date"] || params[:checkout_date] do
        nil ->
          nil

        date_str when is_binary(date_str) ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> date
            _ -> nil
          end

        _ ->
          nil
      end

    {checkin_date, checkout_date}
  end

  defp parse_guests_from_params(params) do
    case Map.get(params, "guests_count") do
      nil ->
        1

      guests_str when is_binary(guests_str) ->
        case Integer.parse(guests_str) do
          {parsed, _} when parsed > 0 -> parsed
          _ -> 1
        end

      guests when is_integer(guests) and guests > 0 ->
        guests

      _ ->
        1
    end
  end

  defp parse_tab_from_params(params) do
    case Map.get(params, "tab") do
      "information" -> :information
      "booking" -> :booking
      _ -> :booking
    end
  end

  defp parse_info_tab_from_params(params) do
    case Map.get(params, "info_tab") do
      "general" -> :general
      "rules" -> :rules
      _ -> nil
    end
  end

  defp parse_booking_mode_from_params(params) do
    case Map.get(params, "booking_mode") do
      "buyout" -> :buyout
      "day" -> :day
      _ -> nil
    end
  end

  defp resolve_booking_mode(mode, day_allowed, buyout_allowed) do
    cond do
      # If mode is explicitly valid, use it
      mode == :day && day_allowed ->
        :day

      mode == :buyout && buyout_allowed ->
        :buyout

      # If mode is nil (default), prefer day if allowed, else buyout
      is_nil(mode) ->
        if day_allowed, do: :day, else: :buyout

      # If mode is invalid (e.g. day requested but not allowed), try the other
      mode == :day && buyout_allowed ->
        :buyout

      mode == :buyout && day_allowed ->
        :day

      # If nothing works, just return day (error will likely be shown elsewhere)
      true ->
        :day
    end
  end

  defp update_url_with_dates(socket, checkin_date, checkout_date) do
    guests_count = socket.assigns.guests_count || 1
    active_tab = socket.assigns.active_tab || :booking
    booking_mode = socket.assigns.selected_booking_mode || :day

    query_params =
      build_query_params(
        checkin_date,
        checkout_date,
        guests_count,
        active_tab,
        booking_mode,
        socket.assigns[:info_tab]
      )

    if map_size(query_params) > 0 do
      query_string = URI.encode_query(query_params)
      push_patch(socket, to: "/bookings/clear-lake?#{query_string}")
    else
      push_patch(socket, to: ~p"/bookings/clear-lake")
    end
  end

  defp update_url_with_guests(socket) do
    checkin_date = socket.assigns.checkin_date
    checkout_date = socket.assigns.checkout_date
    guests_count = socket.assigns.guests_count || 1
    active_tab = socket.assigns.active_tab || :booking
    booking_mode = socket.assigns.selected_booking_mode || :day

    query_params =
      build_query_params(
        checkin_date,
        checkout_date,
        guests_count,
        active_tab,
        booking_mode,
        socket.assigns[:info_tab]
      )

    if map_size(query_params) > 0 do
      query_string = URI.encode_query(query_params)
      push_patch(socket, to: "/bookings/clear-lake?#{query_string}")
    else
      push_patch(socket, to: ~p"/bookings/clear-lake")
    end
  end

  defp update_url_with_booking_mode(socket) do
    checkin_date = socket.assigns.checkin_date
    checkout_date = socket.assigns.checkout_date
    guests_count = socket.assigns.guests_count || 1
    active_tab = socket.assigns.active_tab || :booking
    booking_mode = socket.assigns.selected_booking_mode || :day

    query_params =
      build_query_params(
        checkin_date,
        checkout_date,
        guests_count,
        active_tab,
        booking_mode,
        socket.assigns[:info_tab]
      )

    if map_size(query_params) > 0 do
      query_string = URI.encode_query(query_params)
      push_patch(socket, to: "/bookings/clear-lake?#{query_string}")
    else
      push_patch(socket, to: ~p"/bookings/clear-lake")
    end
  end

  defp build_query_params(
         checkin_date,
         checkout_date,
         guests_count,
         active_tab,
         booking_mode,
         info_tab
       ) do
    params = %{}

    # Always include dates when they are set
    params =
      if checkin_date do
        Map.put(params, "checkin_date", Date.to_string(checkin_date))
      else
        params
      end

    params =
      if checkout_date do
        Map.put(params, "checkout_date", Date.to_string(checkout_date))
      else
        params
      end

    # Always include guests_count when it's set
    params =
      if guests_count do
        Map.put(params, "guests_count", Integer.to_string(guests_count))
      else
        params
      end

    # Include booking_mode when it's not the default (:day)
    params =
      if booking_mode && booking_mode != :day do
        Map.put(params, "booking_mode", Atom.to_string(booking_mode))
      else
        params
      end

    # Include tab when it's not the default (:booking)
    params =
      if active_tab && active_tab != :booking do
        Map.put(params, "tab", Atom.to_string(active_tab))
      else
        params
      end

    # Include info_tab when it's not the default (:general)
    params = add_info_tab_param(params, info_tab)

    params
  end

  defp add_info_tab_param(params, info_tab)
       when not is_nil(info_tab) and info_tab != :general do
    Map.put(params, "info_tab", Atom.to_string(info_tab))
  end

  defp add_info_tab_param(params, _info_tab), do: params

  # Validates that the selected date range is available for the given booking mode
  defp validate_date_range_for_booking_mode(
         checkin_date,
         checkout_date,
         booking_mode,
         guests_count,
         assigns
       ) do
    # Create a temporary assigns with the booking mode to reuse existing validation logic
    temp_assigns = Map.put(assigns, :selected_booking_mode, booking_mode)

    validate_guests_against_availability(
      checkin_date,
      checkout_date,
      guests_count,
      temp_assigns
    )
  end

  # Validates that the selected dates are available for the given booking mode
  defp validate_guests_against_availability(
         checkin_date,
         checkout_date,
         _guests_count,
         assigns
       ) do
    # Get availability for the date range
    availability =
      Bookings.get_clear_lake_daily_availability(checkin_date, checkout_date)

    # Check each date in the range, but exclude checkout_date
    # Since checkout is at 11 AM and check-in is at 3 PM, the checkout_date
    # is not an occupied night and should not be validated
    # Use Date.range directly without converting to list for better performance
    date_range =
      if Date.compare(checkout_date, checkin_date) == :gt do
        # Exclude checkout_date - only validate nights that will be stayed
        Date.range(checkin_date, Date.add(checkout_date, -1))
      else
        # Edge case: same day check-in/check-out (shouldn't happen, but handle gracefully)
        # Return empty range
        Date.range(checkin_date, checkin_date)
      end

    # Use Enum.any? to short-circuit on first unavailable date
    unavailable_date =
      Enum.find_value(date_range, fn date ->
        day_availability = Map.get(availability, date)

        if day_availability do
          if day_availability.is_blacked_out do
            date
          else
            if assigns[:selected_booking_mode] == :day do
              # For day bookings, only check for blackout/buyout conflicts
              if day_availability.can_book_day, do: nil, else: date
            else
              # For buyout, check if buyout is possible
              if day_availability.can_book_buyout, do: nil, else: date
            end
          end
        else
          # Date not in availability map - assume unavailable
          date
        end
      end)

    if unavailable_date do
      # Build error message for the first unavailable date found
      date_str = Date.to_string(unavailable_date)
      day_availability = Map.get(availability, unavailable_date)

      cond do
        day_availability && day_availability.is_blacked_out ->
          YscWeb.BookingUserMessages.clear_lake_blackout_date(date_str)

        day_availability && assigns[:selected_booking_mode] == :day ->
          "The date #{date_str} isn't available for shared stays — the cabin may be reserved for a private group that day."

        day_availability && assigns[:selected_booking_mode] == :buyout ->
          "The date #{date_str} isn't available for reserving the whole cabin — there are existing shared-stay bookings or another whole-cabin reservation."

        true ->
          "The date #{date_str} is unavailable for your selected number of guests."
      end
    else
      nil
    end
  end

  defp refresh_selection_after_availability_change(socket) do
    if socket.assigns.checkin_date && socket.assigns.checkout_date do
      socket
      |> validate_all_conditions(
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        socket.assigns.selected_booking_mode,
        socket.assigns.guests_count,
        socket.assigns.current_season
      )
      |> calculate_price_if_ready()
    else
      socket
    end
  end

  # Validates all conditions for the booking: availability, booking mode restrictions, guest limits, etc.
  # This should be called whenever dates, guests, or booking mode change to ensure data integrity
  # This is especially important when URL parameters are manipulated by users
  defp validate_all_conditions(
         socket,
         checkin_date,
         checkout_date,
         booking_mode,
         guests_count,
         current_season
       ) do
    {day_booking_allowed, buyout_booking_allowed} =
      allowed_booking_modes(
        socket.assigns.property,
        checkin_date,
        checkout_date,
        current_season,
        socket.assigns.seasons
      )

    validated_guests_count = normalize_guests_count(guests_count)
    validated_booking_mode = normalize_booking_mode(booking_mode)

    {validated_checkin_date, validated_checkout_date} =
      normalize_dates(checkin_date, checkout_date, socket.assigns.today)

    booking_mode_error =
      check_booking_mode_allowed(
        validated_booking_mode,
        day_booking_allowed,
        buyout_booking_allowed
      )

    availability_error =
      check_availability_error(
        validated_checkin_date,
        validated_checkout_date,
        booking_mode_error,
        validated_booking_mode,
        validated_guests_count,
        socket.assigns
      )

    final_error = booking_mode_error || availability_error

    update_socket_with_validation(
      socket,
      validated_checkin_date,
      validated_checkout_date,
      validated_guests_count,
      validated_booking_mode,
      final_error,
      day_booking_allowed,
      buyout_booking_allowed
    )
  end

  defp normalize_guests_count(guests_count) do
    max(guests_count, 1)
  end

  defp normalize_booking_mode(booking_mode) do
    if booking_mode in [:day, :buyout], do: booking_mode, else: :day
  end

  defp normalize_dates(checkin_date, checkout_date, today_assign) do
    if checkin_date && checkout_date do
      today =
        today_assign || DateTime.now!(default_timezone()) |> DateTime.to_date()

      validated_checkin_date =
        if Date.compare(checkin_date, today) == :lt,
          do: today,
          else: checkin_date

      validated_checkout_date =
        if Date.compare(checkout_date, validated_checkin_date) != :gt do
          Date.add(validated_checkin_date, 1)
        else
          checkout_date
        end

      {validated_checkin_date, validated_checkout_date}
    else
      {checkin_date, checkout_date}
    end
  end

  defp check_booking_mode_allowed(
         booking_mode,
         day_booking_allowed,
         buyout_booking_allowed
       ) do
    cond do
      booking_mode == :day && !day_booking_allowed ->
        "Shared stays are not available for the selected dates. Try different dates or reserve the whole cabin if that option is open."

      booking_mode == :buyout && !buyout_booking_allowed ->
        "Reserving the whole cabin is not available for the selected dates. Try different dates or choose a shared stay if that option is open."

      true ->
        nil
    end
  end

  defp check_availability_error(
         checkin_date,
         checkout_date,
         booking_mode_error,
         booking_mode,
         guests_count,
         assigns
       ) do
    if checkin_date && checkout_date && is_nil(booking_mode_error) do
      validate_date_range_for_booking_mode(
        checkin_date,
        checkout_date,
        booking_mode,
        guests_count,
        assigns
      )
    else
      nil
    end
  end

  defp update_socket_with_validation(
         socket,
         checkin_date,
         checkout_date,
         guests_count,
         booking_mode,
         availability_error,
         day_booking_allowed,
         buyout_booking_allowed
       ) do
    socket
    |> assign(
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      guests_count: guests_count,
      selected_booking_mode: booking_mode,
      availability_error: availability_error,
      day_booking_allowed: day_booking_allowed,
      buyout_booking_allowed: buyout_booking_allowed
    )
  end

  # Gets active bookings for a user (bookings that haven't ended yet)
  defp get_active_bookings(user_id, today_date, limit \\ 10) do
    query =
      from b in Booking,
        where: b.user_id == ^user_id,
        where: b.property == :clear_lake,
        where: b.status == :complete,
        where: b.checkout_date >= ^today_date,
        order_by: [asc: b.checkin_date],
        limit: ^limit

    Repo.all(query)
  end

  # Determines which booking modes are allowed based on season settings for the selected dates
  # Returns a tuple: {day_booking_allowed, buyout_booking_allowed}
  defp allowed_booking_modes(
         property,
         checkin_date,
         _checkout_date,
         current_season,
         seasons
       ) do
    case property do
      :clear_lake ->
        season =
          if checkin_date do
            Season.find_season_for_date(seasons, checkin_date)
          else
            current_season
          end

        season_id = if season, do: season.id, else: nil

        # Check if pricing rules exist for each mode in this season
        # This ensures we only allow booking modes that have valid pricing configured for the season
        day_pricing_rule =
          Ysc.Bookings.PricingRule.find_most_specific(
            :clear_lake,
            season_id,
            nil,
            nil,
            :day,
            :per_guest_per_day
          )

        buyout_pricing_rule =
          Ysc.Bookings.PricingRule.find_most_specific(
            :clear_lake,
            season_id,
            nil,
            nil,
            :buyout,
            :buyout_fixed
          )

        day_booking_allowed = !is_nil(day_pricing_rule)
        buyout_booking_allowed = !is_nil(buyout_pricing_rule)

        {day_booking_allowed, buyout_booking_allowed}

      _ ->
        # Default: allow both modes
        {true, true}
    end
  end

  defp get_timezone_from_socket(socket) do
    connect_params = get_connect_params(socket) || %{}
    Map.get(connect_params, "timezone", "America/Los_Angeles")
  end

  defp today_in_timezone(timezone)
       when is_binary(timezone) and timezone != "" do
    DateTime.now!(timezone) |> DateTime.to_date()
  rescue
    _ -> DateTime.now!(default_timezone()) |> DateTime.to_date()
  end

  defp today_in_timezone(_),
    do: DateTime.now!(default_timezone()) |> DateTime.to_date()

  defp default_timezone,
    do: Application.get_env(:ysc, :default_timezone, "America/Los_Angeles")
end
