defmodule Ysc.Events.DateTimeFormatter do
  @moduledoc """
  Utility module for formatting date and time values for display.

  Provides functions to format date-time combinations in a human-readable format.
  """
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

  defp format_date_time(date, nil), do: format_date(date)
  defp format_date_time(nil, time), do: format_time(time)

  defp format_date_time(date, time),
    do: "#{format_date(date)} at #{format_time(time)}"

  defp format_date(nil), do: nil
  defp format_date(date), do: Timex.format!(date, "{Mshort} {D}, {YYYY}")

  defp format_time(nil), do: nil
  defp format_time(time), do: Timex.format!(time, "{h12}:{m} {AM}")
end
