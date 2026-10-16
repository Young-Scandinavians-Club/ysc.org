defmodule Ysc.Events.AddToCalendar do
  @moduledoc """
  Shared start/end date and time values for the add-to-calendar web component.

  Event pages and ticket QR both used the same rules: ISO calendar dates,
  Pacific wall-clock times, and a 3-hour default duration when `end_time` is
  missing. Overnight default durations roll the end date to the next day.
  """

  @timezone "America/Los_Angeles"
  @default_duration_seconds 3 * 60 * 60

  @doc """
  IANA timezone for event calendar entries (`America/Los_Angeles`).
  """
  def timezone, do: @timezone

  @doc """
  Formats a calendar date as `YYYY-MM-DD` for `start-date` / `end-date`.

  Accepts `%Date{}`, `%DateTime{}`, or `%NaiveDateTime{}`. Event start/end
  dates are Pacific calendar days stored as DateTimes — convert with
  `DateTime.to_date/1`, never `shift_zone`. Returns `nil` for other values.
  """
  def date(nil), do: nil
  def date(%Date{} = date), do: Date.to_iso8601(date)

  def date(%DateTime{} = datetime),
    do: datetime |> DateTime.to_date() |> Date.to_iso8601()

  def date(%NaiveDateTime{} = datetime),
    do: datetime |> NaiveDateTime.to_date() |> Date.to_iso8601()

  def date(_), do: nil

  @doc """
  Wall-clock end time for the calendar entry.

  Uses `event.end_time` when present. When only `start_time` is set, adds
  three hours (wrapping at midnight). Returns `nil` when there is no start
  or end time.
  """
  def end_time(event) when is_map(event) do
    case {pacific_time(event, :start_time), pacific_time(event, :end_time)} do
      {start_time, nil} when not is_nil(start_time) ->
        Time.add(start_time, @default_duration_seconds, :second)

      {_start_time, end_time} ->
        end_time
    end
  end

  @doc """
  Calendar end date for the calendar entry.

  When `start_time` is set and `end_time` is missing, infers the end date
  from the 3-hour default duration (next day if that duration wraps past
  midnight, otherwise the start date). Otherwise returns `event.end_date`.
  """
  def end_date(event) when is_map(event) do
    case {pacific_time(event, :start_time), pacific_time(event, :end_time),
          Map.get(event, :end_date)} do
      {start_time, nil, _end_date} when not is_nil(start_time) ->
        inferred_end_date(event, start_time)

      {_start_time, _end_time, end_date} ->
        end_date
    end
  end

  defp inferred_end_date(event, start_time) do
    calculated_end_time =
      Time.add(start_time, @default_duration_seconds, :second)

    if Time.compare(calculated_end_time, start_time) == :lt do
      next_calendar_day(Map.get(event, :start_date))
    else
      Map.get(event, :start_date)
    end
  end

  defp next_calendar_day(%DateTime{} = start_date),
    do: start_date |> DateTime.to_date() |> Date.add(1)

  defp next_calendar_day(%NaiveDateTime{} = start_date),
    do: start_date |> NaiveDateTime.to_date() |> Date.add(1)

  defp next_calendar_day(%Date{} = start_date), do: Date.add(start_date, 1)

  defp next_calendar_day(start_date), do: start_date

  defp pacific_time(event, field) do
    case Map.get(event, field) do
      %Time{} = time -> time
      _ -> nil
    end
  end
end
