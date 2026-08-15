defmodule YscWeb.Components.DateRangePicker do
  @moduledoc """
  LiveView component for selecting date ranges.

  Provides an interactive calendar interface for selecting start and end dates.
  """
  use YscWeb, :live_component

  @week_start_at :monday
  @fsm %{
    set_start: :set_end,
    set_end: :reset,
    reset: :set_start
  }
  @initial_state :set_start

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, :date_disable_ctx, date_disable_ctx_from_assigns(assigns))

    ~H"""
    <div
      id={Map.get(assigns, :id, @id)}
      class="date-range-picker"
    >
      <.input field={@start_date_field} type="hidden" />
      <.input :if={@is_range?} field={@end_date_field} type="hidden" />
      <div
        class="relative w-full lg:w-80"
        phx-click="open-calendar"
        phx-target={@myself}
      >
        <.input
          id={"#{@id}_display_value"}
          name={"#{@id}_display_value"}
          required={@required}
          readonly
          type="text"
          class="w-full"
          label={@label}
          value={date_range_display(@range_start, @range_end, @is_range?)}
        />
        <.icon
          name="hero-calendar"
          class="absolute top-10 right-3 mt-0.5 flex text-zinc-600"
        />
      </div>

      <div
        :if={@calendar?}
        id={"#{@id}_calendar"}
        class="absolute z-50 w-96 shadow transition duration-300"
        phx-click-away="close-calendar"
        phx-target={@myself}
      >
        <div
          id="calendar_background"
          class="w-full bg-white rounded-md shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none p-3"
        >
          <div id="calendar_header" class="flex justify-between items-center">
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
              <div id="current_month_year" class="font-semibold">
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
            id="calendar_weekdays"
            class="text-center mt-6 grid grid-cols-7 text-xs leading-6 text-zinc-800"
          >
            <div :for={week_day <- List.first(@current.week_rows)}>
              {Calendar.strftime(week_day, "%a")}
            </div>
          </div>

          <div
            id={"calendar_days_#{String.replace(@current.month, " ", "-")}"}
            class="relative z-20 isolate mt-2 grid grid-cols-7 gap-px text-sm overflow-visible"
            phx-hook="DaterangeHover"
            phx-target={@myself}
            data-component-id={@id}
          >
            <div
              :for={day <- Enum.flat_map(@current.week_rows, & &1)}
              class={[
                "relative overflow-visible",
                if(
                  date_picker_show_tooltip?(
                    day,
                    @date_disable_ctx,
                    active_date_tooltips(@date_disable_ctx)
                  ),
                  do: "group",
                  else: ""
                )
              ]}
            >
              <button
                type="button"
                phx-target={@myself}
                phx-click="pick-date"
                phx-value-date={Calendar.strftime(day, "%Y-%m-%d") <> "T00:00:00Z"}
                disabled={
                  date_disabled?(
                    day,
                    @date_disable_ctx,
                    active_date_tooltips(@date_disable_ctx)
                  )
                }
                class={[
                  "calendar-day overflow-hidden py-1.5 h-12 rounded w-auto focus:z-10 w-full transition duration-300 flex flex-col items-center justify-center",
                  today?(day, @today) &&
                    "font-bold border-2 border-zinc-500 rounded",
                  date_disabled?(
                    day,
                    @date_disable_ctx,
                    active_date_tooltips(@date_disable_ctx)
                  ) &&
                    "text-zinc-300 cursor-not-allowed opacity-50",
                  !date_disabled?(
                    day,
                    @date_disable_ctx,
                    active_date_tooltips(@date_disable_ctx)
                  ) &&
                    !before_min_date?(day, @min) &&
                    "hover:bg-blue-300 hover:border hover:border-blue-500",
                  other_month?(day, @current.date) && "text-zinc-500",
                  selected_range?(day, @range_start, @hover_range_end || @range_end) &&
                    "hover:bg-blue-500 bg-blue-500 text-zinc-100 ring-2 ring-blue-200"
                ]}
                aria-label={
                  date_range_day_aria_label(
                    day,
                    @range_start,
                    @range_end,
                    @hover_range_end,
                    @today,
                    @date_disable_ctx
                  )
                }
                aria-current={if(today?(day, @today), do: "date", else: false)}
                aria-describedby={
                  if(
                    date_picker_show_tooltip?(
                      day,
                      @date_disable_ctx,
                      active_date_tooltips(@date_disable_ctx)
                    ),
                    do: date_picker_tooltip_id(@id, day),
                    else: nil
                  )
                }
              >
                <span
                  class="mx-auto flex h-6 w-6 items-center justify-center rounded-full"
                  aria-hidden="true"
                >
                  {Calendar.strftime(day, "%d")}
                </span>
                <span
                  :if={
                    date_range_day_visible_label(
                      day,
                      @range_start,
                      @range_end,
                      @hover_range_end,
                      @today,
                      @date_disable_ctx
                    ) != ""
                  }
                  class="text-[10px] font-semibold leading-tight"
                  aria-hidden="true"
                >
                  {date_range_day_visible_label(
                    day,
                    @range_start,
                    @range_end,
                    @hover_range_end,
                    @today,
                    @date_disable_ctx
                  )}
                </span>
              </button>
              <span
                :if={
                  date_picker_show_tooltip?(
                    day,
                    @date_disable_ctx,
                    active_date_tooltips(@date_disable_ctx)
                  )
                }
                id={date_picker_tooltip_id(@id, day)}
                role="tooltip"
                class={[
                  "absolute transition-opacity mt-2 top-full left-1/2 transform -translate-x-1/2 duration-200 opacity-0 z-[100] text-xs font-medium text-zinc-100 bg-zinc-900 rounded-lg shadow-lg px-4 py-2 block rounded tooltip group-hover:opacity-100 group-focus-within:opacity-100 whitespace-normal pointer-events-none",
                  "max-w-[400px]",
                  "text-left"
                ]}
              >
                {date_picker_tooltip_text(
                  day,
                  @date_disable_ctx,
                  active_date_tooltips(@date_disable_ctx)
                )}
              </span>
            </div>
          </div>

          <div class="relative z-0 flex w-full justify-end items-center mt-4 space-x-2">
            <button
              :if={@range_start || @range_end}
              type="button"
              phx-click="reset-dates"
              phx-target={@myself}
              class="inline-flex items-center px-3 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-colors"
            >
              <.icon name="hero-x-mark" class="w-4 h-4 me-1" /> Reset
            </button>
            <div :if={!@range_start && !@range_end}></div>
            <.button type="button" phx-click="close-calendar" phx-target={@myself}>
              {select_button_text(@range_start, @range_end)}
            </.button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    current_date = Date.utc_today()

    {
      :ok,
      socket
      |> assign(:calendar?, false)
      |> assign(:current, format_date(current_date))
      |> assign(:is_range?, true)
      |> assign(:range_start, nil)
      |> assign(:range_end, nil)
      |> assign(:hover_range_end, nil)
      |> assign(:readonly, false)
      |> assign(:disabled, false)
      |> assign(:selected_date, nil)
      |> assign(:form, nil)
    }
  end

  @impl true
  def update(assigns, socket) do
    injected_today = assigns[:today]
    today = injected_today || Date.utc_today()

    # Injected today takes priority; otherwise preserve current date if we have one
    current_date =
      injected_today ||
        (socket.assigns[:current] && socket.assigns.current[:date]) ||
        Date.utc_today()

    # While the calendar is open, keep in-progress picks. Parent re-renders
    # (form auto-save, PubSub, etc.) used to overwrite range_* from the form and
    # could leave state at :set_end/:reset so the next click was validated
    # against stale dates and silently ignored.
    calendar_open? = socket.assigns[:calendar?] == true

    {range_start, range_end, state} =
      if calendar_open? do
        {socket.assigns.range_start, socket.assigns.range_end,
         socket.assigns[:state] || @initial_state}
      else
        {from_str!(assigns.start_date_field.value),
         from_str!(end_value(assigns)), @initial_state}
      end

    {
      :ok,
      socket
      |> assign(assigns)
      |> assign(:current, format_date(current_date))
      |> assign(:range_start, range_start)
      |> assign(:range_end, range_end)
      |> assign(:max, assigns[:max])
      |> assign(:property, assigns[:property])
      |> assign(:today, today)
      |> assign(:date_tooltips, assigns[:date_tooltips] || %{})
      |> assign(
        :checkout_date_tooltips,
        assigns[:checkout_date_tooltips] || %{}
      )
      |> assign(
        :blocked_stay_dates,
        assigns[:blocked_stay_dates] || %{}
      )
      |> assign(:max_nights, assigns[:max_nights] || 4)
      |> assign(:min_nights, assigns[:min_nights] || 1)
      |> assign(:seasons, assigns[:seasons])
      |> assign(:allow_saturdays, assigns[:allow_saturdays] || false)
      |> assign(:state, state)
    }
  end

  @impl true
  def handle_event("open-calendar", _, socket) do
    if socket.assigns[:disabled] do
      {:noreply, socket}
    else
      # Focus the month on the current selection (or today) and always start a
      # fresh start-date pick so earlier days are not stuck disabled in :set_end.
      focus_date =
        case socket.assigns.range_start do
          nil -> socket.assigns.today || Date.utc_today()
          start -> DateTime.to_date(to_datetime(start))
        end

      {:noreply,
       socket
       |> assign(:calendar?, true)
       |> assign(:state, @initial_state)
       |> assign(:hover_range_end, nil)
       |> assign(:current, format_date(focus_date))}
    end
  end

  @impl true
  def handle_event(
        "close-calendar",
        _,
        %{assigns: %{range_start: nil, range_end: nil}} = socket
      ) do
    {:noreply, socket |> assign(:calendar?, false)}
  end

  @impl true
  def handle_event("close-calendar", _, socket) do
    range_start = finalize_date(socket.assigns.range_start, socket.assigns)

    range_end =
      finalize_date(
        socket.assigns.range_end || socket.assigns.range_start,
        socket.assigns
      )

    {range_start, range_end} = normalize_sorted_range(range_start, range_end)

    attrs = %{
      id: socket.assigns.id,
      start_date: range_start,
      end_date: range_end,
      form: socket.assigns.form
    }

    send(self(), {:updated_event, attrs})

    {
      :noreply,
      socket
      |> assign(:calendar?, false)
      |> assign(:range_start, range_start)
      |> assign(:range_end, range_end)
      |> assign(
        :end_date_field,
        set_field_value(socket.assigns, :end_date_field, range_end)
      )
      |> assign(
        :start_date_field,
        set_field_value(socket.assigns, :start_date_field, range_start)
      )
      |> assign(:state, @initial_state)
    }
  end

  @impl true
  def handle_event("today", _, socket) do
    new_date = socket.assigns.today
    {:noreply, socket |> assign(:current, format_date(new_date))}
  end

  @impl true
  def handle_event("prev-month", _, socket) do
    new_date = new_date(socket.assigns)
    {:noreply, socket |> assign(:current, format_date(new_date))}
  end

  @impl true
  def handle_event("next-month", _, socket) do
    last_row = socket.assigns.current.week_rows |> List.last()
    new_date = next_month_new_date(socket.assigns.current.date, last_row)
    {:noreply, socket |> assign(:current, format_date(new_date))}
  end

  @impl true
  def handle_event("pick-date", %{"date" => date_str}, socket) do
    if socket.assigns[:disabled] do
      {:noreply, socket}
    else
      date_time = from_str!(date_str)
      date = DateTime.to_date(date_time)

      # Check minimum date
      if Date.compare(socket.assigns.min, date) == :gt do
        {:noreply, socket}
      else
        # Check maximum date (if set)
        if socket.assigns[:max] && Date.compare(date, socket.assigns.max) == :gt do
          {:noreply, socket}
        else
          # Clicking a day before the current start while choosing an end date
          # restarts the selection (needed for events moving to an earlier day).
          socket = maybe_restart_selection_before_start(socket, date)

          # Validate date based on current state and rules
          if valid_date_selection?(socket, date) do
            ranges =
              calculate_date_ranges(
                socket.assigns.state,
                date_time,
                socket.assigns
              )

            state =
              if socket.assigns.is_range? do
                @fsm[socket.assigns.state]
              else
                @initial_state
              end

            {
              :noreply,
              socket
              |> assign(ranges)
              |> assign(:state, state)
            }
          else
            {:noreply, socket}
          end
        end
      end
    end
  end

  @impl true
  def handle_event("cursor-move", date_str, socket) do
    date = from_str!(date_str)
    day = DateTime.to_date(date)

    if Date.compare(socket.assigns.min, day) == :gt do
      {:noreply, socket}
    else
      # Only show hover if date is valid (not disabled)
      hover_range_end =
        case socket.assigns.state do
          :set_end ->
            ctx = date_disable_ctx_from_assigns(socket.assigns)
            tooltips = active_date_tooltips(ctx)

            if date_disabled?(day, ctx, tooltips) do
              nil
            else
              date
            end

          _ ->
            nil
        end

      {:noreply, socket |> assign(:hover_range_end, hover_range_end)}
    end
  end

  @impl true
  def handle_event("cursor-leave", _params, socket) do
    {:noreply, socket |> assign(:hover_range_end, nil)}
  end

  @impl true
  def handle_event("reset-dates", _params, socket) do
    # Clear both dates and reset state
    attrs = %{
      id: socket.assigns.id,
      start_date: nil,
      end_date: nil,
      form: socket.assigns.form
    }

    send(self(), {:updated_event, attrs})

    # Clear field values by setting them to empty strings
    start_date_field =
      if socket.assigns[:start_date_field] do
        Map.put(socket.assigns.start_date_field, :value, "")
      else
        socket.assigns[:start_date_field]
      end

    end_date_field =
      if socket.assigns[:end_date_field] do
        Map.put(socket.assigns.end_date_field, :value, "")
      else
        socket.assigns[:end_date_field]
      end

    {
      :noreply,
      socket
      |> assign(:range_start, nil)
      |> assign(:range_end, nil)
      |> assign(:hover_range_end, nil)
      |> assign(:end_date_field, end_date_field)
      |> assign(:start_date_field, start_date_field)
      |> assign(:state, @initial_state)
    }
  end

  defp maybe_restart_selection_before_start(socket, date) do
    range_start = socket.assigns.range_start

    if socket.assigns.state == :set_end and range_start != nil do
      start_date = DateTime.to_date(to_datetime(range_start))

      if Date.compare(date, start_date) == :lt do
        assign(socket, :state, :set_start)
      else
        socket
      end
    else
      socket
    end
  end

  defp end_value(assigns) when is_map_key(assigns, :end_date_field) do
    case assigns.end_date_field.value do
      nil -> nil
      "" -> nil
      _ -> assigns.end_date_field.value
    end
  end

  defp end_value(assigns) when is_map_key(assigns, :to) do
    case assigns.to.value do
      nil -> nil
      "" -> nil
      _ -> assigns.to.value
    end
  end

  defp end_value(_), do: nil

  defp next_month_new_date(current_date, last_row) do
    last_row_last_day = last_row |> List.last()
    last_row_last_month = last_row_last_day |> Calendar.strftime("%B")
    last_row_first_month = last_row |> List.first() |> Calendar.strftime("%B")
    current_month = Calendar.strftime(current_date, "%B")

    next_month =
      next_month(last_row_first_month, last_row_last_month, last_row_last_day)

    case current_date in last_row && current_month == next_month do
      true ->
        current_date

      false ->
        current_date
        |> Date.end_of_month()
        |> Date.add(1)
    end
  end

  defp next_month(last_row_first_month, last_row_last_month, last_day)
       when last_row_first_month == last_row_last_month do
    last_day
    |> Date.end_of_month()
    |> Date.add(1)
    |> Calendar.strftime("%B")
  end

  defp next_month(_, last_day_of_last_week_month, _),
    do: last_day_of_last_week_month

  defp new_date(%{current: %{date: current_date, week_rows: week_rows}}) do
    current_date = current_date
    first_row = week_rows |> List.first()
    last_row = week_rows |> List.last()

    case current_date in last_row do
      true ->
        first_row
        |> List.last()
        |> Date.beginning_of_month()
        |> Date.add(-1)

      false ->
        current_date
        |> Date.beginning_of_month()
        |> Date.add(-1)
    end
  end

  defp week_rows(current_date) do
    first =
      current_date
      |> Date.beginning_of_month()
      |> Date.beginning_of_week(@week_start_at)

    last =
      current_date
      |> Date.end_of_month()
      |> Date.end_of_week(@week_start_at)

    Date.range(first, last)
    |> Enum.map(& &1)
    |> Enum.chunk_every(7)
  end

  defp calculate_date_ranges(:set_start, date_time, assigns) do
    # min_nights: 0 (admin events) — first click selects a single day; a later
    # click can still extend the end date into a multi-day range.
    # min_nights: 1+ (bookings) — first click only sets check-in; checkout must
    # be a later day (at least one night).
    if Map.get(assigns, :min_nights, 1) == 0 do
      %{
        range_start: date_time,
        range_end: date_time
      }
    else
      %{
        range_start: date_time,
        range_end: nil
      }
    end
  end

  defp calculate_date_ranges(:set_end, date_time, _assigns),
    do: %{range_end: date_time}

  defp calculate_date_ranges(:reset, _date_time, _assigns) do
    %{
      range_start: nil,
      range_end: nil
    }
  end

  defp set_field_value(assigns, field, value) when is_binary(value) do
    if Map.has_key?(assigns, field) and is_map(assigns[field]) do
      {:ok, value, _} = DateTime.from_iso8601(value)
      Map.put(assigns[field], :value, value)
    else
      nil
    end
  end

  # Callers only ever reach this clause with the already-finalized DateTime (or
  # nil) produced by finalize_date/to_datetime, so it's stored as-is. Rebuilding
  # it from just the calendar date (as this used to do via `Date.to_string/1`)
  # silently dropped the time-of-day/timezone anchoring — e.g. it turned an
  # end-of-day Pacific instant back into plain midnight UTC of a possibly
  # different calendar day.
  defp set_field_value(assigns, field, value) do
    if Map.has_key?(assigns, field) and is_map(assigns[field]) do
      Map.put(assigns[field], :value, value)
    else
      nil
    end
  end

  defp before_min_date?(day, min) do
    Date.compare(day, min) == :lt
  end

  defp date_disable_ctx_from_assigns(assigns) do
    %{
      min: assigns.min,
      range_start: assigns.range_start,
      state: assigns.state,
      max: Map.get(assigns, :max),
      property: Map.get(assigns, :property),
      today: Map.get(assigns, :today),
      allow_saturdays: Map.get(assigns, :allow_saturdays, false),
      seasons: Map.get(assigns, :seasons),
      max_nights: Map.get(assigns, :max_nights, 4),
      min_nights: Map.get(assigns, :min_nights, 1),
      date_tooltips: Map.get(assigns, :date_tooltips, %{}),
      checkout_date_tooltips: Map.get(assigns, :checkout_date_tooltips, %{}),
      blocked_stay_dates: Map.get(assigns, :blocked_stay_dates, %{})
    }
  end

  # When selecting checkout, never fall back to check-in tooltips (those mark
  # blackout start / Saturday check-in dates that are valid check-outs).
  defp active_date_tooltips(%{
         state: :set_end,
         checkout_date_tooltips: tooltips
       })
       when is_map(tooltips),
       do: tooltips

  defp active_date_tooltips(%{date_tooltips: tooltips}) when is_map(tooltips),
    do: tooltips

  defp active_date_tooltips(_), do: %{}

  # Check if a date should be disabled based on booking rules
  defp date_disabled?(day, ctx, active_tooltips)

  defp date_disabled?(day, %{state: :set_end} = ctx, active_tooltips)
       when is_map(ctx) do
    cond do
      Map.has_key?(active_tooltips, Date.to_iso8601(day)) ->
        true

      stay_range_unavailable?(day, ctx) ->
        true

      true ->
        date_disabled_by_rules?(day, ctx)
    end
  end

  defp date_disabled?(day, ctx, active_tooltips) when is_map(ctx) do
    if Map.has_key?(active_tooltips, Date.to_iso8601(day)) do
      true
    else
      date_disabled_by_rules?(day, ctx)
    end
  end

  # True when any overnight in [check-in, check-out) is blocked (blackout/buyout/full).
  # Check-out on a blackout start date is allowed (leave by 11am before blackout).
  defp stay_range_unavailable?(checkout_day, %{
         range_start: range_start,
         blocked_stay_dates: blocked
       })
       when not is_nil(range_start) and is_map(blocked) and
              map_size(blocked) > 0 do
    checkin_day = DateTime.to_date(range_start)

    if Date.compare(checkout_day, checkin_day) == :gt do
      checkin_day
      |> Date.range(Date.add(checkout_day, -1))
      |> Enum.any?(fn night ->
        Map.has_key?(blocked, Date.to_iso8601(night))
      end)
    else
      false
    end
  end

  defp stay_range_unavailable?(_checkout_day, _ctx), do: false

  defp stay_range_unavailable_reason(checkout_day, %{
         range_start: range_start,
         blocked_stay_dates: blocked
       })
       when not is_nil(range_start) and is_map(blocked) and
              map_size(blocked) > 0 do
    checkin_day = DateTime.to_date(range_start)

    if Date.compare(checkout_day, checkin_day) == :gt do
      checkin_day
      |> Date.range(Date.add(checkout_day, -1))
      |> Enum.find_value(fn night ->
        Map.get(blocked, Date.to_iso8601(night))
      end)
    end
  end

  defp stay_range_unavailable_reason(_checkout_day, _ctx), do: nil

  defp date_disabled_by_rules?(day, ctx) when is_map(ctx) do
    ctx =
      ctx
      |> Map.put_new(:max_nights, 4)
      |> Map.put_new(:min_nights, 1)

    cond do
      before_min_date?(day, ctx.min) -> true
      after_max_date?(day, ctx.max) -> true
      true -> check_season_and_other_rules(day, ctx)
    end
  end

  defp after_max_date?(day, max) do
    max && Date.compare(day, max) == :gt
  end

  defp check_season_and_other_rules(day, ctx) do
    %{
      range_start: range_start,
      state: state,
      property: property,
      today: today,
      allow_saturdays: allow_saturdays,
      seasons: seasons,
      max_nights: max_nights,
      min_nights: min_nights
    } = ctx

    if property && today do
      alias Ysc.Bookings.SeasonHelpers

      if SeasonHelpers.date_selectable?(property, day, today, seasons) do
        check_end_date_rules(
          day,
          range_start,
          state,
          allow_saturdays,
          max_nights,
          min_nights
        )
      else
        true
      end
    else
      check_end_date_rules(
        day,
        range_start,
        state,
        allow_saturdays,
        max_nights,
        min_nights
      )
    end
  end

  defp saturday?(day) do
    Date.day_of_week(day) == 6
  end

  defp sunday?(day) do
    Date.day_of_week(day) == 7
  end

  defp check_end_date_rules(
         day,
         range_start,
         state,
         allow_saturdays,
         max_nights,
         min_nights
       ) do
    case state do
      :set_end when not is_nil(range_start) ->
        not end_date_allowed?(
          day,
          range_start,
          allow_saturdays,
          max_nights,
          min_nights
        )

      _ ->
        false
    end
  end

  # Shared end-date rules for disable checks and click validation.
  # Returns true when `day` is an allowed checkout / range end.
  defp end_date_allowed?(
         day,
         range_start,
         allow_saturdays,
         max_nights,
         min_nights
       ) do
    start_date = DateTime.to_date(to_datetime(range_start))
    nights = Date.diff(day, start_date)

    cond do
      nights > max_nights ->
        false

      # Days before the current start stay clickable when same-day ranges are
      # allowed so the user can restart on an earlier date (events).
      nights < 0 and min_nights == 0 ->
        true

      nights < min_nights ->
        false

      # Saturday check-out always leaves Sat without Sun in the inclusive span
      saturday?(day) && !allow_saturdays ->
        false

      # Saturday check-in: only Sunday checkout (one night)
      saturday?(start_date) && !allow_saturdays &&
          not (nights == 1 && sunday?(day)) ->
        false

      allow_saturdays ->
        true

      true ->
        date_range = Date.range(start_date, day) |> Enum.to_list()
        day_of_weeks = Enum.map(date_range, &Date.day_of_week/1)
        has_saturday = 6 in day_of_weeks
        has_sunday = 7 in day_of_weeks
        not (has_saturday and not has_sunday)
    end
  end

  defp valid_date_selection?(socket, %Date{} = date) do
    ctx = date_disable_ctx_from_assigns(socket.assigns)
    active_tooltips = active_date_tooltips(ctx)

    cond do
      Map.has_key?(active_tooltips, Date.to_iso8601(date)) ->
        false

      ctx.state == :set_end && stay_range_unavailable?(date, ctx) ->
        false

      true ->
        valid_date_selection_by_rules?(socket, date)
    end
  end

  defp valid_date_selection_by_rules?(socket, %Date{} = date) do
    if socket.assigns[:max] && Date.compare(date, socket.assigns.max) == :gt do
      false
    else
      if socket.assigns[:property] && socket.assigns[:today] do
        alias Ysc.Bookings.SeasonHelpers

        if SeasonHelpers.date_selectable?(
             socket.assigns[:property],
             date,
             socket.assigns[:today],
             socket.assigns[:seasons]
           ) do
          check_other_selection_rules(socket, date)
        else
          false
        end
      else
        check_other_selection_rules(socket, date)
      end
    end
  end

  # Check other date selection rules (Saturday, range validation, etc.)
  defp check_other_selection_rules(socket, date_day) do
    allow_saturdays = Map.get(socket.assigns, :allow_saturdays, false)
    max_nights = Map.get(socket.assigns, :max_nights, 4)
    min_nights = Map.get(socket.assigns, :min_nights, 1)

    case socket.assigns.state do
      :set_end when not is_nil(socket.assigns.range_start) ->
        end_date_allowed?(
          date_day,
          socket.assigns.range_start,
          allow_saturdays,
          max_nights,
          min_nights
        )

      _ ->
        true
    end
  end

  defp date_range_day_visible_label(
         day,
         range_start,
         range_end,
         hover_range_end,
         today,
         _date_disable_ctx
       ) do
    cond do
      range_endpoint?(day, range_start) && range_endpoint?(day, range_end) ->
        "Selected"

      range_endpoint?(day, range_start) ->
        "Start"

      range_endpoint?(day, range_end) ->
        "End"

      selected_range?(day, range_start, hover_range_end || range_end) ->
        "Selected"

      today?(day, today) ->
        "Today"

      true ->
        ""
    end
  end

  defp date_range_day_aria_label(
         day,
         range_start,
         range_end,
         hover_range_end,
         today,
         date_disable_ctx
       ) do
    date_label = Calendar.strftime(day, "%A, %B %d, %Y")

    status =
      date_range_day_visible_label(
        day,
        range_start,
        range_end,
        hover_range_end,
        today,
        date_disable_ctx
      )

    parts =
      [date_label, status]
      |> Enum.reject(&(&1 in [nil, ""]))

    Enum.join(parts, ", ")
  end

  defp date_picker_tooltip_id(id, day) do
    "#{id}-tooltip-#{Date.to_iso8601(day)}"
  end

  defp date_picker_show_tooltip?(day, ctx, tooltips) do
    date_disabled?(day, ctx, tooltips) &&
      date_picker_tooltip_text(day, ctx, tooltips) not in [nil, ""]
  end

  defp date_picker_tooltip_text(day, ctx, tooltips) do
    get_date_tooltip(day, tooltips) ||
      (ctx.state == :set_end && stay_range_unavailable_reason(day, ctx)) ||
      date_picker_rule_tooltip(day, ctx)
  end

  defp date_picker_rule_tooltip(day, ctx) do
    start_date =
      if ctx.range_start, do: DateTime.to_date(ctx.range_start), else: nil

    cond do
      before_min_date?(day, ctx.min) ->
        "Past dates cannot be booked"

      after_max_date?(day, ctx.max) ->
        "Reservations are not open for this date yet"

      saturday?(day) && !ctx.allow_saturdays && ctx.state == :set_end ->
        "Check-outs are not permitted on Saturdays"

      ctx.state == :set_end && start_date && saturday?(start_date) &&
        !ctx.allow_saturdays && Date.compare(day, start_date) == :gt &&
          not (Date.diff(day, start_date) == 1 && sunday?(day)) ->
        "Saturday check-ins must check out on Sunday"

      true ->
        nil
    end
  end

  defp range_endpoint?(_day, nil), do: false
  defp range_endpoint?(day, range_dt), do: DateTime.to_date(range_dt) == day
  defp today?(day, today), do: today && day == today

  defp showing_current_month?(current_date, today) do
    today &&
      Date.beginning_of_month(current_date) == Date.beginning_of_month(today)
  end

  defp other_month?(day, current_date) do
    Date.beginning_of_month(day) != Date.beginning_of_month(current_date)
  end

  defp selected_range?(_day, nil, nil), do: false

  defp selected_range?(day, range_start, nil) do
    day == DateTime.to_date(range_start)
  end

  defp selected_range?(day, nil, range_end) do
    day == DateTime.to_date(range_end)
  end

  defp selected_range?(day, range_start, range_end) do
    start_date = DateTime.to_date(range_start)
    end_date = DateTime.to_date(range_end)
    day in Date.range(start_date, end_date)
  end

  defp format_date(date) do
    %{
      date: date,
      month: Calendar.strftime(date, "%B %Y"),
      week_rows: week_rows(date)
    }
  end

  defp from_str!(""), do: nil

  defp from_str!(date_time_str) when is_binary(date_time_str) do
    case DateTime.from_iso8601(date_time_str) do
      {:ok, date_time, _} -> date_time
      _ -> nil
    end
  end

  defp from_str!(date_time_str), do: date_time_str

  # Ensure range endpoints are comparable DateTimes (or both nil) before sort.
  # Preserves range_end falling back to range_start at the call site.
  defp normalize_sorted_range(nil, nil), do: {nil, nil}
  defp normalize_sorted_range(%DateTime{} = start, nil), do: {start, start}
  defp normalize_sorted_range(nil, %DateTime{} = ending), do: {ending, ending}

  defp normalize_sorted_range(%DateTime{} = start, %DateTime{} = ending) do
    [range_start, range_end] =
      Enum.sort([start, ending], &(DateTime.compare(&1, &2) != :gt))

    {range_start, range_end}
  end

  # Converts a freshly-picked calendar day into the DateTime persisted to the
  # form. Only bare `%Date{}` values (a brand-new pick) are anchored using the
  # caller's `:timezone`/`:end_of_day?` assigns — a `%DateTime{}` already
  # carries its own instant (e.g. reloaded from the DB, or picked on a prior
  # cycle) and is passed straight to `to_datetime/1` unchanged, so this stays
  # idempotent across repeated form submits.
  defp finalize_date(nil, _assigns), do: nil

  defp finalize_date(%Date{} = date, assigns) do
    timezone = Map.get(assigns, :timezone) || "Etc/UTC"

    time =
      if Map.get(assigns, :end_of_day?, false),
        do: ~T[23:59:59],
        else: ~T[00:00:00]

    date
    |> DateTime.new!(time, timezone)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp finalize_date(%DateTime{} = dt, assigns) do
    # Calendar picks arrive as UTC-midnight DateTimes (`…T00:00:00Z`). When the
    # caller opts into a non-UTC timezone (ticket tier sale windows), re-anchor
    # from the picked calendar day instead of preserving the UTC instant.
    case Map.get(assigns, :timezone, "Etc/UTC") do
      "Etc/UTC" ->
        to_datetime(dt)

      _timezone ->
        dt
        |> DateTime.to_date()
        |> finalize_date(assigns)
    end
  end

  defp finalize_date(value, _assigns), do: to_datetime(value)

  defp to_datetime(%DateTime{} = dt), do: DateTime.truncate(dt, :second)

  defp to_datetime(%Date{} = date) do
    DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  end

  defp to_datetime(%NaiveDateTime{} = ndt) do
    DateTime.from_naive!(ndt, "Etc/UTC") |> DateTime.truncate(:second)
  end

  defp to_datetime(other) when is_binary(other), do: from_str!(other)

  defp select_button_text(_start_date, nil) do
    "Select Date"
  end

  defp select_button_text(start_date, end_date) when start_date == end_date do
    "Select Date"
  end

  defp select_button_text(nil, ""), do: "Close"
  defp select_button_text("", ""), do: "Close"
  defp select_button_text(_start_date, _end_date), do: "Select Dates"

  defp date_range_display(start_date, nil, is_range?)
       when start_date in [nil, ""] do
    if is_range? do
      "MM/DD/YYYY - MM/DD/YYYY"
    else
      "MM/DD/YYYY"
    end
  end

  defp date_range_display(start_date, end_date, _is_range?)
       when end_date in [nil, ""] do
    start_date_datetime = extract_date(start_date)
    Calendar.strftime(start_date_datetime, "%b %d, %Y")
  end

  defp date_range_display(start_date, end_date, is_range?) do
    start_date_datetime = extract_date(start_date)
    end_date_datetime = extract_date(end_date)

    if is_range? do
      if start_date_datetime == end_date_datetime do
        Calendar.strftime(start_date_datetime, "%b %d, %Y")
      else
        "#{Calendar.strftime(start_date_datetime, "%b %d, %Y")} - #{Calendar.strftime(end_date_datetime, "%b %d, %Y")}"
      end
    else
      # Single date picker - only show the start date
      Calendar.strftime(start_date_datetime, "%b %d, %Y")
    end
  end

  defp extract_date(input) when input in [nil, ""], do: Date.utc_today()

  defp extract_date(datetime_string) when is_binary(datetime_string) do
    datetime_string
    |> String.split("T")
    |> List.first()
    |> Date.from_iso8601!()
  end

  defp extract_date(%DateTime{} = datetime), do: DateTime.to_date(datetime)

  defp extract_date(%NaiveDateTime{} = datetime),
    do: NaiveDateTime.to_date(datetime)

  defp extract_date(%{calendar: Calendar.ISO} = datetime), do: datetime

  # Get tooltip text for a date, or nil if no tooltip
  defp get_date_tooltip(_day, %{} = tooltips) when map_size(tooltips) == 0,
    do: nil

  defp get_date_tooltip(day, tooltips) when is_map(tooltips) do
    # Try to find tooltip by date string key (ISO format)
    date_str = Date.to_iso8601(day)
    tooltip_data = Map.get(tooltips, date_str) || Map.get(tooltips, day)
    format_tooltip_data(tooltip_data)
  end

  # Format tooltip data into a safe string for rendering
  defp format_tooltip_data(nil), do: nil
  defp format_tooltip_data(tooltip) when is_binary(tooltip), do: tooltip

  defp format_tooltip_data(tooltip) when is_map(tooltip) do
    # If tooltip is a map (e.g., from tahoe_booking_live with bookings data),
    # format it into a readable string
    bookings = tooltip[:bookings] || tooltip["bookings"]

    cond do
      is_list(bookings) and bookings != [] ->
        format_bookings_tooltip(tooltip)

      Map.has_key?(tooltip, :reason) ->
        to_string(tooltip.reason)

      Map.has_key?(tooltip, "reason") ->
        to_string(tooltip["reason"])

      true ->
        # Fallback: try to extract any meaningful string from the map
        inspect(tooltip, limit: :infinity)
    end
  end

  defp format_tooltip_data(other), do: to_string(other)

  defp format_bookings_tooltip(tooltip) do
    bookings = tooltip[:bookings] || tooltip["bookings"] || []
    bookings_count = length(bookings)

    cond do
      bookings_count == 0 ->
        "No availability"

      bookings_count == 1 ->
        booking = List.first(bookings)
        room_names = get_room_names(booking)
        "Booked: #{room_names}"

      true ->
        "Multiple bookings (#{bookings_count} rooms booked)"
    end
  end

  defp get_room_names(booking) do
    rooms = booking[:rooms] || booking["rooms"] || []

    room_names =
      Enum.map(rooms, fn room -> room[:name] || room["name"] || "Room" end)

    Enum.join(room_names, ", ")
  end
end
