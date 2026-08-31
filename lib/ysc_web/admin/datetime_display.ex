defmodule YscWeb.Admin.DateTimeDisplay do
  @moduledoc """
  Human-readable date labels for admin views.

  UTC timestamps are shown in America/Los_Angeles. Event dates use the UTC
  calendar date without timezone conversion.
  """

  @admin_timezone "America/Los_Angeles"
  @short_date_format "%b %d, %Y"
  @long_date_format "%B %d, %Y"
  @month_day_format "%b %d"
  @month_year_format "%B %Y"
  @utc_datetime_format "%b %d, %Y %H:%M UTC"
  @utc_datetime_at_format "%b %d, %Y at %H:%M UTC"
  @utc_datetime_short_format "%b %d at %H:%M UTC"
  @utc_datetime_long_format "%B %d, %Y %H:%M:%S UTC"
  @utc_time_format "%H:%M:%S UTC"
  @utc_iso_format "%Y-%m-%d %H:%M:%S UTC"
  @utc_iso_minute_format "%Y-%m-%d %H:%M UTC"
  @compact_datetime_format "%b %d, %Y %H:%M"
  @pacific_datetime_at_format "%b %-d, %Y at %-I:%M%P"
  @nil_label "—"

  @doc """
  Formats a UTC datetime as a short Pacific date (e.g. `"Mar 15, 2024"`).

  Returns `"—"` for nil or other non-datetime values.
  """
  def format_utc_date(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!(@admin_timezone)
    |> DateTime.to_date()
    |> Calendar.strftime(@short_date_format)
  end

  def format_utc_date(_), do: @nil_label

  @doc """
  Formats a UTC datetime as a short Pacific date and 12-hour time
  (e.g. `"Mar 15, 2024 at 7:30pm"`).

  Matches the Timex `{Mshort} {D}, {YYYY} at {h12}:{m}{am}` labels used on
  admin editor pages and ticket purchase timestamps.

  Returns `"—"` for nil or other non-datetime values.
  """
  def format_pacific_datetime_at(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!(@admin_timezone)
    |> Calendar.strftime(@pacific_datetime_at_format)
  end

  def format_pacific_datetime_at(_), do: @nil_label

  @doc """
  Formats a UTC datetime as a long Pacific date (e.g. `"March 15, 2024"`).

  Returns `"—"` for nil or other non-datetime values.
  """
  def format_utc_date_long(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!(@admin_timezone)
    |> DateTime.to_date()
    |> Calendar.strftime(@long_date_format)
  end

  def format_utc_date_long(_), do: @nil_label

  @doc """
  Formats an event start datetime as a UTC calendar date.

  Returns `"—"` for nil or other non-datetime values.
  """
  def format_event_date(%DateTime{} = dt) do
    dt
    |> DateTime.to_date()
    |> Calendar.strftime(@short_date_format)
  end

  def format_event_date(_), do: @nil_label

  @doc """
  Formats a stored UTC datetime without timezone conversion
  (e.g. `"Mar 15, 2024 14:30 UTC"`).
  """
  def format_utc_datetime(%DateTime{} = dt),
    do: Calendar.strftime(dt, @utc_datetime_format)

  def format_utc_datetime(_), do: @nil_label

  @doc """
  Formats a stored UTC datetime with an "at" separator
  (e.g. `"Mar 15, 2024 at 14:30 UTC"`).
  """
  def format_utc_datetime_at(%DateTime{} = dt),
    do: Calendar.strftime(dt, @utc_datetime_at_format)

  def format_utc_datetime_at(_), do: @nil_label

  @doc """
  Formats a stored UTC datetime as a short month/day and time label
  (e.g. `"Mar 15 at 14:30 UTC"`).
  """
  def format_utc_datetime_short(%DateTime{} = dt),
    do: Calendar.strftime(dt, @utc_datetime_short_format)

  def format_utc_datetime_short(_), do: @nil_label

  @doc """
  Formats a stored UTC datetime with a long date and time label
  (e.g. `"March 15, 2024 14:30:45 UTC"`).
  """
  def format_utc_datetime_long(%DateTime{} = dt),
    do: Calendar.strftime(dt, @utc_datetime_long_format)

  def format_utc_datetime_long(_), do: @nil_label

  @doc """
  Formats a stored UTC datetime as a time-only label
  (e.g. `"14:30:45 UTC"`).
  """
  def format_utc_time(%DateTime{} = dt),
    do: Calendar.strftime(dt, @utc_time_format)

  def format_utc_time(_), do: @nil_label

  @doc """
  Formats a stored UTC datetime in ISO-style date and time
  (e.g. `"2024-03-15 14:30:45 UTC"`).
  """
  def format_utc_iso(%DateTime{} = dt),
    do: Calendar.strftime(dt, @utc_iso_format)

  def format_utc_iso(_), do: @nil_label

  @doc """
  Formats a stored UTC datetime in ISO-style date and time without seconds
  (e.g. `"2024-03-15 14:30 UTC"`).
  """
  def format_utc_iso_minute(%DateTime{} = dt),
    do: Calendar.strftime(dt, @utc_iso_minute_format)

  def format_utc_iso_minute(_), do: @nil_label

  @doc """
  Formats a calendar date with a long month and year
  (e.g. `"March 2024"`).
  """
  def format_date_month_year(%Date{} = date),
    do: Calendar.strftime(date, @month_year_format)

  def format_date_month_year(%DateTime{} = dt),
    do: format_date_month_year(DateTime.to_date(dt))

  def format_date_month_year(_), do: @nil_label

  @doc """
  Formats a calendar date with a long month, day, and year without timezone
  conversion (e.g. `"March 15, 2024"`).
  """
  def format_calendar_date_long(%Date{} = date),
    do: Calendar.strftime(date, @long_date_format)

  def format_calendar_date_long(%DateTime{} = dt),
    do: format_calendar_date_long(DateTime.to_date(dt))

  def format_calendar_date_long(_), do: @nil_label

  @doc """
  Formats a calendar date as a short month and day without timezone conversion
  (e.g. `"Mar 15"`).
  """
  def format_month_day(%Date{} = date),
    do: Calendar.strftime(date, @month_day_format)

  def format_month_day(%DateTime{} = dt),
    do: format_month_day(DateTime.to_date(dt))

  def format_month_day(_), do: @nil_label

  @doc """
  Formats a stored UTC datetime as a compact date and time label
  (e.g. `"Mar 15, 2024 14:30"`) without timezone conversion.

  Returns `""` for nil or other non-datetime values.
  """
  def format_datetime_compact(%DateTime{} = dt) do
    Calendar.strftime(dt, @compact_datetime_format)
  end

  def format_datetime_compact(nil), do: ""
  def format_datetime_compact(_), do: ""
end
