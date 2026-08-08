defmodule YscWeb.DateDisplay do
  @moduledoc """
  Human-readable date labels for public member-facing views.

  Dates are formatted from their stored calendar values without timezone
  conversion. Use `YscWeb.Admin.DateTimeDisplay` for admin Pacific-time
  labels on UTC timestamps.
  """

  @long_date_format "%B %d, %Y"
  @short_date_format "%b %-d"
  @datetime_display_format "%b %-d, %Y"
  @long_datetime_format "%B %d, %Y at %I:%M %p"
  @long_datetime_with_zone_format "%B %d, %Y at %I:%M %p %Z"
  @pacific_timezone "America/Los_Angeles"

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

  def format_pacific_date(%DateTime{} = datetime, default) do
    datetime
    |> DateTime.shift_zone!(@pacific_timezone)
    |> DateTime.to_date()
    |> format_datetime_display(default)
  end

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

  def format_pacific_date_short(%DateTime{} = datetime, default) do
    datetime
    |> DateTime.shift_zone!(@pacific_timezone)
    |> DateTime.to_date()
    |> format_date_short(default)
  end

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
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime(@long_datetime_with_zone_format)
  end

  def format_in_zone(_, _timezone, default), do: default

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
  Returns `:today`, `:tomorrow`, or `nil` for an event's start date, compared
  against the current calendar date in Pacific time.

  Event `start_date` values are Pacific wall-clock calendar days stored as
  DateTimes (use the date component as-is; do not shift timezones). "Today"
  is still evaluated in `America/Los_Angeles`.

  Accepts an event map with a `:start_date` (or `"start_date"`) field.
  """
  def event_day_label(event) do
    start_date =
      Map.get(event, :start_date) || Map.get(event, "start_date")

    case calendar_date(start_date) do
      nil ->
        nil

      date ->
        today =
          DateTime.now!(@pacific_timezone)
          |> DateTime.to_date()

        case Date.diff(date, today) do
          0 -> :today
          1 -> :tomorrow
          _ -> nil
        end
    end
  end

  defp calendar_date(nil), do: nil
  defp calendar_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp calendar_date(%Date{} = date), do: date
  defp calendar_date(_), do: nil
end
