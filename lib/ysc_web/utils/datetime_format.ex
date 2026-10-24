defmodule Ysc.Events.DateTimeFormatter do
  @moduledoc """
  Utility module for formatting date and time values for display.

  Provides functions to format date-time combinations in a human-readable format.
  """

  alias YscWeb.DateDisplay

  @doc """
  Nicely formats and concatenates start_date, start_time, end_date, and end_time for display.

  Examples:
    iex> format_datetime(%{start_date: ~D[2024-12-01], start_time: ~T[10:00:00]})
    "Dec 1, 2024 at 10:00 AM"

    iex> format_datetime(%{start_date: ~D[2024-12-01], start_time: ~T[10:00:00], end_date: ~D[2024-12-01], end_time: ~T[14:00:00]})
    "Dec 1, 2024 from 10:00 AM to 2:00 PM"

    iex> format_datetime(%{start_date: ~D[2024-12-01], start_time: ~T[10:00:00], end_date: ~D[2024-12-02]})
    "Dec 1, 2024 at 10:00 AM to Dec 2, 2024"

    iex> format_datetime(%{start_date: ~D[2024-12-01]})
    "Dec 1, 2024"
  """
  def format_datetime(%{
        start_date: start_date,
        start_time: start_time,
        end_date: end_date,
        end_time: end_time
      }) do
    start = format_date_time(start_date, start_time)

    ending =
      case {end_date, end_time} do
        {nil, nil} -> nil
        {^start_date, time} -> format_time(time)
        {date, nil} -> format_date(date)
        {date, time} -> format_date_time(date, time)
      end

    [start, ending]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" to ")
  end

  def format_datetime(%{
        start_date: start_date,
        start_time: start_time,
        end_date: end_date
      }) do
    format_datetime(%{
      start_date: start_date,
      start_time: start_time,
      end_date: end_date,
      end_time: nil
    })
  end

  def format_datetime(%{start_date: start_date, start_time: start_time}) do
    format_datetime(%{
      start_date: start_date,
      start_time: start_time,
      end_date: nil,
      end_time: nil
    })
  end

  def format_datetime(%{start_date: start_date}) do
    format_date(start_date)
  end

  @doc """
  Formats an event's start date and optional time for compact UI (hero cards, TV posters).

  ## Options

    * `:separator` - between date and time (default `" at "`; TV posters use `" · "`)
    * `:default` - label when `start_date` is nil (default `"Date TBD"`)
    * `:with_year` - include the year in the date label (default `true`)

  Accepts an event map with `:start_date` and `:start_time`. `start_time` may be a
  `%Time{}`, `%NaiveDateTime{}`, `%DateTime{}`, or a wall-clock time string.
  """
  def format_event_start(event, opts \\ [])

  def format_event_start(event, opts) when is_map(event) do
    start_time = Map.get(event, :start_time) || Map.get(event, "start_time")
    separator = Keyword.get(opts, :separator, " at ")
    default = Keyword.get(opts, :default, "Date TBD")
    with_year? = Keyword.get(opts, :with_year, true)

    date_label =
      DateDisplay.format_event_date_range(event,
        default: default,
        with_year: with_year?
      )

    if date_label == default do
      default
    else
      case format_time(start_time) do
        nil -> date_label
        time -> "#{date_label}#{separator}#{time}"
      end
    end
  end

  def format_event_start(nil, _start_time, opts) do
    Keyword.get(opts, :default, "Date TBD")
  end

  def format_event_start(start_date, start_time, opts) do
    separator = Keyword.get(opts, :separator, " at ")

    case format_time(start_time) do
      nil -> format_date(start_date)
      time -> "#{format_date(start_date)}#{separator}#{time}"
    end
  end

  @doc """
  Formats a Pacific wall-clock time for display (e.g. `"10:00 AM"`).

  Accepts `%Time{}`, `%DateTime{}`, `%NaiveDateTime{}`, or a time string
  (`"10:00:00"`, `"10:00"`, `"10:00 AM"`). Returns `nil` for nil, blank, or
  unparseable values.
  """
  def format_time(value)

  def format_time(nil), do: nil
  def format_time(""), do: nil

  def format_time(%Time{} = time), do: Timex.format!(time, "{h12}:{m} {AM}")

  def format_time(%NaiveDateTime{} = dt),
    do: format_time(NaiveDateTime.to_time(dt))

  def format_time(%DateTime{} = dt), do: format_time(DateTime.to_time(dt))

  def format_time(time) when is_binary(time) do
    case parse_time(time) do
      nil -> nil
      parsed -> format_time(parsed)
    end
  end

  def format_time(_), do: nil

  @doc """
  Formats a start/end wall-clock range (e.g. `"10:00 AM - 2:00 PM"`).

  Returns just the present side when the other is missing, and `nil` when both
  are missing.
  """
  def format_time_range(start_time, end_time) do
    case {format_time(start_time), format_time(end_time)} do
      {nil, nil} -> nil
      {nil, ending} -> ending
      {start, nil} -> start
      {start, ending} -> "#{start} - #{ending}"
    end
  end

  @doc """
  Parses a Pacific wall-clock time into a `%Time{}`.

  Accepts the same values as `format_time/1`. Returns `nil` for nil, blank, or
  unparseable values. Use this when you need a `%Time{}` (duration math, form
  values), not a display string.
  """
  def parse_time(value)

  def parse_time(nil), do: nil
  def parse_time(""), do: nil
  def parse_time(%Time{} = time), do: time
  def parse_time(%NaiveDateTime{} = dt), do: NaiveDateTime.to_time(dt)
  def parse_time(%DateTime{} = dt), do: DateTime.to_time(dt)

  def parse_time(time) when is_binary(time) do
    trimmed = String.trim(time)

    if trimmed == "" do
      nil
    else
      parse_time_string(trimmed)
    end
  end

  def parse_time(_), do: nil

  defp format_date_time(date, nil), do: format_date(date)
  defp format_date_time(nil, time), do: format_time(time)

  defp format_date_time(date, time),
    do: "#{format_date(date)} at #{format_time(time)}"

  defp format_date(nil), do: nil
  defp format_date(date), do: Timex.format!(date, "{Mshort} {D}, {YYYY}")

  defp parse_time_string(time) do
    parse_timex(time, "{h12}:{m} {AM}") ||
      parse_timex(time, "%H:%M:%S", :strftime) ||
      parse_timex(time, "%H:%M", :strftime) ||
      parse_iso8601(time)
  end

  defp parse_timex(time, format, parser \\ :default)

  defp parse_timex(time, format, :strftime) do
    case Timex.parse(time, format, :strftime) do
      {:ok, parsed} -> time_from_parsed(parsed)
      {:error, _} -> nil
    end
  end

  defp parse_timex(time, format, :default) do
    case Timex.parse(time, format) do
      {:ok, parsed} -> time_from_parsed(parsed)
      {:error, _} -> nil
    end
  end

  defp parse_iso8601(time) do
    case Time.from_iso8601(time) do
      {:ok, parsed} ->
        parsed

      {:error, _} ->
        case Time.from_iso8601(time <> ":00") do
          {:ok, parsed} -> parsed
          {:error, _} -> nil
        end
    end
  end

  defp time_from_parsed(%NaiveDateTime{} = dt), do: NaiveDateTime.to_time(dt)
  defp time_from_parsed(%DateTime{} = dt), do: DateTime.to_time(dt)

  defp time_from_parsed(%Timex.AmbiguousDateTime{before: dt}),
    do: time_from_parsed(dt)

  defp time_from_parsed(_), do: nil
end
