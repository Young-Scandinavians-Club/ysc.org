defmodule YscWeb.ClearLakeBookingLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, SeasonHelpers, PricingHelpers, BookingLocker}
  alias Ysc.MoneyHelper
  alias Ysc.Accounts
  alias Ysc.Subscriptions
  alias Ysc.Repo
  import Ecto.Query

  @max_guests 12

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    today = Date.utc_today()

    {current_season, season_start_date, season_end_date} =
      SeasonHelpers.get_current_season_info(:clear_lake, today)

    max_booking_date =
      SeasonHelpers.calculate_max_booking_date(:clear_lake, today)

    # Parse query parameters, handling malformed/double-encoded URLs
    parsed_params = parse_mount_params(params)

    # Parse dates and guest counts from URL params if present
    {checkin_date, checkout_date} = parse_dates_from_params(parsed_params)
    guests_count = parse_guests_from_params(parsed_params)
    requested_tab = parse_tab_from_params(parsed_params)
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
    {user_with_subs, can_book, booking_disabled_reason, active_tab,
     membership_type, day_booking_allowed, buyout_booking_allowed, booking_mode,
     active_bookings} =
      if connected?(socket) do
        # Load user with subscriptions and subscription_items FIRST (to avoid multiple fetches)
        # Preloading subscription_items prevents duplicate queries in get_membership_plan_type
        user_with_subs =
          if user do
            # Check if subscriptions are already preloaded from auth
            if Ecto.assoc_loaded?(user.subscriptions) do
              # Check if subscription_items are also preloaded
              subscriptions_with_items_loaded? =
                Enum.all?(user.subscriptions, fn sub ->
                  Ecto.assoc_loaded?(sub.subscription_items)
                end)

              if subscriptions_with_items_loaded? do
                user
              else
                # Preload subscription_items if subscriptions are loaded but items are not
                user
                |> Ysc.Repo.preload(subscriptions: :subscription_items)
              end
            else
              # Load subscriptions with subscription_items to avoid duplicate queries
              Accounts.get_user!(user.id)
              |> Ysc.Repo.preload(subscriptions: :subscription_items)
            end
          else
            nil
          end

        # Check if user can book (pass user_with_subs to avoid re-fetching)
        {can_book, booking_disabled_reason} =
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
            current_season
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
            do: get_active_bookings(user_with_subs.id),
            else: []

        {user_with_subs, can_book, booking_disabled_reason, active_tab,
         membership_type, day_booking_allowed, buyout_booking_allowed,
         booking_mode, active_bookings}
      else
        # Static render: use minimal data for fast initial paint
        user_with_subs = user
        can_book = true
        booking_disabled_reason = nil
        active_tab = requested_tab
        membership_type = if user, do: :none, else: :none
        day_booking_allowed = true
        buyout_booking_allowed = true
        booking_mode = booking_mode || :day
        active_bookings = []

        {user_with_subs, can_book, booking_disabled_reason, active_tab,
         membership_type, day_booking_allowed, buyout_booking_allowed,
         booking_mode, active_bookings}
      end

    socket =
      assign(socket,
        page_title: "Clear Lake Cabin",
        property: :clear_lake,
        user: user_with_subs,
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        today: today,
        max_booking_date: max_booking_date,
        current_season: current_season,
        season_start_date: season_start_date,
        season_end_date: season_end_date,
        selected_booking_mode: booking_mode,
        guests_count: guests_count,
        max_guests: @max_guests,
        guests_dropdown_open: false,
        calculated_price: nil,
        price_error: nil,
        availability_error: nil,
        form_errors: %{},
        date_validation_errors: %{},
        date_form: date_form,
        membership_type: membership_type,
        active_tab: active_tab,
        can_book: can_book,
        booking_disabled_reason: booking_disabled_reason,
        day_booking_allowed: day_booking_allowed,
        buyout_booking_allowed: buyout_booking_allowed,
        active_bookings: active_bookings,
        load_radar: true
      )

    # Validate all conditions (availability, booking mode, guests, etc.)
    # Only run heavy validation when connected (availability checks run queries)
    socket =
      if connected?(socket) do
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
    booking_mode = parse_booking_mode_from_params(params)

    # Reuse eligibility data from mount if already computed (avoid duplicate queries)
    # Use the user with subscriptions preloaded if available
    user_for_check = socket.assigns[:user] || socket.assigns.current_user

    {can_book, booking_disabled_reason} =
      if socket.assigns[:can_book] != nil do
        # Already computed in mount - reuse it
        {socket.assigns.can_book, socket.assigns.booking_disabled_reason}
      else
        # First time (shouldn't happen normally since mount runs first)
        check_booking_eligibility(user_for_check)
      end

    # Load active bookings for the user (only if not already loaded in mount)
    active_bookings =
      if user_for_check && !socket.assigns[:active_bookings] do
        get_active_bookings(user_for_check.id)
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

    # Also check if can_book or booking_disabled_reason changed
    can_book_changed =
      can_book != socket.assigns.can_book ||
        booking_disabled_reason != socket.assigns.booking_disabled_reason

    # Only update if something actually changed
    # This prevents unnecessary updates on initial page load when mount already set everything
    if dates_changed || guests_changed || tab_changed || booking_mode_changed ||
         can_book_changed do
      # Only recalculate today and max_booking_date if dates changed
      # This prevents unnecessary component updates
      {today, max_booking_date, current_season, season_start_date,
       season_end_date} =
        if dates_changed do
          today = Date.utc_today()

          {current_season, season_start_date, season_end_date} =
            SeasonHelpers.get_current_season_info(:clear_lake, today)

          max_booking_date =
            SeasonHelpers.calculate_max_booking_date(:clear_lake, today)

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
          current_season
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
          can_book: can_book,
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
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- Hero Section with Carousel (For logged-in users) -->
    <section
      :if={@user}
      id="hero-section"
      class="relative w-full overflow-hidden -mt-[88px] pt-[88px] min-h-[40vh]"
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
              src: ~p"/images/clear_lake/clear_lake_dock.webp",
              alt: "Clear Lake Dock"
            },
            %{
              src: ~p"/images/clear_lake/clear_lake_dock_2.webp",
              alt: "Clear Lake Dock"
            },
            %{src: ~p"/images/clear_lake/clear_lake_sweep.webp", alt: "Clear Lake"},
            %{
              src: ~p"/images/clear_lake/clear_lake_cabin.webp",
              alt: "Clear Lake Cabin"
            }
          ]}
          class="h-full w-full"
        />
        <div
          class="absolute inset-0 z-[5] bg-black/30 pointer-events-none"
          aria-hidden="true"
        >
        </div>
      </div>
      <!-- Title Text Section -->
      <div class="absolute bottom-0 left-0 right-0 z-[10] px-4 py-12 lg:py-16 pointer-events-none">
        <div class="max-w-screen-xl mx-auto pointer-events-auto">
          <div class="flex items-center gap-3 px-4 mb-2">
            <h1 class="text-3xl sm:text-4xl md:text-5xl font-black text-white tracking-tight drop-shadow-lg">
              Clear Lake Portal
            </h1>
            <span class="px-2 py-1 bg-teal-600 mt-1 text-white text-[10px] font-bold uppercase tracking-widest rounded-full border border-teal-500 backdrop-blur-sm">
              Member Access
            </span>
          </div>
          <p class="text-sm sm:text-base text-zinc-100 px-4 max-w-2xl drop-shadow-md">
            Velkommen back! Manage your stay or reserve new dates below.
          </p>
        </div>
      </div>
    </section>
    <!-- Booking Dashboard Section -->
    <section :if={@user} class="border-b-2 border-zinc-900 py-12">
      <div class="max-w-screen-xl mx-auto px-4 space-y-10">
        <!-- Active Bookings -->
        <div :if={length(@active_bookings) > 0} class="space-y-4">
          <h3 class="text-sm font-bold text-zinc-400 uppercase tracking-widest">
            Upcoming Trips
          </h3>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <%= for booking <- @active_bookings do %>
              <div class="bg-white border-2 border-teal-100 rounded-xl p-5 shadow-sm">
                <div class="flex justify-between items-start mb-3">
                  <span class="text-[10px] font-bold text-teal-600 bg-teal-50 px-2 py-0.5 rounded">
                    <%= booking.reference_id %>
                  </span>
                  <%= if Date.compare(booking.checkout_date, Date.utc_today()) == :eq do %>
                    <span class="text-xs font-bold text-amber-600 italic">
                      Today!
                    </span>
                  <% else %>
                    <span class="text-xs font-bold text-green-600 italic">
                      Active
                    </span>
                  <% end %>
                </div>
                <p class="font-bold text-zinc-900 text-lg leading-none">
                  <%= Calendar.strftime(booking.checkin_date, "%b %d") %> — <%= Calendar.strftime(
                    booking.checkout_date,
                    "%b %d"
                  ) %>
                </p>
                <p class="text-sm text-zinc-500 mt-1">
                  <%= booking.guests_count %> <%= if booking.guests_count == 1,
                    do: "Guest",
                    else: "Guests" %> • <%= if booking.booking_mode == :buyout,
                    do: "Full Buyout",
                    else: "Shared Stay" %>
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
              <p class="text-sm text-zinc-600 mb-6">
                Select how you'd like to book the Clear Lake cabin:
              </p>
              <fieldset>
                <form phx-change="booking-mode-changed">
                  <div
                    class="grid grid-cols-1 md:grid-cols-2 gap-4"
                    role="radiogroup"
                  >
                    <label class={[
                      "flex flex-col p-6 border-2 rounded-lg cursor-pointer transition-all",
                      if(
                        @selected_booking_mode == :day ||
                          @selected_booking_mode == nil,
                        do: "border-teal-600 bg-teal-50 shadow-md",
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
                          A La Carte
                        </span>
                      </div>
                      <p class="text-sm text-zinc-600 ml-9">
                        Shared cabin stay. Perfect for individuals and small groups.
                      </p>
                    </label>
                    <label class={[
                      "flex flex-col p-6 border-2 rounded-lg cursor-pointer transition-all",
                      if(@selected_booking_mode == :buyout,
                        do: "border-teal-600 bg-teal-50 shadow-md",
                        else:
                          "border-zinc-300 hover:border-teal-400 hover:bg-zinc-50"
                      ),
                      if(
                        !@buyout_booking_allowed ||
                          (@selected_booking_mode == :buyout && @availability_error),
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
                          Full Buyout
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
                        Buyout unavailable: Other members have already booked spots on these dates.
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
                    A La Carte bookings are not available for the selected dates based on season settings.
                  </span>
                  <span
                    :if={
                      !@buyout_booking_allowed && @selected_booking_mode == :buyout &&
                        @checkin_date
                    }
                    class="text-amber-600 font-medium"
                  >
                    Full Buyout bookings are not available for the selected dates based on season settings.
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
                        disabled={!@can_book}
                        aria-labelledby="guests-label"
                        aria-expanded={@guests_dropdown_open}
                        aria-haspopup="true"
                        class="w-full px-3 py-2 border border-zinc-300 rounded focus:ring-2 focus:ring-teal-500 focus:border-teal-500 bg-white text-left flex items-center justify-between disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        <span class="text-zinc-900">
                          <%= @guests_count %> <%= if @guests_count == 1,
                            do: "guest",
                            else: "guests" %>
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
                        class="absolute z-50 w-full mt-1 bg-white border border-zinc-300 rounded shadow-lg p-4"
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
                                <%= @guests_count %>
                              </span>
                              <button
                                type="button"
                                id="increase-guests-button"
                                phx-click="increase-guests"
                                phx-click-stop
                                disabled={@guests_count >= (@max_guests || 12)}
                                aria-label="Increase number of guests"
                                class={[
                                  "w-10 h-10 rounded-full border-2 flex items-center justify-center transition-all duration-200 font-semibold",
                                  if(@guests_count >= (@max_guests || 12),
                                    do:
                                      "border-zinc-200 bg-zinc-100 text-zinc-400 cursor-not-allowed",
                                    else:
                                      "border-teal-600 bg-teal-600 hover:bg-teal-700 hover:border-teal-700 text-white"
                                  )
                                ]}
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
                  <p :if={@form_errors[:guests_count]} class="text-red-600 text-sm">
                    <%= @form_errors[:guests_count] %>
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
                />
                <!-- Error Messages -->
                <div class="mt-4 space-y-1">
                  <p
                    :if={@date_validation_errors[:weekend]}
                    class="text-red-600 text-sm"
                  >
                    <%= @date_validation_errors[:weekend] %>
                  </p>
                  <p
                    :if={@date_validation_errors[:max_nights]}
                    class="text-red-600 text-sm"
                  >
                    <%= @date_validation_errors[:max_nights] %>
                  </p>
                  <p
                    :if={@date_validation_errors[:availability]}
                    class="text-red-600 text-sm"
                  >
                    <%= @date_validation_errors[:availability] %>
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
                    The calendar shows how many spots are available for each day (up to 12 guests per day).
                    <span
                      :if={@guests_count && @guests_count > 0}
                      class="font-semibold text-teal-700"
                    >
                      Dates with fewer than <%= @guests_count %> spot<%= if @guests_count ==
                                                                              1,
                                                                            do: "",
                                                                            else:
                                                                              "s" %> available are disabled.
                    </span>
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
                />
                <!-- Error Messages -->
                <div class="mt-4 space-y-1">
                  <p :if={@form_errors[:checkin_date]} class="text-red-600 text-sm">
                    <%= @form_errors[:checkin_date] %>
                  </p>
                  <p :if={@form_errors[:checkout_date]} class="text-red-600 text-sm">
                    <%= @form_errors[:checkout_date] %>
                  </p>
                  <p
                    :if={@date_validation_errors[:weekend]}
                    class="text-red-600 text-sm"
                  >
                    <%= @date_validation_errors[:weekend] %>
                  </p>
                  <p
                    :if={@date_validation_errors[:max_nights]}
                    class="text-red-600 text-sm"
                  >
                    <%= @date_validation_errors[:max_nights] %>
                  </p>
                  <p
                    :if={@date_validation_errors[:active_booking]}
                    class="text-red-600 text-sm"
                  >
                    <%= @date_validation_errors[:active_booking] %>
                  </p>
                  <p
                    :if={@date_validation_errors[:advance_booking_limit]}
                    class="text-red-600 text-sm"
                  >
                    <%= @date_validation_errors[:advance_booking_limit] %>
                  </p>
                  <p
                    :if={@date_validation_errors[:season_date_range]}
                    class="text-red-600 text-sm"
                  >
                    <%= @date_validation_errors[:season_date_range] %>
                  </p>
                </div>
              </section>
            </div>
            <!-- Price Error -->
            <div
              :if={@price_error}
              class="bg-red-50 border border-red-200 rounded-lg p-4"
            >
              <div class="flex items-start">
                <div class="flex-shrink-0">
                  <.icon
                    name="hero-exclamation-circle"
                    class="h-5 w-5 text-red-600 -mt-1"
                  />
                </div>
                <div class="ms-3">
                  <p class="text-sm text-red-800"><%= @price_error %></p>
                </div>
              </div>
            </div>
          </div>
          <!-- Right Column: Sticky Reservation Summary (1 column on large screens) -->
          <aside class="lg:sticky lg:top-24">
            <div class="bg-white rounded-2xl border-2 border-teal-600 shadow-xl overflow-hidden">
              <div class="bg-teal-600 p-4 text-white text-center">
                <h3 class="text-lg font-bold">Reservation Summary</h3>
              </div>
              <div class="p-6 space-y-4">
                <!-- Dates -->
                <div :if={@checkin_date && @checkout_date} class="space-y-3">
                  <div class="flex justify-between items-start text-sm">
                    <span class="text-zinc-500 font-medium">Check-in</span>
                    <span class="font-semibold text-zinc-900 text-right">
                      <%= Calendar.strftime(@checkin_date, "%b %d, %Y") %>
                    </span>
                  </div>
                  <div class="flex justify-between items-start text-sm">
                    <span class="text-zinc-500 font-medium">Check-out</span>
                    <span class="font-semibold text-zinc-900 text-right">
                      <%= Calendar.strftime(@checkout_date, "%b %d, %Y") %>
                    </span>
                  </div>
                  <div class="flex justify-between items-start text-sm">
                    <span class="text-zinc-500 font-medium">Nights</span>
                    <span class="font-semibold text-zinc-900">
                      <%= Date.diff(@checkout_date, @checkin_date) %> <%= if Date.diff(
                                                                               @checkout_date,
                                                                               @checkin_date
                                                                             ) == 1,
                                                                             do:
                                                                               "night",
                                                                             else:
                                                                               "nights" %>
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
                    <%= @guests_count %> <%= if @guests_count == 1,
                      do: "guest",
                      else: "guests" %>
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
                  <div class="text-sm text-zinc-700 font-medium">Full Buyout</div>
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
                  <div class="text-sm text-zinc-700 font-medium">A La Carte</div>
                </div>
                <!-- Sunday Morning Parking Tip -->
                <div
                  :if={@checkin_date && @checkout_date}
                  class="mt-4 p-3 bg-amber-50 border border-amber-200 rounded-lg"
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
                  class="bg-amber-50 border border-amber-200 rounded-lg p-3"
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
                        <%= @availability_error %>
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
                            if @calculated_price && nights > 0 && @guests_count > 0 do
                              case Money.div(
                                     @calculated_price,
                                     nights * @guests_count
                                   ) do
                                {:ok, price} -> price
                                _ -> Money.new(0, :USD)
                              end
                            else
                              Money.new(0, :USD)
                            end
                          end %>
                        <% total_guest_nights = nights * @guests_count %>
                        <div class="flex justify-between items-center text-zinc-600">
                          <span>
                            Spot Rental (<%= @guests_count %> × <%= nights %> night<%= if nights !=
                                                                                            1,
                                                                                          do:
                                                                                            "s",
                                                                                          else:
                                                                                            "" %>)
                          </span>
                          <span class="font-bold text-zinc-900">
                            <%= MoneyHelper.format_money!(
                              Money.mult(
                                price_per_guest_per_night,
                                total_guest_nights
                              )
                              |> elem(1)
                            ) %>
                          </span>
                        </div>
                      </span>
                      <span :if={@selected_booking_mode == :buyout}>
                        <% nights = Date.diff(@checkout_date, @checkin_date) %>
                        <% price_per_night =
                          if @price_breakdown && @price_breakdown.price_per_night do
                            @price_breakdown.price_per_night
                          else
                            if @calculated_price && nights > 0 do
                              case Money.div(@calculated_price, nights) do
                                {:ok, price} -> price
                                _ -> Money.new(0, :USD)
                              end
                            else
                              Money.new(0, :USD)
                            end
                          end %>
                        <div class="flex justify-between items-center text-zinc-600">
                          <span>
                            Full Buyout (<%= nights %> night<%= if nights != 1,
                              do: "s",
                              else: "" %>)
                          </span>
                          <span class="font-bold text-zinc-900">
                            <%= MoneyHelper.format_money!(
                              Money.mult(price_per_night, nights)
                              |> elem(1)
                            ) %>
                          </span>
                        </div>
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
                          <%= MoneyHelper.format_money!(@calculated_price) %>
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
                    <%= @price_error %>
                  </p>
                  <p :if={@availability_error} class="text-red-600 text-xs">
                    <%= @availability_error %>
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
                      Please fix form errors above
                    </li>
                    <li :if={
                      @date_validation_errors &&
                        map_size(@date_validation_errors) > 0
                    }>
                      Please fix date validation errors
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
                      @can_book &&
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
                  <div
                    :if={!@can_book}
                    class="w-full bg-zinc-200 text-zinc-600 font-semibold py-4 rounded text-center cursor-not-allowed"
                  >
                    Booking Unavailable
                  </div>
                </div>
              </div>
            </div>
          </aside>
        </div>
      </div>
    </section>
    <!-- Hero Section with Carousel (For non-logged-in users) -->
    <section
      :if={!@user}
      id="hero-section"
      class="relative w-full overflow-hidden -mt-[88px] pt-[88px]"
      style="min-height: 75vh;"
    >
      <div
        id="clear-lake-carousel-wrapper"
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
              src: ~p"/images/clear_lake/clear_lake_dock.webp",
              alt: "Clear Lake Dock"
            },
            %{
              src: ~p"/images/clear_lake/clear_lake_dock_2.webp",
              alt: "Clear Lake Dock"
            },
            %{src: ~p"/images/clear_lake/clear_lake_sweep.webp", alt: "Clear Lake"},
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
      <!-- Title Text Section - z-index lowered to ensure mobile menu appears above -->
      <div class="absolute bottom-0 left-0 right-0 z-[10] px-4 py-16 lg:py-20 pointer-events-none">
        <div class="max-w-screen-xl mx-auto pointer-events-auto">
          <span class="inline-block px-2.5 sm:px-3 py-1 mb-3 sm:mb-4 text-xs font-bold tracking-widest text-white uppercase bg-amber-700/80 backdrop-blur-sm rounded">
            A Legacy for All Seasons
          </span>
          <h1 class="text-3xl sm:text-4xl md:text-5xl lg:text-6xl xl:text-7xl font-bold text-white mb-3 sm:mb-4 drop-shadow-lg">
            YSC Clear Lake Cabin
          </h1>
          <p class="text-base sm:text-lg md:text-xl lg:text-2xl text-zinc-100 max-w-2xl font-light">
            Owned and operated by our community since 1963. A year-round gateway to California's oldest natural lake.
          </p>
        </div>
      </div>
    </section>
    <!-- Main Content for Non-Logged-In Users -->
    <section :if={!@user} class="max-w-screen-xl mx-auto px-4 py-20">
      <div class="space-y-12">
        <!-- Welcome Header -->
        <div class="text-center max-w-3xl mx-auto">
          <h1 class="text-4xl md:text-5xl font-bold text-zinc-900 mb-4">
            Experience Clear Lake
          </h1>
          <p class="text-lg text-zinc-600 leading-relaxed">
            Welcome to the
            <strong class="text-zinc-900">YSC Clear Lake Cabin</strong>
            — your year-round gateway to California's oldest natural lake. Since <strong class="text-zinc-900">1963</strong>, the YSC has proudly owned this beautiful cabin, located in the heart of
            <strong class="text-zinc-900">Kelseyville</strong>
            on the shores of <strong class="text-zinc-900">Clear Lake</strong>.
          </p>
        </div>
        <!-- Experience Clear Lake Feature Grid -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-5xl mx-auto">
          <!-- Private Dock Access -->
          <div
            class="bg-gradient-to-br from-teal-50 via-teal-50 to-cyan-50 border-2 border-teal-200 rounded-2xl p-6 shadow-lg hover:shadow-xl transition-shadow"
            style="background: linear-gradient(to bottom right, rgb(240 253 250), rgb(207 250 254));"
          >
            <div class="flex items-start gap-4">
              <div class="text-4xl flex-shrink-0">⚓</div>
              <div class="flex-1">
                <h3 class="text-xl font-black text-zinc-900 mb-2">
                  Private Dock Access
                </h3>
                <p class="text-zinc-700 leading-relaxed">
                  Swim, boat, and unwind at our private dock. Perfect for mooring your boat, enjoying morning coffee over the water, or taking a refreshing dip in California's largest natural lake.
                </p>
              </div>
            </div>
          </div>
          <!-- Year-Round Access -->
          <div class="bg-gradient-to-br from-amber-50 to-orange-50 border-2 border-amber-200 rounded-2xl p-6 shadow-lg hover:shadow-xl transition-shadow">
            <div class="flex items-start gap-4">
              <div class="text-4xl flex-shrink-0">🌅</div>
              <div class="flex-1">
                <h3 class="text-xl font-black text-zinc-900 mb-2">
                  Year-Round Access
                </h3>
                <p class="text-zinc-700 leading-relaxed">
                  <strong class="text-amber-700">Summer (May–Sept):</strong>
                  Legendary dock parties, community meals, and boat tie-ups.
                  <strong class="text-amber-700">Winter (Oct–April):</strong>
                  Perfect for hikers and wine enthusiasts seeking quiet lakeside retreats.
                </p>
              </div>
            </div>
          </div>
          <!-- The Dugnad Spirit -->
          <div class="bg-gradient-to-br from-purple-50 to-indigo-50 border-2 border-purple-200 rounded-2xl p-6 shadow-lg hover:shadow-xl transition-shadow">
            <div class="flex items-start gap-4">
              <div class="text-4xl flex-shrink-0">🤝</div>
              <div class="flex-1">
                <h3 class="text-xl font-black text-zinc-900 mb-2">
                  The Dugnad Spirit
                </h3>
                <p class="text-zinc-700 leading-relaxed">
                  Low rates are possible because members steward the cabin together. This is <strong class="text-purple-700">your cabin — not a hotel</strong>. Members share responsibility for cleaning and maintenance, keeping costs affordable for everyone.
                </p>
              </div>
            </div>
          </div>
          <!-- California's Oldest Lake -->
          <div class="bg-gradient-to-br from-green-50 to-emerald-50 border-2 border-green-200 rounded-2xl p-6 shadow-lg hover:shadow-xl transition-shadow">
            <div class="flex items-start gap-4">
              <div class="text-4xl flex-shrink-0">🏞️</div>
              <div class="flex-1">
                <h3 class="text-xl font-black text-zinc-900 mb-2">
                  California's Oldest Lake
                </h3>
                <p class="text-zinc-700 leading-relaxed">
                  Clear Lake is <strong class="text-green-700">2.5 million years old</strong>—the oldest natural lake in North America. Experience a unique ecosystem perfect for bird watching, fishing, and connecting with nature year-round.
                </p>
              </div>
            </div>
          </div>
        </div>
        <!-- CTA Card for Non-Logged-In Users -->
        <div class="mt-12 max-w-2xl mx-auto">
          <div class="p-8 rounded-2xl bg-gradient-to-r from-teal-600 to-teal-700 text-white shadow-2xl">
            <div class="flex flex-col md:flex-row items-center justify-between gap-6">
              <div class="flex-1 text-center md:text-left">
                <h4 class="text-2xl font-black mb-2">
                  Ready to Experience Clear Lake?
                </h4>
                <p class="text-teal-100">
                  <%= raw(@booking_disabled_reason) %>
                </p>
              </div>
              <.link
                navigate={
                  ~p"/users/log-in?#{%{redirect_to: ~p"/bookings/clear-lake"}}"
                }
                class="px-8 py-3 bg-white text-teal-600 font-bold rounded-lg hover:bg-teal-50 transition shadow-lg whitespace-nowrap"
              >
                Sign In to Book
              </.link>
            </div>
          </div>
        </div>
      </div>
    </section>
    <!-- Main Content Grid: 2-column layout (For logged-in users) -->
    <section :if={@user} class="max-w-screen-xl mx-auto px-4 py-20">
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <!-- Left Column: Main Content (2 columns on large screens) -->
        <div class="lg:col-span-2 space-y-20">
          <!-- Your Lakeside Sanctuary Section -->
          <article id="the-experience" class="mb-16">
            <h2 class="text-4xl font-black text-zinc-900 mb-4 tracking-tight">
              Your Lakeside Sanctuary
            </h2>
            <p class="text-xl text-zinc-500 mb-10 font-light">
              Escape the city for North America's oldest lake. Whether it's a high-energy summer weekend or a cozy winter retreat, the YSC Cabin is your home on the water.
            </p>

            <div class="prose prose-lg prose-zinc font-light leading-relaxed text-zinc-600 max-w-none">
              <p>
                Imagine waking up to the mist rolling off Clear Lake, coffee in hand on a <strong>private 100-foot dock</strong>, with the dormant peak of Mt. Konocti as your backdrop. This isn't just a rental; it's a 60-year tradition of Scandinavian lakeside living.
              </p>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-12">
              <div class="p-6 bg-teal-50 rounded-2xl border border-teal-100">
                <span class="text-2xl mb-2 block">🌅</span>
                <h4 class="font-bold text-teal-900 mb-2">Summer on the Water</h4>
                <p class="text-sm text-teal-800/80 leading-relaxed">
                  The legendary YSC summer. Spend your days swimming off the dock, mooring your boat for free, and enjoying communal "Langbord" dinners under the stars.
                </p>
              </div>
              <div class="p-6 bg-amber-50 rounded-2xl border border-amber-100">
                <span class="text-2xl mb-2 block">🍷</span>
                <h4 class="font-bold text-amber-900 mb-2">Winter Wine & Hikes</h4>
                <p class="text-sm text-amber-800/80 leading-relaxed">
                  Cozy up in the Social Hall. Winter is for the Red Hills wine enthusiasts and those looking to summit Konocti without the summer heat.
                </p>
              </div>
            </div>
            <!-- CTA Card when booking is unavailable (not logged in or no membership) -->
            <div
              :if={!@can_book}
              class="mt-10 p-8 rounded-2xl bg-teal-50 border border-teal-100 flex flex-col md:flex-row items-center justify-between gap-6"
            >
              <div>
                <h4 class="text-xl font-bold text-teal-900">Ready to reserve?</h4>
                <p class="text-teal-700"><%= raw(@booking_disabled_reason) %></p>
                <p :if={@user} class="text-teal-600 text-sm mt-2">
                  You will be able to use the booking system as soon as you pay for membership.
                </p>
              </div>
              <.link
                :if={!@user}
                navigate={
                  ~p"/users/log-in?#{%{redirect_to: ~p"/bookings/clear-lake"}}"
                }
                class="px-8 py-3 bg-teal-600 text-white font-bold rounded-lg hover:bg-teal-700 transition shadow-lg shadow-teal-200"
              >
                Sign In to Book
              </.link>
              <.link
                :if={@user}
                navigate={~p"/users/membership"}
                class="px-8 py-3 bg-teal-600 text-white font-bold rounded-lg hover:bg-teal-700 transition shadow-lg shadow-teal-200"
              >
                Manage Membership
              </.link>
            </div>
          </article>
          <!-- Arrival Section -->
          <article id="arrival-section" class="pt-10 border-t border-zinc-100">
            <!-- Door Code & Access (for linking from booking receipt) -->
            <div
              id="door-code-access"
              class="mb-8 p-6 bg-teal-50 border border-teal-200 rounded-lg"
            >
              <h3 class="font-bold text-teal-900 mb-3 flex items-center gap-2">
                <.icon name="hero-key" class="w-5 h-5" /> Door Code & Access
              </h3>
              <p class="text-sm text-teal-800 mb-2">
                Your door code will be sent via email <strong>24 hours before your check-in</strong>.
                The code is also displayed on your booking confirmation page when your stay is within 48 hours of check-in or currently active.
              </p>
              <ul class="text-sm text-teal-800 list-disc list-inside space-y-1">
                <li>
                  Save the door code before you arrive — cell service can be limited in the area
                </li>
                <li>The door code is unique to your booking period</li>
                <li>
                  If you don't receive the code, check your spam folder or contact the Cabin Master
                </li>
              </ul>
            </div>
            <h2 class="text-3xl font-bold text-zinc-900 mb-8">
              Journey to the Lake
            </h2>
            <div class="space-y-4">
              <div class="p-6 bg-zinc-50 border border-zinc-200 rounded flex items-center justify-between">
                <div>
                  <h3 class="text-xs font-bold text-zinc-400 uppercase tracking-widest mb-1">
                    Cabin Address
                  </h3>
                  <p class="text-lg font-bold text-zinc-900">
                    9325 Bass Road, Kelseyville, CA 95451
                  </p>
                </div>
                <a
                  href="https://www.google.com/maps/dir/?api=1&destination=9325+Bass+Road+Kelseyville+CA+95451"
                  target="_blank"
                  class="bg-white px-4 py-2 border border-zinc-300 rounded font-bold text-sm hover:bg-zinc-100 transition-all flex items-center gap-2 whitespace-nowrap"
                >
                  <.icon name="hero-map-pin" class="w-4 h-4" /> Open in Maps
                </a>
              </div>
              <details class="group border border-zinc-200 rounded overflow-hidden">
                <summary class="p-4 cursor-pointer font-bold text-zinc-700 flex justify-between items-center list-none bg-zinc-50 hover:bg-zinc-100 transition-colors">
                  Step-by-Step Directions from San Francisco
                  <.icon
                    name="hero-chevron-down"
                    class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
                  />
                </summary>
                <div class="p-4 border-t border-zinc-100 bg-white">
                  <p class="text-sm text-zinc-600 mb-4">
                    Public transportation options are very limited — <strong>driving is essential</strong>.
                  </p>
                  <div class="flex flex-col items-center my-6">
                    <.live_component
                      id="clear-lake-cabin-map"
                      module={YscWeb.Components.MapComponent}
                      latitude={38.98087180833886}
                      longitude={-122.73563627025182}
                      locked={true}
                      class="my-4"
                    />
                    <YscWeb.Components.MapNavigationButtons.map_navigation_buttons
                      latitude={38.98087180833886}
                      longitude={-122.73563627025182}
                      class="w-full"
                    />
                  </div>
                  <!-- Vertical Trail Directions -->
                  <div class="relative pl-8 space-y-6 mt-6">
                    <!-- Trail line -->
                    <div class="absolute left-3 top-0 bottom-0 w-0.5 bg-teal-300">
                    </div>
                    <!-- Direction steps -->
                    <div class="relative flex gap-4">
                      <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
                        <span class="text-white text-xs font-bold">1</span>
                      </div>
                      <div class="flex-1 pb-6">
                        <p class="text-sm font-semibold text-zinc-900">
                          Take HWY 101 North
                        </p>
                        <p class="text-xs text-zinc-600 mt-1">Past Santa Rosa</p>
                      </div>
                    </div>
                    <div class="relative flex gap-4">
                      <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
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
                      <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
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
                      <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
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
                      <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
                        <span class="text-white text-xs font-bold">5</span>
                      </div>
                      <div class="flex-1 pb-6">
                        <p class="text-sm font-semibold text-zinc-900">
                          Turn left at stop sign onto Foothill Blvd / HWY 128
                        </p>
                        <p class="text-xs text-zinc-600 mt-1">Go 0.8 miles</p>
                      </div>
                    </div>
                    <div class="relative flex gap-4">
                      <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
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
                      <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
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
                      <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
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
                      <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
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
                      <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
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
                      <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-700 border-4 border-white shadow-lg flex items-center justify-center z-10">
                        <.icon name="hero-flag" class="w-4 h-4 text-white" />
                      </div>
                      <div class="flex-1">
                        <p class="text-sm font-bold text-teal-700">
                          Turn right at the third driveway with the YSC sign
                        </p>
                        <p class="text-xs text-zinc-600 mt-1">You've arrived!</p>
                      </div>
                    </div>
                  </div>
                  <div class="mt-4 p-3 bg-amber-50 border border-amber-200 rounded-lg">
                    <p class="text-sm text-amber-800">
                      <strong>Note:</strong>
                      If you reach Konocti Harbor Inn, you've gone too far — turn around.
                    </p>
                  </div>
                  <!-- Parking Strategy Tip -->
                  <div class="mt-6 p-4 bg-zinc-900 text-white rounded-xl shadow-lg">
                    <div class="flex items-center gap-3 mb-2">
                      <.icon name="hero-truck" class="w-5 h-5 text-teal-400" />
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
          </article>
          <!-- Amenities Section -->
          <section id="amenities" class="pt-10 border-t border-zinc-100">
            <h3 class="text-2xl font-bold text-zinc-900 mb-8">
              Everything You Need for a Perfect Stay
            </h3>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
              <div class="flex gap-4">
                <div class="w-12 h-12 flex-shrink-0 bg-zinc-100 rounded-xl flex items-center justify-center">
                  <.icon name="hero-lifebuoy" class="w-6 h-6 text-teal-600" />
                </div>
                <div>
                  <h4 class="font-bold text-zinc-900">The Iconic Private Dock</h4>
                  <p class="text-sm text-zinc-500">
                    Perfect for deep-water swimming, sunbathing, or securing your boat. It's the heart of the property.
                  </p>
                </div>
              </div>
              <div class="flex gap-4">
                <div class="w-12 h-12 flex-shrink-0 bg-zinc-100 rounded-xl flex items-center justify-center">
                  <.icon name="hero-musical-note" class="w-6 h-6 text-teal-600" />
                </div>
                <div>
                  <h4 class="font-bold text-zinc-900">Social Hall & Dance Floor</h4>
                  <p class="text-sm text-zinc-500">
                    A massive cedar hall for evening games, music, and the warmth of a wood-burning fireplace.
                  </p>
                </div>
              </div>
              <div class="flex gap-4">
                <div class="w-12 h-12 flex-shrink-0 bg-zinc-100 rounded-xl flex items-center justify-center">
                  <.icon name="hero-home-modern" class="w-6 h-6 text-teal-600" />
                </div>
                <div>
                  <h4 class="font-bold text-zinc-900">Gourmet Group Kitchen</h4>
                  <p class="text-sm text-zinc-500">
                    Fully equipped with industrial stoves and ample fridge space. Perfect for hosting big group feasts.
                  </p>
                </div>
              </div>
              <div class="flex gap-4">
                <div class="w-12 h-12 flex-shrink-0 bg-zinc-100 rounded-xl flex items-center justify-center">
                  <.icon name="hero-sparkles" class="w-6 h-6 text-teal-600" />
                </div>
                <div>
                  <h4 class="font-bold text-zinc-900">The Sleeping Lawn</h4>
                  <p class="text-sm text-zinc-500">
                    Fall asleep to the sound of crickets and the lake breeze. We provide the mattresses; the stars provide the view.
                  </p>
                </div>
              </div>
            </div>
          </section>
          <!-- Cabin Facilities Section -->
          <section id="facilities" class="py-12 border-t border-zinc-100">
            <h2 class="text-3xl font-bold text-zinc-900 mb-8">Cabin Facilities</h2>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-6">
              <div class="flex flex-col items-center p-6 bg-zinc-50 rounded-2xl text-center">
                <.icon name="hero-home-modern" class="w-8 h-8 text-teal-600 mb-3" />
                <h4 class="font-bold text-base text-zinc-900">Full Kitchen</h4>
                <p class="text-sm text-zinc-500 mt-1">
                  Industrial stove, fridge, and prep space
                </p>
              </div>
              <div class="flex flex-col items-center p-6 bg-zinc-50 rounded-2xl text-center">
                <.icon name="hero-musical-note" class="w-8 h-8 text-teal-600 mb-3" />
                <h4 class="font-bold text-base text-zinc-900">Social Hall</h4>
                <p class="text-sm text-zinc-500 mt-1">
                  Open dance floor and fireplace
                </p>
              </div>
              <div class="flex flex-col items-center p-6 bg-zinc-50 rounded-2xl text-center">
                <.icon name="hero-user-group" class="w-8 h-8 text-teal-600 mb-3" />
                <h4 class="font-bold text-base text-zinc-900">Changing Rooms</h4>
                <p class="text-sm text-zinc-500 mt-1">
                  Men's and Women's facilities
                </p>
              </div>
              <div class="flex flex-col items-center p-6 bg-zinc-50 rounded-2xl text-center">
                <.icon name="hero-bolt" class="w-8 h-8 text-teal-600 mb-3" />
                <h4 class="font-bold text-base text-zinc-900">Power & Water</h4>
                <p class="text-sm text-zinc-500 mt-1">
                  Solar supplemented & filtered well water
                </p>
              </div>
            </div>
          </section>
          <!-- Living the Nordic Way Section -->
          <section id="cabin-rules" class="bg-zinc-50 rounded-3xl p-8 lg:p-12 mb-4">
            <div class="max-w-3xl">
              <h2 class="text-3xl font-bold text-zinc-900 mb-4">
                Living the Nordic Way
              </h2>
              <p class="text-zinc-600 mb-10 leading-relaxed">
                Since 1963, our cabin has operated on mutual respect and shared effort. To keep the legacy alive, we ask all members to follow these standards.
              </p>

              <div class="space-y-4">
                <details class="group bg-white border border-zinc-200 rounded-xl transition-all">
                  <summary class="p-5 cursor-pointer font-bold flex justify-between items-center list-none hover:text-teal-700">
                    <span class="flex items-center gap-3">
                      <span class="text-xl">🤝</span>
                      <span>Community & Kids</span>
                    </span>
                    <.icon
                      name="hero-chevron-down"
                      class="w-5 h-5 text-zinc-400 chevron-icon transition-transform"
                    />
                  </summary>
                  <div class="px-5 pb-5 text-base text-zinc-600 space-y-3 border-t border-zinc-50 pt-4">
                    <p>
                      <strong>Dugnad (Chore Duty):</strong>
                      Everyone signs up for a daily task upon arrival. This is how we keep costs low and the cabin clean.
                    </p>
                    <p>
                      <strong>Midnight Silence:</strong>
                      Quiet hours begin at midnight unless it's a sanctioned party weekend.
                    </p>
                    <p>
                      <strong>Families:</strong>
                      Most weekends are family-friendly; check specific event descriptions for "Adults Only" gatherings.
                    </p>
                    <p>
                      <strong>Non-Member Guests:</strong>
                      Guests are welcome on general visits, but all guests must be included in and paid for by the member making the reservation. Certain events may have guest restrictions—check event details for specifics.
                    </p>
                  </div>
                </details>

                <details class="group bg-white border border-zinc-200 rounded-xl transition-all">
                  <summary class="p-5 cursor-pointer font-bold flex justify-between items-center list-none hover:text-teal-700">
                    <span class="flex items-center gap-3">
                      <span class="text-xl">⚓</span>
                      <span>The Grounds & Water</span>
                    </span>
                    <.icon
                      name="hero-chevron-down"
                      class="w-5 h-5 text-zinc-400 chevron-icon transition-transform"
                    />
                  </summary>
                  <div class="px-5 pb-5 text-sm text-zinc-600 space-y-4 border-t border-zinc-50 pt-4">
                    <p>
                      <strong>Strictly No Pets:</strong>
                      To protect local wildlife and maintain cleanliness, pets are not permitted anywhere on property.
                    </p>
                    <p>
                      <strong>Boating:</strong>
                      Mooring at our private dock is free for members. Please notify the Cabin Master in advance.
                      <em>Note: trailers must be parked off-site.</em>
                    </p>
                    <div class="p-4 bg-rose-50 border border-rose-100 rounded-lg text-rose-800 text-xs">
                      <strong>⚠️ Quagga Mussel Warning:</strong>
                      Mandatory inspection is required. Violations result in a $1,000 fine from Lake County.
                    </div>
                  </div>
                </details>

                <.link
                  navigate={~p"/code-of-conduct"}
                  target="_blank"
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
          <!-- Nearby Section -->
          <section id="nearby" class="py-12 border-t border-zinc-100">
            <h3 class="text-2xl font-bold text-zinc-900 mb-6">
              Explore Kelseyville
            </h3>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
              <div class="space-y-2">
                <h5 class="font-bold text-zinc-800">Volcanic Wines</h5>
                <p class="text-xs text-zinc-500">
                  Visit Laujor or Chacewater for world-class Cabernets in the Red Hills AVA.
                </p>
              </div>
              <div class="space-y-2">
                <h5 class="font-bold text-zinc-800">Mt. Konocti Trails</h5>
                <p class="text-xs text-zinc-500">
                  Incredible 360-degree views of the lake. A must-do hike for every member.
                </p>
              </div>
              <div class="space-y-2">
                <h5 class="font-bold text-zinc-800">Town Charm</h5>
                <p class="text-xs text-zinc-500">
                  10 mins to historic Kelseyville for local breweries and pear orchards.
                </p>
              </div>
            </div>
          </section>
          <!-- Legacy Section -->
          <section
            id="legacy"
            class="bg-zinc-50 rounded-3xl p-8 border border-zinc-100"
          >
            <h4 class="text-xs font-black text-zinc-400 uppercase tracking-widest mb-4">
              The YSC Spirit
            </h4>
            <h2 class="text-2xl font-bold text-zinc-900 mb-4">
              Owned by Members, Loved by All
            </h2>
            <p class="text-zinc-600 mb-6 leading-relaxed">
              This isn't a hotel—it's a collective treasure. Since 1963, we've kept costs low and the quality high through <strong>Dugnad</strong>: the Nordic tradition of "shared effort." Everyone pitches in for one small chore a day, ensuring the cabin stays beautiful for the next generation.
            </p>
            <.link
              navigate={~p"/code-of-conduct"}
              class="text-teal-700 font-bold hover:underline flex items-center gap-2"
            >
              Read the Cabin Code of Conduct
              <.icon name="hero-arrow-right" class="w-4 h-4" />
            </.link>
          </section>
          <!-- Legacy Timeline Section -->
          <section id="legacy-timeline" class="py-16 border-t border-zinc-100">
            <div class="max-w-3xl">
              <h2 class="text-3xl font-bold text-zinc-900 mb-8 leading-tight">
                A 60-Year Legacy
              </h2>
              <div class="space-y-8 relative">
                <div class="absolute left-[11px] top-2 bottom-2 w-0.5 bg-zinc-100">
                </div>

                <div class="relative pl-10">
                  <div class="absolute left-0 top-1.5 w-6 h-6 rounded-full bg-white border-4 border-teal-600">
                  </div>
                  <h4 class="font-bold text-zinc-900">1963: The Vision</h4>
                  <p class="text-base text-zinc-500 leading-relaxed">
                    The Young Scandinavians Club acquires the property, establishing a permanent summer retreat for the Nordic community in California.
                  </p>
                </div>

                <div class="relative pl-10">
                  <div class="absolute left-0 top-1.5 w-6 h-6 rounded-full bg-white border-4 border-teal-600">
                  </div>
                  <h4 class="font-bold text-zinc-900">
                    1970s - 90s: Built by Hand
                  </h4>
                  <p class="text-base text-zinc-500 leading-relaxed">
                    Generations of members spent their weekends on "Dugnad" (work parties), building the kitchen, the social hall, and the iconic private dock.
                  </p>
                </div>

                <div class="relative pl-10">
                  <div class="absolute left-0 top-1.5 w-6 h-6 rounded-full bg-white border-4 border-teal-600">
                  </div>
                  <h4 class="font-bold text-zinc-900">Today: Your Turn</h4>
                  <p class="text-base text-zinc-500 leading-relaxed">
                    As a member-run treasure, the cabin remains a place where we share meals, chores, and the best sunset views on the lake.
                  </p>
                </div>
                <div :if={@user} class="relative pl-10">
                  <div class="absolute left-0 top-1.5 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-sm">
                  </div>
                  <h4 class="font-bold text-zinc-900">Your Chapter</h4>
                  <p class="text-base text-zinc-500 leading-relaxed">
                    By booking a stay, you are participating in the ongoing story of the YSC. Your fees go directly toward the preservation of the cabin and the Dock Revival Project.
                  </p>
                </div>
              </div>
            </div>
          </section>
        </div>
        <!-- Right Sidebar -->
        <aside class="space-y-8">
          <div class="sticky top-24 space-y-8">
            <!-- Your Stay Card -->
            <div class="bg-white border-2 border-zinc-900 rounded-2xl overflow-hidden shadow-xl">
              <div class="bg-zinc-900 px-6 py-4">
                <h3 class="font-bold text-white">Your Stay</h3>
              </div>
              <div class="p-6 space-y-4">
                <div class="flex justify-between text-base">
                  <span class="text-zinc-500">Lakeside Dock</span>
                  <span class="font-bold text-teal-600">Included</span>
                </div>
                <div class="flex justify-between text-base">
                  <span class="text-zinc-500">Group Kitchen</span>
                  <span class="font-bold text-teal-600">Included</span>
                </div>
                <div class="flex justify-between text-base border-t border-zinc-50 pt-4">
                  <span class="text-zinc-500">Check-in</span>
                  <span class="font-bold text-zinc-900">3:00 PM</span>
                </div>
                <div class="flex justify-between text-base">
                  <span class="text-zinc-500">Check-out</span>
                  <span class="font-bold text-zinc-900">11:00 AM</span>
                </div>
              </div>
              <div class="px-6 pb-6">
                <button class="w-full bg-teal-600 hover:bg-teal-700 text-white font-bold py-3 rounded-xl transition-all shadow-lg shadow-teal-600/20">
                  Check Availability
                </button>
              </div>
            </div>
            <!-- The Packing List Card -->
            <div class="bg-teal-900 rounded-2xl p-8 text-white">
              <h3 class="text-lg font-bold mb-6">The Packing List</h3>
              <ul class="space-y-4 text-sm text-teal-100">
                <li class="flex items-center gap-3">
                  <span class="text-teal-400">●</span> Sleeping bag & Pillow
                </li>
                <li class="flex items-center gap-3">
                  <span class="text-teal-400">●</span> Dancing Shoes
                </li>
                <li class="flex items-center gap-3">
                  <span class="text-teal-400">●</span> Reusable Water Bottle
                </li>
                <li class="flex items-center gap-3">
                  <span class="text-teal-400">●</span> Sunscreen & Swimsuit
                </li>
              </ul>
            </div>
            <!-- Lake Lore Card - Dark Background -->
            <div class="bg-zinc-900 rounded-2xl p-8 text-white shadow-xl shadow-zinc-900/20">
              <h3 class="text-lg font-bold mb-4 flex items-center gap-2">
                <.icon name="hero-information-circle" class="w-6 h-6 text-teal-400" />
                Lake Lore
              </h3>
              <div class="space-y-4 text-base text-zinc-300">
                <p>
                  <strong class="text-white">2.5 Million Years:</strong>
                  Clear Lake is the oldest lake in North America, offering a unique ecosystem for bird watching and fishing year-round.
                </p>
                <p>
                  <strong class="text-white">The "Dugnad" Spirit:</strong>
                  Everything you see was built or maintained by members. We don't just stay here; we steward it.
                </p>
              </div>
            </div>
            <!-- Winter Travel Tip Card -->
            <div class="bg-amber-50 border-2 border-amber-200 rounded-2xl p-6 shadow-sm">
              <h3 class="text-lg font-bold mb-3 flex items-center gap-2 text-amber-900">
                <span class="text-xl">🍂</span> Winter Travel Tip
              </h3>
              <p class="text-base text-amber-800 leading-relaxed">
                The lake air gets chilly! We recommend bringing an extra wool blanket and a pair of indoor slippers (a true Scandinavian tradition) to keep cozy in the Social Hall after dark.
              </p>
            </div>
          </div>
        </aside>
      </div>
      <!-- Stewards of the Lake Section -->
      <section class="bg-amber-50 rounded-3xl p-8 lg:p-12 border border-amber-100 mb-20 mt-10">
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
                <p class="text-base font-bold text-amber-900">$150 — Legacy Tier</p>
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

            <div class="flex flex-wrap items-center gap-6">
              <a
                href="#donate"
                class="bg-amber-600 text-white px-8 py-3 rounded-xl font-black hover:bg-amber-700 transition shadow-lg shadow-amber-200"
              >
                Donate Now
              </a>
              <div class="text-base text-amber-800 italic flex items-center">
                <.icon name="hero-heart" class="w-5 h-5 mr-2" />
                The club matches all member donations!
              </div>
            </div>
          </div>

          <div class="space-y-6">
            <div class="bg-white p-6 rounded-2xl shadow-sm border border-amber-200">
              <h4 class="font-bold text-zinc-900 mb-3 text-base uppercase tracking-wider">
                Honorary Stewards
              </h4>
              <p class="text-sm text-zinc-500 leading-relaxed">
                Special thanks to
                <strong>Allen Hinkelman, Solveig Barnes, and Dave Conroy</strong>
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
    </section>
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
        socket.assigns.current_season
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
        socket.assigns.current_season
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

    # Validate that guests_count is within valid range
    guests_count = min(max(guests_count, 1), @max_guests)

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
    new_count = min(current_count + 1, @max_guests)

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
         |> put_flash(
           :error,
           availability_error ||
             "Sorry, there is not enough capacity for your requested dates and number of guests."
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
         |> put_flash(
           :error,
           "Sorry, the property is not available for your requested dates."
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
         |> put_flash(:error, error_message)
         |> assign(
           form_errors: %{general: error_message},
           calculated_price: socket.assigns.calculated_price
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        form_errors = format_errors(changeset)
        error_message = "Please fix the errors above and try again."

        {:noreply,
         socket
         |> put_flash(:error, error_message)
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
         |> put_flash(:error, error_message)
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
         |> put_flash(:error, error_message)
         |> assign(
           form_errors: %{general: error_message},
           calculated_price: socket.assigns.calculated_price
         )}
    end
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
          socket.assigns.selected_booking_mode || :day
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
        socket.assigns.current_season
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
      (booking_mode == :buyout ||
         (booking_mode == :day && guests_count > 0 &&
            guests_count <= @max_guests))
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
      "You must be signed in to make a booking. Please #{sign_in_link} to continue."
    }
  end

  defp check_booking_eligibility(user) do
    # Check if user account is approved
    if user.state != :active do
      {
        false,
        "Your membership application is pending approval. You will be able to make bookings once your application has been approved."
      }
    else
      # Check if user has active membership
      # user should already have subscriptions preloaded (with subscription_items)
      # to avoid duplicate queries
      if Accounts.has_active_membership?(user) do
        {true, nil}
      else
        {
          false,
          "You need an active membership to make bookings. Please activate or renew your membership to continue."
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

        multiple ->
          most_expensive = get_most_expensive_subscription(multiple)
          get_membership_type_from_subscription(most_expensive)
      end
    end
  end

  defp get_membership_type_from_subscription(subscription) do
    case YscWeb.UserAuth.get_membership_plan_type(subscription) do
      nil -> :none
      plan_id -> plan_id
    end
  end

  defp get_most_expensive_subscription(subscriptions) do
    membership_plans = Application.get_env(:ysc, :membership_plans, [])

    price_to_amount =
      Map.new(membership_plans, fn plan ->
        {plan.stripe_price_id, plan.amount}
      end)

    Enum.max_by(subscriptions, fn subscription ->
      subscription_items =
        case subscription.subscription_items do
          %Ecto.Association.NotLoaded{} ->
            # Preload subscription items if not loaded
            subscription = Ysc.Repo.preload(subscription, :subscription_items)
            subscription.subscription_items

          items when is_list(items) ->
            items

          _ ->
            []
        end

      case subscription_items do
        [item | _] ->
          Map.get(price_to_amount, item.stripe_price_id, 0)

        _ ->
          0
      end
    end)
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
      _ -> %{}
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

  defp find_malformed_query_key(_), do: nil

  defp parse_query_string(nil), do: %{}
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
        booking_mode
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
        booking_mode
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
        booking_mode
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
         booking_mode
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

    params
  end

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

  # Validates that the selected dates have enough spots available for the requested number of guests
  defp validate_guests_against_availability(
         checkin_date,
         checkout_date,
         guests_count,
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
          # Check if there are enough spots available
          if day_availability.is_blacked_out do
            date
          else
            if assigns[:selected_booking_mode] == :day do
              # For day bookings, check if there are enough spots
              if day_availability.spots_available < guests_count,
                do: date,
                else: nil
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
          "The date #{date_str} is blacked out and cannot be booked."

        day_availability && assigns[:selected_booking_mode] == :day ->
          spots = day_availability.spots_available

          "The date #{date_str} only has #{spots} spot#{if spots == 1, do: "", else: "s"} available, but you're trying to book #{guests_count} guest#{if guests_count == 1, do: "", else: "s"}."

        day_availability && assigns[:selected_booking_mode] == :buyout ->
          "The date #{date_str} cannot be booked as a buyout (there are existing day bookings or another buyout)."

        true ->
          "The date #{date_str} is unavailable for your selected number of guests."
      end
    else
      nil
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
        current_season
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
    if guests_count, do: min(max(guests_count, 1), @max_guests), else: 1
  end

  defp normalize_booking_mode(booking_mode) do
    if booking_mode in [:day, :buyout], do: booking_mode, else: :day
  end

  defp normalize_dates(checkin_date, checkout_date, today_assign) do
    if checkin_date && checkout_date do
      today = today_assign || Date.utc_today()

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
        "A La Carte bookings are not available for the selected dates based on season settings."

      booking_mode == :buyout && !buyout_booking_allowed ->
        "Full Buyout bookings are not available for the selected dates based on season settings."

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
  defp get_active_bookings(user_id, limit \\ 10) do
    today = Date.utc_today()

    query =
      from b in Booking,
        where: b.user_id == ^user_id,
        where: b.property == :clear_lake,
        where: b.status == :complete,
        where: b.checkout_date >= ^today,
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
         current_season
       ) do
    case property do
      :clear_lake ->
        # Determine the effective season
        # If dates are selected, use the check-in date's season
        # If not, use the current season (based on today)
        season =
          if checkin_date do
            Bookings.Season.for_date(:clear_lake, checkin_date)
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
end
