defmodule YscWeb.Admin.DateTimeDisplay do
  @moduledoc """
  Human-readable date labels for admin views.

  UTC timestamps are shown in America/Los_Angeles. Event dates use the UTC
  calendar date without timezone conversion.
  """

  @admin_timezone "America/Los_Angeles"
  @short_date_format "%b %d, %Y"
  @long_date_format "%B %d, %Y"
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
end
