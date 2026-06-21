defmodule Ysc.Events.EventDateTime do
  @moduledoc """
  Utilities for combining event start/end dates and times and comparing them.
  """

  alias Ysc.Events.Event

  @doc """
  Combines a date and time into a UTC `DateTime`.

  Returns `nil` when either argument is `nil`.

  ## Examples

      iex> combine(~D[2024-12-01], ~T[10:00:00])
      ~U[2024-12-01 10:00:00Z]

      iex> combine(nil, ~T[10:00:00])
      nil
  """
  def combine(nil, _), do: nil
  def combine(_, nil), do: nil

  def combine(%DateTime{} = date, %Time{} = time) do
    date
    |> DateTime.to_naive()
    |> NaiveDateTime.to_date()
    |> NaiveDateTime.new!(time)
    |> DateTime.from_naive!("Etc/UTC")
  end

  def combine(date, time) when not is_nil(date) and not is_nil(time) do
    NaiveDateTime.new!(date, time)
    |> DateTime.from_naive!("Etc/UTC")
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
end
