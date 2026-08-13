defmodule YscWeb.Components.AvailabilityCalendar do
  @moduledoc """
  LiveView component for displaying availability calendar with spot counts.

  Shows how many spots are available for each day and allows date selection.
  """
  use YscWeb, :live_component

  alias Ysc.Bookings

  @week_start_at :monday

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
          <button
            type="button"
            phx-target={@myself}
            phx-click="prev-month"
            class="p-1.5 text-zinc-400 hover:text-zinc-500 transition duration-300"
            aria-label="Previous month"
          >
            <.icon name="hero-arrow-left" />
          </button>

          <div class="flex flex-col items-center gap-1">
            <div class="font-semibold text-lg" id={"#{@id}-month-label"}>
              {@current.month}
            </div>
            <button
              id={"#{@id}-go-to-today"}
              type="button"
              phx-target={@myself}
              phx-click="today"
              disabled={showing_current_month?(@current.date, @today)}
              class={[
                "inline-flex items-center gap-1.5 px-3 py-1 text-xs font-semibold border rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2",
                if(showing_current_month?(@current.date, @today),
                  do:
                    "text-zinc-400 bg-zinc-50 border-zinc-200 cursor-not-allowed opacity-60",
                  else:
                    "text-zinc-700 bg-zinc-100 hover:bg-zinc-200 border-zinc-300"
                )
              ]}
              aria-label={
                if showing_current_month?(@current.date, @today) do
                  "Already showing #{Calendar.strftime(@today, "%B %Y")}"
                else
                  "Go to current month, #{Calendar.strftime(@today, "%B %Y")}"
                end
              }
            >
              <.icon name="hero-calendar-days" class="w-4 h-4" aria-hidden="true" />
              Today
            </button>
          </div>

          <button
            type="button"
            phx-target={@myself}
            phx-click="next-month"
            class="p-1.5 text-zinc-400 hover:text-zinc-500 transition duration-300"
            aria-label="Next month"
          >
            <.icon name="hero-arrow-right" />
          </button>
        </div>

        <div
          id={"#{@id}_calendar_days"}
          class="isolate text-sm overflow-visible relative"
          phx-hook="DaterangeHover"
          phx-target={@myself}
          data-component-id={@id}
          role="grid"
          aria-labelledby={"#{@id}-month-label"}
        >
          <div
            role="row"
            class="grid grid-cols-7 text-xs leading-6 text-zinc-800 font-semibold mb-2"
          >
            <div
              :for={label <- week_day_header_labels(@current.week_rows)}
              role="columnheader"
              class="text-center font-semibold"
            >
              {label}
            </div>
          </div>
          <div
            :for={week <- @current.week_rows}
            role="row"
            class="grid grid-cols-7 gap-1 mb-1"
          >
            <.day_cell
              :for={day <- week}
              day={day}
              id={@id}
              myself={@myself}
              calendar={assigns}
            />
          </div>
        </div>

        <div
          class="mt-8 flex flex-wrap gap-4 text-xs text-zinc-600"
          role="list"
          aria-label="Calendar legend"
        >
          <div class="flex items-center gap-2" role="listitem">
            <div
              class="w-8 h-5 bg-green-50 border border-dashed border-green-700 rounded flex items-center justify-center text-[9px] font-bold text-green-900"
              aria-hidden="true"
            >
              OK
            </div>
            <span>Available</span>
          </div>
          <div class="flex items-center gap-2" role="listitem">
            <div
              class="w-8 h-5 bg-blue-500 rounded ring-2 ring-blue-200 flex items-center justify-center text-[9px] font-bold text-white"
              aria-hidden="true"
            >
              Sel
            </div>
            <span>Selected dates</span>
          </div>
          <div class="flex items-center gap-2" role="listitem">
            <div
              class="w-8 h-5 bg-red-800 border border-red-900 rounded flex items-center justify-center text-[9px] font-bold text-red-100"
              aria-hidden="true"
            >
              X
            </div>
            <span>Already booked</span>
          </div>
          <div class="flex items-center gap-2" role="listitem">
            <div
              class="w-8 h-5 bg-red-200 border border-red-400 rounded flex items-center justify-center text-[9px] font-bold text-red-900 line-through"
              aria-hidden="true"
            >
              --
            </div>
            <span>Closed (maintenance or club event)</span>
          </div>
          <div class="flex items-center gap-2" role="listitem">
            <div
              class="w-8 h-5 bg-gradient-to-r from-red-200 to-green-50 border border-zinc-400 rounded flex items-center justify-center text-[8px] font-bold text-zinc-800"
              aria-hidden="true"
            >
              In
            </div>
            <span>Valid check-in day</span>
          </div>
          <div class="flex items-center gap-2" role="listitem">
            <div
              class="w-8 h-5 bg-gradient-to-r from-green-50 to-red-200 border border-zinc-400 rounded flex items-center justify-center text-[8px] font-bold text-zinc-800"
              aria-hidden="true"
            >
              Out
            </div>
            <span>Valid check-out day</span>
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
      cond do
        is_nil(socket.assigns[:today]) ->
          today

        socket.assigns[:today] != today ->
          today

        socket.assigns[:current] && socket.assigns.current[:date] ->
          socket.assigns.current.date

        true ->
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

    new_availability_version = Map.get(assigns, :availability_cache_version)

    availability_version_changed =
      new_availability_version != nil &&
        new_availability_version != socket.assigns[:availability_cache_version]

    property = assigns[:property] || :clear_lake

    availability =
      if !has_valid_availability || booking_mode_changed ||
           availability_version_changed do
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

    # Prefer fresh seasons from the parent LiveView (after SeasonCache bust).
    # Fall back to prior assigns / DB only when the parent did not pass seasons.
    seasons =
      cond do
        Map.has_key?(assigns, :seasons) and is_list(assigns.seasons) ->
          assigns.seasons

        socket.assigns[:seasons] && socket.assigns[:property] == property ->
          socket.assigns[:seasons]

        true ->
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
      |> assign(
        :availability_cache_version,
        new_availability_version || socket.assigns[:availability_cache_version]
      )
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
    today = socket.assigns.today
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

  # --- Render helpers ---

  defp day_cell(assigns) do
    calendar = assigns.calendar
    day = assigns.day
    date_str = Calendar.strftime(day, "%Y-%m-%d")
    tooltip? = show_day_tooltip?(day, calendar)
    tooltip_text = unavailability_reason(day, calendar)
    interactive_disabled? = day_interactive_disabled?(day, calendar)
    status_label = day_status_label(day, calendar)

    assigns =
      assigns
      |> assign(:date_str, date_str)
      |> assign(:tooltip?, tooltip?)
      |> assign(:interactive_disabled?, interactive_disabled?)
      |> assign(:day_classes, day_classes(day, calendar))
      |> assign(:aria_label, day_aria_label(day, calendar, tooltip?))
      |> assign(:tabindex, day_tabindex(day, calendar))
      |> assign(:show_status?, !other_month?(day, calendar.current.date))
      |> assign(:status_label, status_label)
      |> assign(:has_detail?, day_has_detail?(day, calendar))
      |> assign(:detail_label, day_detail_label(day, calendar))
      |> assign(:tooltip_text, tooltip_text)
      |> assign(:is_today?, today?(day, calendar.today))
      |> assign(:tooltip_id, day_tooltip_id(assigns.id, day))
      |> assign(:day_number, Calendar.strftime(day, "%d"))
      |> assign(:show_ok_badge?, day_shows_ok_badge?(day, calendar))
      |> assign(
        :show_unavailable_icon?,
        day_shows_unavailable_icon?(day, calendar)
      )
      |> assign(:unavailable_icon_class, unavailable_icon_class(day, calendar))

    ~H"""
    <div
      role="gridcell"
      class="relative overflow-visible"
      data-day={@date_str}
    >
      <div class={["relative overflow-visible", @tooltip? && "group"]}>
        <button
          type="button"
          id={"#{@id}-day-#{@date_str}"}
          data-calendar-day
          phx-target={@myself}
          phx-click="pick-date"
          phx-value-date={@date_str}
          tabindex={@tabindex}
          class={@day_classes}
          aria-label={@aria_label}
          aria-disabled={if(@interactive_disabled?, do: "true")}
          aria-current={if(@is_today?, do: "date", else: false)}
          aria-describedby={if(@tooltip?, do: @tooltip_id, else: nil)}
        >
          <span
            :if={@show_ok_badge?}
            class="absolute top-0.5 right-0.5 text-[8px] font-bold text-green-800 leading-none pointer-events-none"
            aria-hidden="true"
          >
            OK
          </span>
          <.icon
            :if={@show_unavailable_icon?}
            name="hero-x-mark"
            class={[
              "absolute top-0.5 right-0.5 w-3 h-3 pointer-events-none",
              @unavailable_icon_class
            ]}
            aria-hidden="true"
          />
          <span class="text-sm font-medium" aria-hidden="true">
            {@day_number}
          </span>
          <div
            :if={@show_status? && (@status_label != "" || @has_detail?)}
            class="text-xs mt-1 leading-tight"
            aria-hidden="true"
          >
            <span :if={@status_label != ""} class="block text-[10px] font-semibold">
              {@status_label}
            </span>
            <span :if={@has_detail?}>
              {@detail_label}
            </span>
          </div>
        </button>
        <span
          :if={@tooltip?}
          id={@tooltip_id}
          role="tooltip"
          class={[
            "absolute transition-opacity mt-2 top-full left-1/2 transform -translate-x-1/2 duration-200 opacity-0 z-[100] text-xs font-medium text-zinc-100 bg-zinc-900 rounded-lg shadow-lg px-4 py-2 block rounded tooltip group-hover:opacity-100 group-focus-within:opacity-100 whitespace-normal pointer-events-none",
            "min-w-[200px] max-w-[400px]",
            "text-left"
          ]}
        >
          {@tooltip_text}
        </span>
      </div>
    </div>
    """
  end

  defp week_day_header_labels(week_rows) do
    week_rows
    |> List.first()
    |> Enum.map(&Calendar.strftime(&1, "%a"))
  end

  defp day_tooltip_id(calendar_id, day) do
    "#{calendar_id}-tooltip-#{Calendar.strftime(day, "%Y-%m-%d")}"
  end

  defp show_day_tooltip?(day, assigns) do
    !other_month?(day, assigns.current.date) &&
      day_interactive_disabled?(day, assigns)
  end

  defp day_interactive_disabled?(day, assigns) do
    date_disabled?(day, assigns) && !selected_start?(day, assigns.checkin_date)
  end

  defp day_tabindex(day, assigns) do
    if Date.compare(day, calendar_focus_day(assigns)) == :eq, do: 0, else: -1
  end

  defp calendar_focus_day(assigns) do
    visible_month = assigns.current.date

    cond do
      assigns.checkout_date &&
          !other_month?(assigns.checkout_date, visible_month) ->
        assigns.checkout_date

      assigns.checkin_date &&
          !other_month?(assigns.checkin_date, visible_month) ->
        assigns.checkin_date

      today_in_visible_month?(assigns) ->
        assigns.today

      true ->
        assigns.current.week_rows
        |> Enum.flat_map(& &1)
        |> Enum.find(fn day -> !other_month?(day, visible_month) end)
    end
  end

  defp today_in_visible_month?(assigns) do
    assigns.today &&
      Date.beginning_of_month(assigns.today) ==
        Date.beginning_of_month(assigns.current.date)
  end

  defp day_shows_ok_badge?(day, assigns) do
    !other_month?(day, assigns.current.date) &&
      !selection_restricted?(day, assigns) &&
      day_visual_state(day, assigns) in [
        :available,
        :check_in_allowed,
        :check_out_allowed
      ]
  end

  defp day_shows_unavailable_icon?(day, assigns) do
    !other_month?(day, assigns.current.date) &&
      day_visual_state(day, assigns) in [
        :fully_blocked_blackout,
        :fully_blocked_booked,
        :fully_blocked_gray
      ]
  end

  defp unavailable_icon_class(day, assigns) do
    case day_visual_state(day, assigns) do
      :fully_blocked_blackout -> "text-red-100"
      :fully_blocked_booked -> "text-red-900"
      _ -> "text-zinc-500"
    end
  end

  # --- Helpers ---

  defp day_visual_state(day, assigns) do
    cond do
      other_month?(day, assigns.current.date) ->
        :other_month

      selected_start?(day, assigns.checkin_date) ->
        :selected_start

      selected_end?(day, assigns.checkout_date) ->
        :selected_end

      assigns.state == :set_end && assigns.hover_checkout_date &&
          day == assigns.hover_checkout_date ->
        :selected_end

      selected_range?(day, assigns.checkin_date, assigns.checkout_date) ->
        :in_range

      assigns.state == :set_end &&
          in_hover_range?(
            day,
            assigns.checkin_date,
            assigns.hover_checkout_date
          ) ->
        :in_range

      true ->
        day_availability_state(day, assigns)
    end
  end

  defp day_availability_state(day, assigns) do
    yesterday = Date.add(day, -1)
    morning_blocked = date_unavailable_for_stay?(yesterday, assigns)
    afternoon_blocked = date_unavailable_for_stay?(day, assigns)

    cond do
      morning_blocked && afternoon_blocked ->
        case get_unavailable_style(day, assigns) do
          :blackout -> :fully_blocked_blackout
          :booked -> :fully_blocked_booked
          _ -> :fully_blocked_gray
        end

      !morning_blocked && !afternoon_blocked ->
        :available

      morning_blocked && !afternoon_blocked ->
        :check_out_allowed

      !morning_blocked && afternoon_blocked ->
        :check_in_allowed
    end
  end

  defp day_status_label(day, assigns) do
    case day_visual_state(day, assigns) do
      :selected_start ->
        "Start"

      :selected_end ->
        "End"

      :in_range ->
        "Selected"

      :fully_blocked_blackout ->
        "Closed"

      :fully_blocked_booked ->
        "Booked"

      :fully_blocked_gray ->
        "Unavailable"

      :check_in_allowed ->
        ""

      :check_out_allowed ->
        ""

      :available ->
        saturday_rule_status_label(day, assigns) ||
          if(today?(day, assigns.today), do: "Today", else: "")

      _ ->
        saturday_rule_status_label(day, assigns) || ""
    end
  end

  defp saturday_rule_status_label(day, assigns) do
    property = assigns[:property]

    cond do
      assigns.state == :set_end && saturday_checkout?(day, property) ->
        "No check-out"

      assigns.state == :set_end &&
          saturday_checkin_requires_sunday_checkout?(day, assigns) ->
        "Sun only"

      true ->
        nil
    end
  end

  defp saturday_checkin_requires_sunday_checkout?(day, assigns) do
    checkin = assigns.checkin_date
    property = assigns[:property]

    checkin &&
      property == :tahoe &&
      Date.day_of_week(checkin) == 6 &&
      Date.compare(day, checkin) == :gt &&
      not (Date.diff(day, checkin) == 1 && Date.day_of_week(day) == 7)
  end

  defp day_detail_label(day, assigns) do
    availability_display(
      day,
      assigns.selected_booking_mode,
      assigns.availability,
      assigns
    )
  end

  defp day_has_detail?(day, assigns) do
    availability_display_text(
      day,
      assigns.selected_booking_mode,
      assigns.availability,
      assigns
    ) != ""
  end

  defp day_aria_label(day, assigns, has_tooltip?) do
    date_label = Calendar.strftime(day, "%A, %B %d, %Y")
    status = day_aria_status(day, assigns)

    parts =
      [date_label, status]
      |> Enum.reject(&(&1 in [nil, ""]))

    if date_disabled?(day, assigns) && !other_month?(day, assigns.current.date) &&
         !has_tooltip? do
      parts ++ [unavailability_reason(day, assigns)]
    else
      parts
    end
    |> Enum.join(", ")
  end

  defp day_aria_status(day, assigns) do
    status = day_status_label(day, assigns)

    detail =
      availability_display_text(
        day,
        assigns.selected_booking_mode,
        assigns.availability,
        assigns
      )

    cond do
      status != "" && detail != "" && status != detail ->
        "#{status}, #{detail}"

      status != "" ->
        status

      detail != "" ->
        detail

      other_month?(day, assigns.current.date) ->
        ""

      true ->
        day_aria_availability_summary(day, assigns)
    end
  end

  defp day_aria_availability_summary(day, assigns) do
    case day_visual_state(day, assigns) do
      :available -> "Available"
      :fully_blocked_blackout -> "Not available for booking"
      :fully_blocked_booked -> "Booked"
      :fully_blocked_gray -> "Unavailable"
      :check_in_allowed -> "Check-in allowed"
      :check_out_allowed -> "Check-out allowed"
      _ -> ""
    end
  end

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
            if selection_restricted?(day, assigns) do
              selection_restricted_classes()
            else
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
                  "bg-green-50 text-zinc-900 border border-green-200 hover:bg-green-100"

                morning_blocked && !afternoon_blocked ->
                  # Check-out day (Blocked -> Available)
                  case morning_style do
                    :gray ->
                      "bg-green-50 text-zinc-900 border border-green-200 hover:opacity-80"

                    :blackout ->
                      "bg-gradient-to-r from-red-800 to-green-50 text-zinc-900 border border-zinc-300"

                    :booked ->
                      "bg-gradient-to-r from-red-200 to-green-50 text-zinc-900 border border-zinc-300"

                    _ ->
                      "bg-green-50 text-zinc-900 border border-green-200 hover:opacity-80"
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
            end

          # Add Today border
          if today?(day, assigns.today) do
            "#{base} #{classes} font-bold border-2 border-zinc-400"
          else
            "#{base} #{classes}"
          end
      end
    end
  end

  defp selection_restricted_classes do
    "bg-zinc-100 text-zinc-400 border border-zinc-200 cursor-not-allowed opacity-60"
  end

  defp selection_restricted?(day, assigns) do
    assigns.state == :set_end &&
      assigns.checkin_date &&
      !selected_start?(day, assigns.checkin_date) &&
      !fully_blocked_for_stay?(day, assigns) &&
      !partial_availability_day?(day, assigns) &&
      checkout_selection_blocked?(day, assigns)
  end

  defp partial_availability_day?(day, assigns) do
    yesterday = Date.add(day, -1)
    morning_blocked = date_unavailable_for_stay?(yesterday, assigns)
    afternoon_blocked = date_unavailable_for_stay?(day, assigns)
    morning_blocked != afternoon_blocked
  end

  defp checkout_selection_blocked?(day, assigns) do
    check_other_rules(
      day,
      assigns.checkin_date,
      assigns.state,
      assigns[:property],
      assigns[:availability],
      assigns[:selected_booking_mode],
      assigns[:seasons]
    ) ||
      (Date.compare(day, assigns.checkin_date) == :gt &&
         !valid_date_range?(assigns.checkin_date, day, assigns))
  end

  defp fully_blocked_for_stay?(day, assigns) do
    yesterday = Date.add(day, -1)

    date_unavailable_for_stay?(yesterday, assigns) &&
      date_unavailable_for_stay?(day, assigns)
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
              # Unavailable for day booking if blacked out or has a buyout
              !day_info.can_book_day

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
            checkin = assigns.checkin_date

            cond do
              is_nil(checkin) ->
                false

              Date.compare(day, checkin) != :gt ->
                false

              !valid_date_range?(checkin, day, assigns) ->
                true

              true ->
                false
            end
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
        "Not available for booking"
    end
  end

  defp get_bookings_reason(day, assigns) do
    cond do
      winter_buyout_blocked?(day, assigns) ->
        "Entire cabin is not available in winter"

      assigns[:selected_booking_mode] == :buyout ->
        "Other members already have reservations on this date. Choose different dates or book a group or room stay instead."

      true ->
        "Another member has already booked this date. Try different dates, or choose a shared stay if that's available."
    end
  end

  defp get_other_reason(day, assigns) do
    selection_rule_reason(day, assigns) ||
      cond do
        winter_buyout_blocked?(day, assigns) ->
          "Entire cabin is not available in winter"

        check_other_rules(
          day,
          assigns.checkin_date,
          assigns.state,
          assigns[:property],
          assigns[:availability],
          assigns[:selected_booking_mode],
          assigns[:seasons]
        ) ->
          "Restricted (e.g. min/max stay)"

        true ->
          "Unavailable"
      end
  end

  defp winter_buyout_blocked?(day, assigns) do
    assigns[:property] == :tahoe &&
      assigns[:selected_booking_mode] == :buyout &&
      is_list(assigns[:seasons]) &&
      not Ysc.Bookings.Season.buyout_allowed_on_date?(assigns.seasons, day)
  end

  defp selection_rule_reason(day, assigns) do
    property = assigns[:property]
    state = assigns.state
    checkin_date = assigns.checkin_date
    seasons = assigns[:seasons]

    cond do
      state == :set_end && saturday_checkout?(day, property) ->
        "Check-outs are not permitted on Saturdays"

      state == :set_end &&
          saturday_checkin_requires_sunday_checkout?(day, assigns) ->
        "Saturday check-ins must check out on Sunday"

      state == :set_end && checkin_date &&
          Date.compare(day, checkin_date) == :gt ->
        nights = Date.diff(day, checkin_date)
        max_nights = get_max_nights(property, checkin_date, seasons)

        if nights > max_nights do
          "Maximum #{max_nights} nights allowed per booking"
        end

      true ->
        nil
    end
  end

  defp unavailability_type(day, assigns) do
    day_info = Map.get(assigns.availability, day)

    if day_info do
      cond do
        day_info.is_blacked_out ->
          :blackout

        assigns.selected_booking_mode == :day && day_info.has_buyout ->
          :bookings

        assigns.selected_booking_mode == :day && !day_info.can_book_day ->
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
    # Saturday check-in is allowed; checkout rules enforce Sat→Sun / weekend span
    check_end_date_rules(day, checkin_date, state, property, seasons)
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
      nights < 1 ->
        true

      nights > max_nights ->
        true

      saturday_checkout?(day, property) ->
        true

      property == :tahoe && Date.day_of_week(checkin_date) == 6 &&
          not (nights == 1 && Date.day_of_week(day) == 7) ->
        true

      property == :tahoe && saturday_without_sunday?(checkin_date, day) ->
        true

      true ->
        false
    end
  end

  defp saturday_without_sunday?(checkin_date, checkout_date) do
    days =
      Date.range(checkin_date, checkout_date) |> Enum.map(&Date.day_of_week/1)

    6 in days and 7 not in days
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

  defp today?(day, today), do: today && day == today

  defp showing_current_month?(current_date, today) do
    today &&
      Date.beginning_of_month(current_date) == Date.beginning_of_month(today)
  end

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

    # For Clear Lake day bookings, show how many guests are registered
    if assigns[:property] == :clear_lake && mode == :day && info &&
         Map.has_key?(info, :day_bookings_count) do
      booked = info.day_bookings_count

      is_selected =
        selected_start?(day, assigns.checkin_date) ||
          selected_end?(day, assigns.checkout_date) ||
          selected_range?(day, assigns.checkin_date, assigns.checkout_date)

      text_class = if is_selected, do: "text-white/80", else: "text-zinc-500"

      if booked > 0 do
        assigns = %{booked: booked, text_class: text_class}

        ~H"""
        <span class={["text-xs font-medium", @text_class]}>{@booked} booked</span>
        """
      else
        ""
      end
    else
      availability_display_text(day, mode, availability, assigns)
    end
  end

  defp availability_display_text(day, mode, availability, assigns) do
    info = Map.get(availability, day)

    if info do
      is_valid_checkout = valid_checkout_date?(day, assigns)

      cond do
        is_valid_checkout && checkout_partially_blocked?(mode, info) ->
          "Check-out only"

        is_valid_checkout ->
          ""

        info.is_blacked_out ->
          "Not available"

        mode == :buyout && !info.can_book_buyout ->
          "Partially booked"

        mode == :day && !info.can_book_day ->
          "Unavailable"

        mode == :room && !info.can_book_room ->
          "Unavailable"

        mode == :day ->
          if info.day_bookings_count > 0,
            do: "#{info.day_bookings_count} booked",
            else: ""

        mode == :buyout ->
          ""

        mode == :room ->
          ""

        true ->
          ""
      end
    else
      ""
    end
  end

  defp valid_checkout_date?(day, assigns) do
    assigns.state == :set_end && assigns.checkin_date &&
      Date.compare(day, assigns.checkin_date) == :gt &&
      !date_unavailable_for_stay?(Date.add(day, -1), assigns)
  end

  defp checkout_partially_blocked?(mode, info) do
    info.is_blacked_out ||
      (mode == :buyout && !info.can_book_buyout) ||
      (mode == :day && !info.can_book_day) ||
      (mode == :room && !info.can_book_room)
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
