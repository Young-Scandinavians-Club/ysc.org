defmodule YscWeb.DateDisplay do
  @moduledoc """
  Human-readable date labels for public member-facing views.

  Dates in this app fall into three buckets — do not mix the conversions.
  The kind is configured on the schema field via `Ysc.Ecto.DateKind`
  (`field :start_date, Ysc.Ecto.DateKind, kind: :california_calendar_datetime`).
  Credo `EX9003` / `EX9004` enforce that configuration.

  ## California calendar days (never `shift_zone`)

  Events and cabin stays happen in California. Their dates are **Pacific
  wall-clock calendar days**:

    * Event `start_date` / `end_date` — stored as DateTimes (typically midnight
      UTC of that day). Use `calendar_date/1` / `format_event_date_range/2`.
    * Event `start_time` / `end_time` — `%Time{}` values in Pacific wall-clock.
    * Booking `checkin_date` / `checkout_date` — `%Date{}` values for Tahoe and
      Clear Lake. Check-in is 3:00 PM Pacific.

  Relative labels ("Today", "Tomorrow") compare against **today in Pacific**,
  not the browser timezone.

  ## Pacific-anchored UTC instants (shift to Pacific)

  Ticket-tier sale windows are real timestamps picked in the admin UI as
  Pacific calendar days. Use `format_sale_window_range/2` / `format_pacific_date/1`.

  ## Other UTC instants (browser timezone, Pacific fallback)

  `published_on`, membership period ends, payment timestamps, and login times
  are global instants. Shift with `format_date_in_zone/2` into `@timezone`
  (from LiveSocket), defaulting to Pacific.

  Use `YscWeb.Admin.DateTimeDisplay` for admin Pacific-time labels on UTC
  timestamps.
  """

  alias YscWeb.TimeZone

  @long_date_format "%B %d, %Y"
  @short_date_format "%b %-d"
  @datetime_display_format "%b %-d, %Y"
  @long_datetime_format "%B %d, %Y at %I:%M %p"
  @long_datetime_with_zone_format "%B %d, %Y at %I:%M %p %Z"
  @pacific_timezone "America/Los_Angeles"
  @cabin_checkin_time ~T[15:00:00]

  @doc """
  Formats a date as a long label (e.g. `"March 15, 2024"`).

  Returns `default` for nil or other non-date values.
  """
  def format_date_long(value, default \\ "")

  def format_date_long(nil, default), do: default

  def format_date_long(%Date{} = date, _default),
    do: Calendar.strftime(date, @long_date_format)

  def format_date_long(%DateTime{} = datetime, default),
    do: format_date_long(DateTime.to_date(datetime), default)

  def format_date_long(_, default), do: default

  @doc """
  Formats a date as a short month/day label (e.g. `"Mar 15"`).

  Returns `default` for nil or other non-date values.
  """
  def format_date_short(value, default \\ "")

  def format_date_short(nil, default), do: default

  def format_date_short(%Date{} = date, _default),
    do: Calendar.strftime(date, @short_date_format)

  def format_date_short(%DateTime{} = datetime, default),
    do: format_date_short(DateTime.to_date(datetime), default)

  def format_date_short(_, default), do: default

  @doc """
  Formats an event date or date range for compact UI (cards, pills).

  Accepts an event map with `:start_date` and `:end_date`.

  ## Options

    * `:default` — when start date is missing (default `""`)
    * `:with_year` — include year on single-day labels and on the end of ranges
      (default `false`)
  """
  def format_event_date_range(event, opts \\ [])

  def format_event_date_range(%{} = event, opts) do
    start_date = Map.get(event, :start_date) || Map.get(event, "start_date")
    end_date = Map.get(event, :end_date) || Map.get(event, "end_date")
    default = Keyword.get(opts, :default, "")
    with_year? = Keyword.get(opts, :with_year, false)

    case calendar_date(start_date) do
      nil ->
        default

      start ->
        case calendar_date(end_date) do
          end_date when not is_nil(end_date) ->
            if Date.compare(start, end_date) == :eq do
              format_event_single_date(start, with_year?, default)
            else
              format_event_date_span(start, end_date, with_year?)
            end

          _ ->
            format_event_single_date(start, with_year?, default)
        end
    end
  end

  @doc """
  Formats a ticket tier sale window (real UTC instants, e.g. `start_date`/
  `end_date` on a `TicketTier`) as a date range.

  Unlike `format_event_date_range/2`, boundaries are shifted to Pacific time
  before formatting. Sale windows are picked in the admin UI as Pacific
  calendar days and stored as real UTC instants.

  ## Options

    * `:default` — when start date is missing (default `""`)
    * `:with_year` — include year on single-day labels and on the end of ranges
      (default `false`)
  """
  def format_sale_window_range(tier, opts \\ [])

  def format_sale_window_range(%{} = tier, opts) do
    start_date = Map.get(tier, :start_date) || Map.get(tier, "start_date")
    end_date = Map.get(tier, :end_date) || Map.get(tier, "end_date")
    default = Keyword.get(opts, :default, "")
    with_year? = Keyword.get(opts, :with_year, false)

    case pacific_instant_date(start_date) do
      nil ->
        default

      start ->
        case pacific_instant_date(end_date) do
          end_date when not is_nil(end_date) ->
            if Date.compare(start, end_date) == :eq do
              format_event_single_date(start, with_year?, default)
            else
              format_event_date_span(start, end_date, with_year?)
            end

          _ ->
            format_event_single_date(start, with_year?, default)
        end
    end
  end

  @doc """
  Formats a date as a short month/day/year label (e.g. `"Mar 15, 2024"`).

  Returns `default` for nil or other non-date values.
  """
  def format_datetime_display(value, default \\ "")

  def format_datetime_display(nil, default), do: default

  def format_datetime_display(%Date{} = date, _default),
    do: Calendar.strftime(date, @datetime_display_format)

  def format_datetime_display(%DateTime{} = datetime, default),
    do: format_datetime_display(DateTime.to_date(datetime), default)

  def format_datetime_display(_, default), do: default

  @doc """
  Formats a UTC datetime as a short Pacific calendar date (e.g. `"Mar 15, 2024"`).

  Datetimes are shifted to `America/Los_Angeles` before formatting. Dates use the
  short month/day/year format without conversion.

  Returns `default` for nil or other non-date values.
  """
  def format_pacific_date(value, default \\ "")

  def format_pacific_date(nil, default), do: default

  def format_pacific_date(%Date{} = date, _default),
    do: Calendar.strftime(date, @datetime_display_format)

  def format_pacific_date(%DateTime{} = datetime, default),
    do: format_date_in_zone(datetime, @pacific_timezone, default)

  def format_pacific_date(_, default), do: default

  @doc """
  Formats a UTC datetime as a short Pacific calendar date (e.g. `"Mar 5"`).

  Datetimes are shifted to `America/Los_Angeles` before formatting. Dates use the
  short month/day format without conversion.

  Returns `default` for nil or other non-date values.
  """
  def format_pacific_date_short(value, default \\ "")

  def format_pacific_date_short(nil, default), do: default

  def format_pacific_date_short(%Date{} = date, _default),
    do: format_date_short(date)

  def format_pacific_date_short(%DateTime{} = datetime, default),
    do: format_date_short_in_zone(datetime, @pacific_timezone, default)

  def format_pacific_date_short(_, default), do: default

  @doc """
  Formats a datetime as a long date and time label without timezone conversion
  (e.g. `"March 15, 2024 at 3:30 PM"`).

  Returns `default` for nil or other non-datetime values.
  """
  def format_datetime_at(value, default \\ "")

  def format_datetime_at(nil, default), do: default

  def format_datetime_at(%DateTime{} = datetime, _default),
    do: Calendar.strftime(datetime, @long_datetime_format)

  def format_datetime_at(_, default), do: default

  @doc """
  Formats a date or datetime for display in a specific timezone.

  Dates use the long date format. Datetimes are shifted to `timezone` and
  include the zone abbreviation (e.g. `"March 15, 2024 at 3:30 PM PDT"`).

  Returns `default` for nil or other unsupported values.
  """
  def format_in_zone(value, timezone, default \\ "")

  def format_in_zone(nil, _timezone, default), do: default

  def format_in_zone(%Date{} = date, _timezone, default),
    do: format_date_long(date, default)

  def format_in_zone(%DateTime{} = datetime, timezone, _default) do
    datetime
    |> TimeZone.shift(timezone)
    |> Calendar.strftime(@long_datetime_with_zone_format)
  end

  def format_in_zone(_, _timezone, default), do: default

  @doc """
  Formats a UTC instant as a short month/day/year label in `timezone`
  (e.g. `"Mar 15, 2024"`). Dates are formatted without conversion.

  Invalid timezones fall back to Pacific time.
  """
  def format_date_in_zone(value, timezone, default \\ "")

  def format_date_in_zone(nil, _timezone, default), do: default

  def format_date_in_zone(%Date{} = date, _timezone, default),
    do: format_datetime_display(date, default)

  def format_date_in_zone(%DateTime{} = datetime, timezone, default) do
    datetime
    |> TimeZone.shift(timezone)
    |> DateTime.to_date()
    |> format_datetime_display(default)
  end

  def format_date_in_zone(_, _timezone, default), do: default

  @doc """
  Formats a UTC instant as a short month/day label in `timezone`
  (e.g. `"Mar 5"`). Dates are formatted without conversion.

  Invalid timezones fall back to Pacific time.
  """
  def format_date_short_in_zone(value, timezone, default \\ "")

  def format_date_short_in_zone(nil, _timezone, default), do: default

  def format_date_short_in_zone(%Date{} = date, _timezone, default),
    do: format_date_short(date, default)

  def format_date_short_in_zone(%DateTime{} = datetime, timezone, default) do
    datetime
    |> TimeZone.shift(timezone)
    |> DateTime.to_date()
    |> format_date_short(default)
  end

  def format_date_short_in_zone(_, _timezone, default), do: default

  defp format_event_single_date(date, true, _default),
    do: Calendar.strftime(date, "%b %-d, %Y")

  defp format_event_single_date(date, false, _default),
    do: format_date_short(date)

  defp format_event_date_span(start_date, end_date, true) do
    if start_date.year == end_date.year do
      "#{format_date_short(start_date)} – #{Calendar.strftime(end_date, "%b %-d, %Y")}"
    else
      "#{format_datetime_display(start_date)} – #{format_datetime_display(end_date)}"
    end
  end

  defp format_event_date_span(start_date, end_date, false) do
    if start_date.year == end_date.year do
      "#{format_date_short(start_date)} – #{format_date_short(end_date)}"
    else
      "#{format_datetime_display(start_date)} – #{format_datetime_display(end_date)}"
    end
  end

  @doc """
  Returns the number of Pacific calendar days until an event's start date.

  Event `start_date` values are California wall-clock days stored as DateTimes
  (typically midnight UTC of that day). The date component is used as-is —
  do not shift timezones, or midnight UTC becomes the previous evening in
  Pacific time.

  "Today" is always Pacific, because events are hosted in California.

  Returns `nil` when the start date is missing or in the past.
  """
  def days_until_event(event) do
    start_date =
      Map.get(event, :start_date) || Map.get(event, "start_date")

    case calendar_date(start_date) do
      nil ->
        nil

      date ->
        case Date.diff(date, TimeZone.today()) do
          diff when diff >= 0 -> diff
          _ -> nil
        end
    end
  end

  @doc """
  Returns `:today`, `:tomorrow`, or `nil` for an event's start date.

  See `days_until_event/1`. Compared against today in Pacific time.
  """
  def event_day_label(event) do
    case days_until_event(event) do
      0 -> :today
      1 -> :tomorrow
      _ -> nil
    end
  end

  @doc """
  Human-readable relative day label: `"Today"`, `"Tomorrow"`, or `"In N days"`.
  """
  def relative_days_phrase(0), do: "Today"
  def relative_days_phrase(1), do: "Tomorrow"

  def relative_days_phrase(days) when is_integer(days) and days > 1,
    do: "In #{days} days"

  def relative_days_phrase(_), do: ""

  @doc """
  Days until cabin check-in, using Pacific time.

  Check-in / check-out are `%Date{}` values for California cabins. Check-in
  is 3:00 PM Pacific. Returns:

    * `:started` — after 3:00 PM Pacific on the check-in day, or any later day
    * `0` — check-in is today and it is still before 3:00 PM Pacific
    * a positive integer — calendar days until check-in
  """
  def days_until_cabin_checkin(%{checkin_date: %Date{} = checkin_date}) do
    now = TimeZone.now()
    today = DateTime.to_date(now)

    checkin_at =
      DateTime.new!(checkin_date, @cabin_checkin_time, TimeZone.default())

    cond do
      Date.compare(today, checkin_date) == :gt ->
        :started

      Date.compare(today, checkin_date) == :eq and
          DateTime.compare(now, checkin_at) != :lt ->
        :started

      Date.compare(today, checkin_date) == :eq ->
        0

      true ->
        Date.diff(checkin_date, today)
    end
  end

  def days_until_cabin_checkin(_), do: nil

  @doc """
  Combines an event's stored calendar date with `start_time` as a Pacific
  wall-clock time.

  Does not shift `start_date` through a timezone. Midnight Pacific is used
  when time is missing. Returns `nil` when the start date is missing.
  """
  def event_start_datetime(event) when is_map(event) do
    start_date = Map.get(event, :start_date) || Map.get(event, "start_date")
    start_time = Map.get(event, :start_time) || Map.get(event, "start_time")

    case calendar_date(start_date) do
      nil ->
        nil

      date ->
        time = event_wall_clock_time(start_time) || ~T[00:00:00]
        pacific_wall_clock(date, time)
    end
  end

  @doc """
  Extracts the stored calendar date from a date or datetime.

  For event `start_date` values, this is the intended wall-clock day and must
  not be timezone-shifted.
  """
  def calendar_date(nil), do: nil
  def calendar_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  def calendar_date(%Date{} = date), do: date
  def calendar_date(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt)
  def calendar_date(_), do: nil

  defp event_wall_clock_time(%Time{} = time), do: time

  defp event_wall_clock_time(%NaiveDateTime{} = dt),
    do: NaiveDateTime.to_time(dt)

  defp event_wall_clock_time(%DateTime{} = dt), do: DateTime.to_time(dt)
  defp event_wall_clock_time(_), do: nil

  defp pacific_wall_clock(date, time) do
    case DateTime.new(date, time, @pacific_timezone) do
      {:ok, dt} -> dt
      {:gap, _before, after_dt} -> after_dt
      {:ambiguous, first, _second} -> first
    end
  end

  defp pacific_instant_date(nil), do: nil

  defp pacific_instant_date(%DateTime{} = dt),
    do: dt |> TimeZone.shift(@pacific_timezone) |> DateTime.to_date()

  defp pacific_instant_date(%Date{} = date), do: date
  defp pacific_instant_date(_), do: nil
end
