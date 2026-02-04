defmodule YscWeb.Components.AvailabilityCalendar do
  @moduledoc """
  LiveView component for displaying availability calendar with spot counts.

  Shows how many spots are available for each day and allows date selection.
  """
  use YscWeb, :live_component

  alias Ysc.Bookings

  @week_start_at :sunday

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="availability-calendar overflow-visible"
      data-phx-component={@id}
    >
      <div class="bg-white rounded-lg border border-zinc-200 p-6 overflow-visible">
        <div class="flex justify-between items-center mb-4">
          <div>
            <button
              type="button"
              phx-target={@myself}
              phx-click="prev-month"
              class="p-1.5 text-zinc-400 hover:text-zinc-500 transition duration-300"
            >
              <.icon name="hero-arrow-left" />
            </button>
          </div>

          <div class="font-semibold text-lg">
            <%= @current.month %>
          </div>

          <div>
            <button
              type="button"
              phx-target={@myself}
              phx-click="next-month"
              class="p-1.5 text-zinc-400 hover:text-zinc-500 transition duration-300"
            >
              <.icon name="hero-arrow-right" />
            </button>
          </div>
        </div>

        <div class="text-sm text-center mb-2">
          <.link
            phx-click="today"
            phx-target={@myself}
            class="text-zinc-700 hover:text-zinc-500"
          >
            Today
          </.link>
        </div>

        <div class="text-center grid grid-cols-7 text-xs leading-6 text-zinc-800 font-semibold mb-2">
          <div :for={week_day <- List.first(@current.week_rows)}>
            <%= Calendar.strftime(week_day, "%a") %>
          </div>
        </div>

        <div
          id={"#{@id}_calendar_days"}
          class="isolate grid grid-cols-7 gap-1 text-sm overflow-visible relative"
          phx-hook="DaterangeHover"
          phx-target={@myself}
          data-component-id={@id}
        >
          <div
            :for={day <- Enum.flat_map(@current.week_rows, & &1)}
            class="relative overflow-visible"
          >
            <div
              :if={
                date_disabled?(day, assigns) && !other_month?(day, @current.date) &&
                  !selected_start?(day, @checkin_date)
              }
              class="group relative overflow-visible"
            >
              <button
                type="button"
                phx-target={@myself}
                phx-click="pick-date"
                phx-value-date={Calendar.strftime(day, "%Y-%m-%d")}
                disabled={true}
                class={day_classes(day, assigns)}
              >
                <time
                  class="text-sm font-medium"
                  datetime={Calendar.strftime(day, "%Y-%m-%d")}
                >
                  <%= Calendar.strftime(day, "%d") %>
                </time>
              </button>
              <span
                role="tooltip"
                class={[
                  "absolute transition-opacity mt-2 top-full left-1/2 transform -translate-x-1/2 duration-200 opacity-0 z-[100] text-xs font-medium text-zinc-100 bg-zinc-900 rounded-lg shadow-lg px-4 py-2 block rounded tooltip group-hover:opacity-100 whitespace-normal pointer-events-none",
                  "min-w-[200px] max-w-[400px]",
                  "text-left"
                ]}
              >
                <%= unavailability_reason(day, assigns) %>
              </span>
            </div>
            <button
              :if={
                !date_disabled?(day, assigns) || other_month?(day, @current.date) ||
                  selected_start?(day, @checkin_date)
              }
              type="button"
              phx-target={@myself}
              phx-click="pick-date"
              phx-value-date={Calendar.strftime(day, "%Y-%m-%d")}
              disabled={
                date_disabled?(day, assigns) && !selected_start?(day, @checkin_date)
              }
              class={day_classes(day, assigns)}
            >
              <time
                class="text-sm font-medium"
                datetime={Calendar.strftime(day, "%Y-%m-%d")}
              >
                <%= Calendar.strftime(day, "%d") %>
              </time>
              <div
                :if={
                  (!date_disabled?(day, assigns) ||
                     selected_start?(day, @checkin_date)) &&
                    !other_month?(day, @current.date)
                }
                class="text-xs mt-1"
              >
                <%= availability_display(
                  day,
                  @selected_booking_mode,
                  @availability,
                  assigns
                ) %>
              </div>
            </button>
          </div>
        </div>

        <div class="mt-8 flex flex-wrap gap-4 text-xs text-zinc-600">
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 bg-green-50 border border-green-200 rounded"></div>
            <span>Available</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 bg-blue-500 rounded"></div>
            <span>Selected dates</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 bg-red-800 border border-red-900 rounded"></div>
            <span>Blackout dates</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 bg-red-200 border border-red-300 rounded"></div>
            <span>Unavailable</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 bg-gradient-to-r from-red-200 to-green-50 border border-zinc-300 rounded">
            </div>
            <span>Check-in allowed</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 bg-gradient-to-r from-green-50 to-red-200 border border-zinc-300 rounded">
            </div>
            <span>Check-out allowed</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    today = Date.utc_today()

    {
      :ok,
      socket
      |> assign(:current, format_date(today))
      |> assign(:checkin_date, nil)
      |> assign(:checkout_date, nil)
      |> assign(:hover_checkout_date, nil)
      |> assign(:state, :set_start)
      |> assign(:availability, %{})
      |> assign(:seasons, [])
    }
  end

  @impl true
  def update(assigns, socket) do
    today = assigns[:today] || Date.utc_today()

    current_date =
      if socket.assigns[:current] && socket.assigns.current[:date] do
        socket.assigns.current.date
      else
        today
      end

    # Calculate availability range
    visible_month_start = Date.beginning_of_month(current_date)
    visible_month_end = Date.end_of_month(current_date)
    month_start_minus_30 = Date.add(visible_month_start, -30)

    start_date =
      if Date.compare(month_start_minus_30, today) == :lt,
        do: today,
        else: month_start_minus_30

    end_date = Date.add(visible_month_end, 30)

    # Expand range if needed for selections
    checkin_date = assigns[:checkin_date]
    checkout_date = assigns[:checkout_date]

    {start_date, end_date} =
      cond do
        checkin_date && checkout_date ->
          {
            if(Date.compare(start_date, checkin_date) == :gt,
              do: checkin_date,
              else: start_date
            )
            |> Date.add(-30),
            if(Date.compare(end_date, checkout_date) == :lt,
              do: checkout_date,
              else: end_date
            )
            |> Date.add(30)
          }

        checkin_date ->
          {
            if(Date.compare(start_date, checkin_date) == :gt,
              do: checkin_date,
              else: start_date
            )
            |> Date.add(-30),
            if(Date.compare(end_date, checkin_date) == :lt,
              do: checkin_date,
              else: end_date
            )
            |> Date.add(30)
          }

        true ->
          {start_date, end_date}
      end

    # Check if reload needed
    existing_today = socket.assigns[:today]
    existing_availability = socket.assigns[:availability]

    has_valid_availability =
      if !is_nil(existing_availability) && !is_nil(existing_today) &&
           Date.compare(existing_today, today) == :eq do
        availability_dates = Map.keys(existing_availability)

        if Enum.empty?(availability_dates) do
          false
        else
          existing_min = Enum.min(availability_dates)
          existing_max = Enum.max(availability_dates)

          Date.compare(existing_min, start_date) != :gt &&
            Date.compare(existing_max, end_date) != :lt
        end
      else
        false
      end

    existing_booking_mode = socket.assigns[:selected_booking_mode] || :day
    new_booking_mode = assigns[:selected_booking_mode] || :day
    booking_mode_changed = existing_booking_mode != new_booking_mode

    property = assigns[:property] || :clear_lake

    availability =
      if !has_valid_availability || booking_mode_changed do
        case property do
          :clear_lake ->
            Bookings.get_clear_lake_daily_availability(start_date, end_date)

          :tahoe ->
            Bookings.get_tahoe_daily_availability(start_date, end_date)

          _ ->
            Bookings.get_clear_lake_daily_availability(start_date, end_date)
        end
      else
        socket.assigns[:availability]
      end

    seasons =
      if socket.assigns[:seasons] && socket.assigns[:property] == property do
        socket.assigns[:seasons]
      else
        Bookings.list_seasons(property)
      end

    new_state =
      cond do
        checkin_date && checkout_date -> :set_start
        checkin_date && !checkout_date -> :set_end
        true -> :set_start
      end

    updated_socket =
      socket
      |> assign(assigns)
      |> assign(:current, format_date(current_date))
      |> assign(:availability, availability)
      |> assign(:today, today)
      |> assign(:min, assigns[:min] || today)
      |> assign(:max, assigns[:max])
      |> assign(:property, property)
      |> assign(:seasons, seasons)
      |> assign(:selected_booking_mode, assigns[:selected_booking_mode] || :day)
      |> assign(:state, new_state)

    {:ok, updated_socket}
  end

  @impl true
  def handle_event("prev-month", _, socket) do
    new_date = prev_month_date(socket.assigns.current.date)
    socket = socket |> assign(:current, format_date(new_date))
    socket = reload_availability_if_needed(socket, new_date)
    {:noreply, socket}
  end

  @impl true
  def handle_event("next-month", _, socket) do
    new_date = next_month_date(socket.assigns.current.date)
    socket = socket |> assign(:current, format_date(new_date))
    socket = reload_availability_if_needed(socket, new_date)
    {:noreply, socket}
  end

  @impl true
  def handle_event("today", _, socket) do
    today = Date.utc_today()
    socket = socket |> assign(:current, format_date(today))
    socket = reload_availability_if_needed(socket, today)
    {:noreply, socket}
  end

  @impl true
  def handle_event("pick-date", %{"date" => date_str}, socket) do
    date = Date.from_iso8601!(date_str)

    if date_disabled?(date, socket.assigns) do
      {:noreply, socket}
    else
      case socket.assigns.state do
        :set_start ->
          {:noreply,
           socket
           |> assign(:checkin_date, date)
           |> assign(:checkout_date, nil)
           |> assign(:state, :set_end)
           |> send_date_update()}

        :set_end ->
          checkin_date = socket.assigns.checkin_date

          if Date.compare(date, checkin_date) == :eq do
            {:noreply,
             socket
             |> assign(:checkin_date, nil)
             |> assign(:checkout_date, nil)
             |> assign(:hover_checkout_date, nil)
             |> assign(:state, :set_start)
             |> send_date_update()}
          else
            if Date.compare(date, checkin_date) == :lt do
              {:noreply,
               socket
               |> assign(:checkin_date, date)
               |> assign(:checkout_date, nil)
               |> assign(:state, :set_end)
               |> send_date_update()}
            else
              if valid_date_range?(checkin_date, date, socket.assigns) do
                {:noreply,
                 socket
                 |> assign(:checkout_date, date)
                 |> assign(:state, :set_start)
                 |> send_date_update()}
              else
                {:noreply, socket}
              end
            end
          end
      end
    end
  end

  @impl true
  def handle_event("cursor-move", date_str, socket) do
    date_string =
      if is_map(date_str),
        do: Map.get(date_str, "date") || Map.get(date_str, :date) || "",
        else: date_str

    date =
      case Date.from_iso8601(date_string) do
        {:ok, d} ->
          d

        _ ->
          if date_string != "", do: Date.from_iso8601!(date_string), else: nil
      end

    if is_nil(date) do
      {:noreply, socket}
    else
      if socket.assigns.state == :set_end && socket.assigns.checkin_date do
        checkin_date = socket.assigns.checkin_date

        hover_checkout_date =
          if Date.compare(date, checkin_date) != :lt &&
               !date_disabled?(date, socket.assigns) &&
               valid_date_range?(checkin_date, date, socket.assigns) do
            date
          else
            nil
          end

        {:noreply, socket |> assign(:hover_checkout_date, hover_checkout_date)}
      else
        {:noreply, socket |> assign(:hover_checkout_date, nil)}
      end
    end
  end

  @impl true
  def handle_event("cursor-leave", _params, socket) do
    {:noreply, socket |> assign(:hover_checkout_date, nil)}
  end

  # --- Helpers ---

  defp day_classes(day, assigns) do
    base =
      "calendar-day overflow-hidden py-2 h-16 rounded w-full focus:z-10 transition duration-300 flex flex-col items-center justify-center relative"

    # 1. Check if other month (lowest priority)
    is_other_month = other_month?(day, assigns.current.date)

    if is_other_month do
      "#{base} text-zinc-400 bg-zinc-50/50"
    else
      # 2. Check selection states (highest priority)
      is_start = selected_start?(day, assigns.checkin_date)
      is_end = selected_end?(day, assigns.checkout_date)

      hover_end =
        assigns.state == :set_end && assigns.hover_checkout_date &&
          day == assigns.hover_checkout_date

      is_range =
        selected_range?(day, assigns.checkin_date, assigns.checkout_date)

      is_hover_range =
        assigns.state == :set_end &&
          in_hover_range?(
            day,
            assigns.checkin_date,
            assigns.hover_checkout_date
          )

      cond do
        is_start ->
          "#{base} bg-gradient-to-br from-blue-600 to-blue-700 text-white font-bold shadow-lg ring-4 ring-blue-200 ring-offset-2 transform scale-105 z-30"

        is_end || hover_end ->
          "#{base} bg-gradient-to-br from-blue-600 to-blue-700 text-white font-bold shadow-lg ring-4 ring-blue-200 ring-offset-2 transform scale-105 z-30"

        is_range || is_hover_range ->
          "#{base} bg-blue-400 text-white hover:bg-blue-500"

        true ->
          # 3. Availability colors
          # Determine status of morning (based on yesterday) and afternoon (based on today)
          yesterday = Date.add(day, -1)

          # Morning is blocked if yesterday was unavailable
          morning_blocked = date_unavailable_for_stay?(yesterday, assigns)
          # Afternoon is blocked if today is unavailable
          afternoon_blocked = date_unavailable_for_stay?(day, assigns)

          # Determine styles for blocks
          morning_style =
            if morning_blocked,
              do: get_unavailable_style(yesterday, assigns),
              else: :available

          afternoon_style =
            if afternoon_blocked,
              do: get_unavailable_style(day, assigns),
              else: :available

          classes =
            cond do
              morning_blocked && afternoon_blocked ->
                # Fully blocked. Use the style of the afternoon (current day).
                case afternoon_style do
                  :gray ->
                    "bg-zinc-100 text-zinc-400 border border-zinc-200 cursor-not-allowed opacity-60"

                  :blackout ->
                    "bg-red-800 text-red-100 border border-red-900 cursor-not-allowed"

                  :booked ->
                    "bg-red-200 text-red-900 border border-red-300 cursor-not-allowed"

                  _ ->
                    "bg-zinc-100 text-zinc-400 border border-zinc-200 cursor-not-allowed opacity-60"
                end

              !morning_blocked && !afternoon_blocked ->
                # Fully available
                # For Clear Lake day bookings, add spot-based background color
                spot_bg_class = get_clear_lake_spot_background(day, assigns)

                if spot_bg_class do
                  "#{spot_bg_class} text-zinc-900 border border-green-200 hover:opacity-80"
                else
                  "bg-green-50 text-zinc-900 border border-green-200 hover:bg-green-100"
                end

              morning_blocked && !afternoon_blocked ->
                # Check-out day (Blocked -> Available)
                spot_bg_class = get_clear_lake_spot_background(day, assigns)

                case morning_style do
                  :gray ->
                    # If yesterday was gray (past/scope), and today is available, use spot-based or green
                    bg_class =
                      if spot_bg_class, do: spot_bg_class, else: "bg-green-50"

                    "#{bg_class} text-zinc-900 border border-green-200 hover:opacity-80"

                  :blackout ->
                    if spot_bg_class == "bg-amber-50" do
                      "bg-gradient-to-r from-red-800 to-amber-50 text-zinc-900 border border-zinc-300"
                    else
                      if spot_bg_class == "bg-teal-50" do
                        "bg-gradient-to-r from-red-800 to-teal-50 text-zinc-900 border border-zinc-300"
                      else
                        "bg-gradient-to-r from-red-800 to-green-50 text-zinc-900 border border-zinc-300"
                      end
                    end

                  :booked ->
                    if spot_bg_class == "bg-amber-50" do
                      "bg-gradient-to-r from-red-200 to-amber-50 text-zinc-900 border border-zinc-300"
                    else
                      if spot_bg_class == "bg-teal-50" do
                        "bg-gradient-to-r from-red-200 to-teal-50 text-zinc-900 border border-zinc-300"
                      else
                        "bg-gradient-to-r from-red-200 to-green-50 text-zinc-900 border border-zinc-300"
                      end
                    end

                  _ ->
                    bg_class =
                      if spot_bg_class, do: spot_bg_class, else: "bg-green-50"

                    "#{bg_class} text-zinc-900 border border-green-200 hover:opacity-80"
                end

              !morning_blocked && afternoon_blocked ->
                # Check-in day (Available -> Blocked)
                case afternoon_style do
                  :gray ->
                    "bg-gradient-to-r from-green-50 to-zinc-100 text-zinc-900 border border-zinc-300"

                  :blackout ->
                    "bg-gradient-to-r from-green-50 to-red-800 text-zinc-900 border border-zinc-300"

                  :booked ->
                    "bg-gradient-to-r from-green-50 to-red-200 text-zinc-900 border border-zinc-300"

                  _ ->
                    "bg-gradient-to-r from-green-50 to-zinc-100 text-zinc-900 border border-zinc-300"
                end
            end

          # Add Today border
          if today?(day) do
            "#{base} #{classes} font-bold border-2 border-zinc-400"
          else
            "#{base} #{classes}"
          end
      end
    end
  end

  defp get_unavailable_style(day, assigns) do
    cond do
      Date.compare(day, assigns.min) == :lt ->
        :gray

      assigns.max && Date.compare(day, assigns.max) == :gt ->
        :gray

      assigns[:property] && assigns[:today] &&
          !date_selectable_cached?(
            assigns.property,
            day,
            assigns.today,
            assigns.seasons
          ) ->
        :gray

      true ->
        # Check availability map
        case unavailability_type(day, assigns) do
          :blackout -> :blackout
          :bookings -> :booked
          :other -> :gray
        end
    end
  end

  # Returns true if the date is "Unavailable" for staying the night.
  # This logic drives the red/green coloring.
  defp date_unavailable_for_stay?(day, assigns) do
    # Basic checks first
    if Date.compare(day, assigns.min) == :lt or
         (assigns.max && Date.compare(day, assigns.max) == :gt) do
      true
    else
      # Season check
      if assigns[:property] && assigns[:today] &&
           !date_selectable_cached?(
             assigns.property,
             day,
             assigns.today,
             assigns.seasons
           ) do
        true
      else
        # Availability Check
        availability = assigns.availability
        day_info = Map.get(availability, day)

        if day_info do
          cond do
            day_info.is_blacked_out ->
              true

            assigns.selected_booking_mode == :buyout ->
              # Unavailable for buyout if any room/day bookings exist or already bought out
              # For Tahoe: checks for any room bookings
              # For Clear Lake: checks for any day bookings
              !day_info.can_book_buyout

            assigns.selected_booking_mode == :day ->
              # Unavailable for day booking if full or bought out OR not enough spots for selected guests
              # Only applies to Clear Lake
              !day_info.can_book_day ||
                (assigns[:guests_count] &&
                   day_info.spots_available < assigns.guests_count)

            assigns.selected_booking_mode == :room ->
              # Unavailable for room booking if buyout exists
              # Only applies to Tahoe
              !day_info.can_book_room

            true ->
              true
          end
        else
          # Not in loaded range -> consider unavailable
          true
        end
      end
    end
  end

  # Date is disabled for SELECTION (clicking)
  defp date_disabled?(day, assigns) do
    # 1. Must be selectable for a stay (Green or Green-half)
    # BUT:
    # - If selecting check-in: Can select a "Check-out day" (Red->Green)? YES.
    # - If selecting check-out: Can select a "Check-in day" (Green->Red)? YES (if it's after check-in).
    # - Can select a fully Green day? YES.
    # - Can select a fully Red day? NO.

    yesterday = Date.add(day, -1)
    morning_blocked = date_unavailable_for_stay?(yesterday, assigns)
    afternoon_blocked = date_unavailable_for_stay?(day, assigns)

    fully_blocked = morning_blocked && afternoon_blocked

    if fully_blocked do
      # Special case: Check for blackout explicitly.
      # If it's blacked out, it's disabled.
      # If it's "Full" (Red), it's disabled.
      true
    else
      # It is at least partially green.

      # Other validation rules (Saturdays, etc.)
      if check_other_rules(
           day,
           assigns.checkin_date,
           assigns.state,
           assigns[:property],
           assigns[:availability],
           assigns[:selected_booking_mode],
           assigns[:seasons]
         ) do
        true
      else
        # If partial block, we need to check context
        case assigns.state do
          :set_start ->
            # Picking check-in date.
            # We arrive in afternoon. Afternoon must be free.
            # So 'afternoon_blocked' must be false.
            if afternoon_blocked do
              true
            else
              false
            end

          :set_end ->
            # Picking check-out date.
            # We leave in morning. Morning must be free (from *other* bookings).
            # Actually, if we are booking, we occupy the previous night.
            # So the day *we click* is the checkout day.
            # The night *before* this day must be available for us to book.
            # This is validated by valid_date_range?.
            # For the *click* itself, is the date disabled?
            # If I click Jan 3 as checkout, I am not staying Jan 3 night.
            # So Jan 3 afternoon availability doesn't matter.
            # Jan 3 morning availability matters?
            # If Jan 3 morning is "occupied" by someone else... I can't check out?
            # No, if someone else is there, I can't have stayed the night Jan 2-3.
            # valid_date_range? checks the *span*.
            # So for the click target, we mainly check if it's a valid date in general.
            false
        end
      end
    end
  end

  defp unavailability_reason(day, assigns) do
    case check_date_boundaries(day, assigns) do
      {:boundary, reason} -> reason
      :ok -> get_unavailability_reason_for_date(day, assigns)
    end
  end

  defp check_date_boundaries(day, assigns) do
    cond do
      Date.compare(day, assigns.min) == :lt ->
        {:boundary, "Past date"}

      assigns.max && Date.compare(day, assigns.max) == :gt ->
        {:boundary, "Too far in future"}

      assigns[:property] && assigns[:today] &&
          !date_selectable_cached?(
            assigns.property,
            day,
            assigns.today,
            assigns.seasons
          ) ->
        {:boundary, "Season closed"}

      true ->
        :ok
    end
  end

  defp get_unavailability_reason_for_date(day, assigns) do
    {is_blackout_start, is_blackout_end, morning_blocked, afternoon_blocked} =
      determine_blackout_start_end(day, assigns)

    type = unavailability_type(day, assigns)

    case type do
      :blackout ->
        get_blackout_reason(
          is_blackout_start,
          is_blackout_end,
          morning_blocked,
          afternoon_blocked
        )

      :bookings ->
        get_bookings_reason(day, assigns)

      :other ->
        get_other_reason(day, assigns)
    end
  end

  defp determine_blackout_start_end(day, assigns) do
    yesterday = Date.add(day, -1)
    morning_blocked = date_unavailable_for_stay?(yesterday, assigns)
    afternoon_blocked = date_unavailable_for_stay?(day, assigns)

    day_info = Map.get(assigns.availability, day)
    yesterday_info = Map.get(assigns.availability, yesterday)

    is_blackout_start =
      day_info && day_info.is_blacked_out &&
        (!yesterday_info || !yesterday_info.is_blacked_out)

    is_blackout_end =
      day_info && day_info.is_blacked_out &&
        (yesterday_info && yesterday_info.is_blacked_out) &&
        !afternoon_blocked

    {is_blackout_start, is_blackout_end, morning_blocked, afternoon_blocked}
  end

  defp get_blackout_reason(
         is_blackout_start,
         is_blackout_end,
         morning_blocked,
         afternoon_blocked
       ) do
    cond do
      is_blackout_start && !morning_blocked && afternoon_blocked ->
        "Check-in allowed"

      is_blackout_end && morning_blocked && !afternoon_blocked ->
        "Check-in allowed"

      true ->
        "Blackout date"
    end
  end

  defp get_bookings_reason(day, assigns) do
    day_info = Map.get(assigns.availability, day)

    if assigns.selected_booking_mode == :day && day_info &&
         day_info.spots_available < (assigns[:guests_count] || 1) do
      "Not enough spots"
    else
      "Booking already exists"
    end
  end

  defp get_other_reason(day, assigns) do
    if check_other_rules(
         day,
         assigns.checkin_date,
         assigns.state,
         assigns[:property],
         assigns[:availability],
         assigns[:selected_booking_mode],
         assigns[:seasons]
       ) do
      "Restricted (e.g. min/max stay)"
    else
      "Unavailable"
    end
  end

  defp unavailability_type(day, assigns) do
    day_info = Map.get(assigns.availability, day)

    if day_info do
      cond do
        day_info.is_blacked_out ->
          :blackout

        assigns.selected_booking_mode == :day &&
            (!day_info.can_book_day ||
               (assigns[:guests_count] &&
                  day_info.spots_available < assigns.guests_count)) ->
          :bookings

        assigns.selected_booking_mode == :buyout && !day_info.can_book_buyout ->
          :bookings

        assigns.selected_booking_mode == :room && !day_info.can_book_room ->
          :bookings

        true ->
          :other
      end
    else
      :other
    end
  end

  defp check_other_rules(
         day,
         checkin_date,
         state,
         property,
         _availability,
         _mode,
         seasons
       ) do
    # Saturday check-in rule (Tahoe only)
    if saturday_checkin?(day, property, state) do
      true
    else
      check_end_date_rules(day, checkin_date, state, property, seasons)
    end
  end

  defp saturday_checkin?(day, property, state) do
    Date.day_of_week(day) == 6 && property == :tahoe && state != :set_end
  end

  defp check_end_date_rules(day, checkin_date, state, property, seasons) do
    case state do
      :set_end when not is_nil(checkin_date) ->
        validate_checkout_date(day, checkin_date, property, seasons)

      _ ->
        false
    end
  end

  defp validate_checkout_date(day, checkin_date, property, seasons) do
    nights = Date.diff(day, checkin_date)
    max_nights = get_max_nights(property, checkin_date, seasons)

    cond do
      nights < 1 -> true
      nights > max_nights -> true
      saturday_checkout?(day, property) -> true
      true -> false
    end
  end

  defp saturday_checkout?(day, property) do
    Date.day_of_week(day) == 6 && property == :tahoe
  end

  defp get_max_nights(property, date, seasons) do
    if seasons && date do
      season = Ysc.Bookings.Season.find_season_for_date(seasons, date)
      Ysc.Bookings.Season.get_max_nights(season, property || :clear_lake)
    else
      case property do
        :tahoe -> 4
        :clear_lake -> 30
        _ -> 4
      end
    end
  end

  defp valid_date_range?(checkin_date, checkout_date, assigns) do
    # Validate that every night in the range is available
    # Range is checkin..(checkout-1)
    nights =
      Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

    all_available =
      Enum.all?(nights, fn night ->
        !date_unavailable_for_stay?(night, assigns)
      end)

    # Also check max nights / min nights / saturday rules
    rules_pass =
      !check_other_rules(
        checkout_date,
        checkin_date,
        :set_end,
        assigns[:property],
        nil,
        nil,
        assigns[:seasons]
      )

    all_available && rules_pass
  end

  defp send_date_update(socket) do
    attrs = %{
      id: socket.assigns.id,
      checkin_date: socket.assigns.checkin_date,
      checkout_date: socket.assigns.checkout_date
    }

    send(self(), {:availability_calendar_date_changed, attrs})
    socket
  end

  defp reload_availability_if_needed(socket, date) do
    # Logic to reload availability if month changed significantly
    # Reusing simplified logic: just reload if month changed
    today = socket.assigns.today
    start_date = Date.beginning_of_month(date) |> Date.add(-30)

    start_date =
      if Date.compare(start_date, today) == :lt, do: today, else: start_date

    end_date = Date.end_of_month(date) |> Date.add(30)

    property = socket.assigns[:property] || :clear_lake

    new_availability =
      case property do
        :clear_lake ->
          Bookings.get_clear_lake_daily_availability(start_date, end_date)

        :tahoe ->
          Bookings.get_tahoe_daily_availability(start_date, end_date)

        _ ->
          Bookings.get_clear_lake_daily_availability(start_date, end_date)
      end

    socket |> assign(:availability, new_availability)
  end

  defp prev_month_date(date),
    do: date |> Date.beginning_of_month() |> Date.add(-1)

  defp next_month_date(date), do: date |> Date.end_of_month() |> Date.add(1)

  defp today?(day), do: day == Date.utc_today()

  defp other_month?(day, current),
    do: Date.beginning_of_month(day) != Date.beginning_of_month(current)

  defp selected_start?(day, start), do: start && day == start
  defp selected_end?(day, end_d), do: end_d && day == end_d

  defp selected_range?(day, start, end_d),
    do:
      start && end_d && Date.compare(day, start) != :lt &&
        Date.compare(day, end_d) != :gt

  defp in_hover_range?(day, start, hover),
    do:
      start && hover && Date.compare(day, start) != :lt &&
        Date.compare(day, hover) != :gt

  defp date_selectable_cached?(property, date, today, seasons) do
    season =
      if seasons,
        do: Ysc.Bookings.Season.find_season_for_date(seasons, date),
        else: Ysc.Bookings.Season.for_date(property, date)

    if season && season.advance_booking_days && season.advance_booking_days > 0 do
      max_date = Date.add(today, season.advance_booking_days)
      Date.compare(date, max_date) != :gt
    else
      true
    end
  end

  defp availability_display(day, mode, availability, assigns) do
    info = Map.get(availability, day)

    # For Clear Lake day bookings, render visual indicator
    # Tahoe doesn't show per-guest-spot indicators (only buyout or room mode)
    if assigns[:property] == :clear_lake && mode == :day && info &&
         Map.has_key?(info, :spots_available) do
      render_clear_lake_spots_html(day, info, assigns)
    else
      availability_display_text(day, mode, availability, assigns)
    end
  end

  # sobelow_skip ["XSS.Raw"]
  defp render_clear_lake_spots_html(day, info, assigns) do
    spots_available = info.spots_available
    max_spots = 12
    spots_taken = max_spots - spots_available

    # Check if this date is selected (has blue background)
    is_selected =
      selected_start?(day, assigns.checkin_date) ||
        selected_end?(day, assigns.checkout_date) ||
        selected_range?(day, assigns.checkin_date, assigns.checkout_date)

    visual_state =
      cond do
        spots_available == 0 -> :full
        spots_available <= 3 -> :high_occupancy
        spots_available <= 6 -> :medium_occupancy
        true -> :low_occupancy
      end

    dots_html =
      for i <- 1..12 do
        dot_class =
          if i <= spots_taken do
            if visual_state == :full, do: "bg-red-500", else: "bg-amber-400"
          else
            # For selected dates, use lighter dots for better contrast
            if is_selected, do: "bg-white/80", else: "bg-teal-200"
          end

        "<div class=\"w-1 h-1 rounded-full #{dot_class}\"></div>"
      end
      |> Enum.join("")

    # Use white/light text for selected dates, otherwise use the visual state colors
    text_class =
      if is_selected do
        "text-white"
      else
        case visual_state do
          :full -> "text-red-600"
          :high_occupancy -> "text-amber-600"
          _ -> "text-zinc-600"
        end
      end

    spots_text = if spots_available != 1, do: "spots", else: "spot"

    """
    <div class="flex flex-col items-center gap-1">
      <div class="flex flex-wrap justify-center gap-0.5 max-w-[60px]">
        #{dots_html}
      </div>
      <span class="text-[10px] font-medium whitespace-nowrap #{text_class}">
        #{spots_available} #{spots_text}
      </span>
    </div>
    """
    |> Phoenix.HTML.raw()
  end

  defp availability_display_text(day, mode, availability, assigns) do
    info = Map.get(availability, day)

    if info do
      # Check if this is a valid checkout date in the current context
      is_valid_checkout =
        if assigns && assigns.state == :set_end && assigns.checkin_date do
          # If we are selecting an end date, and this date is after start date
          # And the previous night was available (meaning we can stay until this morning)
          Date.compare(day, assigns.checkin_date) == :gt &&
            !date_unavailable_for_stay?(Date.add(day, -1), assigns)
        else
          false
        end

      cond do
        info.is_blacked_out ->
          "Blackout"

        mode == :buyout && !info.can_book_buyout ->
          if is_valid_checkout do
            "Check-out only"
          else
            "Busy"
          end

        mode == :day && !info.can_book_day ->
          if is_valid_checkout do
            "Check-out only"
          else
            "Full"
          end

        mode == :room && !info.can_book_room ->
          if is_valid_checkout do
            "Check-out only"
          else
            "Unavailable"
          end

        mode == :day ->
          "#{info.spots_available} spots"

        mode == :buyout ->
          "Available"

        mode == :room ->
          "Available"

        true ->
          ""
      end
    else
      ""
    end
  end

  defp get_clear_lake_spot_background(day, assigns) do
    # Only apply spot-based background for Clear Lake day bookings
    # Tahoe doesn't use spot-based backgrounds (only buyout or room mode)
    if assigns[:property] == :clear_lake &&
         assigns[:selected_booking_mode] == :day do
      info = Map.get(assigns.availability, day)

      if info && info.spots_available do
        spots_available = info.spots_available

        cond do
          # Fully booked
          spots_available == 0 ->
            nil

          # Let the existing unavailable styling handle this

          # Low availability (1-3 spots)
          spots_available >= 1 && spots_available <= 3 ->
            "bg-amber-50"

          # High availability (9-12 spots)
          spots_available >= 9 && spots_available <= 12 ->
            "bg-teal-50"

          # Medium availability (4-8 spots) - use default green
          true ->
            nil
            # Use default green-50 background
        end
      else
        nil
      end
    else
      nil
    end
  end

  defp format_date(date) do
    %{
      date: date,
      month: Calendar.strftime(date, "%B %Y"),
      week_rows: week_rows(date)
    }
  end

  defp week_rows(date) do
    first =
      date
      |> Date.beginning_of_month()
      |> Date.beginning_of_week(@week_start_at)

    last = date |> Date.end_of_month() |> Date.end_of_week(@week_start_at)
    Date.range(first, last) |> Enum.map(& &1) |> Enum.chunk_every(7)
  end
end
