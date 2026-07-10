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
end
