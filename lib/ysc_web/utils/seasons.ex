defmodule YscWeb.Seasons do
  @moduledoc """
  Utility module for determining seasons based on dates.

  Defines winter and summer seasons and provides functions to determine
  which season a given date falls into.
  """
  @doc """
  Determines the current season based on the date.
  """

  @winter_start {11, 1}
  @winter_end {4, 1}

  def get_current_season() do
    get_season(Date.utc_today())
  end

  def get_season(date) do
    {month, day} = {date.month, date.day}

    if {month, day} >= @winter_start or {month, day} <= @winter_end do
      :winter
    else
      :summer
    end
  end
end
