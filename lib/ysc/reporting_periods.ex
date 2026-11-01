defmodule Ysc.ReportingPeriods do
  @moduledoc """
  Calendar-period boundaries for club reporting (admin dashboard stats).

  The club operates in `America/Los_Angeles`, so "this month" and "this year"
  roll over at local midnight, not at midnight UTC (which is 4-5pm Pacific the
  day before). Every function returns UTC instants suitable for comparing
  against `:utc_datetime` columns.
  """

  @timezone "America/Los_Angeles"

  def timezone, do: @timezone

  @doc "Current local calendar date for the instant `now`."
  def local_date(%DateTime{} = now) do
    now |> DateTime.shift_zone!(@timezone) |> DateTime.to_date()
  end

  @doc """
  UTC instant of local midnight at the start of the month containing `now`,
  moved by `months_offset` calendar months.
  """
  def start_of_month(%DateTime{} = now, months_offset \\ 0) do
    now
    |> local_date()
    |> Date.beginning_of_month()
    |> Date.shift(month: months_offset)
    |> local_midnight_utc()
  end

  @doc """
  UTC instant of local midnight at the start of the year containing `now`,
  moved by `years_offset` calendar years.
  """
  def start_of_year(%DateTime{} = now, years_offset \\ 0) do
    %Date{year: year} = local_date(now)

    year
    |> Date.new!(1, 1)
    |> Date.shift(year: years_offset)
    |> local_midnight_utc()
  end

  @doc "UTC instant of local midnight at the start of `date`."
  def local_midnight_utc(%Date{} = date) do
    date
    |> DateTime.new!(~T[00:00:00], @timezone)
    |> DateTime.shift_zone!("Etc/UTC")
  end
end
