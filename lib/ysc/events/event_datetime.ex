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
  Returns the start `DateTime` for an event, or `nil`.
  """
  def start_datetime(%Event{start_date: start_date, start_time: start_time}) do
    combine(start_date, start_time)
  end

  def start_datetime(_), do: nil

  @doc """
  Returns `true` when the event start is strictly in the future.
  """
  def in_future?(%Event{} = event) do
    case start_datetime(event) do
      nil -> false
      datetime -> DateTime.compare(datetime, DateTime.utc_now()) == :gt
    end
  end

  @doc """
  Returns `true` when the event start is in the past.
  """
  def in_past?(%Event{start_date: nil}), do: false

  def in_past?(%Event{start_date: start_date, start_time: nil}) do
    DateTime.compare(DateTime.utc_now(), start_date) == :gt
  end

  def in_past?(%Event{} = event) do
    case start_datetime(event) do
      nil -> false
      datetime -> DateTime.compare(DateTime.utc_now(), datetime) == :gt
    end
  end

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
