defmodule YscWeb.TahoeBookingLive do
  use YscWeb, :live_view

  alias Ysc.Bookings

  alias Ysc.Bookings.{
    Season,
    Booking,
    PricingRule,
    Room,
    BookingLocker,
    PropertyInventory
  }

  alias Ysc.Bookings.SeasonHelpers
  alias Ysc.Bookings.PricingHelpers
  alias Ysc.MoneyHelper
  alias Ysc.Accounts
  alias Ysc.Subscriptions
  alias Ysc.Repo
  require Logger
  import Ecto.Query

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    today = Date.utc_today()

    # Load seasons once using cache to avoid multiple queries
    alias Ysc.Bookings.SeasonCache
    seasons = SeasonCache.get_all_for_property(:tahoe)

    {current_season, season_start_date, season_end_date} =
      get_current_season_info_cached(seasons, today)

    max_booking_date = calculate_max_booking_date_cached(seasons, today)

    # Parse query parameters, handling malformed/double-encoded URLs
    parsed_params = parse_mount_params(params)

    # Parse dates and guest counts from URL params if present
    {checkin_date, checkout_date} = parse_dates_from_params(parsed_params)
    guests_count = parse_guests_from_params(parsed_params)
    children_count = parse_children_from_params(parsed_params)
    requested_tab = parse_tab_from_params(parsed_params)
    booking_mode = parse_booking_mode_from_params(parsed_params)
    requested_info_tab = parse_info_tab_from_params(parsed_params)

    redirect_to =
      tahoe_redirect_to(
        checkin_date,
        checkout_date,
        guests_count,
        children_count,
        requested_tab,
        booking_mode || :room
      )

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
    {user_with_subs, active_bookings, can_book, booking_error_title,
     booking_disabled_reason, active_tab, membership_type, restricted_min_date,
     restricted_max_date, dates_restricted, buyout_refund_policy,
     room_refund_policy} =
      if connected?(socket) do
        # Load user with subscriptions and subscription_items FIRST (to avoid multiple fetches)
        # This user_with_subs will be reused by check_booking_eligibility and get_membership_type
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

        # Load active bookings for the entire family group (needed for eligibility check)
        active_bookings =
          if user, do: get_family_group_active_bookings(user), else: []

        # Check if user can book (pass user_with_subs to avoid re-fetching subscriptions)
        {can_book, booking_error_title, booking_disabled_reason} =
          check_booking_eligibility(
            user_with_subs,
            active_bookings,
            redirect_to
          )

        # If user can't book, default to information tab
        active_tab =
          if can_book do
            requested_tab
          else
            :information
          end

        # Calculate membership type once and cache it (if user exists)
        # user_with_subs already has subscriptions loaded, so this won't re-fetch
        membership_type =
          if user_with_subs do
            get_membership_type(user_with_subs)
          else
            :none
          end

        # Calculate restricted date range for family/lifetime members with 1 room booking
        {restricted_min_date, restricted_max_date} =
          if membership_type in [:family, :lifetime] && active_bookings != [] do
            total_rooms = count_rooms_in_active_bookings(active_bookings)

            if total_rooms == 1 do
              calculate_restricted_date_range(active_bookings, max_booking_date)
            else
              {today, max_booking_date}
            end
          else
            {today, max_booking_date}
          end

        # Check if dates are actually restricted (different from default range)
        dates_restricted =
          dates_are_restricted?(
            restricted_min_date,
            restricted_max_date,
            today,
            max_booking_date
          )

        # Load refund policies for both booking modes
        buyout_refund_policy =
          Bookings.get_active_refund_policy(:tahoe, :buyout)

        room_refund_policy = Bookings.get_active_refund_policy(:tahoe, :room)

        {user_with_subs, active_bookings, can_book, booking_error_title,
         booking_disabled_reason, active_tab, membership_type,
         restricted_min_date, restricted_max_date, dates_restricted,
         buyout_refund_policy, room_refund_policy}
      else
        # Static render: use minimal data for fast initial paint
        user_with_subs = user
        active_bookings = []
        can_book = true
        booking_error_title = nil
        booking_disabled_reason = nil
        active_tab = requested_tab
        membership_type = if user, do: :none, else: :none
        restricted_min_date = today
        restricted_max_date = max_booking_date
        dates_restricted = false
        buyout_refund_policy = nil
        room_refund_policy = nil

        {user_with_subs, active_bookings, can_book, booking_error_title,
         booking_disabled_reason, active_tab, membership_type,
         restricted_min_date, restricted_max_date, dates_restricted,
         buyout_refund_policy, room_refund_policy}
      end

    # Generate date tooltips asynchronously (heavy operation with multiple queries)
    # This runs only when connected and loads in the background
    socket =
      if connected?(socket) do
        start_async(socket, :load_date_tooltips, fn ->
          generate_date_tooltips(
            restricted_min_date,
            restricted_max_date,
            today,
            :tahoe,
            seasons
          )
        end)
      else
        socket
      end

    socket =
      assign(socket,
        page_title: "Tahoe Cabin",
        property: :tahoe,
        user: user_with_subs,
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        today: today,
        max_booking_date: max_booking_date,
        restricted_min_date: restricted_min_date,
        restricted_max_date: restricted_max_date,
        dates_restricted: dates_restricted,
        current_season: current_season,
        season_start_date: season_start_date,
        season_end_date: season_end_date,
        seasons: seasons,
        selected_room_id: nil,
        selected_room_ids: [],
        selected_booking_mode: booking_mode || :room,
        guests_count: guests_count,
        children_count: children_count,
        guests_dropdown_open: socket.assigns[:guests_dropdown_open] || false,
        available_rooms: [],
        calculated_price: nil,
        price_breakdown: nil,
        price_error: nil,
        capacity_error: nil,
        form_errors: %{},
        date_validation_errors: %{},
        date_form: date_form,
        membership_type: membership_type,
        active_tab: active_tab,
        can_book: can_book,
        booking_error_title: booking_error_title,
        booking_disabled_reason: booking_disabled_reason,
        active_bookings: active_bookings,
        buyout_refund_policy: buyout_refund_policy,
        room_refund_policy: room_refund_policy,
        date_tooltips: %{},
        load_radar: true,
        terms_agreed: false,
        info_tab: requested_info_tab || :general,
        show_confirm_modal: false,
        show_terms_modal: false,
        linens_confirmed: false,
        chores_confirmed: false,
        party_size_confirmed: false,
        booking_step: if(booking_mode, do: :details, else: :mode_selection)
      )

    # If dates are present and user can book, initialize validation and room availability
    socket =
      if checkin_date && checkout_date && can_book do
        socket
        |> enforce_season_booking_mode()
        |> validate_dates()
        |> update_available_rooms()
        |> calculate_price_if_ready()
      else
        socket
      end

    # Handle scroll to section if hash is present in URL
    socket =
      if connected?(socket) do
        socket
      else
        # For static render, we'll handle scroll in JavaScript
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, uri, socket) do
    # Parse query parameters, handling malformed/double-encoded URLs
    params = parse_query_params(params, uri)

    # Parse all params from URI
    parsed_params = parse_all_params_from_uri(params, uri)

    # Get booking eligibility
    {can_book, booking_error_title, booking_disabled_reason} =
      get_booking_eligibility(socket, parsed_params)

    # Determine active tab
    active_tab = determine_active_tab(parsed_params.requested_tab, can_book)
    tab_changed = active_tab != socket.assigns.active_tab

    # Update if dates, guest counts, or tab have changed
    if should_update_availability(socket, parsed_params, tab_changed) do
      today = Date.utc_today()
      seasons = socket.assigns.seasons

      {current_season, season_start_date, season_end_date} =
        get_current_season_info_cached(seasons, today)

      max_booking_date = calculate_max_booking_date_cached(seasons, today)

      # Calculate restricted date range for family/lifetime members with 1 room booking
      {restricted_min_date, restricted_max_date, dates_restricted} =
        calculate_restricted_dates(socket, today, max_booking_date)

      # Only regenerate date tooltips if the date range actually changed
      socket =
        maybe_load_date_tooltips(
          socket,
          restricted_min_date,
          restricted_max_date,
          today,
          seasons
        )

      date_tooltips = socket.assigns[:date_tooltips] || %{}

      socket =
        update_socket_with_parsed_params(
          socket,
          parsed_params,
          %{
            today: today,
            max_booking_date: max_booking_date,
            restricted_min_date: restricted_min_date,
            restricted_max_date: restricted_max_date,
            dates_restricted: dates_restricted,
            current_season: current_season,
            season_start_date: season_start_date,
            season_end_date: season_end_date,
            can_book: can_book,
            booking_error_title: booking_error_title,
            booking_disabled_reason: booking_disabled_reason,
            active_tab: active_tab,
            date_tooltips: date_tooltips
          }
        )
        |> then(fn s ->
          # Only run validation/room updates if dates changed, not just tab
          if should_update_rooms(socket, parsed_params) do
            s
            |> enforce_season_booking_mode()
            |> validate_dates()
            |> update_available_rooms()
            |> calculate_price_if_ready()
          else
            s
          end
        end)

      {:noreply, socket}
    else
      # Even if nothing changed, update scroll_to_section if hash is present
      socket = update_scroll_section(socket, uri)
      {:noreply, socket}
    end
  end

  # Helper function to parse all params from URI
  defp parse_all_params_from_uri(params, uri) do
    {checkin_date, checkout_date} = parse_dates_from_params(params)
    guests_count = parse_guests_from_params(params)
    children_count = parse_children_from_params(params)
    requested_tab = parse_tab_from_params(params)
    booking_mode = parse_booking_mode_from_params(params)
    requested_info_tab = parse_info_tab_from_params(params)

    scroll_to_section =
      if uri do
        parsed_uri = URI.parse(uri)

        if parsed_uri.fragment && parsed_uri.fragment != "",
          do: parsed_uri.fragment,
          else: nil
      else
        nil
      end

    %{
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      guests_count: guests_count,
      children_count: children_count,
      requested_tab: requested_tab,
      booking_mode: booking_mode,
      requested_info_tab: requested_info_tab,
      scroll_to_section: scroll_to_section
    }
  end

  # Helper function to get booking eligibility
  defp get_booking_eligibility(socket, parsed_params) do
    if socket.assigns[:can_book] != nil do
      # Already computed in mount - reuse it
      {
        socket.assigns.can_book,
        socket.assigns.booking_error_title,
        socket.assigns.booking_disabled_reason
      }
    else
      # First time (shouldn't happen normally since mount runs first)
      user = socket.assigns.current_user

      active_bookings_loaded =
        if user && !socket.assigns[:active_bookings] do
          get_family_group_active_bookings(user)
        else
          socket.assigns[:active_bookings] || []
        end

      # Use the user with subscriptions preloaded if available
      user_for_check = socket.assigns[:user] || user

      redirect_to =
        tahoe_redirect_to(
          parsed_params.checkin_date,
          parsed_params.checkout_date,
          parsed_params.guests_count,
          parsed_params.children_count,
          parsed_params.requested_tab,
          parsed_params.booking_mode || :room
        )

      check_booking_eligibility(
        user_for_check,
        active_bookings_loaded,
        redirect_to
      )
    end
  end

  # Helper function to determine active tab
  defp determine_active_tab(requested_tab, can_book) do
    if requested_tab == :booking && !can_book do
      :information
    else
      requested_tab
    end
  end

  # Helper function to check if we should update availability
  defp should_update_availability(socket, parsed_params, tab_changed) do
    parsed_params.checkin_date != socket.assigns.checkin_date ||
      parsed_params.checkout_date != socket.assigns.checkout_date ||
      parsed_params.guests_count != socket.assigns.guests_count ||
      parsed_params.children_count != socket.assigns.children_count ||
      parsed_params.booking_mode != socket.assigns.selected_booking_mode ||
      tab_changed
  end

  # Helper function to check if we should update rooms
  defp should_update_rooms(socket, parsed_params) do
    parsed_params.checkin_date != socket.assigns.checkin_date ||
      parsed_params.checkout_date != socket.assigns.checkout_date ||
      parsed_params.guests_count != socket.assigns.guests_count ||
      parsed_params.children_count != socket.assigns.children_count ||
      parsed_params.booking_mode != socket.assigns.selected_booking_mode
  end

  # Helper function to calculate restricted dates
  defp calculate_restricted_dates(socket, today, max_booking_date) do
    membership_type = socket.assigns.membership_type || :none
    active_bookings = socket.assigns[:active_bookings] || []

    {restricted_min_date, restricted_max_date} =
      if membership_type in [:family, :lifetime] && active_bookings != [] do
        total_rooms = count_rooms_in_active_bookings(active_bookings)

        if total_rooms == 1 do
          calculate_restricted_date_range(active_bookings, max_booking_date)
        else
          {today, max_booking_date}
        end
      else
        {today, max_booking_date}
      end

    dates_restricted =
      dates_are_restricted?(
        restricted_min_date,
        restricted_max_date,
        today,
        max_booking_date
      )

    {restricted_min_date, restricted_max_date, dates_restricted}
  end

  # Helper function to maybe load date tooltips
  defp maybe_load_date_tooltips(
         socket,
         restricted_min_date,
         restricted_max_date,
         today,
         seasons
       ) do
    if restricted_min_date != socket.assigns[:restricted_min_date] ||
         restricted_max_date != socket.assigns[:restricted_max_date] ||
         !socket.assigns[:date_tooltips] ||
         socket.assigns[:date_tooltips] == %{} do
      start_async(socket, :load_date_tooltips, fn ->
        generate_date_tooltips(
          restricted_min_date,
          restricted_max_date,
          today,
          :tahoe,
          seasons
        )
      end)
    else
      socket
    end
  end

  # Helper function to update socket with parsed params
  defp update_socket_with_parsed_params(
         socket,
         parsed_params,
         additional_assigns
       ) do
    date_form =
      to_form(
        %{
          "checkin_date" => date_to_datetime_string(parsed_params.checkin_date),
          "checkout_date" =>
            date_to_datetime_string(parsed_params.checkout_date)
        },
        as: "booking_dates"
      )

    active_bookings = socket.assigns[:active_bookings] || []

    socket
    |> assign(
      page_title: "Tahoe Cabin",
      checkin_date: parsed_params.checkin_date,
      checkout_date: parsed_params.checkout_date,
      guests_count: parsed_params.guests_count,
      children_count: parsed_params.children_count,
      selected_booking_mode: parsed_params.booking_mode || :room,
      selected_room_id: nil,
      selected_room_ids: [],
      guests_dropdown_open: socket.assigns[:guests_dropdown_open] || false,
      available_rooms: [],
      calculated_price: nil,
      price_error: nil,
      form_errors: %{},
      date_form: date_form,
      date_validation_errors: %{},
      active_bookings: active_bookings,
      booking_step:
        if(parsed_params.booking_mode, do: :details, else: :mode_selection),
      info_tab:
        parsed_params.requested_info_tab || socket.assigns[:info_tab] ||
          :general,
      scroll_to_section: parsed_params.scroll_to_section
    )
    |> assign(additional_assigns)
  end

  # Helper function to update scroll section
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
  def handle_async(:load_date_tooltips, {:ok, date_tooltips}, socket) do
    {:noreply, assign(socket, :date_tooltips, date_tooltips)}
  end

  def handle_async(:load_date_tooltips, {:exit, reason}, socket) do
    require Logger
    Logger.error("Failed to load date tooltips async: #{inspect(reason)}")
    {:noreply, assign(socket, :date_tooltips, %{})}
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

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        date_form: date_form,
        calculated_price: nil,
        price_error: nil
      )
      |> validate_dates()
      |> calculate_price_if_ready()
      |> update_url_with_dates(checkin_date, checkout_date)

    {:noreply, socket}
  end

  def handle_info(
        {:updated_event, %{start_date: start_date, end_date: end_date}},
        socket
      ) do
    checkin_date = if start_date, do: DateTime.to_date(start_date), else: nil
    checkout_date = if end_date, do: DateTime.to_date(end_date), else: nil

    date_form =
      to_form(
        %{
          "checkin_date" => date_to_datetime_string(checkin_date),
          "checkout_date" => date_to_datetime_string(checkout_date)
        },
        as: "booking_dates"
      )

    # Recalculate restricted dates if needed
    membership_type = socket.assigns.membership_type || :none
    active_bookings = socket.assigns[:active_bookings] || []
    max_booking_date = socket.assigns.max_booking_date

    {restricted_min_date, restricted_max_date} =
      if membership_type in [:family, :lifetime] && active_bookings != [] do
        total_rooms = count_rooms_in_active_bookings(active_bookings)

        if total_rooms == 1 do
          calculate_restricted_date_range(active_bookings, max_booking_date)
        else
          {socket.assigns.today, max_booking_date}
        end
      else
        {socket.assigns.today, max_booking_date}
      end

    # Check if dates are actually restricted
    dates_restricted =
      dates_are_restricted?(
        restricted_min_date,
        restricted_max_date,
        socket.assigns.today,
        max_booking_date
      )

    # Only regenerate date tooltips if the date range actually changed
    date_tooltips =
      if restricted_min_date != socket.assigns[:restricted_min_date] ||
           restricted_max_date != socket.assigns[:restricted_max_date] ||
           !socket.assigns[:date_tooltips] do
        generate_date_tooltips(
          restricted_min_date,
          restricted_max_date,
          socket.assigns.today,
          :tahoe,
          socket.assigns.seasons
        )
      else
        socket.assigns[:date_tooltips] || %{}
      end

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        restricted_min_date: restricted_min_date,
        restricted_max_date: restricted_max_date,
        dates_restricted: dates_restricted,
        selected_room_id: nil,
        selected_room_ids: [],
        available_rooms: [],
        calculated_price: nil,
        price_error: nil,
        form_errors: %{},
        date_form: date_form,
        date_validation_errors: %{},
        date_tooltips: date_tooltips
      )
      |> enforce_season_booking_mode()
      |> validate_dates()
      |> update_available_rooms()
      |> calculate_price_if_ready()
      |> update_url_with_dates(checkin_date, checkout_date)

    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="tahoe-booking-page"
      phx-hook={if assigns[:scroll_to_section], do: "ScrollToSection", else: nil}
      data-section={
        if assigns[:scroll_to_section], do: assigns.scroll_to_section, else: nil
      }
    >
      <!-- Hero Section with Carousel (For logged-in users) -->
      <section
        :if={@user}
        id="hero-section"
        class="relative w-full overflow-hidden -mt-[88px] pt-[88px] min-h-[40vh]"
      >
        <div class="absolute inset-0 h-full w-full z-[2]">
          <img
            src={~p"/images/tahoe/tahoe_cabin_main.webp"}
            alt="Tahoe Cabin Exterior"
            class="h-full w-full object-cover"
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
            <div class="flex items-center gap-3 px-4">
              <h1 class="text-3xl sm:text-4xl md:text-5xl font-black text-white tracking-tight drop-shadow-lg">
                Lake Tahoe Cabin
              </h1>
              <span class="px-2 py-1 bg-blue-700/90 mt-1 text-white text-[10px] font-bold uppercase tracking-widest rounded-full border border-blue-500/50 backdrop-blur-sm">
                Member Access
              </span>
            </div>
          </div>
        </div>
      </section>
      <!-- Hero Section with Carousel (For non-logged-in users) -->
      <section
        :if={!@user}
        id="hero-section"
        class="relative w-full overflow-hidden -mt-[88px] pt-[88px] min-h-[75vh]"
      >
        <div class="absolute inset-0 h-full w-full z-[2]">
          <img
            src={~p"/images/tahoe/tahoe_cabin_main.webp"}
            alt="Tahoe Cabin Exterior"
            class="h-full w-full object-cover"
          />
          <div
            class="absolute inset-0 z-[5] bg-black/30 pointer-events-none"
            aria-hidden="true"
          >
          </div>
        </div>
        <!-- Title Text Section -->
        <div class="absolute bottom-0 left-0 right-0 z-[10] px-4 py-16 lg:py-20 pointer-events-none">
          <div class="max-w-screen-xl mx-auto pointer-events-auto">
            <span class="inline-block px-2.5 sm:px-3 py-1 mb-3 sm:mb-4 text-xs font-bold tracking-widest text-white uppercase bg-blue-700/80 backdrop-blur-sm rounded">
              A Year-Round Retreat
            </span>
            <h1 class="text-3xl sm:text-4xl md:text-5xl lg:text-6xl xl:text-7xl font-bold text-white mb-3 sm:mb-4 drop-shadow-lg">
              YSC Lake Tahoe Cabin
            </h1>
            <p class="text-base sm:text-lg md:text-xl lg:text-2xl text-zinc-100 max-w-2xl font-light">
              Owned and operated by our community since 1993. A beautiful cabin on the west shore of Lake Tahoe.
            </p>
          </div>
        </div>
      </section>
      <!-- Booking Dashboard Section -->
      <section :if={@user} class="py-8">
        <div class="max-w-screen-xl mx-auto px-4 space-y-10">
          <!-- Essential Alerts Bar (High-Contrast) -->
          <div class="grid grid-cols-1 md:grid-cols-4 gap-4 bg-zinc-900 text-white p-4 rounded-xl shadow-xl">
            <div class="flex items-center gap-3">
              <span class="text-xl flex-shrink-0">🧺</span>
              <div>
                <p class="text-[10px] font-black text-blue-400 uppercase">
                  Mandatory
                </p>
                <p class="text-xs font-bold leading-tight">BRING YOUR OWN LINENS</p>
              </div>
            </div>
            <div class="flex items-center gap-3">
              <span class="text-xl flex-shrink-0">🚫</span>
              <div>
                <p class="text-[10px] font-black text-zinc-400 uppercase">
                  Enforced
                </p>
                <p class="text-xs font-bold leading-tight">NO PETS / NO SMOKING</p>
              </div>
            </div>
            <div class="flex items-center gap-3">
              <span class="text-xl flex-shrink-0">❄️</span>
              <div>
                <p class="text-[10px] font-black text-amber-400 uppercase">
                  Safety
                </p>
                <p class="text-xs font-bold leading-tight">
                  WINTER 4WD / CHAINS REQ.
                </p>
              </div>
            </div>
            <div class="flex items-center gap-3">
              <span class="text-xl flex-shrink-0">🧹</span>
              <div>
                <p class="text-[10px] font-black text-zinc-400 uppercase">
                  Community
                </p>
                <p class="text-xs font-bold leading-tight">
                  NOT A HOTEL: DO CHORES
                </p>
              </div>
            </div>
          </div>
          <!-- Active Bookings -->
          <div :if={length(@active_bookings) > 0} class="space-y-4">
            <h3 class="text-sm font-bold text-zinc-400 uppercase tracking-widest">
              <%= if Accounts.sub_account?(@user) || Accounts.primary_user?(@user) do %>
                Family Active Bookings
              <% else %>
                Your Active Bookings
              <% end %>
            </h3>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for booking <- @active_bookings do %>
                <div class="bg-white border-2 border-blue-100 rounded-xl p-5 shadow-sm">
                  <div class="flex justify-between items-start mb-3">
                    <span class="text-[10px] font-bold text-blue-600 bg-blue-50 px-2 py-0.5 rounded">
                      <%= booking.reference_id %>
                    </span>
                    <%= if Date.compare(booking.checkout_date, Date.utc_today()) == :eq do %>
                      <span class="text-xs font-bold text-amber-600 italic">
                        Today!
                      </span>
                    <% else %>
                      <span class="text-xs font-bold text-blue-600 italic">
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
                      else: "Guests" %> • <%= if booking.booking_mode == :buyout do
                      "Full Buyout"
                    else
                      if Ecto.assoc_loaded?(booking.rooms) &&
                           length(booking.rooms) > 0 do
                        Enum.map_join(booking.rooms, ", ", fn room -> room.name end)
                      else
                        "Rooms"
                      end
                    end %>
                  </p>
                  <.link
                    navigate={~p"/bookings/#{booking.id}/receipt"}
                    class="inline-block mt-4 text-sm font-semibold text-blue-600 hover:underline"
                  >
                    View Booking<.icon
                      name="hero-arrow-right-solid"
                      class="w-4 h-4 ms-1"
                    />
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
              <!-- Booking Eligibility Banner -->
              <div
                :if={!@can_book}
                class="bg-amber-50 border border-amber-200 rounded p-4"
              >
                <div class="flex items-start">
                  <div class="flex-shrink-0">
                    <.icon
                      name="hero-exclamation-triangle-solid"
                      class="h-5 w-5 text-amber-600"
                    />
                  </div>
                  <div class="ms-2 flex-1">
                    <h3
                      :if={@booking_error_title}
                      class="text-sm font-semibold text-amber-900"
                    >
                      <%= @booking_error_title %>
                    </h3>
                    <div class="mt-2 text-sm text-amber-800">
                      <p><%= raw(@booking_disabled_reason) %></p>
                    </div>
                  </div>
                </div>
              </div>
              <div :if={!@can_book} class="relative opacity-60 pointer-events-none">
              </div>
              <!-- Step 1: Booking Mode Selection -->
              <section class="bg-zinc-50 p-6 rounded border border-zinc-200">
                <h2 class="text-lg font-bold mb-4 flex items-center gap-2">
                  <span class="w-6 h-6 bg-blue-600 text-white rounded-full flex items-center justify-center text-xs font-semibold">
                    1
                  </span>
                  Choose Booking Type
                </h2>
                <p class="text-sm text-zinc-600 mb-6">
                  Select how you'd like to book the Tahoe cabin:
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
                          @selected_booking_mode == :room ||
                            @selected_booking_mode == nil,
                          do: "border-blue-600 bg-blue-50 shadow-md",
                          else:
                            "border-zinc-300 hover:border-blue-400 hover:bg-zinc-50"
                        )
                      ]}>
                        <input
                          type="radio"
                          id="booking-mode-room"
                          name="booking_mode"
                          value="room"
                          checked={
                            @selected_booking_mode == :room ||
                              @selected_booking_mode == nil
                          }
                          class="sr-only"
                        />
                        <div class="flex items-center gap-3 mb-2">
                          <div class={[
                            "w-6 h-6 rounded-full border-2 flex items-center justify-center",
                            if(
                              @selected_booking_mode == :room ||
                                @selected_booking_mode == nil,
                              do: "border-blue-600 bg-blue-600",
                              else: "border-zinc-300 bg-white"
                            )
                          ]}>
                            <svg
                              :if={
                                @selected_booking_mode == :room ||
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
                            Individual Room(s)
                          </span>
                        </div>
                        <p class="text-sm text-zinc-600 ml-9">
                          Book one or more individual rooms. Perfect for smaller groups or when you want to share the cabin with other members.
                        </p>
                      </label>
                      <label class={[
                        "flex flex-col p-6 border-2 rounded-lg cursor-pointer transition-all",
                        if(@selected_booking_mode == :buyout,
                          do: "border-blue-600 bg-blue-50 shadow-md",
                          else:
                            "border-zinc-300 hover:border-blue-400 hover:bg-zinc-50"
                        ),
                        if(not can_select_booking_mode?(@seasons, Date.utc_today()),
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
                            not can_select_booking_mode?(@seasons, Date.utc_today())
                          }
                          class="sr-only"
                        />
                        <div class="flex items-center gap-3 mb-2">
                          <div class={[
                            "w-6 h-6 rounded-full border-2 flex items-center justify-center",
                            if(@selected_booking_mode == :buyout,
                              do: "border-blue-600 bg-blue-600",
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
                            Full Cabin Buyout
                          </span>
                        </div>
                        <p class="text-sm text-zinc-600 ml-9">
                          Reserve the entire cabin exclusively for your group. Includes all 7 bedrooms, 3 bathrooms, and the sauna.
                        </p>
                        <p
                          :if={
                            not can_select_booking_mode?(@seasons, Date.utc_today())
                          }
                          class="text-xs text-amber-600 mt-2 ml-9 font-medium"
                        >
                          Full buyout is only available May–November.
                        </p>
                      </label>
                    </div>
                  </form>
                </fieldset>
              </section>
              <!-- Booking Rules & Policies (Above Stay Details) -->
              <div :if={@booking_step == :details} class="space-y-3 mb-6">
                <!-- Weekend Rule Alert (Reactive - shows when Saturday selected without Sunday) -->
                <div
                  :if={
                    @checkin_date &&
                      Date.day_of_week(@checkin_date) == 6 &&
                      (!@checkout_date || Date.day_of_week(@checkout_date) != 7)
                  }
                  class="p-3 bg-red-50 border border-red-200 rounded-lg"
                >
                  <div class="flex items-start gap-2">
                    <.icon
                      name="hero-exclamation-triangle-solid"
                      class="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5"
                    />
                    <div class="flex-1">
                      <p class="text-sm font-semibold text-red-900">
                        ⚠️ Action Required
                      </p>
                      <p class="text-xs text-red-800">
                        You've selected Saturday. Please select Sunday as your checkout date to complete your booking.
                      </p>
                    </div>
                  </div>
                </div>
                <!-- Winter Policy Notice -->
                <div
                  :if={@checkin_date}
                  class="p-3 bg-blue-50 border border-blue-200 rounded-lg"
                >
                  <p class="text-xs text-blue-900">
                    <strong>Winter Policy:</strong>
                    <%= if @checkin_date do
                      month = @checkin_date.month

                      if month >= 12 or month <= 4 do
                        "December–April: Individual rooms only. Full buyouts available May–Nov."
                      else
                        "May–November: Full buyouts available. Individual rooms also available."
                      end
                    end %>
                  </p>
                </div>
                <!-- Pricing & Membership Info -->
                <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <div class="p-3 bg-blue-50 border border-blue-200 rounded-lg">
                    <p class="text-xs font-semibold text-blue-900 mb-2">
                      Pricing Breakdown:
                    </p>
                    <div class="text-xs text-blue-800 space-y-0.5">
                      <% season_id =
                        if @checkin_date do
                          season =
                            Season.find_season_for_date(@seasons, @checkin_date)

                          if season, do: season.id, else: nil
                        else
                          nil
                        end %>
                      <% default_adult_price =
                        get_default_adult_price(@property, season_id) %>
                      <% default_children_price =
                        get_default_children_price(@property, season_id) %>
                      <p>
                        Adults:
                        <strong>
                          <%= MoneyHelper.format_money!(default_adult_price) %>
                        </strong>
                        per night
                      </p>
                      <p>
                        Children (5-17):
                        <strong>
                          <%= MoneyHelper.format_money!(default_children_price) %>
                        </strong>
                        per night
                      </p>
                      <p>Under 5: <strong>Free</strong></p>
                    </div>
                  </div>
                  <div class="p-3 bg-zinc-50 border border-zinc-200 rounded-lg">
                    <p class="text-xs font-semibold text-zinc-900 mb-2">
                      Membership Limits:
                    </p>
                    <div class="text-xs text-zinc-700 space-y-0.5">
                      <p>Single: <strong>1 Room</strong> per booking</p>
                      <p>Family/Lifetime: <strong>2 Rooms</strong> per booking</p>
                    </div>
                  </div>
                </div>
              </div>
              <!-- Step 2a: Room Booking Details (shown when room mode selected) -->
              <div :if={@selected_booking_mode == :room}>
                <!-- Section 1: Stay Details -->
                <section class="bg-zinc-50 p-6 rounded border border-zinc-200">
                  <h2 class="text-lg font-bold mb-4 flex items-center gap-2">
                    <span class="w-6 h-6 bg-blue-600 text-white rounded-full flex items-center justify-center text-xs font-semibold">
                      2
                    </span>
                    Stay Details
                  </h2>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <!-- Date Selection -->
                    <div>
                      <.date_range_picker
                        label="Check-in & Check-out Dates"
                        id="1"
                        form={@date_form}
                        start_date_field={@date_form[:checkin_date]}
                        end_date_field={@date_form[:checkout_date]}
                        min={@restricted_min_date}
                        max={@restricted_max_date}
                        disabled={!@can_book}
                        date_tooltips={@date_tooltips}
                        property={@property}
                        today={@today}
                      />
                    </div>
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
                          class="w-full px-3 py-2 border border-zinc-300 rounded focus:ring-2 focus:ring-blue-500 focus:border-blue-500 bg-white text-left flex items-center justify-between disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                          <span class="text-zinc-900">
                            <%= format_guests_display(
                              @guests_count,
                              @children_count
                            ) %>
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
                            <!-- Adults Counter -->
                            <div>
                              <div
                                id="adults-label"
                                class="block text-sm font-semibold text-zinc-700 mb-2"
                              >
                                Number of Adults
                              </div>
                              <div
                                class="flex items-center space-x-3"
                                role="group"
                                aria-labelledby="adults-label"
                              >
                                <button
                                  type="button"
                                  id="decrease-guests-button"
                                  phx-click="decrease-guests"
                                  phx-click-stop
                                  disabled={@guests_count <= 1}
                                  aria-label="Decrease number of adults"
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
                                  aria-label="Increase number of adults"
                                  class="w-10 h-10 rounded-full border-2 border-blue-700 bg-blue-700 hover:bg-blue-800 hover:border-blue-800 text-white flex items-center justify-center transition-all duration-200 font-semibold"
                                >
                                  <.icon name="hero-plus" class="w-5 h-5" />
                                </button>
                              </div>
                            </div>
                            <!-- Children Counter -->
                            <div>
                              <div
                                id="children-label"
                                class="block text-sm font-semibold text-zinc-700 mb-2"
                              >
                                Number of Children (ages 5-17)
                              </div>
                              <div
                                class="flex items-center space-x-3"
                                role="group"
                                aria-labelledby="children-label"
                              >
                                <button
                                  type="button"
                                  id="decrease-children-button"
                                  phx-click="decrease-children"
                                  phx-click-stop
                                  disabled={@children_count <= 0}
                                  aria-label="Decrease number of children"
                                  class={[
                                    "w-10 h-10 rounded-full border flex items-center justify-center transition-colors",
                                    if(@children_count <= 0,
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
                                  id="children-count-display"
                                  class="w-12 text-center font-medium text-lg text-zinc-900"
                                  aria-live="polite"
                                >
                                  <%= @children_count %>
                                </span>
                                <button
                                  type="button"
                                  id="increase-children-button"
                                  phx-click="increase-children"
                                  phx-click-stop
                                  aria-label="Increase number of children"
                                  class="w-10 h-10 rounded-full border-2 border-blue-700 bg-blue-700 hover:bg-blue-800 hover:border-blue-800 text-white flex items-center justify-center transition-all duration-200 font-semibold"
                                >
                                  <.icon name="hero-plus" class="w-5 h-5" />
                                </button>
                              </div>
                            </div>
                            <p class="text-sm text-zinc-600 pt-2 border-t border-zinc-200">
                              <% season_id =
                                if @checkin_date do
                                  season =
                                    Season.find_season_for_date(
                                      @seasons,
                                      @checkin_date
                                    )

                                  if season, do: season.id, else: nil
                                else
                                  nil
                                end %>
                              <% default_children_price =
                                get_default_children_price(@property, season_id) %> Children 5-17 years: <%= MoneyHelper.format_money!(
                                default_children_price
                              ) %>/night. Children under 5 stay for free.
                            </p>
                            <!-- Done Button -->
                            <div class="pt-2">
                              <button
                                type="button"
                                phx-click="close-guests-dropdown"
                                class="w-full px-4 py-2 bg-blue-700 hover:bg-blue-800 text-white font-semibold rounded transition-colors duration-200"
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
                      :if={@form_errors[:checkin_date]}
                      class="text-red-600 text-sm"
                    >
                      <%= @form_errors[:checkin_date] %>
                    </p>
                    <p
                      :if={@form_errors[:checkout_date]}
                      class="text-red-600 text-sm"
                    >
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
                      :if={@date_validation_errors[:season_booking_mode]}
                      class="text-red-600 text-sm"
                    >
                      <%= @date_validation_errors[:season_booking_mode] %>
                    </p>
                    <p
                      :if={@date_validation_errors[:season_date_range]}
                      class="text-red-600 text-sm"
                    >
                      <%= @date_validation_errors[:season_date_range] %>
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
              <!-- Step 2b: Buyout Calendar (shown when buyout mode selected) -->
              <div :if={@selected_booking_mode == :buyout}>
                <section class="bg-zinc-50 p-6 rounded border border-zinc-200">
                  <div class="flex items-center justify-between mb-4">
                    <h2 class="text-lg font-bold flex items-center gap-2">
                      <span class="w-6 h-6 bg-blue-600 text-white rounded-full flex items-center justify-center text-xs font-semibold">
                        2
                      </span>
                      Select Dates
                    </h2>
                    <button
                      :if={@checkin_date || @checkout_date}
                      type="button"
                      phx-click="reset-dates"
                      class="text-xs font-semibold text-blue-600 hover:text-blue-800 transition-colors"
                    >
                      Reset Dates
                    </button>
                  </div>
                  <div class="mb-4">
                    <p class="text-sm font-medium text-zinc-800 mb-2">
                      The calendar shows which dates are available for exclusive full cabin rental.
                      <span class="font-semibold text-blue-700">
                        Dates with any room bookings are not available for buyout.
                      </span>
                    </p>
                    <p class="text-xs text-zinc-600">
                      Click on a date to start your selection, then click another date to complete your range.
                    </p>
                  </div>
                  <.live_component
                    module={YscWeb.Components.AvailabilityCalendar}
                    id="tahoe-buyout-availability-calendar"
                    checkin_date={@checkin_date}
                    checkout_date={@checkout_date}
                    selected_booking_mode={:buyout}
                    min={@restricted_min_date}
                    max={@max_booking_date}
                    property={:tahoe}
                    today={@today}
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
              <!-- Restricted Date Range Message -->
              <div
                :if={@dates_restricted && @membership_type in [:family, :lifetime]}
                class="p-3 bg-blue-50 border border-blue-200 rounded"
              >
                <div class="flex items-start">
                  <div class="flex-shrink-0">
                    <.icon
                      name="hero-information-circle"
                      class="h-5 w-5 text-blue-600"
                    />
                  </div>
                  <div class="ms-2 flex-1">
                    <p class="text-sm text-blue-800">
                      <strong>Second Room Booking:</strong>
                      Since you already have one room reserved, your second room booking must be within the same time period. The date range is restricted to ensure both bookings overlap and stay within the 4-night maximum.
                    </p>
                  </div>
                </div>
              </div>
              <!-- Section 3: Choose Your Rooms -->
              <section :if={
                @selected_booking_mode == :room && @checkin_date && @checkout_date
              }>
                <h2 class="text-lg font-bold mb-4 flex items-center gap-2">
                  <span class="w-6 h-6 bg-blue-600 text-white rounded-full flex items-center justify-center text-xs font-semibold">
                    3
                  </span>
                  Choose Your Rooms
                  <%= if can_select_multiple_rooms?(assigns) && length(@selected_room_ids) > 0 do %>
                    <span class="text-sm font-normal text-zinc-500">
                      (<%= length(@selected_room_ids) %>/<%= max_rooms_for_user(
                        assigns
                      ) %>)
                    </span>
                  <% end %>
                </h2>
                <!-- Family Membership Notice -->
                <div
                  :if={
                    can_select_multiple_rooms?(assigns) &&
                      length(@selected_room_ids) < max_rooms_for_user(assigns) &&
                      (parse_guests_count(@guests_count) || 1) > 1
                  }
                  class="mb-4 p-3 bg-blue-50 border border-blue-200 rounded"
                >
                  <div class="flex items-start gap-2">
                    <.icon
                      name="hero-light-bulb-solid"
                      class="w-5 h-5 text-blue-600 flex-shrink-0"
                    />
                    <p class="text-sm text-blue-900 font-medium">
                      <strong>Family Membership Benefit:</strong>
                      You can book up to <%= max_rooms_for_user(assigns) %> rooms in the same reservation.
                    </p>
                  </div>
                </div>
                <fieldset>
                  <div
                    class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 items-stretch"
                    role={
                      if can_select_multiple_rooms?(assigns),
                        do: "group",
                        else: "radiogroup"
                    }
                  >
                    <%= for room <- @available_rooms do %>
                      <% {availability, reason} =
                        room.availability_status || {:available, nil} %>
                      <% is_unavailable = availability == :unavailable %>
                      <% max_rooms_reached =
                        can_select_multiple_rooms?(assigns) &&
                          length(@selected_room_ids) >= max_rooms_for_user(assigns) %>
                      <% room_already_selected =
                        (can_select_multiple_rooms?(assigns) &&
                           room.id in @selected_room_ids) ||
                          (!can_select_multiple_rooms?(assigns) &&
                             @selected_room_id == room.id) %>
                      <% guests_count = parse_guests_count(@guests_count) || 1 %>
                      <% children_count = parse_children_count(@children_count) || 0 %>
                      <% total_people = guests_count + children_count %>
                      <% only_one_person_selected = total_people == 1 %>
                      <% cannot_add_second_room =
                        can_select_multiple_rooms?(assigns) &&
                          only_one_person_selected &&
                          length(@selected_room_ids) > 0 && !room_already_selected %>
                      <% is_disabled =
                        (is_unavailable && !room_already_selected) ||
                          (max_rooms_reached && !room_already_selected) ||
                          cannot_add_second_room %>
                      <div class={[
                        "border-2 rounded overflow-hidden flex flex-col h-full transition-all",
                        if(is_disabled,
                          do:
                            "border-zinc-200 bg-zinc-50 cursor-not-allowed opacity-60",
                          else:
                            if(
                              (can_select_multiple_rooms?(assigns) &&
                                 room.id in @selected_room_ids) ||
                                (!can_select_multiple_rooms?(assigns) &&
                                   @selected_room_id == room.id),
                              do: "border-blue-500 bg-blue-50 shadow-lg",
                              else:
                                "border-zinc-300 hover:border-blue-400 hover:shadow-lg cursor-pointer"
                            )
                        )
                      ]}>
                        <label
                          :if={!is_disabled}
                          class="block cursor-pointer flex flex-col h-full"
                        >
                          <input
                            type={
                              if can_select_multiple_rooms?(assigns),
                                do: "checkbox",
                                else: "radio"
                            }
                            id={"room-#{room.id}"}
                            name={
                              if can_select_multiple_rooms?(assigns),
                                do: "room_ids",
                                else: "room_id"
                            }
                            value={room.id}
                            checked={
                              if can_select_multiple_rooms?(assigns) do
                                room.id in @selected_room_ids
                              else
                                @selected_room_id == room.id
                              end
                            }
                            aria-label={"Select #{room.name}"}
                            phx-click="room-changed"
                            phx-value-room-id={room.id}
                            class="sr-only"
                          />
                          <!-- Room Image with Alert Overlay -->
                          <div class="w-full h-32 bg-zinc-200 relative overflow-hidden">
                            <!-- Availability Badge -->
                            <div
                              :if={!is_unavailable}
                              class="absolute top-2 right-2 z-10 px-2 py-1 bg-green-500 text-white text-xs font-bold rounded shadow-lg"
                            >
                              Available
                            </div>
                            <!-- Alert Overlay on Image -->
                            <div
                              :if={is_unavailable && reason}
                              class="absolute top-0 left-0 right-0 bg-gradient-to-r from-amber-50 to-amber-100 border-b border-amber-200 p-2 z-10"
                            >
                              <div class="flex items-start gap-2">
                                <.icon
                                  name="hero-exclamation-triangle-solid"
                                  class="w-4 h-4 text-amber-600 flex-shrink-0 mt-0.5"
                                />
                                <div class="flex-1">
                                  <p class="text-xs font-semibold text-amber-900 mb-1">
                                    Not Available
                                  </p>
                                  <p class="text-xs text-amber-800">
                                    <%= reason %>
                                  </p>
                                </div>
                              </div>
                            </div>
                            <%= if room.image && room.image.id do %>
                              <!-- Render image with blur hash -->
                              <canvas
                                id={"blur-hash-room-#{room.id}"}
                                src={get_room_blur_hash(room.image)}
                                class="absolute inset-0 z-0 w-full h-full object-cover"
                                phx-hook="BlurHashCanvas"
                              >
                              </canvas>
                              <img
                                src={get_room_image_url(room.image)}
                                id={"image-room-#{room.id}"}
                                loading="lazy"
                                phx-hook="BlurHashImage"
                                class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out w-full h-full object-cover"
                                alt={
                                  room.image.alt_text || room.image.title ||
                                    "#{room.name} image"
                                }
                              />
                            <% else %>
                              <!-- Placeholder when no image -->
                              <div class="absolute inset-0 flex items-center justify-center">
                                <div class="text-zinc-400 text-sm flex flex-col items-center justify-center">
                                  <.icon
                                    name="hero-photo"
                                    class="w-20 h-20 mx-auto mb-2"
                                  />Room Image
                                </div>
                              </div>
                            <% end %>
                          </div>
                          <!-- Room Content -->
                          <div class="p-4 flex-1 flex flex-col">
                            <div class="flex items-start justify-between mb-2">
                              <div class="flex-1">
                                <div class="font-bold text-zinc-900 text-base mb-1">
                                  <%= room.name %>
                                </div>
                                <div class="text-xs text-zinc-600 line-clamp-2">
                                  <%= room.description %>
                                </div>
                              </div>
                              <div class="ml-3 flex-shrink-0">
                                <div class={
                                  if (can_select_multiple_rooms?(assigns) &&
                                        room.id in @selected_room_ids) or
                                       (!can_select_multiple_rooms?(assigns) &&
                                          @selected_room_id == room.id) do
                                    "w-6 h-6 rounded-full border-2 flex items-center justify-center bg-blue-600 border-blue-600 shadow-md"
                                  else
                                    "w-6 h-6 rounded-full border-2 flex items-center justify-center border-zinc-300 bg-white"
                                  end
                                }>
                                  <svg
                                    :if={
                                      (can_select_multiple_rooms?(assigns) &&
                                         room.id in @selected_room_ids) or
                                        (!can_select_multiple_rooms?(assigns) &&
                                           @selected_room_id == room.id)
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
                              </div>
                            </div>
                            <div class="flex items-center gap-2 mb-2 flex-wrap">
                              <span class="px-2 py-1 bg-blue-100 text-blue-700 text-xs font-bold rounded border border-blue-200">
                                Max <%= room.capacity_max %> Guests
                              </span>
                              <span
                                :if={room.min_billable_occupancy > 1}
                                class="px-2 py-1 bg-amber-100 text-amber-700 text-xs font-bold rounded border border-amber-200"
                              >
                                Min <%= room.min_billable_occupancy %> Guests
                              </span>
                            </div>
                            <!-- Room Features: Compact Badges -->
                            <div
                              :if={
                                room.single_beds > 0 || room.queen_beds > 0 ||
                                  room.king_beds > 0
                              }
                              class="mb-2 flex items-center gap-2 flex-wrap"
                            >
                              <span
                                :if={room.single_beds > 0}
                                class="inline-flex items-center gap-1 px-2 py-0.5 bg-zinc-100 text-zinc-700 text-xs rounded border border-zinc-200"
                                title="Twin beds"
                              >
                                <%= raw(
                                  bed_icon_svg(:single, "w-3 h-3 text-zinc-600")
                                ) %>
                                <span><%= room.single_beds %></span>
                              </span>
                              <span
                                :if={room.queen_beds > 0}
                                class="inline-flex items-center gap-1 px-2 py-0.5 bg-zinc-100 text-zinc-700 text-xs rounded border border-zinc-200"
                                title="Queen beds"
                              >
                                <%= raw(
                                  bed_icon_svg(:queen, "w-3 h-3 text-zinc-600")
                                ) %>
                                <span><%= room.queen_beds %></span>
                              </span>
                              <span
                                :if={room.king_beds > 0}
                                class="inline-flex items-center gap-1 px-2 py-0.5 bg-zinc-100 text-zinc-700 text-xs rounded border border-zinc-200"
                                title="King beds"
                              >
                                <%= raw(
                                  bed_icon_svg(:king, "w-3 h-3 text-zinc-600")
                                ) %>
                                <span><%= room.king_beds %></span>
                              </span>
                            </div>
                            <div class="border-t border-zinc-200 pt-2 mt-auto">
                              <% season_id =
                                if @checkin_date do
                                  season =
                                    Season.find_season_for_date(
                                      @seasons,
                                      @checkin_date
                                    )

                                  if season, do: season.id, else: nil
                                else
                                  nil
                                end %>
                              <div class="text-sm text-zinc-900 font-bold">
                                <div :if={room.minimum_price}>
                                  <%= MoneyHelper.format_money!(room.minimum_price) %> min
                                  <span class="text-xs text-zinc-500 font-normal ml-1">
                                    (<%= room.min_billable_occupancy %> guest)
                                  </span>
                                </div>
                                <div :if={!room.minimum_price}>
                                  <% fallback_adult_price =
                                    get_default_adult_price(@property, season_id) %>
                                  <%= MoneyHelper.format_money!(
                                    room.adult_price_per_night ||
                                      fallback_adult_price
                                  ) %>/adult
                                </div>
                              </div>
                              <div class="text-xs text-zinc-500">
                                <% fallback_children_price =
                                  get_default_children_price(@property, season_id) %>
                                <%= MoneyHelper.format_money!(
                                  room.children_price_per_night ||
                                    fallback_children_price
                                ) %>/child
                              </div>
                            </div>
                          </div>
                        </label>
                        <div
                          :if={is_disabled}
                          class="block cursor-not-allowed flex flex-col h-full relative"
                        >
                          <input
                            type={
                              if can_select_multiple_rooms?(assigns),
                                do: "checkbox",
                                else: "radio"
                            }
                            name={
                              if can_select_multiple_rooms?(assigns),
                                do: "room_ids",
                                else: "room_id"
                            }
                            value={room.id}
                            checked={false}
                            disabled={true}
                            class="sr-only"
                            readonly
                          />
                          <!-- Room Image with Alert Overlay -->
                          <div class="w-full h-32 bg-zinc-200 relative overflow-hidden">
                            <!-- Availability Badge -->
                            <div
                              :if={!is_unavailable}
                              class="absolute top-2 right-2 z-10 px-2 py-1 bg-green-500 text-white text-xs font-bold rounded shadow-lg"
                            >
                              Available
                            </div>
                            <!-- Alert Overlay on Image -->
                            <div
                              :if={is_unavailable && reason}
                              class="absolute top-0 left-0 right-0 bg-gradient-to-r from-amber-50 to-amber-100 border-b border-amber-200 p-2 z-10"
                            >
                              <div class="flex items-start gap-2">
                                <.icon
                                  name="hero-exclamation-triangle-solid"
                                  class="w-4 h-4 text-amber-600 flex-shrink-0 mt-0.5"
                                />
                                <div class="flex-1">
                                  <p class="text-xs font-semibold text-amber-900 mb-1">
                                    Not Available
                                  </p>
                                  <p class="text-xs text-amber-800">
                                    <%= reason %>
                                  </p>
                                </div>
                              </div>
                            </div>
                            <%= if room.image && room.image.id do %>
                              <!-- Render image with blur hash -->
                              <canvas
                                id={"blur-hash-room-disabled-#{room.id}"}
                                src={get_room_blur_hash(room.image)}
                                class="absolute inset-0 z-0 w-full h-full object-cover"
                                phx-hook="BlurHashCanvas"
                              >
                              </canvas>
                              <img
                                src={get_room_image_url(room.image)}
                                id={"image-room-disabled-#{room.id}"}
                                loading="lazy"
                                phx-hook="BlurHashImage"
                                class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out w-full h-full object-cover"
                                alt={
                                  room.image.alt_text || room.image.title ||
                                    "#{room.name} image"
                                }
                              />
                            <% else %>
                              <!-- Placeholder when no image -->
                              <div class="absolute inset-0 flex items-center justify-center">
                                <div class="text-zinc-400 text-sm flex flex-col items-center justify-center">
                                  <.icon
                                    name="hero-photo"
                                    class="w-20 h-20 mx-auto mb-2"
                                  />Room Image
                                </div>
                              </div>
                            <% end %>
                          </div>
                          <!-- Room Content (Disabled) -->
                          <div class="p-4 flex-1 flex flex-col opacity-60">
                            <div class="flex items-start justify-between mb-2">
                              <div class="flex-1">
                                <div class="font-bold text-zinc-900 text-base mb-1">
                                  <%= room.name %>
                                </div>
                                <div class="text-xs text-zinc-600 line-clamp-2">
                                  <%= room.description %>
                                </div>
                              </div>
                              <div class="ml-3 flex-shrink-0">
                                <div class="w-6 h-6 rounded-full border-2 flex items-center justify-center border-zinc-300 bg-white">
                                </div>
                              </div>
                            </div>
                            <div class="flex items-center gap-2 mb-2 flex-wrap">
                              <span class="px-2 py-1 bg-blue-100 text-blue-700 text-xs font-bold rounded border border-blue-200">
                                Max <%= room.capacity_max %> Guests
                              </span>
                              <span
                                :if={room.min_billable_occupancy > 1}
                                class="px-2 py-1 bg-amber-100 text-amber-700 text-xs font-bold rounded border border-amber-200"
                              >
                                Min <%= room.min_billable_occupancy %> Guests
                              </span>
                            </div>
                            <!-- Room Features: Compact Badges -->
                            <div
                              :if={
                                room.single_beds > 0 || room.queen_beds > 0 ||
                                  room.king_beds > 0
                              }
                              class="mb-2 flex items-center gap-2 flex-wrap"
                            >
                              <span
                                :if={room.single_beds > 0}
                                class="inline-flex items-center gap-1 px-2 py-0.5 bg-zinc-100 text-zinc-700 text-xs rounded border border-zinc-200"
                                title="Twin beds"
                              >
                                <%= raw(
                                  bed_icon_svg(:single, "w-3 h-3 text-zinc-600")
                                ) %>
                                <span><%= room.single_beds %></span>
                              </span>
                              <span
                                :if={room.queen_beds > 0}
                                class="inline-flex items-center gap-1 px-2 py-0.5 bg-zinc-100 text-zinc-700 text-xs rounded border border-zinc-200"
                                title="Queen beds"
                              >
                                <%= raw(
                                  bed_icon_svg(:queen, "w-3 h-3 text-zinc-600")
                                ) %>
                                <span><%= room.queen_beds %></span>
                              </span>
                              <span
                                :if={room.king_beds > 0}
                                class="inline-flex items-center gap-1 px-2 py-0.5 bg-zinc-100 text-zinc-700 text-xs rounded border border-zinc-200"
                                title="King beds"
                              >
                                <%= raw(
                                  bed_icon_svg(:king, "w-3 h-3 text-zinc-600")
                                ) %>
                                <span><%= room.king_beds %></span>
                              </span>
                            </div>
                            <div class="border-t border-zinc-200 pt-2 mt-auto">
                              <% season_id =
                                if @checkin_date do
                                  season =
                                    Season.find_season_for_date(
                                      @seasons,
                                      @checkin_date
                                    )

                                  if season, do: season.id, else: nil
                                else
                                  nil
                                end %>
                              <div class="text-sm text-zinc-900 font-bold">
                                <div :if={room.minimum_price}>
                                  <%= MoneyHelper.format_money!(room.minimum_price) %> min
                                  <span class="text-xs text-zinc-500 font-normal ml-1">
                                    (<%= room.min_billable_occupancy %> guest)
                                  </span>
                                </div>
                                <div :if={!room.minimum_price}>
                                  <% fallback_adult_price =
                                    get_default_adult_price(@property, season_id) %>
                                  <%= MoneyHelper.format_money!(
                                    room.adult_price_per_night ||
                                      fallback_adult_price
                                  ) %>/adult
                                </div>
                              </div>
                              <div class="text-xs text-zinc-500">
                                <% fallback_children_price =
                                  get_default_children_price(@property, season_id) %>
                                <%= MoneyHelper.format_money!(
                                  room.children_price_per_night ||
                                    fallback_children_price
                                ) %>/child
                              </div>
                            </div>
                          </div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </fieldset>
                <p :if={@form_errors[:room_id]} class="text-red-600 text-sm mt-1">
                  <%= @form_errors[:room_id] %>
                </p>
                <p
                  :if={
                    can_select_multiple_rooms?(assigns) &&
                      length(@selected_room_ids) > 0 &&
                      (parse_guests_count(@guests_count) || 1) +
                        (parse_children_count(@children_count) || 0) == 1
                  }
                  class="text-amber-600 text-sm mt-2"
                >
                  <.icon
                    name="hero-exclamation-triangle-solid"
                    class="w-4 h-4 text-amber-600 inline-block me-1"
                  />
                  Cannot book multiple rooms with only 1 person. Please select more people to book additional rooms.
                </p>
              </section>
            </div>
            <!-- Right Column: Sticky Reservation Summary (1 column on large screens) -->
            <aside class="lg:sticky lg:top-24">
              <div class="bg-white rounded-2xl border-2 border-blue-600 shadow-xl overflow-hidden">
                <div class="bg-blue-600 p-4 text-white text-center">
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
                                                                               ) ==
                                                                                 1,
                                                                               do:
                                                                                 "night",
                                                                               else:
                                                                                 "nights" %>
                      </span>
                    </div>
                  </div>
                  <!-- Guests -->
                  <div
                    :if={@guests_count || @children_count}
                    class="flex justify-between text-sm"
                  >
                    <span class="text-zinc-500 font-medium">Guests</span>
                    <span class="font-semibold text-zinc-900">
                      <%= format_guests_display(@guests_count, @children_count) %>
                    </span>
                  </div>
                  <!-- Family Membership Notice in Summary Card -->
                  <div
                    :if={
                      @selected_booking_mode == :room &&
                        can_select_multiple_rooms?(assigns) &&
                        length(@selected_room_ids) < max_rooms_for_user(assigns) &&
                        (parse_guests_count(@guests_count) || 1) > 1
                    }
                    class="p-2 bg-blue-50 border border-blue-200 rounded"
                  >
                    <div class="flex items-start gap-2">
                      <.icon
                        name="hero-light-bulb-solid"
                        class="w-4 h-4 text-blue-600 flex-shrink-0"
                      />
                      <p class="text-xs text-blue-900 leading-tight">
                        <strong>Family Membership:</strong>
                        You can book up to <%= max_rooms_for_user(assigns) %> rooms.
                      </p>
                    </div>
                  </div>
                  <!-- Rule Compliance Checklist (Smart Summary) -->
                  <div
                    :if={
                      @selected_booking_mode == :room &&
                        length(@selected_room_ids) > 0 &&
                        @checkin_date &&
                        @checkout_date
                    }
                    class="mt-4"
                  >
                    <p class="text-xs font-bold text-zinc-400 uppercase mb-2">
                      Rule Compliance
                    </p>
                    <div class="space-y-2">
                      <%= for room_id <- @selected_room_ids do %>
                        <% room = Enum.find(@available_rooms, &(&1.id == room_id)) %>
                        <%= if room do %>
                          <% guests_count = parse_guests_count(@guests_count) || 1 %>
                          <% children_count =
                            parse_children_count(@children_count) || 0 %>
                          <% total_people = guests_count + children_count %>
                          <% min_required = room.min_billable_occupancy || 1 %>
                          <div
                            :if={total_people < min_required}
                            class="p-2 bg-red-50 border border-red-200 rounded"
                          >
                            <div class="flex items-start gap-2">
                              <.icon
                                name="hero-exclamation-triangle-solid"
                                class="w-4 h-4 text-red-600 flex-shrink-0 mt-0.5"
                              />
                              <div class="flex-1">
                                <p class="text-xs font-semibold text-red-900">
                                  <%= room.name %> requires minimum of <%= min_required %> guests
                                </p>
                                <p class="text-xs text-red-800 mt-0.5">
                                  <% season_id =
                                    if @checkin_date do
                                      season =
                                        Season.find_season_for_date(
                                          @seasons,
                                          @checkin_date
                                        )

                                      if season, do: season.id, else: nil
                                    else
                                      nil
                                    end %>
                                  <% fallback_adult_price =
                                    get_default_adult_price(@property, season_id) %>
                                  <% room_adult_price =
                                    room.adult_price_per_night ||
                                      fallback_adult_price %> (<%= MoneyHelper.format_money!(
                                    case Money.mult(room_adult_price, min_required) do
                                      {:ok, total} -> total
                                      _ -> room_adult_price
                                    end
                                  ) %>/night minimum)
                                </p>
                              </div>
                            </div>
                          </div>
                          <div
                            :if={total_people >= min_required}
                            class="p-2 bg-green-50 border border-green-200 rounded flex items-center gap-2"
                          >
                            <.icon
                              name="hero-check-circle"
                              class="w-4 h-4 text-green-600 flex-shrink-0"
                            />
                            <p class="text-xs text-green-900">
                              <%= room.name %>: Guest count OK
                            </p>
                          </div>
                        <% end %>
                      <% end %>
                    </div>
                  </div>

                  <hr class="border-zinc-100" />
                  <!-- Selected Rooms or Buyout -->
                  <div
                    :if={
                      @selected_booking_mode == :room &&
                        length(@selected_room_ids) > 0
                    }
                    class="space-y-2"
                  >
                    <p class="text-xs font-bold text-zinc-400 uppercase">
                      Selected Rooms
                    </p>
                    <%= for room_id <- @selected_room_ids do %>
                      <% room = Enum.find(@available_rooms, &(&1.id == room_id)) %>
                      <div
                        :if={room}
                        class="flex justify-between items-center text-sm"
                      >
                        <span class="text-zinc-700"><%= room.name %></span>
                        <button
                          phx-click="remove-room"
                          phx-value-room-id={room_id}
                          class="text-red-600 hover:text-red-800 text-xs underline"
                        >
                          Remove
                        </button>
                      </div>
                    <% end %>
                  </div>

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
                      Full Cabin Buyout
                    </div>
                  </div>
                  <!-- Price Breakdown -->
                  <div :if={
                    @calculated_price && @price_breakdown && @checkin_date &&
                      @checkout_date
                  }>
                    <hr class="border-zinc-100" />
                    <div class="space-y-2">
                      <!-- Buyout Price -->
                      <div
                        :if={@selected_booking_mode == :buyout}
                        class="flex justify-between text-sm"
                      >
                        <span class="text-zinc-600">
                          Full Buyout
                          <%= if @price_breakdown.nights && @price_breakdown.price_per_night do %>
                            (<%= MoneyHelper.format_money!(
                              @price_breakdown.price_per_night
                            ) %> × <%= @price_breakdown.nights %>)
                          <% end %>
                        </span>
                        <span class="font-semibold text-zinc-900">
                          <%= MoneyHelper.format_money!(@calculated_price) %>
                        </span>
                      </div>
                      <!-- Room Price Breakdown -->
                      <div :if={@selected_booking_mode == :room}>
                        <div
                          :if={@price_breakdown[:using_minimum_pricing]}
                          class="mb-2 p-2 bg-amber-50 border border-amber-200 rounded"
                        >
                          <div class="flex items-start gap-2">
                            <.icon
                              name="hero-information-circle"
                              class="w-3 h-3 text-amber-600 flex-shrink-0 mt-0.5"
                            />
                            <p class="text-[10px] text-amber-800 leading-tight">
                              Minimum occupancy pricing applied
                            </p>
                          </div>
                        </div>
                        <div class="flex justify-between text-sm">
                          <span class="text-zinc-600">
                            Base Price
                            <%= if @price_breakdown.nights && @price_breakdown[:adult_price_per_night] do %>
                              <% adult_count =
                                @price_breakdown[:billable_people] ||
                                  @price_breakdown[:guests_count] ||
                                  0 %> (<%= adult_count %> <%= if adult_count == 1,
                                do: "adult",
                                else: "adults" %> × <%= @price_breakdown.nights %>)
                            <% end %>
                          </span>
                          <span class="font-semibold text-zinc-900">
                            <%= if @price_breakdown[:base],
                              do: MoneyHelper.format_money!(@price_breakdown.base) %>
                          </span>
                        </div>
                        <div
                          :if={
                            @price_breakdown[:children] &&
                              @price_breakdown[:children_per_night]
                          }
                          class="flex justify-between text-sm"
                        >
                          <span class="text-zinc-600">
                            Children
                            <%= if @price_breakdown.nights do %>
                              (<%= @price_breakdown[:children_count] || 0 %> × <%= @price_breakdown.nights %>)
                            <% end %>
                          </span>
                          <span class="font-semibold text-zinc-900">
                            <%= MoneyHelper.format_money!(@price_breakdown.children) %>
                          </span>
                        </div>
                      </div>
                    </div>

                    <hr class="border-zinc-200 my-3" />

                    <div class="flex justify-between items-end">
                      <span class="text-lg font-bold text-zinc-900">Total</span>
                      <div class="text-right">
                        <span class="text-2xl font-black text-blue-600">
                          <%= MoneyHelper.format_money!(@calculated_price) %>
                        </span>
                      </div>
                    </div>
                  </div>
                  <!-- Error Messages -->
                  <div :if={@price_error || @capacity_error} class="space-y-1">
                    <p :if={@price_error} class="text-red-600 text-xs">
                      <%= @price_error %>
                    </p>
                    <p :if={@capacity_error} class="text-red-600 text-xs">
                      <%= @capacity_error %>
                    </p>
                  </div>
                  <!-- Missing Info List (Smart Sidebar) -->
                  <div
                    :if={
                      !can_submit_booking?(
                        @selected_booking_mode,
                        @checkin_date,
                        @checkout_date,
                        get_selected_rooms_for_submit(assigns),
                        @capacity_error,
                        @price_error,
                        @form_errors,
                        @date_validation_errors
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
                          @selected_booking_mode == :room &&
                          length(get_selected_rooms_for_submit(assigns) || []) == 0
                      }>
                        Please select at least one room
                      </li>
                      <li :if={
                        @checkin_date &&
                          @checkout_date &&
                          @selected_booking_mode == :buyout &&
                          @date_validation_errors[:availability]
                      }>
                        Full buyout unavailable for selected dates
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
                  <!-- Agreement Checkbox -->
                  <div
                    :if={
                      @can_book &&
                        can_submit_booking?(
                          @selected_booking_mode,
                          @checkin_date,
                          @checkout_date,
                          get_selected_rooms_for_submit(assigns),
                          @capacity_error,
                          @price_error,
                          @form_errors,
                          @date_validation_errors
                        )
                    }
                    class="pt-2"
                  >
                    <label class="flex items-start gap-2 cursor-pointer">
                      <input
                        type="checkbox"
                        id="terms-agreement"
                        phx-click="toggle-terms-agreement"
                        checked={@terms_agreed}
                        class="mt-1 items-center"
                      />
                      <span class="text-xs text-zinc-600">
                        I have read and agree to the Tahoe Cabin <button
                          type="button"
                          phx-click="show-terms-modal"
                          class="text-blue-600 hover:text-blue-800 underline"
                        >
                        Rules & Policies
                      </button>.
                      </span>
                    </label>
                  </div>
                  <!-- Submit Button -->
                  <div class="pt-2">
                    <.button
                      :if={@can_book}
                      phx-click="show-confirm-modal"
                      phx-disable-with="Loading..."
                      disabled={
                        !can_submit_booking?(
                          @selected_booking_mode,
                          @checkin_date,
                          @checkout_date,
                          get_selected_rooms_for_submit(assigns),
                          @capacity_error,
                          @price_error,
                          @form_errors,
                          @date_validation_errors
                        ) || !Map.get(assigns, :terms_agreed, false)
                      }
                      class={
                        if can_submit_booking?(
                             @selected_booking_mode,
                             @checkin_date,
                             @checkout_date,
                             get_selected_rooms_for_submit(assigns),
                             @capacity_error,
                             @price_error,
                             @form_errors,
                             @date_validation_errors
                           ) &&
                             Map.get(assigns, :terms_agreed, false) do
                          "w-full text-lg py-3"
                        else
                          "w-full bg-zinc-200 text-zinc-600 hover:bg-zinc-300 opacity-50 cursor-not-allowed py-3"
                        end
                      }
                    >
                      <span class="flex items-center justify-center gap-2">
                        <.icon name="hero-check-circle-solid" class="w-5 h-5" />Confirm Booking
                      </span>
                    </.button>
                    <div
                      :if={!@can_book}
                      class="w-full bg-zinc-200 text-zinc-600 font-semibold py-4 rounded text-center cursor-not-allowed"
                    >
                      Booking Unavailable
                    </div>
                    <p
                      :if={@can_book && @calculated_price}
                      class="text-center text-xs text-zinc-400 mt-2"
                    >
                      You won't be charged yet.
                    </p>
                  </div>
                </div>
              </div>
            </aside>
          </div>
          <!-- Confirmation Modal (Interstitial) -->
          <div
            :if={Map.get(assigns, :show_confirm_modal, false)}
            class="fixed inset-0 z-50 overflow-y-auto"
            phx-click-away="close-confirm-modal"
          >
            <div class="flex items-center justify-center min-h-screen px-4 pt-4 pb-20 text-center sm:block sm:p-0">
              <div
                class="fixed inset-0 transition-opacity bg-zinc-500 bg-opacity-75"
                aria-hidden="true"
              >
              </div>
              <span
                class="hidden sm:inline-block sm:align-middle sm:h-screen"
                aria-hidden="true"
              >
                &#8203;
              </span>
              <div
                class="inline-block align-bottom bg-white rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full"
                phx-click="ignore"
                phx-click-stop
              >
                <div class="bg-white px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                  <div class="sm:flex sm:items-start">
                    <div class="mx-auto flex-shrink-0 flex items-center justify-center h-12 w-12 rounded-full bg-blue-100 sm:mx-0 sm:h-10 sm:w-10">
                      <.icon
                        name="hero-exclamation-triangle-solid"
                        class="h-6 w-6 text-blue-600"
                      />
                    </div>
                    <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left w-full">
                      <h3 class="text-lg leading-6 font-medium text-zinc-900 mb-4">
                        Confirm Your Booking
                      </h3>
                      <div class="mt-2 space-y-4">
                        <p class="text-sm text-zinc-500 mb-4">
                          Before confirming, please acknowledge the following requirements:
                        </p>
                        <label class="flex items-start gap-3 cursor-pointer p-3 bg-amber-50 border border-amber-200 rounded">
                          <input
                            type="checkbox"
                            phx-click="toggle-linens-confirmation"
                            checked={Map.get(assigns, :linens_confirmed, false)}
                            class="mt-1"
                          />
                          <div class="flex-1">
                            <span class="text-sm font-semibold text-amber-900">
                              I understand that no bed linens or towels are provided and I will bring my own.
                            </span>
                          </div>
                        </label>
                        <label class="flex items-start gap-3 cursor-pointer p-3 bg-blue-50 border border-blue-200 rounded">
                          <input
                            type="checkbox"
                            phx-click="toggle-chores-confirmation"
                            checked={Map.get(assigns, :chores_confirmed, false)}
                            class="mt-1"
                          />
                          <div class="flex-1">
                            <span class="text-sm font-semibold text-blue-900">
                              I agree to perform the required chores (cleaning the booked rooms, cleaning the kitchen and bathrooms) before I depart.
                            </span>
                          </div>
                        </label>
                        <label class="flex items-start gap-3 cursor-pointer p-3 bg-red-50 border border-red-200 rounded">
                          <input
                            type="checkbox"
                            phx-click="toggle-party-size-confirmation"
                            checked={Map.get(assigns, :party_size_confirmed, false)}
                            class="mt-1"
                          />
                          <div class="flex-1">
                            <span class="text-sm font-semibold text-red-900">
                              <% party_size_text =
                                if assigns.selected_booking_mode == :buyout do
                                  "17 guests (full cabin)"
                                else
                                  guests_count =
                                    parse_guests_count(assigns.guests_count) || 1

                                  children_count =
                                    parse_children_count(assigns.children_count) ||
                                      0

                                  total = guests_count + children_count

                                  "#{total} #{if total == 1, do: "guest", else: "guests"}"
                                end %> I confirm that the number of people in my booking (<%= party_size_text %>) matches my actual party size.
                            </span>
                          </div>
                        </label>
                      </div>
                    </div>
                  </div>
                </div>
                <div class="bg-zinc-50 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
                  <.button
                    phx-click="create-booking"
                    disabled={
                      !Map.get(assigns, :linens_confirmed, false) ||
                        !Map.get(assigns, :chores_confirmed, false) ||
                        !Map.get(assigns, :party_size_confirmed, false)
                    }
                    class={
                      [
                        "w-full sm:ml-3 sm:w-auto px-4 py-2 text-sm font-semibold rounded",
                        if(
                          Map.get(assigns, :linens_confirmed, false) &&
                            Map.get(assigns, :chores_confirmed, false) &&
                            Map.get(assigns, :party_size_confirmed, false),
                          do: "bg-blue-600 text-white hover:bg-blue-700",
                          else: "bg-zinc-300 text-zinc-500 cursor-not-allowed"
                        )
                      ]
                      |> Enum.filter(& &1)
                      |> Enum.join(" ")
                    }
                  >
                    Confirm Booking
                  </.button>
                  <button
                    type="button"
                    phx-click="close-confirm-modal"
                    class="mt-3 w-full sm:mt-0 sm:w-auto px-4 py-2 text-sm font-semibold text-zinc-700 bg-white border border-zinc-300 rounded hover:bg-zinc-50"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            </div>
          </div>
          <!-- Terms & Policies Modal -->
          <div
            :if={Map.get(assigns, :show_terms_modal, false)}
            class="fixed inset-0 z-50 overflow-y-auto"
            phx-click="close-terms-modal"
            phx-click-away="close-terms-modal"
          >
            <div class="flex items-center justify-center min-h-screen px-4 pt-4 pb-20 text-center sm:block sm:p-0">
              <div
                class="fixed inset-0 transition-opacity bg-zinc-500 bg-opacity-75"
                aria-hidden="true"
              >
              </div>
              <span
                class="hidden sm:inline-block sm:align-middle sm:h-screen"
                aria-hidden="true"
              >
                &#8203;
              </span>
              <div
                class="inline-block align-bottom bg-white rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-3xl sm:w-full"
                phx-click-away="close-terms-modal"
              >
                <div class="bg-white px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                  <div class="flex items-start justify-between mb-4">
                    <h3 class="text-2xl font-bold text-zinc-900">
                      Tahoe Cabin Rules & Policies
                    </h3>
                    <button
                      type="button"
                      phx-click="close-terms-modal"
                      class="text-zinc-400 hover:text-zinc-600 transition-colors"
                      aria-label="Close modal"
                    >
                      <.icon name="hero-x-mark" class="w-6 h-6" />
                    </button>
                  </div>
                  <!-- Payment Notice -->
                  <div class="mt-4 mb-4 p-3 bg-red-50 border-2 border-red-300 rounded-lg">
                    <p class="text-sm font-semibold text-red-900">
                      All guests(adults & children) must be paid for in advance of showing up at the cabin.
                    </p>
                  </div>
                  <div class="mt-4 max-h-[70vh] overflow-y-auto pr-2 space-y-6 text-sm text-zinc-700">
                    <!-- Arrival & Departure -->
                    <div>
                      <h4 class="text-lg font-bold text-zinc-900 mb-2">
                        🕒 Arrival & Departure
                      </h4>
                      <div class="space-y-1 ml-4">
                        <p><strong>Check-In:</strong> 3:00 p.m.</p>
                        <p><strong>Check-Out:</strong> 11:00 a.m.</p>
                        <p>
                          <strong>Registration:</strong>
                          All guests must sign the guest book upon arrival.
                        </p>
                      </div>
                    </div>
                    <!-- Reservations & Rates -->
                    <div>
                      <h4 class="text-lg font-bold text-zinc-900 mb-2">
                        📝 Reservations & Rates
                      </h4>
                      <div class="space-y-2 ml-4">
                        <p>
                          <strong>Booking:</strong>
                          All stays must be booked and paid in advance via the website.
                        </p>
                        <p>
                          <strong>Active Stays:</strong>
                          Only one active reservation is allowed per membership. You may book your next stay once your current one is completed.
                        </p>
                        <div>
                          <p class="font-semibold mb-1">Winter Limits (Dec–Apr):</p>
                          <ul class="list-disc list-inside ml-2 space-y-1">
                            <li>Single Members: Max 1 room.</li>
                            <li>
                              Family Members: Max 2 rooms (must be same dates).
                            </li>
                            <li>No full cabin buyouts during winter.</li>
                          </ul>
                        </div>
                        <div>
                          <p class="font-semibold mb-1">
                            Pricing (Per Person/Night):
                          </p>
                          <p>Adults: $45 | Children (5–17): $25 | Under 5: Free.</p>
                        </div>
                      </div>
                    </div>
                    <!-- Location & Parking -->
                    <div>
                      <h4 class="text-lg font-bold text-zinc-900 mb-2">
                        🚗 Location & Parking
                      </h4>
                      <div class="space-y-1 ml-4">
                        <p>
                          <strong>Address:</strong>
                          2685 Cedar Lane, Homewood, CA 96141.
                        </p>
                        <p>
                          <strong>Winter Driving:</strong>
                          You must carry chains or drive a 4WD with snow tires. Check Caltrans (800-427-7623) before travel.
                        </p>
                        <p>
                          <strong>Parking:</strong>
                          Extremely limited; carpooling is encouraged.
                        </p>
                        <p>
                          <strong>Street Parking Ban:</strong>
                          Do NOT park on the street from Nov 1st – May 1st. You will be towed for snow removal.
                        </p>
                      </div>
                    </div>
                    <!-- Bear Safety -->
                    <div>
                      <h4 class="text-lg font-bold text-zinc-900 mb-2">
                        🐻 Bear Safety & The Electric Wire
                      </h4>
                      <div class="space-y-2 ml-4">
                        <p>
                          The cabin is protected by an electric bear wire. It is safe if handled correctly:
                        </p>
                        <div>
                          <p class="font-semibold mb-1">To Enter:</p>
                          <p>
                            Disconnect the TOP handle first (this disables the system). Then remove the middle and bottom wires.
                          </p>
                        </div>
                        <div>
                          <p class="font-semibold mb-1">To Secure:</p>
                          <p>
                            When leaving or at night, replace wires from BOTTOM to TOP. The top wire activates the barrier.
                          </p>
                        </div>
                        <p>
                          <strong>Trash:</strong>
                          Use bearproof lids on all garbage cans at all times.
                        </p>
                      </div>
                    </div>
                    <!-- Cabin Etiquette -->
                    <div>
                      <h4 class="text-lg font-bold text-zinc-900 mb-2">
                        🏠 Cabin Etiquette
                      </h4>
                      <div class="space-y-1 ml-4">
                        <p>
                          <strong>Quiet Hours:</strong>
                          10:00 p.m. – 7:00 a.m. (Please step lightly on the stairs).
                        </p>
                        <p>
                          <strong>Children:</strong>
                          For safety and noise, children are not permitted to play on the stairs.
                        </p>
                        <p>
                          <strong>Prohibited:</strong>
                          No pets. No smoking or vaping inside the cabin.
                        </p>
                        <p>
                          <strong>Storage:</strong>
                          Store ski boots in the laundry room racks; all other ski gear goes in the outside stairwell. Do not clutter common areas.
                        </p>
                      </div>
                    </div>
                    <!-- What to Bring -->
                    <div>
                      <h4 class="text-lg font-bold text-zinc-900 mb-2">
                        🧺 What to Bring
                      </h4>
                      <div class="space-y-1 ml-4">
                        <p>
                          <strong>Linens:</strong>
                          You must bring your own sheets, pillowcases, towels, and sleeping bags. None are provided.
                        </p>
                        <p>
                          <strong>Food:</strong>
                          Bring your own food. A full kitchen and spices are available.
                        </p>
                        <p>
                          <strong>Firewood:</strong>
                          Bring fire starter/kindling and some dry wood to start the stove.
                        </p>
                      </div>
                    </div>
                    <!-- Cleaning & Chores -->
                    <div>
                      <h4 class="text-lg font-bold text-zinc-900 mb-2">
                        🧹 Cleaning & Chores (Required)
                      </h4>
                      <div class="space-y-1 ml-4">
                        <p>
                          <strong>Kitchen:</strong>
                          Leave it spotless; remove all food from the refrigerator.
                        </p>
                        <p>
                          <strong>Rooms:</strong>
                          Clean your room and strip the beds.
                        </p>
                        <p>
                          <strong>Laundry:</strong>
                          If you use club bedding, you must wash, dry, and fold it before leaving.
                        </p>
                      </div>
                    </div>
                    <!-- Cancellation Policy -->
                    <div>
                      <h4 class="text-lg font-bold text-zinc-900 mb-2">
                        📅 Cancellation Policy
                      </h4>
                      <div class="space-y-1 ml-4">
                        <p>
                          <strong>Full Cabin:</strong>
                          50% forfeiture &lt; 21 days; 100% forfeiture &lt; 14 days.
                        </p>
                        <p>
                          <strong>Rooms:</strong>
                          50% forfeiture &lt; 14 days; 100% forfeiture &lt; 7 days.
                        </p>
                        <p class="mt-2">
                          <strong>Note:</strong>
                          All cash refunds are subject to a 3% processing fee. Road closure cancellations must be reported immediately to the Cabin Master for credit.
                        </p>
                      </div>
                    </div>
                    <!-- Compliance & Disciplinary Actions -->
                    <div>
                      <h4 class="text-lg font-bold text-zinc-900 mb-2">
                        ⚠️ Compliance & Disciplinary Actions
                      </h4>
                      <div class="space-y-1 ml-4">
                        <p>
                          Failure to comply with the rules and policies may lead to disciplinary actions or penalties, up to board discretion.
                        </p>
                      </div>
                    </div>
                    <!-- Board Authority -->
                    <div>
                      <h4 class="text-lg font-bold text-zinc-900 mb-2">
                        📋 Board Authority
                      </h4>
                      <div class="space-y-1 ml-4">
                        <p>
                          Any booking may be cancelled or adjusted for any reason by the board of directors.
                        </p>
                      </div>
                    </div>
                  </div>
                </div>
                <div class="bg-zinc-50 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
                  <button
                    type="button"
                    phx-click="close-terms-modal"
                    class="w-full sm:w-auto px-6 py-2 text-sm font-semibold text-white bg-blue-600 rounded hover:bg-blue-700 transition-colors"
                  >
                    I Understand
                  </button>
                </div>
              </div>
            </div>
          </div>
          <!-- Booking Eligibility Banner (shown when user can't book) -->
          <div
            :if={!@can_book}
            class="bg-amber-50 border border-amber-200 rounded p-4"
          >
            <div class="flex items-start">
              <div class="flex-shrink-0">
                <.icon
                  name="hero-exclamation-triangle-solid"
                  class="h-5 w-5 text-amber-600"
                />
              </div>
              <div class="ms-2 flex-1">
                <h3
                  :if={@booking_error_title}
                  class="text-sm font-semibold text-amber-900"
                >
                  <%= @booking_error_title %>
                </h3>
                <div class="mt-2 text-sm text-amber-800">
                  <p><%= raw(@booking_disabled_reason) %></p>
                </div>
              </div>
            </div>
          </div>
          <!-- Information Sections (Tab System) -->
          <div id="information-section" class="mt-12 max-w-screen-xl mx-auto">
            <!-- Tab Navigation (Sticky) -->
            <div class="sticky top-0 z-10 bg-white/80 backdrop-blur-md border-b border-zinc-200 mb-8 -mx-4 px-4 py-2">
              <nav class="flex gap-2 overflow-x-auto" role="tablist">
                <button
                  phx-click="switch-info-tab"
                  phx-value-tab="general"
                  class={[
                    "px-4 py-2 text-sm font-bold rounded-lg transition-all whitespace-nowrap",
                    if(Map.get(assigns, :info_tab, :general) == :general,
                      do: "bg-blue-50 text-blue-600 border border-blue-100",
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
                    "px-4 py-2 text-sm font-medium rounded-lg transition-all whitespace-nowrap",
                    if(Map.get(assigns, :info_tab, :general) == :rules,
                      do: "bg-blue-50 text-blue-600 border border-blue-100",
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
                      Welcome to the YSC Tahoe Cabin
                    </h1>
                    <p class="text-lg text-zinc-600 leading-relaxed">
                      Your year-round retreat in the heart of Lake Tahoe. Since <strong>1993</strong>, the YSC has proudly owned this beautiful cabin, located just minutes from Tahoe City, on the
                      <strong>west shore</strong>
                      of <strong>Lake Tahoe</strong>.
                    </p>
                  </div>
                  <!-- Important Notice -->
                  <div class="flex items-center gap-3 p-4 bg-amber-50 border border-amber-100 rounded-xl not-prose mb-10">
                    <span class="text-2xl flex-shrink-0">💡</span>
                    <p class="text-sm text-amber-900 m-0">
                      <strong>Remember:</strong>
                      The Tahoe Cabin is <strong>your cabin — not a hotel.</strong>
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
                    The Lake Tahoe region offers endless outdoor opportunities:
                  </p>
                  <!-- At-A-Glance Hero Grid -->
                  <div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-12">
                    <div class="bg-white border border-zinc-200 rounded-2xl p-5 shadow-sm hover:border-blue-200 transition-colors">
                      <div class="w-10 h-10 bg-blue-50 rounded-full flex items-center justify-center text-xl mb-4 mx-auto">
                        🛏️
                      </div>
                      <div class="text-xs uppercase tracking-widest text-zinc-500 font-bold mb-1 text-center">
                        Capacity
                      </div>
                      <div class="text-lg font-bold text-zinc-900 leading-tight text-center">
                        17 Guests
                      </div>
                      <div class="text-xs text-zinc-500 text-center mt-1">
                        7 Bedrooms
                      </div>
                    </div>
                    <div class="bg-white border border-zinc-200 rounded-2xl p-5 shadow-sm hover:border-blue-200 transition-colors">
                      <div class="w-10 h-10 bg-blue-50 rounded-full flex items-center justify-center text-xl mb-4 mx-auto">
                        🧖
                      </div>
                      <div class="text-xs uppercase tracking-widest text-zinc-500 font-bold mb-1 text-center">
                        Sauna
                      </div>
                      <div class="text-lg font-bold text-zinc-900 leading-tight text-center">
                        Traditional
                      </div>
                      <div class="text-xs text-zinc-500 text-center mt-1">
                        Scandinavian Style
                      </div>
                    </div>
                    <div class="bg-white border border-zinc-200 rounded-2xl p-5 shadow-sm hover:border-blue-200 transition-colors">
                      <div class="w-10 h-10 bg-blue-50 rounded-full flex items-center justify-center text-xl mb-4 mx-auto">
                        🔥
                      </div>
                      <div class="text-xs uppercase tracking-widest text-zinc-500 font-bold mb-1 text-center">
                        Features
                      </div>
                      <div class="text-lg font-bold text-zinc-900 leading-tight text-center">
                        Wood Fireplace
                      </div>
                      <div class="text-xs text-zinc-500 text-center mt-1">
                        And Fully Equipped Kitchen!
                      </div>
                    </div>
                    <div class="bg-white border border-zinc-200 rounded-2xl p-5 shadow-sm hover:border-blue-200 transition-colors">
                      <div class="w-10 h-10 bg-blue-50 rounded-full flex items-center justify-center text-xl mb-4 mx-auto">
                        🛶
                      </div>
                      <div class="text-xs uppercase tracking-widest text-zinc-500 font-bold mb-1 text-center">
                        Summer
                      </div>
                      <div class="text-lg font-bold text-zinc-900 leading-tight text-center">
                        Kayaks
                      </div>
                      <div class="text-xs text-zinc-500 text-center mt-1">
                        Available for use
                      </div>
                    </div>
                  </div>

                  <YscWeb.Components.ImageCarousel.image_carousel
                    id="about-the-tahoe-cabin-carousel"
                    images={[
                      %{
                        src: ~p"/images/tahoe/tahoe_cabin_main.webp",
                        alt: "Tahoe Cabin Exterior"
                      },
                      %{
                        src: ~p"/images/tahoe/tahoe_room_1.webp",
                        alt: "Tahoe Cabin Room 1"
                      },
                      %{
                        src: ~p"/images/tahoe/tahoe_room_2.webp",
                        alt: "Tahoe Cabin Room 2"
                      },
                      %{
                        src: ~p"/images/tahoe/tahoe_room_4.webp",
                        alt: "Tahoe Cabin Room 4"
                      },
                      %{
                        src: ~p"/images/tahoe/tahoe_room_5.webp",
                        alt: "Tahoe Cabin Room 5"
                      },
                      %{
                        src: ~p"/images/tahoe/tahoe_room_6.webp",
                        alt: "Tahoe Cabin Room 6"
                      },
                      %{
                        src: ~p"/images/tahoe/tahoe_room_7.webp",
                        alt: "Tahoe Cabin Room 7"
                      }
                    ]}
                    class="mb-12 rounded-2xl overflow-hidden shadow-2xl"
                  />
                  <!-- Nearby Destinations -->
                  <section class="mb-12">
                    <h2 class="text-xl font-bold text-zinc-900 mb-4 flex items-center gap-2">
                      <span>🏔️</span>
                      <span>Nearby Destinations</span>
                    </h2>
                    <div class="bg-white border border-zinc-200 rounded-2xl overflow-hidden shadow-sm">
                      <div class="flex items-center justify-between p-4 border-b border-zinc-100">
                        <div class="flex items-center gap-3">
                          <span class="text-xl">⛷️</span>
                          <span class="font-semibold">Palisades Tahoe</span>
                        </div>
                        <span class="bg-blue-100 text-blue-700 px-3 py-1 rounded-full text-xs font-bold">
                          20 MINS
                        </span>
                      </div>
                      <div class="flex items-center justify-between p-4 border-b border-zinc-100">
                        <div class="flex items-center gap-3">
                          <span class="text-xl">❄️</span>
                          <span class="font-semibold">Northstar Ski Resort</span>
                        </div>
                        <span class="bg-blue-100 text-blue-700 px-3 py-1 rounded-full text-xs font-bold">
                          30 MINS
                        </span>
                      </div>
                      <div class="flex items-center justify-between p-4">
                        <div class="flex items-center gap-3">
                          <span class="text-xl">🛷</span>
                          <span class="font-semibold">Granlibakken (Sledding)</span>
                        </div>
                        <span class="bg-blue-100 text-blue-700 px-3 py-1 rounded-full text-xs font-bold">
                          5 MINS
                        </span>
                      </div>
                    </div>
                    <p class="text-sm text-zinc-600 mt-4">
                      <strong>📍 Location:</strong>
                      South of Tahoe City, near the lake's west shore.
                    </p>
                  </section>
                </section>
                <!-- How to Book -->
                <section class="bg-white border border-zinc-200 rounded-2xl p-6 shadow-sm">
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
                        Browse available rooms and select the ones that best fit your group size.
                      </li>
                      <li>
                        Complete your booking and payment <strong>through this website</strong>. You'll receive a confirmation email with your booking details.
                      </li>
                      <li>
                        After booking, you can view and manage your reservation, including cancellation options, from your booking details page (accessible via the link in your confirmation email).
                      </li>
                      <li>
                        For cancellation policies and refund information, see the
                        <strong>Cancellation Policy</strong>
                        in the Cabin Rules tab.
                      </li>
                    </ul>
                  </div>
                </section>
                <!-- Getting There -->
                <section id="getting-there">
                  <h2 class="text-2xl font-bold text-zinc-900 mb-4 flex items-center gap-2">
                    <span>🚗</span>
                    <span>Getting There</span>
                  </h2>
                  <div class="grid md:grid-cols-2 gap-8 items-start">
                    <div>
                      <div class="bg-zinc-50 border border-zinc-200 rounded-2xl p-6">
                        <p class="text-xs uppercase tracking-widest text-zinc-500 font-bold mb-2">
                          Address
                        </p>
                        <p class="text-xl font-medium text-zinc-900 mb-6">
                          2685 Cedar Lane<br />Homewood, CA 96141
                        </p>

                        <h3 class="font-bold text-zinc-900 mb-3">
                          From the Bay Area
                        </h3>
                        <ol class="space-y-3 text-zinc-700 text-sm">
                          <li class="flex gap-3">
                            <span class="font-bold text-blue-600 flex-shrink-0">
                              1.
                            </span>
                            <span>
                              Take <strong>I-80 East</strong> toward Reno.
                            </span>
                          </li>
                          <li class="flex gap-3">
                            <span class="font-bold text-blue-600 flex-shrink-0">
                              2.
                            </span>
                            <span>
                              Exit at <strong>Truckee</strong>, onto <strong>Highway 89 South</strong>.
                            </span>
                          </li>
                          <li class="flex gap-3">
                            <span class="font-bold text-blue-600 flex-shrink-0">
                              3.
                            </span>
                            <span>
                              In <strong>Tahoe City</strong>, turn right at the first light to stay on Hwy 89.
                            </span>
                          </li>
                          <li class="flex gap-3">
                            <span class="font-bold text-blue-600 flex-shrink-0">
                              4.
                            </span>
                            <span>
                              After ~3 miles, turn
                              <strong>right onto Timberland Lane</strong>
                              (look for the Timberland totem pole).
                            </span>
                          </li>
                          <li class="flex gap-3">
                            <span class="font-bold text-blue-600 flex-shrink-0">
                              5.
                            </span>
                            <span>
                              Turn <strong>left onto Cedar Lane</strong>
                              — the cabin is on your left.
                            </span>
                          </li>
                        </ol>
                        <p class="text-sm text-zinc-600 mt-6">
                          <strong>Transportation Notes:</strong>
                          Public transportation is limited —
                          <strong>driving is recommended.</strong>
                          <strong>Carpooling</strong>
                          is encouraged to reduce parking strain and environmental impact.
                        </p>
                      </div>
                    </div>

                    <div class="space-y-4">
                      <div class="rounded-2xl overflow-hidden border border-zinc-200 shadow-sm h-80">
                        <.live_component
                          id="tahoe-cabin-map"
                          module={YscWeb.Components.MapComponent}
                          latitude={39.12591794747629}
                          longitude={-120.16648676079016}
                          locked={true}
                          class="w-full h-full"
                        />
                      </div>
                      <YscWeb.Components.MapNavigationButtons.map_navigation_buttons
                        latitude={39.12591794747629}
                        longitude={-120.16648676079016}
                        class="w-full"
                      />
                    </div>
                  </div>
                </section>
                <!-- Pre-Arrival Checklist & Door Code -->
                <section class="grid md:grid-cols-2 gap-6">
                  <div class="bg-blue-600 rounded-2xl p-8 text-white shadow-lg shadow-blue-200">
                    <div class="flex items-center gap-3 mb-6">
                      <div class="p-2 bg-white/20 rounded-lg">🔑</div>
                      <h2 class="text-xl font-bold text-white">
                        Door Code & Access
                      </h2>
                    </div>
                    <p class="text-blue-100 mb-6 leading-relaxed">
                      Sent via email <strong>24 hours before check-in</strong>. Unique to your booking. The code is also displayed on your booking confirmation page when your stay is within 48 hours of check-in or currently active.
                    </p>
                    <div class="bg-blue-700/50 border border-white/10 rounded-xl p-4 text-sm">
                      <p class="font-semibold text-blue-50 mb-2">Important:</p>
                      <ul class="list-disc list-inside space-y-1 text-blue-100 text-xs">
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

                  <div class="bg-zinc-900 rounded-2xl p-8 text-white shadow-lg">
                    <h2 class="text-xl font-bold mb-6">Pre-Arrival Checklist</h2>
                    <ul class="space-y-4">
                      <li class="flex items-center gap-3">
                        <input
                          type="checkbox"
                          class="w-5 h-5 rounded border-zinc-700 bg-zinc-800 text-blue-500 focus:ring-0"
                        />
                        <div>
                          <span class="font-semibold">Screenshot Door Code</span>
                          <p class="text-xs text-zinc-400 mt-1">
                            Cell service is spotty at the cabin
                          </p>
                        </div>
                      </li>
                      <li class="flex items-center gap-3">
                        <input
                          type="checkbox"
                          class="w-5 h-5 rounded border-zinc-700 bg-zinc-800 text-blue-500 focus:ring-0"
                        />
                        <div>
                          <span class="font-semibold">Download Offline Maps</span>
                          <p class="text-xs text-zinc-400 mt-1">
                            Google Maps/Apple Maps for Homewood, CA
                          </p>
                        </div>
                      </li>
                      <li class="flex items-center gap-3">
                        <input
                          type="checkbox"
                          class="w-5 h-5 rounded border-zinc-700 bg-zinc-800 text-blue-500 focus:ring-0"
                        />
                        <div>
                          <span class="font-semibold">Winter Driving Ready</span>
                          <p class="text-xs text-zinc-400 mt-1">
                            Chains in trunk or snow tires confirmed
                          </p>
                        </div>
                      </li>
                      <li class="flex items-center gap-3">
                        <input
                          type="checkbox"
                          class="w-5 h-5 rounded border-zinc-700 bg-zinc-800 text-blue-500 focus:ring-0"
                        />
                        <div>
                          <span class="font-semibold">Pack bedding and towels</span>
                          <p class="text-xs text-zinc-400 mt-1">
                            Sheets, Pillowcases, Comforters or Sleeping Bags & Towels Required
                          </p>
                        </div>
                      </li>
                    </ul>
                  </div>
                </section>
                <!-- Winter Driving & Weather Tips -->
                <section class="bg-blue-50 border border-blue-200 rounded-2xl p-6">
                  <h2 class="text-xl font-bold text-blue-900 mb-4 flex items-center gap-2">
                    <span>❄️</span>
                    <span>Winter Driving & Weather Tips</span>
                  </h2>
                  <div>
                    <ul class="list-disc list-inside space-y-2 mb-4 text-blue-900">
                      <li>
                        Always carry <strong>snow chains</strong>
                        or use a <strong>4WD vehicle with snow tires</strong>.
                      </li>
                      <li>
                        Check <strong>road and weather conditions</strong>
                        before traveling.
                      </li>
                    </ul>
                    <div>
                      <p class="font-semibold mb-2 text-blue-900">
                        Helpful Resources:
                      </p>
                      <ul class="list-disc list-inside space-y-1 text-blue-800">
                        <li>
                          <a
                            href="https://dot.ca.gov/travel/winter-driving-tips"
                            target="_blank"
                            class="text-blue-700 hover:text-blue-900 underline"
                          >
                            California Winter Driving Tips
                          </a>
                        </li>
                        <li>
                          Caltrans Road Info:
                          <a
                            href="tel:8004277623"
                            class="text-blue-700 hover:text-blue-900 underline"
                          >
                            (800) 427-7623
                          </a>
                        </li>
                        <li>
                          Twitter:
                          <a
                            href="https://twitter.com/CHP_Truckee"
                            target="_blank"
                            class="text-blue-700 hover:text-blue-900 underline"
                          >
                            @CHP_Truckee
                          </a>
                          ,
                          <a
                            href="https://twitter.com/CaltransDist3"
                            target="_blank"
                            class="text-blue-700 hover:text-blue-900 underline"
                          >
                            @CaltransDist3
                          </a>
                          ,
                          <a
                            href="https://twitter.com/NWSReno"
                            target="_blank"
                            class="text-blue-700 hover:text-blue-900 underline"
                          >
                            @NWSReno
                          </a>
                        </li>
                      </ul>
                    </div>
                  </div>
                </section>
                <!-- Parking & Transportation -->
                <section
                  id="parking-transportation"
                  class="bg-white border border-zinc-200 rounded-2xl p-6 shadow-sm"
                >
                  <h2 class="text-xl font-bold text-zinc-900 mb-4 flex items-center gap-2">
                    <span>🚙</span>
                    <span>Parking & Transportation</span>
                  </h2>
                  <div class="grid md:grid-cols-2 gap-6">
                    <div>
                      <p class="font-semibold mb-2 text-zinc-900">
                        Local Services:
                      </p>
                      <ul class="list-disc list-inside space-y-1 text-zinc-700">
                        <li>
                          <strong>Tahoe Bus Transit:</strong>
                          <a
                            href="tel:5305816365"
                            class="text-blue-600 hover:text-blue-800 underline"
                          >
                            (530) 581-6365
                          </a>
                        </li>
                        <li>
                          <strong>Tahoe Taxi:</strong>
                          <a
                            href="tel:5305463181"
                            class="text-blue-600 hover:text-blue-800 underline"
                          >
                            (530) 546-3181
                          </a>
                        </li>
                      </ul>
                    </div>
                    <div>
                      <p class="font-semibold mb-2 text-zinc-900">Parking Rules:</p>
                      <ul class="list-disc list-inside space-y-1 text-zinc-700">
                        <li>
                          Limited parking — <strong>carpool if possible.</strong>
                        </li>
                        <li>
                          You may need to move vehicles to accommodate others.
                        </li>
                        <li>
                          <strong>No street parking Nov 1 – May 1</strong>
                          (towing enforced for snow removal).
                        </li>
                        <li>Do not block driveways or neighbors' access.</li>
                      </ul>
                    </div>
                  </div>
                </section>
              </div>
              <!-- Cabin and Booking Rules Tab -->
              <div
                :if={Map.get(assigns, :info_tab, :general) == :rules}
                id="cabin-rules"
              >
                <!-- Golden Rules Banner -->
                <section class="bg-zinc-100 rounded-2xl p-6 mb-12 shadow-lg">
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
                <!-- Winter Season Reservations Notice -->
                <section class="bg-blue-50 border border-blue-200 rounded-2xl p-6 mb-12">
                  <div class="flex items-start gap-3">
                    <.icon
                      name="hero-megaphone"
                      class="w-6 h-6 text-blue-700 flex-shrink-0 mt-0.5"
                    />
                    <div class="flex-1">
                      <h2 class="text-xl font-bold text-blue-900 mb-2">
                        Winter Season 2025/2026 Reservations
                      </h2>
                      <p class="text-blue-800 font-semibold mb-3">
                        Reservations for winter season 2025/2026 are now open!
                      </p>
                      <div class="bg-white rounded-xl p-4 border border-blue-200">
                        <div class="flex items-start gap-2">
                          <.icon
                            name="hero-exclamation-triangle"
                            class="w-5 h-5 text-blue-700 flex-shrink-0 mt-0.5"
                          />
                          <p class="text-sm text-blue-900">
                            <strong>Important:</strong>
                            Full cabin buyouts are <strong>NOT available</strong>
                            during the winter season.
                          </p>
                        </div>
                      </div>
                    </div>
                  </div>
                </section>
                <!-- Booking Policies -->
                <section class="bg-white border border-zinc-200 rounded-2xl p-6 shadow-sm mb-12">
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
                          You are only allowed to have
                          <strong>one active reservation per membership</strong>
                        </li>
                        <li>
                          When your current stay is completed, another reservation can be made
                        </li>
                      </ul>
                    </div>
                    <div class="p-5 bg-zinc-50 rounded-xl border border-zinc-200">
                      <h3 class="font-semibold text-zinc-900 mb-2">
                        Winter Season Room Limits (December through April)
                      </h3>
                      <ul class="list-disc list-inside space-y-2 text-zinc-700">
                        <li>
                          <strong>Single membership holders:</strong>
                          Can only reserve <strong>1 room</strong>
                          during winter season
                        </li>
                        <li>
                          <strong>Family membership holders:</strong>
                          Allowed to reserve <strong>2 rooms</strong>
                          for the same stay during winter season
                          <span class="text-sm text-zinc-600">
                            (both rooms must be reserved for the same dates)
                          </span>
                        </li>
                      </ul>
                    </div>
                    <div class="p-5 bg-zinc-50 rounded-xl border border-zinc-200">
                      <h3 class="font-semibold text-zinc-900 mb-2">
                        Guest Count & Payment
                      </h3>
                      <p class="text-zinc-700 mb-2">
                        Please make sure you specify the <strong>correct number of people</strong>, including guests, that will be staying in the room(s) with you.
                      </p>
                      <p class="text-zinc-700">
                        <strong>
                          Payment is determined by number of guests, not a fixed rate per room.
                        </strong>
                      </p>
                    </div>
                    <div class="p-5 bg-amber-50 rounded-xl border border-amber-200">
                      <h3 class="font-semibold text-amber-900 mb-2">
                        Cancellation Refunds
                      </h3>
                      <p class="text-sm text-amber-800">
                        Cash refunds due to cancellations are subject to a
                        <strong>3% processing fee</strong>
                        to cover the club's credit card handling costs.
                      </p>
                    </div>
                    <div class="p-5 bg-red-50 rounded-xl border border-red-200">
                      <div class="flex items-start gap-2">
                        <.icon
                          name="hero-shield-exclamation"
                          class="w-5 h-5 text-red-700 flex-shrink-0 mt-0.5"
                        />
                        <p class="text-sm text-red-800">
                          <strong>Board Authority:</strong>
                          The board reserves the right to cancel reservations that are in violation of these rules.
                        </p>
                      </div>
                    </div>
                  </div>
                </section>
                <!-- Booking Rules -->
                <section
                  id="booking-rules"
                  class="bg-white border border-zinc-200 rounded-2xl p-6 shadow-sm mb-12"
                >
                  <h2 class="text-xl font-bold text-zinc-900 mb-4 flex items-center gap-2">
                    <span>📋</span>
                    <span>Booking Rules</span>
                  </h2>
                  <div class="bg-zinc-50 rounded-xl border border-zinc-200 overflow-hidden">
                    <div class="overflow-x-auto">
                      <table class="w-full border-collapse">
                        <thead>
                          <tr class="bg-zinc-100 border-b border-zinc-200">
                            <th class="text-left py-3 px-4 font-semibold text-zinc-900">
                              Rule
                            </th>
                            <th class="text-left py-3 px-4 font-semibold text-zinc-900">
                              Details
                            </th>
                          </tr>
                        </thead>
                        <tbody class="text-zinc-700">
                          <tr class="border-b border-zinc-100 hover:bg-white">
                            <td class="py-3 px-4 font-semibold">Check-In / Out</td>
                            <td class="py-3 px-4">3:00 PM / 11:00 AM</td>
                          </tr>
                          <tr class="border-b border-zinc-100 hover:bg-white">
                            <td class="py-3 px-4 font-semibold">Maximum Stay</td>
                            <td class="py-3 px-4">4 nights per booking</td>
                          </tr>
                          <tr class="border-b border-zinc-100 hover:bg-white">
                            <td class="py-3 px-4 font-semibold">Weekend Policy</td>
                            <td class="py-3 px-4">
                              Saturday bookings must include Sunday
                            </td>
                          </tr>
                          <tr class="border-b border-zinc-100 hover:bg-white">
                            <td class="py-3 px-4 font-semibold">Active Bookings</td>
                            <td class="py-3 px-4">One active booking per member</td>
                          </tr>
                          <tr class="border-b border-zinc-100 hover:bg-white">
                            <td class="py-3 px-4 font-semibold">Winter</td>
                            <td class="py-3 px-4">Individual rooms only</td>
                          </tr>
                          <tr class="border-b border-zinc-100 hover:bg-white">
                            <td class="py-3 px-4 font-semibold">Summer</td>
                            <td class="py-3 px-4">Rooms or full cabin allowed</td>
                          </tr>
                          <tr class="border-b border-zinc-100 hover:bg-white">
                            <td class="py-3 px-4 font-semibold">
                              Membership Limits
                            </td>
                            <td class="py-3 px-4">
                              Family/Lifetime: 2 rooms<br />Single: 1 room
                            </td>
                          </tr>
                          <tr class="hover:bg-white">
                            <td class="py-3 px-4 font-semibold">
                              Children Pricing
                            </td>
                            <td class="py-3 px-4">
                              <% season_id =
                                if @checkin_date do
                                  season =
                                    Season.find_season_for_date(
                                      @seasons,
                                      @checkin_date
                                    )

                                  if season, do: season.id, else: nil
                                else
                                  nil
                                end %>
                              <% default_children_price =
                                get_default_children_price(@property, season_id) %> 5–17 years: <%= MoneyHelper.format_money!(
                                default_children_price
                              ) %>/night<br />Under 5: Free
                            </td>
                          </tr>
                        </tbody>
                      </table>
                    </div>
                  </div>
                </section>
                <!-- Bear Safety Instructions -->
                <section
                  id="bear-safety"
                  class="bg-red-50 border border-red-200 rounded-2xl p-6 mb-12"
                >
                  <h2 class="text-xl font-bold text-red-900 mb-4 flex items-center gap-2">
                    <span>🐻</span>
                    <span>Bear Safety Instructions</span>
                  </h2>
                  <div class="space-y-6">
                    <div class="p-5 bg-white rounded-xl border border-red-200">
                      <p class="text-base text-red-900 leading-relaxed">
                        The cabin's deck is surrounded by
                        <strong class="font-bold">electric bear wire</strong>
                        — it won't harm you but must be handled properly.
                      </p>
                    </div>
                    <!-- Bear Wire Visual Guide: Side-by-Side Day vs Night -->
                    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
                      <!-- To Enter (Day) -->
                      <div class="bg-green-50 border border-green-200 rounded-lg p-6">
                        <div class="flex items-center gap-3 mb-5">
                          <.icon name="hero-sun" class="w-6 h-6 text-green-700" />
                          <h3 class="text-lg font-bold text-green-900">To Enter</h3>
                        </div>
                        <div class="space-y-3">
                          <div class="flex items-start gap-3 p-3 bg-white rounded-lg border border-green-200">
                            <div class="flex-shrink-0 w-7 h-7 bg-green-600 text-white rounded-full flex items-center justify-center text-xs font-bold">
                              1
                            </div>
                            <div class="flex-1 pt-0.5">
                              <p class="text-sm font-semibold text-green-900">
                                Grab top black handle
                              </p>
                              <p class="text-xs text-green-800">
                                Disconnect to disable circuit
                              </p>
                            </div>
                          </div>
                          <div class="flex items-start gap-3 p-3 bg-white rounded-lg border border-green-200">
                            <div class="flex-shrink-0 w-7 h-7 bg-green-600 text-white rounded-full flex items-center justify-center text-xs font-bold">
                              2
                            </div>
                            <div class="flex-1 pt-0.5">
                              <p class="text-sm font-semibold text-green-900">
                                Remove second wire
                              </p>
                            </div>
                          </div>
                          <div class="flex items-start gap-3 p-3 bg-white rounded-lg border border-green-200">
                            <div class="flex-shrink-0 w-7 h-7 bg-green-600 text-white rounded-full flex items-center justify-center text-xs font-bold">
                              3
                            </div>
                            <div class="flex-1 pt-0.5">
                              <p class="text-sm font-semibold text-green-900">
                                Remove third wire
                              </p>
                              <p class="text-xs text-green-800">Enter safely</p>
                            </div>
                          </div>
                        </div>
                      </div>
                      <!-- When Leaving (Night) -->
                      <div class="bg-amber-50 border border-amber-200 rounded-lg p-6">
                        <div class="flex items-center gap-3 mb-5">
                          <.icon name="hero-moon" class="w-6 h-6 text-amber-700" />
                          <h3 class="text-lg font-bold text-amber-900">
                            When Leaving or Going to Sleep
                          </h3>
                        </div>
                        <div class="space-y-3">
                          <div class="flex items-start gap-3 p-3 bg-white rounded-lg border border-amber-200">
                            <div class="flex-shrink-0 w-7 h-7 bg-amber-600 text-white rounded-full flex items-center justify-center text-xs font-bold">
                              1
                            </div>
                            <div class="flex-1 pt-0.5">
                              <p class="text-sm font-semibold text-amber-900">
                                Connect lowest wire first
                              </p>
                            </div>
                          </div>
                          <div class="flex items-start gap-3 p-3 bg-white rounded-lg border border-amber-200">
                            <div class="flex-shrink-0 w-7 h-7 bg-amber-600 text-white rounded-full flex items-center justify-center text-xs font-bold">
                              2
                            </div>
                            <div class="flex-1 pt-0.5">
                              <p class="text-sm font-semibold text-amber-900">
                                Connect middle wire
                              </p>
                            </div>
                          </div>
                          <div class="flex items-start gap-3 p-3 bg-white rounded-lg border border-amber-200">
                            <div class="flex-shrink-0 w-7 h-7 bg-amber-600 text-white rounded-full flex items-center justify-center text-xs font-bold">
                              3
                            </div>
                            <div class="flex-1 pt-0.5">
                              <p class="text-sm font-semibold text-amber-900">
                                Connect top wire last
                              </p>
                              <p class="text-xs text-amber-800">
                                Reactivates barrier
                              </p>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                    <!-- Important Safety Note -->
                    <div class="p-4 bg-red-100 border border-red-200 rounded-lg">
                      <div class="flex items-start gap-3">
                        <.icon
                          name="hero-exclamation-triangle"
                          class="w-5 h-5 text-red-700 flex-shrink-0 mt-0.5"
                        />
                        <div>
                          <p class="text-sm font-bold text-red-900 mb-1">
                            Important Safety Note
                          </p>
                          <p class="text-sm text-red-800 leading-relaxed">
                            Always secure garbage cans and remove all food waste from outdoor areas.
                          </p>
                        </div>
                      </div>
                    </div>
                  </div>
                </section>
                <!-- Cancellation Policy -->
                <section
                  id="cancellation-policy"
                  class="bg-white border border-zinc-200 rounded-2xl p-6 shadow-sm mb-12"
                >
                  <h2 class="text-xl font-bold text-zinc-900 mb-4 flex items-center gap-2">
                    <span>🧾</span>
                    <span>Cancellation Policy</span>
                  </h2>
                  <div>
                    <!-- Comparison Table -->
                    <div class="bg-zinc-50 rounded-xl border border-zinc-200 overflow-hidden mb-4">
                      <div class="overflow-x-auto">
                        <table class="w-full border-collapse">
                          <thead>
                            <tr class="bg-zinc-100 text-zinc-900">
                              <th class="px-4 py-3 text-left font-bold">
                                Days Before Check-In
                              </th>
                              <th class="px-4 py-3 text-center font-bold border-l border-zinc-200">
                                <%= if @buyout_refund_policy &&
                                         @buyout_refund_policy.name,
                                       do: @buyout_refund_policy.name,
                                       else: "Full Cabin" %>
                              </th>
                              <th class="px-4 py-3 text-center font-bold border-l border-zinc-200">
                                <%= if @room_refund_policy &&
                                         @room_refund_policy.name,
                                       do: @room_refund_policy.name,
                                       else: "Room Booking" %>
                              </th>
                            </tr>
                          </thead>
                          <tbody>
                            <%= if @buyout_refund_policy || @room_refund_policy do %>
                              <% # Get all unique days_before_checkin values from both policies
                              buyout_days =
                                if @buyout_refund_policy &&
                                     @buyout_refund_policy.rules,
                                   do:
                                     Enum.map(
                                       @buyout_refund_policy.rules,
                                       & &1.days_before_checkin
                                     ),
                                   else: []

                              room_days =
                                if @room_refund_policy && @room_refund_policy.rules,
                                  do:
                                    Enum.map(
                                      @room_refund_policy.rules,
                                      & &1.days_before_checkin
                                    ),
                                  else: []

                              all_days =
                                Enum.uniq(buyout_days ++ room_days)
                                |> Enum.sort(:desc) %>
                              <%= for days <- all_days do %>
                                <% buyout_rule =
                                  if @buyout_refund_policy &&
                                       @buyout_refund_policy.rules,
                                     do:
                                       Enum.find(
                                         @buyout_refund_policy.rules,
                                         &(&1.days_before_checkin == days)
                                       ),
                                     else: nil

                                room_rule =
                                  if @room_refund_policy &&
                                       @room_refund_policy.rules,
                                     do:
                                       Enum.find(
                                         @room_refund_policy.rules,
                                         &(&1.days_before_checkin == days)
                                       ),
                                     else: nil %>
                                <tr class="border-b border-zinc-100 hover:bg-white">
                                  <td class="px-4 py-3 font-semibold text-zinc-900">
                                    <%= days %>+ days
                                  </td>
                                  <td class={[
                                    "px-4 py-3 text-center border-l border-zinc-100",
                                    if(buyout_rule && buyout_rule.refund_percentage,
                                      do:
                                        if(
                                          Decimal.to_float(
                                            buyout_rule.refund_percentage
                                          ) >= 100,
                                          do: "text-green-700 font-bold",
                                          else:
                                            if(
                                              Decimal.to_float(
                                                buyout_rule.refund_percentage
                                              ) >= 50,
                                              do: "text-amber-700 font-semibold",
                                              else: "text-red-700 font-semibold"
                                            )
                                        ),
                                      else: "text-zinc-400"
                                    )
                                  ]}>
                                    <%= if buyout_rule && buyout_rule.refund_percentage do %>
                                      <%= trunc(
                                        Decimal.to_float(
                                          buyout_rule.refund_percentage
                                        )
                                      ) %>%
                                    <% else %>
                                      —
                                    <% end %>
                                  </td>
                                  <td class={[
                                    "px-4 py-3 text-center border-l border-zinc-100",
                                    if(room_rule && room_rule.refund_percentage,
                                      do:
                                        if(
                                          Decimal.to_float(
                                            room_rule.refund_percentage
                                          ) >= 100,
                                          do: "text-green-700 font-bold",
                                          else:
                                            if(
                                              Decimal.to_float(
                                                room_rule.refund_percentage
                                              ) >= 50,
                                              do: "text-amber-700 font-semibold",
                                              else: "text-red-700 font-semibold"
                                            )
                                        ),
                                      else: "text-zinc-400"
                                    )
                                  ]}>
                                    <%= if room_rule && room_rule.refund_percentage do %>
                                      <%= trunc(
                                        Decimal.to_float(
                                          room_rule.refund_percentage
                                        )
                                      ) %>%
                                    <% else %>
                                      —
                                    <% end %>
                                  </td>
                                </tr>
                              <% end %>
                            <% else %>
                              <tr>
                                <td
                                  colspan="3"
                                  class="px-4 py-3 text-center text-zinc-600"
                                >
                                  Policy information will be displayed here
                                </td>
                              </tr>
                            <% end %>
                          </tbody>
                        </table>
                      </div>
                    </div>
                    <!-- Plain English Description -->
                    <div class="bg-blue-50 border border-blue-200 rounded-xl p-5 mb-4">
                      <h3 class="font-semibold text-blue-900 mb-3">
                        Cancellation Policy Summary
                      </h3>
                      <div class="space-y-4 text-sm text-blue-900">
                        <%= if @buyout_refund_policy && @buyout_refund_policy.rules do %>
                          <div>
                            <p class="font-semibold mb-2">
                              <%= if @buyout_refund_policy.name,
                                do: @buyout_refund_policy.name,
                                else: "Full Cabin Buyout" %>:
                            </p>
                            <ul class="list-disc list-inside space-y-1 ml-2">
                              <%= for rule <- Enum.sort_by(@buyout_refund_policy.rules, & &1.days_before_checkin, :desc) do %>
                                <% refund_pct =
                                  trunc(Decimal.to_float(rule.refund_percentage)) %>
                                <li>
                                  If you cancel <%= rule.days_before_checkin %> or more days before check-in, you'll receive a <%= refund_pct %>% refund.
                                </li>
                              <% end %>
                            </ul>
                          </div>
                        <% end %>
                        <%= if @room_refund_policy && @room_refund_policy.rules do %>
                          <div>
                            <p class="font-semibold mb-2">
                              <%= if @room_refund_policy.name,
                                do: @room_refund_policy.name,
                                else: "Room Booking" %>:
                            </p>
                            <ul class="list-disc list-inside space-y-1 ml-2">
                              <%= for rule <- Enum.sort_by(@room_refund_policy.rules, & &1.days_before_checkin, :desc) do %>
                                <% refund_pct =
                                  trunc(Decimal.to_float(rule.refund_percentage)) %>
                                <li>
                                  If you cancel <%= rule.days_before_checkin %> or more days before check-in, you'll receive a <%= refund_pct %>% refund.
                                </li>
                              <% end %>
                            </ul>
                          </div>
                        <% end %>
                        <%= if (!@buyout_refund_policy || !@buyout_refund_policy.rules) && (!@room_refund_policy || !@room_refund_policy.rules) do %>
                          <p class="text-blue-800">
                            Cancellation policy details will be displayed here once available.
                          </p>
                        <% end %>
                      </div>
                    </div>
                    <div class="bg-zinc-50 rounded-xl p-4 text-sm border border-zinc-200">
                      <p class="mb-2 font-semibold text-zinc-900">
                        Important Notes:
                      </p>
                      <ul class="list-disc list-inside space-y-1 text-zinc-700">
                        <li>
                          Members are responsible for the behavior and payments of their guests.
                        </li>
                        <li>
                          <strong>Road closure cancellations</strong>
                          may be credited for a future stay (contact the Cabin Master).
                        </li>
                        <li>
                          <strong>Cash refunds</strong>
                          incur a <strong>3% processing fee</strong>
                          to cover credit card costs.
                        </li>
                      </ul>
                    </div>
                  </div>
                </section>
                <!-- Cabin Rules & Etiquette -->
                <section class="bg-white border border-zinc-200 rounded-2xl p-6 shadow-sm mb-12">
                  <h2 class="text-xl font-bold text-zinc-900 mb-4 flex items-center gap-2">
                    <span>🧺</span>
                    <span>Cabin Rules & Etiquette</span>
                  </h2>
                  <div class="space-y-4">
                    <div class="p-5 bg-zinc-50 rounded-xl border border-zinc-200">
                      <h3 class="font-semibold text-zinc-900 mb-2">
                        General Guidelines
                      </h3>
                      <ul class="list-disc list-inside space-y-1 text-zinc-700">
                        <li>
                          Treat the cabin as your own — it's <strong>not a hotel</strong>.
                        </li>
                        <li>
                          Respect quiet hours (<strong>10:00 PM – 7:00 AM</strong>).
                        </li>
                        <li>
                          Be considerate — stairs and hallways carry sound easily.
                        </li>
                      </ul>
                    </div>
                    <div class="p-5 bg-zinc-50 rounded-xl border border-zinc-200">
                      <h3 class="font-semibold text-zinc-900 mb-2">
                        Common Areas & Storage
                      </h3>
                      <ul class="list-disc list-inside space-y-1 text-zinc-700">
                        <li>Keep personal items out of shared spaces.</li>
                        <li>
                          Store <strong>ski boots</strong>
                          in the laundry room racks.
                        </li>
                        <li>
                          Store other gear in the <strong>outside stairwell</strong>.
                        </li>
                      </ul>
                    </div>
                    <div class="p-5 bg-zinc-50 rounded-xl border border-zinc-200">
                      <h3 class="font-semibold text-zinc-900 mb-2">Pets</h3>
                      <p class="text-zinc-700">
                        No pets are allowed — <strong>no exceptions.</strong>
                      </p>
                    </div>
                    <div class="p-5 bg-zinc-50 rounded-xl border border-zinc-200">
                      <h3 class="font-semibold text-zinc-900 mb-2">
                        Smoking & Vaping
                      </h3>
                      <p class="text-zinc-700">
                        <strong>Prohibited</strong> indoors and on decks.
                      </p>
                    </div>
                    <div class="p-5 bg-zinc-50 rounded-xl border border-zinc-200">
                      <h3 class="font-semibold text-zinc-900 mb-2">Children</h3>
                      <p class="text-zinc-700">
                        For safety, children should not play on or near the stairs.
                      </p>
                    </div>
                  </div>
                </section>
                <!-- What to Bring -->
                <section class="bg-white border border-zinc-200 rounded-2xl p-6 shadow-sm mb-12">
                  <h2 class="text-xl font-bold text-zinc-900 mb-4 flex items-center gap-2">
                    <span>🎒</span>
                    <span>Packing List</span>
                  </h2>
                  <div>
                    <div class="mb-6 p-5 bg-red-50 border border-red-200 rounded-xl">
                      <div class="flex items-start gap-3">
                        <.icon
                          name="hero-exclamation-triangle"
                          class="w-6 h-6 text-red-700 flex-shrink-0 mt-0.5"
                        />
                        <div>
                          <p class="font-bold text-red-900 text-base mb-1">
                            ⚠️ Critical: Linens and towels are NOT provided
                          </p>
                          <p class="text-sm text-red-800">
                            You must bring your own bedding and towels for your stay.
                          </p>
                        </div>
                      </div>
                    </div>
                    <!-- Suitcase Graphic Style -->
                    <div class="bg-amber-50 border border-amber-200 rounded-2xl p-6">
                      <div class="flex items-center gap-3 mb-5">
                        <div class="text-4xl">🧳</div>
                        <h3 class="text-lg font-bold text-amber-900">
                          Don't Forget
                        </h3>
                      </div>
                      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <div class="bg-white rounded-xl p-4 border border-amber-200 flex items-start gap-3">
                          <div class="text-2xl flex-shrink-0">🛏️</div>
                          <div class="flex-1">
                            <div class="font-bold text-amber-900 mb-1">
                              Essential: Bedding
                            </div>
                            <div class="text-sm text-amber-800">
                              Sheets, pillowcases, or sleeping bags
                            </div>
                          </div>
                        </div>
                        <div class="bg-white rounded-xl p-4 border border-amber-200 flex items-start gap-3">
                          <div class="text-2xl flex-shrink-0">🧼</div>
                          <div class="flex-1">
                            <div class="font-bold text-amber-900 mb-1">
                              Essential: Towels
                            </div>
                            <div class="text-sm text-amber-800">
                              For showers and the sauna
                            </div>
                          </div>
                        </div>
                        <div class="bg-white rounded-xl p-4 border border-amber-200 flex items-start gap-3">
                          <div class="text-2xl flex-shrink-0">🔥</div>
                          <div class="flex-1">
                            <div class="font-bold text-amber-900 mb-1">
                              Essential: Fire Starters
                            </div>
                            <div class="text-sm text-amber-800">
                              Kindling (wood provided but may be damp)
                            </div>
                          </div>
                        </div>
                        <div class="bg-white rounded-xl p-4 border border-amber-200 flex items-start gap-3">
                          <div class="text-2xl flex-shrink-0">🍳</div>
                          <div class="flex-1">
                            <div class="font-bold text-amber-900 mb-1">
                              Food & Ingredients
                            </div>
                            <div class="text-sm text-amber-800">
                              Kitchen is fully equipped
                            </div>
                          </div>
                        </div>
                      </div>
                      <div class="mt-4 p-4 bg-blue-50 border border-blue-200 rounded-xl">
                        <div class="flex items-start gap-2">
                          <.icon
                            name="hero-sparkles"
                            class="w-5 h-5 text-blue-700 flex-shrink-0 mt-0.5"
                          />
                          <p class="text-sm text-blue-900">
                            <strong>Pro Tip:</strong>
                            Bring an extra layer—the Scandinavian design keeps it authentic, but Tahoe nights are cold!
                          </p>
                        </div>
                      </div>
                    </div>
                  </div>
                </section>
                <!-- Rates & Seasonal Rules -->
                <section class="bg-white border border-zinc-200 rounded-2xl p-6 shadow-sm mb-12">
                  <h2 class="text-xl font-bold text-zinc-900 mb-4 flex items-center gap-2">
                    <span>💰</span>
                    <span>Rates & Seasonal Rules</span>
                  </h2>
                  <div class="space-y-4">
                    <div class="p-5 bg-zinc-50 rounded-xl border border-zinc-200">
                      <p class="font-semibold mb-2 text-zinc-900">
                        Per-Person, Per-Night Rates
                      </p>
                      <ul class="list-disc list-inside space-y-1 text-zinc-700">
                        <% season_id =
                          if @checkin_date do
                            season =
                              Season.find_season_for_date(@seasons, @checkin_date)

                            if season, do: season.id, else: nil
                          else
                            nil
                          end %>
                        <% default_adult_price =
                          get_default_adult_price(@property, season_id) %>
                        <% default_children_price =
                          get_default_children_price(@property, season_id) %>
                        <li>
                          Adults:
                          <strong>
                            <%= MoneyHelper.format_money!(default_adult_price) %>
                          </strong>
                        </li>
                        <li>
                          Children (5–17):
                          <strong>
                            <%= MoneyHelper.format_money!(default_children_price) %>
                          </strong>
                        </li>
                        <li>Children under 5: <strong>Free</strong></li>
                      </ul>
                    </div>
                    <div class="p-5 bg-zinc-50 rounded-xl border border-zinc-200">
                      <p class="font-semibold mb-2 text-zinc-900">
                        Seasonal Availability
                      </p>
                      <ul class="list-disc list-inside space-y-1 text-zinc-700">
                        <li>
                          <strong>Summer (May 1 – Nov 30):</strong>
                          Full-cabin or room reservations allowed (up to 17 guests)
                        </li>
                        <li>
                          <strong>Winter (Dec – Apr):</strong>
                          Individual room bookings only
                        </li>
                      </ul>
                    </div>
                  </div>
                </section>
                <!-- Cleanliness & Chores (Accordion) -->
                <details class="bg-white border border-zinc-200 rounded-2xl shadow-sm overflow-hidden">
                  <summary class="cursor-pointer p-6 list-none flex items-center justify-between hover:bg-zinc-50 transition-colors">
                    <h2 class="text-xl font-bold text-zinc-900 flex items-center gap-2">
                      <span>🧹</span>
                      <span>Cleanliness & Chores</span>
                    </h2>
                    <.icon
                      name="hero-chevron-down"
                      class="w-6 h-6 text-zinc-500 chevron-icon flex-shrink-0"
                    />
                  </summary>
                  <div class="px-6 pb-6 pt-0">
                    <p class="mb-4 text-zinc-700">
                      Keeping the cabin affordable depends on everyone pitching in!
                    </p>
                    <div class="bg-zinc-50 rounded-xl p-5 border border-zinc-200 mb-4">
                      <p class="font-semibold mb-3 text-zinc-900">Guests must:</p>
                      <div class="space-y-2">
                        <label class="flex items-start gap-3 p-3 bg-white rounded-lg border border-zinc-200 cursor-pointer hover:bg-zinc-50 transition">
                          <input type="checkbox" class="mt-1 w-5 h-5 text-blue-600" />
                          <span class="text-sm text-zinc-700">
                            Clean up after themselves
                          </span>
                        </label>
                        <label class="flex items-start gap-3 p-3 bg-white rounded-lg border border-zinc-200 cursor-pointer hover:bg-zinc-50 transition">
                          <input type="checkbox" class="mt-1 w-5 h-5 text-blue-600" />
                          <span class="text-sm text-zinc-700">
                            Strip and clean their rooms
                          </span>
                        </label>
                        <label class="flex items-start gap-3 p-3 bg-white rounded-lg border border-zinc-200 cursor-pointer hover:bg-zinc-50 transition">
                          <input type="checkbox" class="mt-1 w-5 h-5 text-blue-600" />
                          <span class="text-sm text-zinc-700">
                            Wash, dry, and store any used club bedding
                          </span>
                        </label>
                        <label class="flex items-start gap-3 p-3 bg-white rounded-lg border border-zinc-200 cursor-pointer hover:bg-zinc-50 transition">
                          <input type="checkbox" class="mt-1 w-5 h-5 text-blue-600" />
                          <span class="text-sm text-zinc-700">
                            Leave the kitchen spotless and remove all food
                          </span>
                        </label>
                        <label class="flex items-start gap-3 p-3 bg-white rounded-lg border border-zinc-200 cursor-pointer hover:bg-zinc-50 transition">
                          <input type="checkbox" class="mt-1 w-5 h-5 text-blue-600" />
                          <span class="text-sm text-zinc-700">
                            Secure bear-proof garbage lids
                          </span>
                        </label>
                      </div>
                    </div>
                    <div class="bg-gradient-to-r from-green-50 to-emerald-50 border border-green-200 rounded-xl p-4">
                      <p class="text-sm text-green-900 font-semibold">
                        <strong>
                          Your cooperation helps keep cabin rates low for all members.
                        </strong>
                      </p>
                    </div>
                  </div>
                </details>
              </div>
            </div>
          </div>
          <!-- Mobile Sticky Footer (only visible on mobile) -->
          <div class="lg:hidden fixed bottom-0 left-0 right-0 bg-white border-t-2 border-zinc-200 shadow-2xl z-50 p-4">
            <div class="max-w-screen-xl mx-auto flex items-center justify-between gap-4">
              <div class="flex-1">
                <div :if={@calculated_price} class="text-right">
                  <p class="text-xs text-zinc-500 uppercase">Total</p>
                  <p class="text-xl font-black text-blue-600">
                    <%= MoneyHelper.format_money!(@calculated_price) %>
                  </p>
                </div>
                <div :if={!@calculated_price} class="text-sm text-zinc-500">
                  Select dates and rooms
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
                    get_selected_rooms_for_submit(assigns),
                    @capacity_error,
                    @price_error,
                    @form_errors,
                    @date_validation_errors
                  )
                }
                class={
                  if can_submit_booking?(
                       @selected_booking_mode,
                       @checkin_date,
                       @checkout_date,
                       get_selected_rooms_for_submit(assigns),
                       @capacity_error,
                       @price_error,
                       @form_errors,
                       @date_validation_errors
                     ) do
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
        </div>
      </section>
      <!-- Main Content for Non-Logged-In Users -->
      <section :if={!@user} class="max-w-screen-xl mx-auto px-4 py-20">
        <div class="space-y-12">
          <!-- Welcome Header -->
          <div class="text-center max-w-3xl mx-auto">
            <h1 class="text-4xl md:text-5xl font-bold text-zinc-900 mb-4">
              Experience Tahoe
            </h1>
            <p class="text-lg text-zinc-600 leading-relaxed">
              Welcome to the <strong class="text-zinc-900">YSC Tahoe Cabin</strong>
              — your year-round retreat in the heart of Lake Tahoe. Since <strong class="text-zinc-900">1993</strong>, the YSC has proudly owned this beautiful cabin, located just minutes from Tahoe City on the
              <strong class="text-zinc-900">west shore</strong>
              of <strong class="text-zinc-900">Lake Tahoe</strong>.
            </p>
          </div>
          <!-- Experience Tahoe Feature Grid -->
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-5xl mx-auto">
            <!-- Traditional Sauna -->
            <div class="bg-gradient-to-br from-amber-50 to-orange-50 border-2 border-amber-200 rounded-2xl p-6 shadow-lg hover:shadow-xl transition-shadow">
              <div class="flex items-start gap-4">
                <div class="text-4xl flex-shrink-0">🔥</div>
                <div class="flex-1">
                  <h3 class="text-xl font-black text-zinc-900 mb-2">
                    Traditional Sauna and Wood-Fired Fireplace
                  </h3>
                  <p class="text-zinc-700 leading-relaxed">
                    Experience the authentic Scandinavian sauna and our wood-fired fireplace. This traditional feature brings the Nordic wellness culture to the mountains, perfect for unwinding after a day on the slopes or trails.
                  </p>
                </div>
              </div>
            </div>
            <!-- Ski Proximity -->
            <div class="bg-gradient-to-br from-blue-50 to-cyan-50 border-2 border-blue-200 rounded-2xl p-6 shadow-lg hover:shadow-xl transition-shadow">
              <div class="flex items-start gap-4">
                <div class="text-4xl flex-shrink-0">🎿</div>
                <div class="flex-1">
                  <h3 class="text-xl font-black text-zinc-900 mb-2">
                    Ski Proximity
                  </h3>
                  <p class="text-zinc-700 leading-relaxed">
                    <strong class="text-blue-700">20 minutes</strong>
                    to Palisades Tahoe (site of the 1960 Winter Olympics) and Alpine Meadows. And about
                    <strong class="text-blue-700">30 minutes</strong>
                    to Northstar Ski Resort. World-class skiing is right at your doorstep.
                  </p>
                </div>
              </div>
            </div>
            <!-- West Shore Magic -->
            <div class="bg-gradient-to-br from-green-50 to-emerald-50 border-2 border-green-200 rounded-2xl p-6 shadow-lg hover:shadow-xl transition-shadow">
              <div class="flex items-start gap-4">
                <div class="text-4xl flex-shrink-0">🌲</div>
                <div class="flex-1">
                  <h3 class="text-xl font-black text-zinc-900 mb-2">
                    West Shore Magic
                  </h3>
                  <p class="text-zinc-700 leading-relaxed">
                    Escape the tourist traps. Our cabin offers quiet, forested living on Tahoe's pristine west shore. Experience the authentic mountain lifestyle away from the crowds.
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
                    <% season_id =
                      if @checkin_date do
                        season =
                          Season.find_season_for_date(@seasons, @checkin_date)

                        if season, do: season.id, else: nil
                      else
                        nil
                      end %>
                    <% default_adult_price =
                      get_default_adult_price(@property, season_id) %> Low rates (<strong class="text-purple-700"><%= MoneyHelper.format_money!(default_adult_price) %>/adult</strong>) are possible because members steward the cabin together. This is <strong class="text-purple-700">your cabin — not a hotel</strong>. Members share responsibility for cleaning and maintenance, keeping costs affordable for everyone.
                  </p>
                </div>
              </div>
            </div>
          </div>
          <!-- CTA Card for Non-Logged-In Users -->
          <div class="mt-12 max-w-2xl mx-auto">
            <div class="p-8 rounded-2xl bg-gradient-to-r from-blue-600 to-blue-700 text-white shadow-2xl">
              <div class="flex flex-col md:flex-row items-center justify-between gap-6">
                <div class="flex-1 text-center md:text-left">
                  <h4 class="text-2xl font-black mb-2">
                    Ready to Experience Tahoe?
                  </h4>
                  <p class="text-blue-100">
                    <%= raw(@booking_disabled_reason) %>
                  </p>
                </div>
                <.link
                  navigate={
                    ~p"/users/log-in?#{%{redirect_to: ~p"/bookings/tahoe"}}"
                  }
                  class="px-8 py-3 bg-white text-blue-600 font-bold rounded-lg hover:bg-blue-50 transition shadow-lg whitespace-nowrap"
                >
                  Sign In to Book
                </.link>
              </div>
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

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        selected_room_id: nil,
        selected_room_ids: [],
        available_rooms: [],
        calculated_price: nil,
        price_error: nil,
        form_errors: %{}
      )
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event(
        "date-changed",
        %{"checkin_date" => checkin_date_str},
        socket
      ) do
    checkin_date = parse_date(checkin_date_str)

    # Smart Weekend Rule: Auto-select Sunday if Saturday is selected
    checkout_date =
      if checkin_date && Date.day_of_week(checkin_date) == 6 do
        # Saturday selected - auto-select Sunday
        Date.add(checkin_date, 1)
      else
        socket.assigns.checkout_date
      end

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        selected_room_id: nil,
        selected_room_ids: [],
        available_rooms: [],
        calculated_price: nil,
        price_error: nil,
        form_errors: %{}
      )
      |> update_available_rooms()
      |> calculate_price_if_ready()

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

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        selected_room_id: nil,
        selected_room_ids: [],
        available_rooms: [],
        calculated_price: nil,
        price_error: nil,
        form_errors: %{}
      )
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("booking-mode-changed", %{"booking_mode" => "room"}, socket) do
    socket =
      socket
      |> assign(
        selected_booking_mode: :room,
        guests_count: 1,
        children_count: 0,
        calculated_price: nil,
        price_error: nil
      )
      |> update_available_rooms()
      # Validate availability immediately
      |> validate_dates()
      |> calculate_price_if_ready()
      |> then(fn s ->
        update_url_with_search_params(
          s,
          s.assigns.checkin_date,
          s.assigns.checkout_date,
          s.assigns.guests_count,
          s.assigns.children_count,
          :room
        )
      end)

    {:noreply, socket}
  end

  def handle_event(
        "booking-mode-changed",
        %{"booking_mode" => "buyout"},
        socket
      ) do
    # Allow buyout selection - calendar will show availability
    # For buyout, set guests_count to full house capacity (17) - not required from user
    socket =
      socket
      |> assign(
        selected_booking_mode: :buyout,
        selected_room_id: nil,
        selected_room_ids: [],
        available_rooms: [],
        calculated_price: nil,
        price_error: nil,
        checkin_date: nil,
        checkout_date: nil,
        guests_count: 17,
        children_count: 0
      )
      |> then(fn s ->
        date_form =
          to_form(
            %{
              "checkin_date" => nil,
              "checkout_date" => nil
            },
            as: "booking_dates"
          )

        assign(s, date_form: date_form)
      end)
      |> then(fn s ->
        update_url_with_search_params(
          s,
          nil,
          nil,
          s.assigns.guests_count,
          s.assigns.children_count,
          :buyout
        )
      end)

    {:noreply, socket}
  end

  def handle_event("room-changed", params, socket) do
    room_id = extract_room_id_from_params(params)

    if should_allow_room_selection?(socket, room_id) do
      handle_room_selection(socket, room_id)
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove-room", %{"room-id" => room_id}, socket) do
    # Remove room from selected list
    current_ids = socket.assigns.selected_room_ids || []
    selected_room_ids = List.delete(current_ids, room_id)

    socket =
      socket
      |> assign(
        selected_room_ids: selected_room_ids,
        selected_room_id:
          if(length(selected_room_ids) == 1,
            do: List.first(selected_room_ids),
            else: nil
          ),
        calculated_price: nil,
        price_error: nil
      )
      |> validate_guest_capacity()
      |> update_available_rooms()
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
      |> update_url_with_search_params(
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        socket.assigns.guests_count,
        socket.assigns.children_count,
        socket.assigns.selected_booking_mode
      )

    {:noreply, socket}
  end

  def handle_event("ignore", _params, socket) do
    # Handler to prevent click-away from closing dropdown when clicking inside
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
        selected_room_id: nil,
        selected_room_ids: [],
        available_rooms: [],
        calculated_price: nil,
        price_error: nil,
        availability_error: nil,
        date_validation_errors: %{},
        date_form: date_form
      )
      |> update_url_with_dates(nil, nil)

    {:noreply, socket}
  end

  def handle_event("increase-guests", _params, socket) do
    new_count = (socket.assigns.guests_count || 1) + 1

    socket =
      socket
      |> assign(
        guests_count: new_count,
        calculated_price: nil,
        price_error: nil,
        guests_dropdown_open: socket.assigns.guests_dropdown_open
      )
      |> validate_guest_capacity()
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("decrease-guests", _params, socket) do
    current_count = socket.assigns.guests_count || 1
    new_count = max(1, current_count - 1)

    socket =
      socket
      |> assign(
        guests_count: new_count,
        calculated_price: nil,
        price_error: nil,
        guests_dropdown_open: socket.assigns.guests_dropdown_open
      )
      |> validate_guest_capacity()
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("increase-children", _params, socket) do
    new_count = (socket.assigns.children_count || 0) + 1

    socket =
      socket
      |> assign(
        children_count: new_count,
        calculated_price: nil,
        price_error: nil,
        guests_dropdown_open: socket.assigns.guests_dropdown_open
      )
      |> validate_guest_capacity()
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("decrease-children", _params, socket) do
    current_count = socket.assigns.children_count || 0
    new_count = max(0, current_count - 1)

    socket =
      socket
      |> assign(
        children_count: new_count,
        calculated_price: nil,
        price_error: nil,
        guests_dropdown_open: socket.assigns.guests_dropdown_open
      )
      |> validate_guest_capacity()
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("guests-changed", %{"guests_count" => guests_str}, socket) do
    guests_count = parse_integer(guests_str) || 1

    socket =
      socket
      |> assign(
        guests_count: guests_count,
        calculated_price: nil,
        price_error: nil
      )
      |> validate_guest_capacity()
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event(
        "children-changed",
        %{"children_count" => children_str},
        socket
      ) do
    children_count = parse_integer(children_str) || 0

    socket =
      socket
      |> assign(
        children_count: children_count,
        calculated_price: nil,
        price_error: nil
      )
      |> validate_guest_capacity()
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  # Fallback handlers for cursor-move and cursor-leave events
  # These events are handled by the DateRangePicker component, but we add
  # these handlers as a safety measure in case events reach the parent LiveView
  def handle_event("cursor-move", _date_str, socket) do
    # These events should be handled by the DateRangePicker component
    # Ignore them here to prevent crashes
    {:noreply, socket}
  end

  def handle_event("cursor-leave", _params, socket) do
    # These events should be handled by the DateRangePicker component
    # Ignore them here to prevent crashes
    {:noreply, socket}
  end

  def handle_event("show-confirm-modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_confirm_modal: true,
       linens_confirmed: false,
       chores_confirmed: false,
       party_size_confirmed: false
     )}
  end

  def handle_event("close-confirm-modal", _params, socket) do
    {:noreply, assign(socket, show_confirm_modal: false)}
  end

  def handle_event("toggle-linens-confirmation", _params, socket) do
    {:noreply,
     assign(socket,
       linens_confirmed: !Map.get(socket.assigns, :linens_confirmed, false)
     )}
  end

  def handle_event("toggle-chores-confirmation", _params, socket) do
    {:noreply,
     assign(socket,
       chores_confirmed: !Map.get(socket.assigns, :chores_confirmed, false)
     )}
  end

  def handle_event("toggle-party-size-confirmation", _params, socket) do
    {:noreply,
     assign(socket,
       party_size_confirmed:
         !Map.get(socket.assigns, :party_size_confirmed, false)
     )}
  end

  def handle_event("create-booking", _params, socket) do
    # Check if confirmation modal checkboxes are checked
    if Map.get(socket.assigns, :linens_confirmed, false) &&
         Map.get(socket.assigns, :chores_confirmed, false) &&
         Map.get(socket.assigns, :party_size_confirmed, false) do
      case validate_and_create_booking(socket) do
        {:ok, booking} ->
          # Redirect to checkout page for payment
          {:noreply,
           socket
           |> assign(
             show_confirm_modal: false,
             linens_confirmed: false,
             chores_confirmed: false,
             party_size_confirmed: false
           )
           |> put_flash(
             :info,
             "Booking created! Please complete payment to confirm."
           )
           |> push_navigate(to: ~p"/bookings/checkout/#{booking.id}")}

        {:error, :insufficient_capacity} ->
          {:noreply,
           socket
           |> put_flash(
             :error,
             "Sorry, there is not enough capacity for your requested dates."
           )
           |> assign(
             form_errors: %{
               general:
                 "Sorry, there is not enough capacity for your requested dates."
             },
             calculated_price: nil,
             price_error: "Insufficient capacity"
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
             calculated_price: nil,
             price_error: "Property unavailable"
           )}

        {:error, :rooms_already_booked} ->
          {:noreply,
           socket
           |> put_flash(
             :error,
             "Sorry, some rooms are already booked for your requested dates."
           )
           |> assign(
             form_errors: %{
               general:
                 "Sorry, some rooms are already booked for your requested dates."
             },
             calculated_price: nil,
             price_error: "Rooms unavailable"
           )}

        {:error, :room_unavailable} ->
          # Map room_unavailable to rooms_already_booked for consistent error handling
          {:noreply,
           socket
           |> put_flash(
             :error,
             "Sorry, some rooms are already booked for your requested dates."
           )
           |> assign(
             form_errors: %{
               general:
                 "Sorry, some rooms are already booked for your requested dates."
             },
             calculated_price: nil,
             price_error: "Rooms unavailable"
           )}

        {:error, :stale_inventory} ->
          {:noreply,
           socket
           |> put_flash(
             :error,
             "The availability changed while you were booking. Please refresh the calendar and try again."
           )
           |> assign(
             form_errors: %{
               general:
                 "The availability changed while you were booking. Please refresh the calendar and try again."
             },
             calculated_price: nil,
             price_error: "Availability changed"
           )}

        {:error, :invalid_parameters} ->
          {:noreply,
           socket
           |> put_flash(:error, "Please fill in all required fields.")
           |> assign(
             form_errors: %{general: "Please fill in all required fields."},
             calculated_price: nil,
             price_error: "Invalid parameters",
             show_confirm_modal: false
           )}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, "Please fix the errors below.")
           |> assign(
             form_errors: format_errors(changeset),
             calculated_price: nil,
             price_error: "Validation errors",
             show_confirm_modal: false
           )}

        {:error, _reason} ->
          # Handle any other error atoms that weren't explicitly handled above
          {:noreply,
           socket
           |> put_flash(
             :error,
             "An error occurred while creating your booking. Please try again."
           )
           |> assign(
             form_errors: %{
               general:
                 "An error occurred while creating your booking. Please try again."
             },
             calculated_price: nil,
             price_error: "Booking failed",
             show_confirm_modal: false
           )}
      end
    else
      {:noreply, assign(socket, show_confirm_modal: true)}
    end
  end

  def handle_event("toggle-terms-agreement", _params, socket) do
    {:noreply,
     assign(socket,
       terms_agreed: !Map.get(socket.assigns, :terms_agreed, false)
     )}
  end

  def handle_event("show-terms-modal", _params, socket) do
    {:noreply, assign(socket, show_terms_modal: true)}
  end

  def handle_event("close-terms-modal", _params, socket) do
    {:noreply, assign(socket, show_terms_modal: false)}
  end

  def handle_event("switch-info-tab", %{"tab" => tab}, socket) do
    info_tab =
      case tab do
        "general" -> :general
        "rules" -> :rules
        _ -> :general
      end

    # Update URL with the new info tab
    query_params =
      build_query_params(
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        socket.assigns.guests_count,
        socket.assigns.children_count,
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
            to: ~p"/bookings/tahoe?#{URI.encode_query(query_params)}"
          )
        else
          push_patch(s, to: ~p"/bookings/tahoe")
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
    socket =
      if active_tab != socket.assigns.active_tab do
        # Update URL with the new tab
        query_params =
          build_query_params(
            socket.assigns.checkin_date,
            socket.assigns.checkout_date,
            socket.assigns.guests_count,
            socket.assigns.children_count,
            active_tab,
            socket.assigns.selected_booking_mode,
            socket.assigns[:info_tab]
          )

        socket
        |> assign(active_tab: active_tab)
        |> push_patch(to: ~p"/bookings/tahoe?#{URI.encode_query(query_params)}")
      else
        socket
      end

    {:noreply, socket}
  end

  # Helper functions for handle_event("room-changed", ...)

  defp extract_room_id_from_params(params) do
    room_id_str =
      cond do
        Map.has_key?(params, "room_id") ->
          Map.get(params, "room_id")

        Map.has_key?(params, "room-id") ->
          Map.get(params, "room-id")

        Map.has_key?(params, "value") ->
          extract_room_id_from_value(params["value"])

        true ->
          nil
      end

    if room_id_str && room_id_str != "", do: room_id_str, else: nil
  end

  defp extract_room_id_from_value(value) do
    cond do
      is_map(value) -> Map.get(value, "room-id") || Map.get(value, "value")
      is_binary(value) -> value
      true -> nil
    end
  end

  defp should_allow_room_selection?(socket, room_id) do
    is_deselection = room_deselection?(socket, room_id)
    {availability, _reason} = get_room_availability(socket, room_id)

    availability == :available || is_deselection
  end

  defp room_deselection?(socket, room_id) do
    current_selected_id = socket.assigns.selected_room_id
    current_selected_ids = socket.assigns.selected_room_ids || []

    room_id == current_selected_id || room_id in current_selected_ids
  end

  defp get_room_availability(socket, room_id) do
    room = Enum.find(socket.assigns.available_rooms || [], &(&1.id == room_id))

    if room do
      room.availability_status || {:available, nil}
    else
      {:unavailable, "Room not found"}
    end
  end

  defp handle_room_selection(socket, room_id) do
    if can_select_multiple_rooms?(socket.assigns) do
      handle_multiple_room_selection(socket, room_id)
    else
      handle_single_room_selection(socket, room_id)
    end
  end

  defp handle_multiple_room_selection(socket, room_id) do
    current_ids = socket.assigns.selected_room_ids || []
    selected_room_ids = toggle_room_in_list(socket, current_ids, room_id)

    socket =
      socket
      |> assign(
        selected_room_ids: selected_room_ids,
        selected_room_id: get_single_selected_room_id(selected_room_ids),
        calculated_price: nil,
        price_error: nil
      )
      |> validate_guest_capacity()
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  defp toggle_room_in_list(socket, current_ids, room_id) do
    if room_id in current_ids do
      List.delete(current_ids, room_id)
    else
      add_room_to_list_if_allowed(socket, current_ids, room_id)
    end
  end

  defp add_room_to_list_if_allowed(socket, current_ids, room_id) do
    if can_add_room_to_list?(socket, current_ids) do
      [room_id | current_ids]
    else
      current_ids
    end
  end

  defp can_add_room_to_list?(socket, current_ids) do
    max_rooms = max_rooms_for_user(socket.assigns)
    guests_count = parse_guests_count(socket.assigns.guests_count) || 1
    children_count = parse_children_count(socket.assigns.children_count) || 0
    total_people = guests_count + children_count

    has_enough_people = total_people > 1 || current_ids == []
    within_max_rooms = length(current_ids) < max_rooms

    has_enough_people && within_max_rooms
  end

  defp handle_single_room_selection(socket, room_id) do
    current_selected_id = socket.assigns.selected_room_id
    new_selected_id = if room_id == current_selected_id, do: nil, else: room_id

    socket =
      socket
      |> assign(
        selected_room_id: new_selected_id,
        selected_room_ids: if(new_selected_id, do: [new_selected_id], else: []),
        calculated_price: nil,
        price_error: nil
      )
      |> validate_guest_capacity()
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  defp get_single_selected_room_id(selected_room_ids) do
    if length(selected_room_ids) == 1,
      do: List.first(selected_room_ids),
      else: nil
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

  defp update_available_rooms(socket) do
    if should_update_available_rooms?(socket) do
      log_update_available_rooms_start(socket)

      {_guests_count, _children_count, total_people} =
        parse_and_validate_guest_counts(socket)

      all_rooms = fetch_all_rooms_for_property(socket.assigns.property)
      available_room_ids = check_room_availability(all_rooms, socket)
      can_select_multiple = can_select_multiple_rooms?(socket.assigns)
      selected_room_ids = socket.assigns.selected_room_ids || []

      total_selected_capacity =
        calculate_total_selected_capacity(all_rooms, selected_room_ids)

      rooms_with_status =
        all_rooms
        |> determine_room_availability_status(
          available_room_ids,
          selected_room_ids,
          can_select_multiple,
          total_selected_capacity,
          total_people,
          socket
        )
        |> enrich_rooms_with_pricing(socket)
        |> calculate_minimum_prices()

      assign(socket, available_rooms: rooms_with_status)
    else
      assign(socket, available_rooms: [])
    end
  end

  defp should_update_available_rooms?(socket) do
    socket.assigns.checkin_date && socket.assigns.checkout_date &&
      socket.assigns.selected_booking_mode == :room
  end

  defp log_update_available_rooms_start(socket) do
    Logger.info(
      "[TahoeBookingLive] update_available_rooms called. " <>
        "Check-in: #{socket.assigns.checkin_date}, " <>
        "Check-out: #{socket.assigns.checkout_date}, " <>
        "Property: #{socket.assigns.property}"
    )
  end

  defp parse_and_validate_guest_counts(socket) do
    raw_guests = Map.get(socket.assigns, :guests_count, 1)
    raw_children = Map.get(socket.assigns, :children_count, 0)

    guests_count = parse_guests_count(raw_guests)
    children_count = parse_children_count(raw_children)

    Logger.info(
      "[TahoeBookingLive] Guest counts - Raw: guests=#{inspect(raw_guests)}, children=#{inspect(raw_children)}. " <>
        "Parsed: guests=#{guests_count}, children=#{children_count}"
    )

    validated_guests =
      if is_integer(guests_count) && guests_count > 0, do: guests_count, else: 1

    validated_children =
      if is_integer(children_count) && children_count >= 0,
        do: children_count,
        else: 0

    total_people = validated_guests + validated_children

    {validated_guests, validated_children, total_people}
  end

  defp fetch_all_rooms_for_property(property) do
    rooms =
      from(r in Room,
        where: r.property == ^property,
        order_by: [asc: r.property, asc: r.name],
        preload: [:room_category, :image]
      )
      |> Repo.all()

    Logger.info(
      "[TahoeBookingLive] Found #{length(rooms)} rooms for property #{property}"
    )

    rooms
  end

  defp check_room_availability(all_rooms, socket) do
    all_room_ids = Enum.map(all_rooms, & &1.id)

    Bookings.batch_check_room_availability(
      all_room_ids,
      socket.assigns.property,
      socket.assigns.checkin_date,
      socket.assigns.checkout_date
    )
  end

  defp calculate_total_selected_capacity(all_rooms, selected_room_ids) do
    selected_room_ids
    |> Enum.map(fn room_id ->
      case Enum.find(all_rooms, &(&1.id == room_id)) do
        nil -> 0
        selected_room -> selected_room.capacity_max
      end
    end)
    |> Enum.sum()
  end

  defp determine_room_availability_status(
         rooms,
         available_room_ids,
         selected_room_ids,
         can_select_multiple,
         total_selected_capacity,
         total_people,
         socket
       ) do
    Enum.map(rooms, fn room ->
      availability_status =
        calculate_room_availability_status(
          room,
          available_room_ids,
          selected_room_ids,
          can_select_multiple,
          total_selected_capacity,
          total_people,
          socket
        )

      Map.put(room, :availability_status, availability_status)
    end)
  end

  defp calculate_room_availability_status(
         room,
         available_room_ids,
         selected_room_ids,
         can_select_multiple,
         total_selected_capacity,
         total_people,
         socket
       ) do
    is_available = MapSet.member?(available_room_ids, room.id)
    is_active = room.is_active
    room_already_selected = room.id in selected_room_ids

    capacity_ok =
      check_room_capacity(
        room,
        can_select_multiple,
        room_already_selected,
        total_selected_capacity,
        total_people
      )

    {_guests_count, _children_count, total_people} =
      parse_and_validate_guest_counts(socket)

    only_one_person = total_people == 1

    trying_to_add_second_room =
      can_select_multiple && selected_room_ids != [] &&
        not room_already_selected

    cannot_select_another_room =
      not can_select_multiple && selected_room_ids != [] &&
        not room_already_selected

    has_existing_booking = check_has_existing_booking(socket)
    membership_type = socket.assigns[:membership_type] || :none

    availability_context = %{
      is_active: is_active,
      is_available: is_available,
      cannot_select_another_room: cannot_select_another_room,
      has_existing_booking: has_existing_booking,
      membership_type: membership_type,
      only_one_person: only_one_person,
      trying_to_add_second_room: trying_to_add_second_room,
      capacity_ok: capacity_ok,
      can_select_multiple: can_select_multiple,
      room: room,
      total_selected_capacity: total_selected_capacity,
      total_people: total_people
    }

    determine_availability_status(availability_context)
  end

  defp check_room_capacity(
         room,
         can_select_multiple,
         room_already_selected,
         total_selected_capacity,
         total_people
       ) do
    if can_select_multiple do
      check_multiple_room_capacity(
        room,
        room_already_selected,
        total_selected_capacity,
        total_people
      )
    else
      check_single_room_capacity(room, total_people)
    end
  end

  defp check_multiple_room_capacity(
         room,
         room_already_selected,
         total_selected_capacity,
         total_people
       ) do
    if room_already_selected do
      true
    else
      if total_selected_capacity == 0 do
        true
      else
        total_selected_capacity + room.capacity_max >= total_people
      end
    end
  end

  defp check_single_room_capacity(room, total_people) do
    if total_people > 0, do: room.capacity_max >= total_people, else: true
  end

  defp check_has_existing_booking(socket) do
    if socket.assigns[:active_bookings] do
      active_bookings = socket.assigns[:active_bookings] || []
      count_rooms_in_active_bookings(active_bookings) > 0
    else
      false
    end
  end

  defp determine_availability_status(context) do
    cond do
      not context.is_active ->
        {:unavailable, "Room is not active"}

      not context.is_available ->
        {:unavailable, "Already booked for selected dates"}

      context.cannot_select_another_room ->
        build_cannot_select_another_room_error(
          context.has_existing_booking,
          context.membership_type
        )

      context.only_one_person && context.trying_to_add_second_room ->
        {:unavailable,
         "Cannot book multiple rooms with only 1 person. Please select more guests to book additional rooms."}

      not context.capacity_ok ->
        build_capacity_error(
          context.can_select_multiple,
          context.total_selected_capacity,
          context.total_people,
          context.room
        )

      true ->
        {:available, nil}
    end
  end

  defp build_cannot_select_another_room_error(
         has_existing_booking,
         membership_type
       ) do
    error_message =
      if has_existing_booking && membership_type in [:family, :lifetime] do
        "You already have a room reserved. You can only select one room for your second booking. Please deselect the current room to select a different one."
      else
        "Single membership allows only one room per booking. Please deselect the current room to select a different one."
      end

    {:unavailable, error_message}
  end

  defp build_capacity_error(
         can_select_multiple,
         total_selected_capacity,
         total_people,
         room
       ) do
    if can_select_multiple do
      {:unavailable,
       "Adding this room would not provide enough total capacity. Selected rooms: #{total_selected_capacity} guests, need #{total_people} total. This room: #{room.capacity_max} guests."}
    else
      {:unavailable,
       "Room capacity (#{room.capacity_max}) is less than number of guests (#{total_people})"}
    end
  end

  defp enrich_rooms_with_pricing(rooms, socket) do
    season_id = get_season_id(socket)

    Enum.map(rooms, fn room ->
      adult_price =
        get_adult_price_for_room(socket.assigns.property, season_id, room)

      children_price =
        get_children_price_for_room(socket.assigns.property, season_id, room)

      {room, adult_price, children_price}
    end)
  end

  defp get_season_id(socket) do
    if socket.assigns.checkin_date do
      season =
        Season.find_season_for_date(
          socket.assigns.seasons,
          socket.assigns.checkin_date
        )

      if season, do: season.id, else: nil
    else
      nil
    end
  end

  defp get_adult_price_for_room(property, season_id, room) do
    pricing_rule =
      PricingRule.find_most_specific(
        property,
        season_id,
        room.id,
        nil,
        :room,
        :per_person_per_night
      ) ||
        PricingRule.find_most_specific(
          property,
          season_id,
          nil,
          room.room_category_id,
          :room,
          :per_person_per_night
        )

    if pricing_rule && pricing_rule.amount do
      pricing_rule.amount
    else
      get_default_adult_price(property, season_id)
    end
  end

  defp get_children_price_for_room(property, season_id, room) do
    children_pricing_rule =
      PricingRule.find_children_pricing_rule(
        property,
        season_id,
        room.id,
        nil,
        :room,
        :per_person_per_night
      ) ||
        PricingRule.find_children_pricing_rule(
          property,
          season_id,
          nil,
          room.room_category_id,
          :room,
          :per_person_per_night
        ) ||
        PricingRule.find_children_pricing_rule(
          property,
          season_id,
          nil,
          nil,
          :room,
          :per_person_per_night
        )

    if children_pricing_rule && children_pricing_rule.children_amount do
      children_pricing_rule.children_amount
    else
      get_default_children_price(property, season_id)
    end
  end

  defp calculate_minimum_prices(rooms_with_pricing) do
    Enum.map(rooms_with_pricing, fn {room, adult_price, children_price} ->
      min_occupancy = room.min_billable_occupancy || 1

      minimum_price =
        if min_occupancy > 1 do
          case Money.mult(adult_price, min_occupancy) do
            {:ok, total} -> total
            {:error, _} -> adult_price
          end
        else
          nil
        end

      room
      |> Map.put(:adult_price_per_night, adult_price)
      |> Map.put(:children_price_per_night, children_price)
      |> Map.put(:minimum_price, minimum_price)
      |> Map.put(:min_billable_occupancy, min_occupancy)
    end)
  end

  defp calculate_price_if_ready(socket) do
    PricingHelpers.calculate_price_if_ready(socket, :tahoe,
      parse_guests_fn: &parse_guests_count/1,
      parse_children_fn: &parse_children_count/1,
      can_select_multiple_rooms_fn: &can_select_multiple_rooms?/1
    )
  end

  # Helper function that works with seasons and checkin_date (for template usage)
  defp can_select_booking_mode?(seasons, checkin_date) when is_list(seasons) do
    # Check if pricing rules allow buyout mode for the selected date's season
    if checkin_date do
      season = Season.find_season_for_date(seasons, checkin_date)
      season_id = if season, do: season.id, else: nil

      pricing_rule =
        PricingRule.find_most_specific(
          :tahoe,
          season_id,
          nil,
          nil,
          :buyout,
          :buyout_fixed
        )

      !is_nil(pricing_rule)
    else
      false
    end
  end

  # Helper function that works with socket (for code usage)
  defp can_select_booking_mode?(socket, checkin_date) when is_struct(socket) do
    can_select_booking_mode?(socket.assigns.seasons, checkin_date)
  end

  defp can_submit_booking?(
         booking_mode,
         checkin_date,
         checkout_date,
         room_ids_or_id,
         capacity_error,
         price_error,
         form_errors,
         date_validation_errors
       ) do
    dates_present? = checkin_date && checkout_date
    rooms_selected? = has_rooms_selected?(room_ids_or_id)
    booking_mode_valid? = booking_mode_valid?(booking_mode, rooms_selected?)

    no_errors? =
      !has_any_errors?(
        capacity_error,
        price_error,
        form_errors,
        date_validation_errors
      )

    dates_present? && booking_mode_valid? && no_errors?
  end

  defp has_rooms_selected?(room_ids_or_id) do
    case room_ids_or_id do
      room_id when is_binary(room_id) -> not is_nil(room_id)
      room_ids when is_list(room_ids) -> room_ids != []
      _ -> false
    end
  end

  defp booking_mode_valid?(booking_mode, rooms_selected?) do
    booking_mode == :buyout || (booking_mode == :room && rooms_selected?)
  end

  defp has_any_errors?(
         capacity_error,
         price_error,
         form_errors,
         date_validation_errors
       ) do
    (capacity_error && capacity_error != "") ||
      (price_error && price_error != "") ||
      (form_errors && map_size(form_errors) > 0) ||
      (date_validation_errors && map_size(date_validation_errors) > 0)
  end

  defp validate_and_create_booking(socket) do
    property = socket.assigns.property
    checkin_date = socket.assigns.checkin_date
    checkout_date = socket.assigns.checkout_date
    booking_mode = socket.assigns.selected_booking_mode
    guests_count = socket.assigns.guests_count
    children_count = socket.assigns.children_count || 0
    user_id = socket.assigns.user.id

    # Validate required fields
    # For buyout, guests_count is not required (full house capacity)
    # For room bookings, guests_count is required
    guests_count_valid? =
      case booking_mode do
        :buyout -> true
        :room -> not is_nil(guests_count) && guests_count > 0
      end

    if is_nil(checkin_date) || is_nil(checkout_date) || !guests_count_valid? do
      {:error, :invalid_parameters}
    else
      case booking_mode do
        :buyout ->
          # For buyout, use full house capacity (17 guests max for Tahoe)
          # Guests count is not required from user, but we need a value for the booking record
          buyout_guests_count = guests_count || 17

          # Use BookingLocker for buyout booking with inventory locking
          BookingLocker.create_buyout_booking(
            user_id,
            property,
            checkin_date,
            checkout_date,
            buyout_guests_count
          )

        :room ->
          # Determine which rooms to book
          room_ids =
            if can_select_multiple_rooms?(socket.assigns) do
              socket.assigns.selected_room_ids
            else
              if socket.assigns.selected_room_id,
                do: [socket.assigns.selected_room_id],
                else: []
            end

          if room_ids == [] do
            {:error, :invalid_parameters}
          else
            # Create room bookings using BookingLocker
            # For multiple rooms, create them sequentially and return the first one for checkout
            create_room_bookings_with_locking(
              user_id,
              property,
              checkin_date,
              checkout_date,
              guests_count,
              children_count,
              room_ids
            )
          end

        _ ->
          {:error, :invalid_booking_mode}
      end
    end
  end

  defp create_room_bookings_with_locking(
         user_id,
         _property,
         checkin_date,
         checkout_date,
         guests_count,
         children_count,
         room_ids
       ) do
    # Create a single booking with all rooms using BookingLocker
    # This ensures proper inventory locking for all rooms atomically
    case BookingLocker.create_room_booking(
           user_id,
           room_ids,
           checkin_date,
           checkout_date,
           guests_count,
           children_count: children_count
         ) do
      {:ok, booking} ->
        {:ok, booking}

      {:error, :room_unavailable} ->
        {:error, :rooms_already_booked}

      {:error, :stale_inventory} ->
        {:error, :stale_inventory}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      if is_binary(msg) do
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      else
        to_string(msg)
      end
    end)
  end

  defp date_to_datetime_string(nil), do: nil

  defp date_to_datetime_string(date) when is_struct(date, Date) do
    Date.to_string(date) <> "T00:00:00Z"
  end

  defp date_to_datetime_string(_), do: nil

  # URL parameter helpers

  # Parse query parameters, handling malformed/double-encoded URLs
  defp parse_query_params(params, uri) do
    # Priority 1: Use uri.query if available (most reliable)
    # Priority 2: Check for malformed key in params
    # Priority 3: Use params as-is

    cond do
      is_struct(uri, URI) && uri.query && uri.query != "" ->
        # uri.query is the most reliable source - it's the raw query string from the URL
        parsed = parse_query_string(uri.query)
        # Merge with existing params (path params take precedence)
        Map.merge(parsed, params)

      find_malformed_query_key(params) ->
        malformed_key = find_malformed_query_key(params)
        # Params are malformed - the entire query string is the key
        # Parse it directly from the key
        parsed = parse_query_string(malformed_key)
        # Remove the malformed key from params before merging
        clean_params = Map.delete(params, malformed_key)
        Map.merge(parsed, clean_params)

      true ->
        # Params are already correctly parsed
        params
    end
  end

  # Find a key that looks like a malformed query string (contains & and =)
  defp find_malformed_query_key(params) do
    Enum.find_value(params, fn
      {key, _value} when is_binary(key) ->
        if String.contains?(key, "&") and String.contains?(key, "=") do
          key
        else
          nil
        end

      _ ->
        nil
    end)
  end

  # Parse a query string into a map
  defp parse_query_string(query_string) when is_binary(query_string) do
    query_string
    |> String.split("&")
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [key, value] ->
          decoded_key = URI.decode(key)
          decoded_value = URI.decode(value)
          Map.put(acc, decoded_key, decoded_value)

        [key] ->
          decoded_key = URI.decode(key)
          Map.put(acc, decoded_key, "")

        _ ->
          acc
      end
    end)
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

  defp parse_children_from_params(params) do
    case Map.get(params, "children_count") do
      nil ->
        0

      children_str when is_binary(children_str) ->
        case Integer.parse(children_str) do
          {parsed, _} when parsed >= 0 -> parsed
          _ -> 0
        end

      children when is_integer(children) and children >= 0 ->
        children

      _ ->
        0
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
      "room" -> :room
      # Default handled by resolve logic or socket default
      _ -> nil
    end
  end

  defp update_url_with_dates(socket, checkin_date, checkout_date) do
    guests_count = socket.assigns.guests_count || 1
    children_count = socket.assigns.children_count || 0
    active_tab = socket.assigns.active_tab || :booking
    booking_mode = socket.assigns.selected_booking_mode || :room

    query_params =
      build_query_params(
        checkin_date,
        checkout_date,
        guests_count,
        children_count,
        active_tab,
        booking_mode,
        socket.assigns[:info_tab]
      )

    if map_size(query_params) > 0 do
      push_patch(socket,
        to: ~p"/bookings/tahoe?#{URI.encode_query(query_params)}"
      )
    else
      push_patch(socket, to: ~p"/bookings/tahoe")
    end
  end

  defp update_url_with_search_params(
         socket,
         checkin_date,
         checkout_date,
         guests_count,
         children_count,
         booking_mode
       ) do
    active_tab = socket.assigns.active_tab || :booking

    query_params =
      build_query_params(
        checkin_date,
        checkout_date,
        guests_count,
        children_count,
        active_tab,
        booking_mode,
        socket.assigns[:info_tab]
      )

    if map_size(query_params) > 0 do
      push_patch(socket,
        to: ~p"/bookings/tahoe?#{URI.encode_query(query_params)}"
      )
    else
      push_patch(socket, to: ~p"/bookings/tahoe")
    end
  end

  defp build_query_params(
         checkin_date,
         checkout_date,
         guests_count,
         children_count,
         active_tab,
         booking_mode,
         info_tab
       ) do
    %{}
    |> add_date_param("checkin_date", checkin_date)
    |> add_date_param("checkout_date", checkout_date)
    |> add_guests_count_param(guests_count)
    |> add_children_count_param(children_count)
    |> add_tab_param(active_tab)
    |> add_booking_mode_param(booking_mode)
    |> add_info_tab_param(info_tab)
  end

  defp add_date_param(params, key, date) when not is_nil(date) do
    Map.put(params, key, Date.to_string(date))
  end

  defp add_date_param(params, _key, _date), do: params

  defp add_guests_count_param(params, guests_count)
       when is_integer(guests_count) and guests_count > 0 do
    Map.put(params, "guests_count", Integer.to_string(guests_count))
  end

  defp add_guests_count_param(params, _guests_count), do: params

  defp add_children_count_param(params, children_count)
       when is_integer(children_count) and children_count >= 0 do
    Map.put(params, "children_count", Integer.to_string(children_count))
  end

  defp add_children_count_param(params, _children_count), do: params

  defp add_tab_param(params, active_tab)
       when not is_nil(active_tab) and active_tab != :booking do
    Map.put(params, "tab", Atom.to_string(active_tab))
  end

  defp add_tab_param(params, _active_tab), do: params

  defp add_booking_mode_param(params, booking_mode)
       when not is_nil(booking_mode) and booking_mode != :room do
    Map.put(params, "booking_mode", Atom.to_string(booking_mode))
  end

  defp add_booking_mode_param(params, _booking_mode), do: params

  defp add_info_tab_param(params, info_tab)
       when not is_nil(info_tab) and info_tab != :general do
    Map.put(params, "info_tab", Atom.to_string(info_tab))
  end

  defp add_info_tab_param(params, _info_tab), do: params

  # Real-time validation functions

  # Enforces booking mode rules based on pricing availability
  defp enforce_season_booking_mode(socket) do
    checkin_date = socket.assigns.checkin_date
    booking_mode = socket.assigns.selected_booking_mode

    if checkin_date && booking_mode == :buyout do
      if can_select_booking_mode?(socket.assigns.seasons, checkin_date) do
        socket
      else
        # Force booking mode to room if buyout not allowed
        socket
        |> assign(
          selected_booking_mode: :room,
          selected_room_id: nil,
          selected_room_ids: [],
          calculated_price: nil,
          price_error: nil
        )
      end
    else
      socket
    end
  end

  defp validate_dates(socket) do
    errors = %{}

    errors =
      if socket.assigns.checkin_date && socket.assigns.checkout_date do
        errors
        |> validate_season_date_range(socket)
        |> validate_advance_booking_limit(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date
        )
        |> validate_weekend_rule(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date
        )
        |> validate_max_nights(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date
        )
        |> validate_season_booking_mode(socket)
        |> validate_buyout_availability(socket)
      else
        errors
      end

    errors =
      validate_active_booking(%{
        socket
        | assigns: Map.put(socket.assigns, :date_validation_errors, errors)
      })

    assign(socket, date_validation_errors: errors)
  end

  defp validate_season_date_range(errors, _socket) do
    # validate_season_date_range always returns empty map (cross-season bookings allowed)
    # No validation needed here
    errors
  end

  defp validate_advance_booking_limit(errors, checkin_date, checkout_date) do
    validation_errors =
      SeasonHelpers.validate_advance_booking_limit(
        :tahoe,
        checkin_date,
        checkout_date
      )

    if Map.has_key?(validation_errors, :advance_booking_limit) do
      Map.put(
        errors,
        :advance_booking_limit,
        validation_errors.advance_booking_limit
      )
    else
      errors
    end
  end

  defp validate_season_booking_mode(errors, socket) do
    if socket.assigns.checkin_date &&
         socket.assigns.selected_booking_mode == :buyout do
      if can_select_booking_mode?(
           socket.assigns.seasons,
           socket.assigns.checkin_date
         ) do
        errors
      else
        Map.put(
          errors,
          :season_booking_mode,
          "Full buyout is not available for the selected dates"
        )
      end
    else
      errors
    end
  end

  defp validate_buyout_availability(errors, socket) do
    if socket.assigns.selected_booking_mode == :buyout &&
         socket.assigns.checkin_date &&
         socket.assigns.checkout_date do
      checkin = socket.assigns.checkin_date
      checkout = socket.assigns.checkout_date

      # 1. Check if user has ANY active or future bookings (stricter rule for buyout)
      if socket.assigns.user do
        user = socket.assigns.user
        family_user_ids = get_family_group_user_ids(user)
        today = Date.utc_today()

        # Check for any active bookings (status = :complete) with checkout_date >= today
        has_active_booking =
          Repo.exists?(
            from b in Booking,
              where: b.user_id in ^family_user_ids,
              where: b.property == :tahoe,
              where: b.status == :complete,
              where: b.checkout_date >= ^today
          )

        if has_active_booking do
          Map.put(
            errors,
            :availability,
            "You cannot book a full buyout while you have an active or future reservation. Please complete or cancel your existing reservation first."
          )
        else
          # 2. Check for blackouts
          # has_blackout? uses inclusive overlap, which is safer for availability checks
          if Bookings.has_blackout?(:tahoe, checkin, checkout) do
            Map.put(
              errors,
              :availability,
              "Selected dates are not available due to blackout dates."
            )
          else
            # 3. Check for ANY existing active bookings on the selected dates (rooms or buyouts)
            # list_bookings returns potentially overlapping bookings (inclusive)
            # We filter for status and strict overlap to be precise
            overlaps = Bookings.list_bookings(:tahoe, checkin, checkout)

            has_conflict =
              Enum.any?(overlaps, fn booking ->
                booking.status in [:hold, :complete] &&
                  Bookings.bookings_overlap?(
                    checkin,
                    checkout,
                    booking.checkin_date,
                    booking.checkout_date
                  )
              end)

            if has_conflict do
              Map.put(
                errors,
                :availability,
                "Selected dates are not available due to existing bookings."
              )
            else
              errors
            end
          end
        end
      else
        errors
      end
    else
      errors
    end
  end

  defp validate_weekend_rule(errors, checkin_date, checkout_date) do
    if Date.compare(checkout_date, checkin_date) == :lt do
      # Invalid: checkout before checkin; skip weekend rule to avoid negative Date.range
      errors
    else
      date_range = Date.range(checkin_date, checkout_date) |> Enum.to_list()

      has_saturday =
        Enum.any?(date_range, fn date ->
          Date.day_of_week(date) == 6
        end)

      if has_saturday do
        has_sunday =
          Enum.any?(date_range, fn date ->
            Date.day_of_week(date) == 7
          end)

        if has_sunday do
          errors
        else
          Map.put(
            errors,
            :weekend,
            "Bookings containing Saturday must also include Sunday (full weekend required)"
          )
        end
      else
        errors
      end
    end
  end

  defp validate_max_nights(errors, checkin_date, checkout_date) do
    nights = Date.diff(checkout_date, checkin_date)

    # Get max nights from season for check-in date
    max_nights =
      if checkin_date do
        season = Ysc.Bookings.Season.for_date(:tahoe, checkin_date)
        Ysc.Bookings.Season.get_max_nights(season, :tahoe)
      else
        # Fallback to Tahoe default
        4
      end

    if nights > max_nights do
      Map.put(
        errors,
        :max_nights,
        "Maximum #{max_nights} nights allowed per booking"
      )
    else
      errors
    end
  end

  defp validate_active_booking(socket) do
    errors = socket.assigns.date_validation_errors || %{}

    if socket.assigns.checkin_date && socket.assigns.checkout_date &&
         socket.assigns.user do
      user = socket.assigns.user

      user_with_subs =
        case user.subscriptions do
          %Ecto.Association.NotLoaded{} ->
            Accounts.get_user!(user.id) |> Repo.preload(:subscriptions)

          _ ->
            user
        end

      membership_type = get_membership_type(user_with_subs)

      # Get all user IDs in the family group
      family_user_ids = get_family_group_user_ids(user)

      # For family/lifetime members, check room count instead of just booking existence
      if membership_type in [:family, :lifetime] do
        # Count rooms in overlapping bookings across entire family group
        overlapping_query =
          from b in Booking,
            join: br in "booking_rooms",
            on: br.booking_id == b.id,
            where: b.user_id in ^family_user_ids,
            where: b.property == :tahoe,
            where: b.status in [:complete],
            where:
              fragment(
                "? < ? AND ? > ?",
                b.checkin_date,
                ^socket.assigns.checkout_date,
                b.checkout_date,
                ^socket.assigns.checkin_date
              )

        room_count_query =
          from br in "booking_rooms",
            join: b in subquery(overlapping_query),
            on: br.booking_id == b.id,
            select: count(br.id)

        existing_room_count = Repo.one(room_count_query) || 0

        if existing_room_count >= 2 do
          Map.put(
            errors,
            :active_booking,
            "Your family group has reached the maximum of 2 rooms for your #{String.capitalize("#{membership_type}")} membership in this time period."
          )
        else
          errors
        end
      else
        # Single membership: only one booking at a time (check entire family group)
        overlapping_query =
          from b in Booking,
            where: b.user_id in ^family_user_ids,
            where: b.property == :tahoe,
            where: b.status in [:complete],
            where:
              fragment(
                "? < ? AND ? > ?",
                b.checkin_date,
                ^socket.assigns.checkout_date,
                b.checkout_date,
                ^socket.assigns.checkin_date
              )

        if Repo.exists?(overlapping_query) do
          Map.put(
            errors,
            :active_booking,
            "Your family group can only have one active reservation at a time. Please complete the existing reservation first."
          )
        else
          errors
        end
      end
    else
      errors
    end
  end

  defp check_booking_eligibility(user, active_bookings, redirect_to)

  defp check_booking_eligibility(nil, _active_bookings, redirect_to) do
    sign_in_path = ~p"/users/log-in?#{%{redirect_to: redirect_to}}"

    sign_in_link =
      ~s(<a href="#{sign_in_path}" class="font-semibold text-zinc-100 hover:text-blue-200 underline">sign in</a>)

    {
      false,
      "Sign In Required",
      "You must be signed in to make a booking. Please #{sign_in_link} to continue."
    }
  end

  defp check_booking_eligibility(user, active_bookings, _redirect_to) do
    if user.state != :active do
      membership_pending_approval_error()
    else
      check_eligibility_with_active_membership(user, active_bookings)
    end
  end

  defp membership_pending_approval_error do
    {
      false,
      "Membership Pending Approval",
      "Your membership application is pending approval. You will be able to make bookings once your application has been approved."
    }
  end

  defp check_eligibility_with_active_membership(user, active_bookings) do
    user_with_subs = ensure_user_with_subscriptions(user)

    if Accounts.has_active_membership?(user_with_subs) do
      check_booking_limits(user, user_with_subs, active_bookings)
    else
      membership_required_error()
    end
  end

  defp ensure_user_with_subscriptions(user) do
    case user.subscriptions do
      %Ecto.Association.NotLoaded{} ->
        Accounts.get_user!(user.id)
        |> Ysc.Repo.preload(:subscriptions)

      _ ->
        user
    end
  end

  defp membership_required_error do
    {
      false,
      "Membership Required",
      "You need an active membership to make bookings. Please activate or renew your membership to continue."
    }
  end

  defp check_booking_limits(user, user_with_subs, active_bookings) do
    active_bookings_list =
      active_bookings || get_family_group_active_bookings(user)

    membership_type = get_membership_type(user_with_subs)

    if membership_type in [:family, :lifetime] do
      check_family_lifetime_booking_limits(
        user_with_subs,
        active_bookings_list,
        membership_type
      )
    else
      check_single_membership_booking_limits(user, active_bookings_list)
    end
  end

  defp check_family_lifetime_booking_limits(
         _user_with_subs,
         active_bookings_list,
         membership_type
       ) do
    total_rooms = count_rooms_in_active_bookings(active_bookings_list)

    if total_rooms >= 2 do
      check_family_max_rooms_reached(active_bookings_list, membership_type)
    else
      {true, nil, nil}
    end
  end

  defp check_family_max_rooms_reached(active_bookings_list, membership_type) do
    latest_checkout_date = get_latest_checkout_date(active_bookings_list)

    if latest_checkout_date && booking_still_active?(latest_checkout_date) do
      formatted_date = format_date(latest_checkout_date)

      {
        false,
        "Maximum rooms reached",
        "Your family group has reached the maximum of 2 rooms for your #{String.capitalize("#{membership_type}")} membership. You can make a new reservation once the current stay is complete (after #{formatted_date}) or if the existing booking is cancelled."
      }
    else
      {true, nil, nil}
    end
  end

  defp booking_still_active?(checkout_date) do
    today = Date.utc_today()

    Date.compare(checkout_date, today) == :gt or
      (Date.compare(checkout_date, today) == :eq and not past_checkout_time?())
  end

  defp check_single_membership_booking_limits(user, active_bookings_list) do
    case get_active_booking_from_family_group(user, active_bookings_list) do
      nil ->
        {true, nil, nil}

      active_booking ->
        check_single_booking_active_status(user, active_booking)
    end
  end

  defp check_single_booking_active_status(user, active_booking) do
    checkout_date = active_booking.checkout_date

    if booking_still_active?(checkout_date) do
      formatted_date = format_date(checkout_date)

      booking_owner =
        if active_booking.user_id == user.id, do: "you", else: "a family member"

      {
        false,
        "Looks like #{booking_owner} already have a booking!",
        "You can make a new reservation once the current stay is complete (after #{formatted_date}) or if the existing booking is cancelled."
      }
    else
      {true, nil, nil}
    end
  end

  defp tahoe_redirect_to(
         checkin_date,
         checkout_date,
         guests_count,
         children_count,
         tab,
         booking_mode
       ) do
    query_params =
      build_query_params(
        checkin_date,
        checkout_date,
        guests_count,
        children_count,
        tab || :booking,
        booking_mode || :room,
        nil
      )

    if map_size(query_params) > 0 do
      ~p"/bookings/tahoe?#{URI.encode_query(query_params)}"
    else
      ~p"/bookings/tahoe"
    end
  end

  defp get_active_booking_from_family_group(_user, active_bookings) do
    # active_bookings should already contain all family group bookings
    List.first(active_bookings)
  end

  defp get_latest_checkout_date(active_bookings) do
    case active_bookings do
      [] ->
        nil

      bookings when is_list(bookings) ->
        bookings
        |> Enum.max_by(& &1.checkout_date, Date)

      _ ->
        nil
    end
    |> case do
      nil -> nil
      booking -> booking.checkout_date
    end
  end

  # Get active bookings for the entire family group (primary user + all sub-accounts)
  defp get_family_group_active_bookings(user, limit \\ 10) do
    family_user_ids = get_family_group_user_ids(user)
    today = Date.utc_today()
    checkout_time = ~T[11:00:00]

    query =
      from b in Booking,
        where: b.user_id in ^family_user_ids,
        where: b.property == :tahoe,
        where: b.status == :complete,
        where: b.checkout_date >= ^today,
        order_by: [asc: b.checkin_date],
        limit: ^limit,
        preload: [:rooms, :user]

    bookings = Repo.all(query)

    # Filter out bookings that are past checkout time today
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
    |> Enum.take(limit)
  end

  # Get all user IDs in the family group (primary user + all sub-accounts)
  defp get_family_group_user_ids(user) do
    family_group = Accounts.get_family_group(user)
    Enum.map(family_group, & &1.id)
  end

  defp past_checkout_time? do
    today = Date.utc_today()
    checkout_time = ~T[11:00:00]
    checkout_datetime = DateTime.new!(today, checkout_time, "Etc/UTC")
    now = DateTime.utc_now()
    DateTime.compare(now, checkout_datetime) == :gt
  end

  defp get_membership_type(user) do
    # Check for lifetime membership first
    if Accounts.has_lifetime_membership?(user) do
      :lifetime
    else
      # Get active subscriptions
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
      subscription = Repo.preload(subscription, :subscription_items)

      case subscription.subscription_items do
        [item | _] -> Map.get(price_to_amount, item.stripe_price_id, 0)
        _ -> 0
      end
    end)
  end

  defp count_rooms_in_active_bookings(active_bookings) do
    active_bookings
    |> Enum.map(fn booking ->
      # Rooms are preloaded, count them
      case booking.rooms do
        %Ecto.Association.NotLoaded{} -> 0
        rooms when is_list(rooms) -> length(rooms)
        _ -> 0
      end
    end)
    |> Enum.sum()
  end

  defp dates_are_restricted?(
         restricted_min,
         restricted_max,
         default_min,
         default_max
       ) do
    # Dates are restricted if they differ from the default range
    Date.compare(restricted_min, default_min) != :eq ||
      Date.compare(restricted_max, default_max) != :eq
  end

  defp calculate_restricted_date_range(active_bookings, max_booking_date) do
    # Get the first active booking (should only be one for this use case)
    case List.first(active_bookings) do
      nil ->
        # No active bookings, use default range
        {Date.utc_today(), max_booking_date}

      booking ->
        existing_checkin = booking.checkin_date
        existing_checkout = booking.checkout_date
        existing_nights = Date.diff(existing_checkout, existing_checkin)
        max_nights = 4

        if existing_nights >= max_nights do
          # Booking is already 4 days, restrict to those exact dates (no extension)
          {existing_checkin, existing_checkout}
        else
          # Calculate how many nights to add in each direction
          # If existing is 1 night, extend 3 days backward and forward
          # If existing is 2 nights, extend 2 days backward and forward
          # If existing is 3 nights, extend 1 day backward and forward
          nights_to_add = max_nights - existing_nights

          # Extend backward from check-in date
          restricted_min = Date.add(existing_checkin, -nights_to_add)

          # Extend forward: maximum checkout is 4 nights from check-in
          restricted_max = Date.add(existing_checkin, max_nights)

          # Ensure we don't go before today or after max_booking_date
          today = Date.utc_today()

          restricted_min =
            if Date.compare(restricted_min, today) == :lt,
              do: today,
              else: restricted_min

          restricted_max =
            if Date.compare(restricted_max, max_booking_date) == :gt,
              do: max_booking_date,
              else: restricted_max

          {restricted_min, restricted_max}
        end
    end
  end

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  defp can_select_multiple_rooms?(assigns) do
    # Use cached membership_type if available, otherwise compute it
    membership_type =
      case assigns[:membership_type] do
        nil ->
          if assigns.user do
            get_membership_type(assigns.user)
          else
            :none
          end

        type ->
          type
      end

    # Family/lifetime members can select multiple rooms only if they don't already have a booking
    # If they have 1 room booking, they can only select 1 room for their second booking
    if membership_type in [:family, :lifetime] do
      active_bookings = assigns[:active_bookings] || []
      total_rooms = count_rooms_in_active_bookings(active_bookings)

      # Can select multiple rooms only if they have 0 rooms (no existing booking)
      total_rooms == 0
    else
      false
    end
  end

  defp max_rooms_for_user(user_or_assigns) do
    # Handle both user struct and assigns map
    membership_type =
      cond do
        is_map(user_or_assigns) &&
            Map.has_key?(user_or_assigns, :membership_type) ->
          user_or_assigns.membership_type

        is_map(user_or_assigns) && Map.has_key?(user_or_assigns, :user) ->
          # It's an assigns map with user
          case user_or_assigns[:membership_type] do
            nil -> get_membership_type(user_or_assigns.user)
            type -> type
          end

        true ->
          # It's a user struct
          get_membership_type(user_or_assigns)
      end

    # Check if user already has a booking (for assigns map only)
    existing_rooms =
      if is_map(user_or_assigns) &&
           Map.has_key?(user_or_assigns, :active_bookings) do
        active_bookings = user_or_assigns[:active_bookings] || []
        count_rooms_in_active_bookings(active_bookings)
      else
        0
      end

    # If user already has 1 room booking, they can only book 1 more room
    # Otherwise, family/lifetime members can book up to 2 rooms
    case membership_type do
      :family ->
        if existing_rooms >= 1 do
          1
        else
          2
        end

      :lifetime ->
        if existing_rooms >= 1 do
          1
        else
          2
        end

      _ ->
        1
    end
  end

  defp get_selected_rooms_for_submit(assigns) do
    if can_select_multiple_rooms?(assigns) do
      assigns.selected_room_ids
    else
      assigns.selected_room_id
    end
  end

  defp parse_guests_count(count) do
    case count do
      count when is_integer(count) and count > 0 ->
        count

      count when is_binary(count) ->
        case Integer.parse(count) do
          {parsed, _} when parsed > 0 -> parsed
          _ -> 1
        end

      _ ->
        1
    end
  end

  defp parse_children_count(count) do
    case count do
      count when is_integer(count) and count >= 0 ->
        count

      count when is_binary(count) ->
        case Integer.parse(count) do
          {parsed, _} when parsed >= 0 -> parsed
          _ -> 0
        end

      _ ->
        0
    end
  end

  defp format_guests_display(guests_count, children_count) do
    guests_text =
      if guests_count == 1, do: "1 adult", else: "#{guests_count} adults"

    children_text =
      cond do
        children_count == 0 -> nil
        children_count == 1 -> "1 child"
        true -> "#{children_count} children"
      end

    if children_text do
      "#{guests_text} • #{children_text}"
    else
      guests_text
    end
  end

  defp validate_guest_capacity(socket) do
    # Only validate if rooms are selected and we're in room booking mode
    if socket.assigns.selected_booking_mode == :room &&
         (socket.assigns.selected_room_id ||
            (socket.assigns.selected_room_ids &&
               socket.assigns.selected_room_ids != [])) do
      guests_count = parse_guests_count(socket.assigns.guests_count) || 1
      children_count = parse_children_count(socket.assigns.children_count) || 0
      total_guests = guests_count + children_count

      # Get selected room IDs
      selected_room_ids =
        if can_select_multiple_rooms?(socket.assigns) do
          socket.assigns.selected_room_ids || []
        else
          if socket.assigns.selected_room_id,
            do: [socket.assigns.selected_room_id],
            else: []
        end

      if selected_room_ids != [] do
        # Reuse rooms from available_rooms if available (already loaded in update_available_rooms)
        # Otherwise fall back to loading them
        all_rooms =
          if socket.assigns[:available_rooms] &&
               socket.assigns.available_rooms != [] do
            socket.assigns.available_rooms
          else
            Bookings.list_rooms(socket.assigns.property)
          end

        total_capacity =
          selected_room_ids
          |> Enum.map(fn room_id ->
            case Enum.find(all_rooms, &(&1.id == room_id)) do
              nil -> 0
              room -> room.capacity_max
            end
          end)
          |> Enum.sum()

        if total_guests > total_capacity do
          assign(socket,
            capacity_error:
              "Total number of guests (#{total_guests}) exceeds the combined capacity of selected rooms (#{total_capacity} guests). Please select more rooms or reduce the number of guests."
          )
        else
          assign(socket, capacity_error: nil)
        end
      else
        assign(socket, capacity_error: nil)
      end
    else
      assign(socket, capacity_error: nil)
    end
  end

  # Bed icon SVG helpers
  defp bed_icon_svg(bed_type, class)

  defp bed_icon_svg(:single, class) do
    """
    <svg class="#{class}" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" role="img" aria-labelledby="twinBedTitle">
      <path d="M6 9h12" />
      <rect x="6" y="9" width="12" height="8" rx="2" />
      <path d="M8 17v2m8-2v2" />
      <rect x="9.75" y="10.25" width="4.5" height="2.5" rx="1" />
    </svg>
    """
  end

  defp bed_icon_svg(:queen, class) do
    """
    <svg class="#{class}" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" role="img" aria-labelledby="queenBedTitle">
      <path d="M4 9h16" />
      <rect x="4" y="9" width="16" height="8" rx="2" />
      <path d="M7 17v2m10-2v2" />
      <rect x="7.5" y="10.25" width="5" height="2.5" rx="1" />
      <rect x="11.5" y="10.25" width="5" height="2.5" rx="1" />
    </svg>
    """
  end

  defp bed_icon_svg(:king, class) do
    """
    <svg class="#{class}" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" role="img" aria-labelledby="kingBedTitle">
      <path d="M3 9h18" />
      <rect x="3" y="9" width="18" height="8" rx="2" />
      <path d="M6 17v2m12-2v2" />
      <rect x="6.25" y="10.25" width="6" height="2.5" rx="1" />
      <rect x="11.75" y="10.25" width="6" height="2.5" rx="1" />
    </svg>
    """
  end

  # Room image helper functions
  defp get_room_blur_hash(nil), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

  defp get_room_blur_hash(%Ysc.Media.Image{blur_hash: nil}),
    do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

  defp get_room_blur_hash(%Ysc.Media.Image{blur_hash: blur_hash}), do: blur_hash

  defp get_room_image_url(nil), do: "/images/ysc_logo.png"

  defp get_room_image_url(%Ysc.Media.Image{} = image) do
    # Prefer thumbnail for room cards (smaller, faster loading)
    cond do
      not is_nil(image.thumbnail_path) -> image.thumbnail_path
      not is_nil(image.optimized_image_path) -> image.optimized_image_path
      not is_nil(image.raw_image_path) -> image.raw_image_path
      true -> "/images/ysc_logo.png"
    end
  end

  # Helper to get default adult price from pricing rules (property-level fallback)
  defp get_default_adult_price(property, season_id) do
    pricing_rule =
      PricingRule.find_most_specific(
        property,
        season_id,
        nil,
        nil,
        :room,
        :per_person_per_night
      )

    if pricing_rule && pricing_rule.amount do
      pricing_rule.amount
    else
      # Last resort fallback - should rarely happen if pricing rules are configured
      Money.new(45, :USD)
    end
  end

  # Helper to get default children price from pricing rules (property-level fallback)
  defp get_default_children_price(property, season_id) do
    children_pricing_rule =
      PricingRule.find_children_pricing_rule(
        property,
        season_id,
        nil,
        nil,
        :room,
        :per_person_per_night
      )

    if children_pricing_rule && children_pricing_rule.children_amount do
      children_pricing_rule.children_amount
    else
      # Last resort fallback - should rarely happen if pricing rules are configured
      Money.new(25, :USD)
    end
  end

  # Season caching helpers to avoid multiple database queries

  defp get_current_season_info_cached(seasons, today) do
    current_season = Season.find_season_for_date(seasons, today)

    if current_season do
      {season_start_date, season_end_date} =
        SeasonHelpers.get_season_date_range(current_season, today)

      {current_season, season_start_date, season_end_date}
    else
      {nil, nil, nil}
    end
  end

  defp calculate_max_booking_date_cached(seasons, today) do
    current_season = Season.find_season_for_date(seasons, today)

    if current_season do
      if current_season.advance_booking_days &&
           current_season.advance_booking_days > 0 do
        # Current season has a limit - apply it
        Date.add(today, current_season.advance_booking_days)
      else
        # Current season has no limit - allow up to the end of current season
        {_season_start, season_end} =
          SeasonHelpers.get_season_date_range(current_season, today)

        # Also check if we can book into the next season (if it has a limit)
        next_season = get_next_season_cached(seasons, today, current_season)

        max_date = season_end

        if next_season && next_season.advance_booking_days &&
             next_season.advance_booking_days > 0 do
          # Next season has a limit - we can book up to that limit
          next_season_max = Date.add(today, next_season.advance_booking_days)
          # Use the later of: end of current season or next season's limit
          if Date.compare(next_season_max, max_date) == :gt do
            next_season_max
          else
            max_date
          end
        else
          max_date
        end
      end
    else
      # No current season found - use a conservative default
      Date.add(today, 365)
    end
  end

  defp get_next_season_cached(seasons, reference_date, current_season) do
    if current_season && length(seasons) > 1 do
      # Find the next season by calculating which one starts next
      next_seasons =
        seasons
        |> Enum.filter(fn season -> season.id != current_season.id end)
        |> Enum.map(fn season ->
          {season, get_next_season_occurrence_start(season, reference_date)}
        end)
        |> Enum.filter(fn {_season, start_date} -> start_date != nil end)
        |> Enum.sort_by(fn {_season, start_date} -> start_date end)

      case next_seasons do
        [{next_season, _start_date} | _] -> next_season
        _ -> nil
      end
    else
      nil
    end
  end

  # Gets the next occurrence start date for a season after the reference date
  defp get_next_season_occurrence_start(season, reference_date) do
    {ref_month, ref_day} = {reference_date.month, reference_date.day}
    {start_month, start_day} = {season.start_date.month, season.start_date.day}
    {end_month, end_day} = {season.end_date.month, season.end_date.day}

    cond do
      # If season spans years (e.g., Nov to Apr)
      start_month > end_month ->
        # If we're before the end date, next start could be this year or next
        if {ref_month, ref_day} <= {end_month, end_day} do
          # We're in the later part (Jan-Apr), next start is this year
          candidate = Date.new!(reference_date.year, start_month, start_day)

          if Date.compare(candidate, reference_date) == :gt,
            do: candidate,
            else: Date.new!(reference_date.year + 1, start_month, start_day)
        else
          # We're in the earlier part (Nov-Dec), next start is next year
          Date.new!(reference_date.year + 1, start_month, start_day)
        end

      # Same-year range
      {ref_month, ref_day} < {start_month, start_day} ->
        # Next start is this year
        Date.new!(reference_date.year, start_month, start_day)

      true ->
        # Next start is next year
        Date.new!(reference_date.year + 1, start_month, start_day)
    end
  end

  # Generate tooltips for unavailable dates
  # Returns a map of date strings (ISO format) to tooltip messages
  defp generate_date_tooltips(min_date, max_date, today, property, _seasons) do
    # Generate tooltips for a more limited date range (1 month before min to 1 month after max)
    # This reduces the number of dates we need to check significantly
    start_range = Date.add(min_date, -30)
    end_range = Date.add(max_date, 30)
    date_range = Date.range(start_range, end_range) |> Enum.to_list()

    # Get all rooms for the property
    all_rooms = Bookings.list_rooms(property) |> Enum.filter(& &1.is_active)

    # Get all bookings in the range (preload rooms for availability checking)
    bookings =
      Bookings.list_bookings(property, start_range, end_range,
        preload: [:rooms]
      )

    # Get all blackouts in the range
    blackouts =
      Bookings.get_overlapping_blackouts(property, start_range, end_range)

    blackout_dates =
      blackouts
      |> Enum.flat_map(fn blackout ->
        Date.range(blackout.start_date, blackout.end_date) |> Enum.to_list()
      end)
      |> MapSet.new()

    # Get buyout dates from property inventory
    buyout_dates =
      from(pi in PropertyInventory,
        where: pi.property == ^property,
        where: pi.day >= ^start_range and pi.day <= ^end_range,
        where: pi.buyout_held == true or pi.buyout_booked == true,
        select: pi.day
      )
      |> Repo.all()
      |> MapSet.new()

    # Build tooltip map
    date_range
    |> Enum.reduce(%{}, fn date, acc ->
      availability_context = %{
        date: date,
        min_date: min_date,
        max_date: max_date,
        today: today,
        property: property,
        all_rooms: all_rooms,
        bookings: bookings,
        blackout_dates: blackout_dates,
        buyout_dates: buyout_dates
      }

      tooltip = get_date_unavailability_reason(availability_context)

      if tooltip do
        Map.put(acc, Date.to_iso8601(date), tooltip)
      else
        acc
      end
    end)
  end

  # Get the reason why a date is unavailable (returns nil if available)
  defp get_date_unavailability_reason(context) do
    cond do
      # Past dates
      Date.compare(context.date, context.min_date) == :lt ->
        "Past dates cannot be booked"

      # Too far in future
      Date.compare(context.date, context.max_date) == :gt ->
        "Reservations are not open for this date yet"

      # Season restrictions (check if date is selectable based on season rules)
      not SeasonHelpers.date_selectable?(
        context.property,
        context.date,
        context.today
      ) ->
        "Bookings for this season are not yet open"

      # Saturday check-in (Tahoe rule)
      Date.day_of_week(context.date) == 6 && context.property == :tahoe ->
        "Check-ins are not permitted on Saturdays"

      # Blackout
      MapSet.member?(context.blackout_dates, context.date) ->
        "This date is unavailable"

      # Buyout
      MapSet.member?(context.buyout_dates, context.date) ->
        "Full cabin buyout is already reserved on this date"

      # Check if all rooms are booked (for room booking mode)
      true ->
        # Check if all active rooms are booked for this date
        # We need to check if there's at least one room available for a single night stay
        date_available =
          check_date_availability_for_rooms(
            context.date,
            context.all_rooms,
            context.bookings
          )

        if date_available do
          nil
        else
          "All rooms are booked"
        end
    end
  end

  # Check if at least one room is available for a specific date (as check-in date)
  defp check_date_availability_for_rooms(checkin_date, all_rooms, bookings) do
    if Enum.empty?(all_rooms) do
      false
    else
      # For tooltip purposes, we check if a single night stay is possible
      # (checkin_date to checkin_date + 1 day)
      checkout_date = Date.add(checkin_date, 1)

      # Filter bookings that overlap with this date range
      overlapping_bookings =
        Enum.filter(bookings, fn booking ->
          booking.status in [:hold, :complete] &&
            Bookings.bookings_overlap?(
              checkin_date,
              checkout_date,
              booking.checkin_date,
              booking.checkout_date
            )
        end)

      # Get room IDs that are booked
      booked_room_ids =
        overlapping_bookings
        |> Enum.flat_map(fn booking ->
          if Ecto.assoc_loaded?(booking.rooms) do
            Enum.map(booking.rooms, & &1.id)
          else
            []
          end
        end)
        |> MapSet.new()

      # Check if there's at least one room not booked
      available_rooms =
        Enum.filter(all_rooms, fn room ->
          not MapSet.member?(booked_room_ids, room.id)
        end)

      available_rooms != []
    end
  end
end
