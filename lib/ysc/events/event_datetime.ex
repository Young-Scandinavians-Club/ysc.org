defmodule Ysc.Events.EventDateTime do
  @moduledoc """
  Utilities for combining event start/end dates and times and comparing them.
  """

  alias Ysc.Events.Event

  # Event `start_date`/`end_date` are Pacific calendar days and
  # `start_time`/`end_time` are Pacific wall-clock times (see `Ysc.Ecto.DateKind`).
  @event_timezone "America/Los_Angeles"

  @doc """
  Combines an event date and Pacific wall-clock time into a UTC `DateTime`.

  The date and time are interpreted in the event timezone
  (`America/Los_Angeles`) before converting to UTC, so comparisons against
  `DateTime.utc_now/0` line up with when the event actually happens locally.

  Returns `nil` when either argument is `nil`.

  ## Examples

      iex> combine(~D[2024-12-01], ~T[10:00:00])
      ~U[2024-12-01 18:00:00Z]

      iex> combine(nil, ~T[10:00:00])
      nil
  """
  def combine(nil, _), do: nil
  def combine(_, nil), do: nil

  def combine(%DateTime{} = date, %Time{} = time) do
    date
    |> DateTime.to_date()
    |> pacific_wall_clock_to_utc(time)
  end

  def combine(date, time) when not is_nil(date) and not is_nil(time) do
    pacific_wall_clock_to_utc(date, time)
  end

  defp pacific_wall_clock_to_utc(date, time) do
    case DateTime.new(date, time, @event_timezone) do
      {:ok, datetime} ->
        DateTime.shift_zone!(datetime, "Etc/UTC")

      # DST boundaries: pick the earlier instant rather than raising.
      {:ambiguous, earlier, _later} ->
        DateTime.shift_zone!(earlier, "Etc/UTC")

      {:gap, just_before, _just_after} ->
        DateTime.shift_zone!(just_before, "Etc/UTC")

      # No usable timezone database — fall back to a naive UTC combination.
      {:error, _reason} ->
        NaiveDateTime.new!(date, time) |> DateTime.from_naive!("Etc/UTC")
    end
  end

  @doc """
  Returns the start `DateTime` for an event that has both a date and a time.

  Returns `nil` when either is missing. Date-only events should use
  `starts_at/1` (Pacific midnight of the calendar day).
  """
  def start_datetime(%Event{start_date: start_date, start_time: start_time}) do
    combine(start_date, start_time)
  end

  def start_datetime(_), do: nil

  @doc """
  UTC instant at which the event begins.

  Timed events combine `start_date` + `start_time` as Pacific wall-clock.
  Date-only events (no `start_time`) start at Pacific midnight of the
  calendar day stored on `start_date`.

  The admin date picker persists event days as midnight UTC of that calendar
  day (`~U[2026-08-29 00:00:00Z]` for Saturday Aug 29). That encoding is
  **not** the start instant — comparing it to `DateTime.utc_now/0` closes
  checkout at 5pm Pacific the previous evening. Pacific midnight of the same
  date is the matching cutoff for "the event day has started".
  """
  def starts_at(%Event{start_date: start_date, start_time: start_time}) do
    starts_at(start_date, start_time)
  end

  def starts_at(start_date, start_time)

  def starts_at(nil, _), do: nil

  def starts_at(start_date, nil) do
    case calendar_date(start_date) do
      nil -> nil
      date -> combine(date, ~T[00:00:00])
    end
  end

  def starts_at(start_date, start_time), do: combine(start_date, start_time)

  @doc """
  Returns `true` when the event start is strictly in the future.

  Date-only events return `false` — a missing start time is treated as
  "cannot determine a future start" (used to skip retroactive notifications).
  """
  def in_future?(%Event{} = event) do
    case start_datetime(event) do
      nil -> false
      datetime -> DateTime.compare(datetime, DateTime.utc_now()) == :gt
    end
  end

  @doc """
  Returns `true` when the event start is in the past.

  Date-only events use Pacific midnight of the stored calendar day, not the
  raw UTC-midnight encoding. Pass `now` in tests to pin the comparison.
  """
  def in_past?(event, now \\ DateTime.utc_now())

  def in_past?(%Event{} = event, %DateTime{} = now) do
    case starts_at(event) do
      nil -> false
      datetime -> DateTime.compare(now, datetime) == :gt
    end
  end

  defp calendar_date(%DateTime{} = datetime), do: DateTime.to_date(datetime)
  defp calendar_date(%Date{} = date), do: date
  defp calendar_date(_), do: nil

  @pass_date_format "%a, %b %-d, %Y"
  @pass_time_format "%-I:%M %p"

  @doc """
  Formats an event start date and optional time for wallet passes
  (e.g. `"Sat, Mar 15, 2024 at 3:30 PM"`).

  Returns `"TBD"` when `start_date` is nil.
  """
  def format_pass_datetime(nil, _start_time), do: "TBD"

  def format_pass_datetime(%DateTime{} = start_date, start_time) do
    start_date
    |> DateTime.to_date()
    |> format_pass_datetime(start_time)
  end

  def format_pass_datetime(%Date{} = start_date, start_time) do
    date_str = Calendar.strftime(start_date, @pass_date_format)

    if start_time do
      "#{date_str} at #{Calendar.strftime(start_time, @pass_time_format)}"
    else
      date_str
    end
  end
end
