defmodule Ysc.Bookings.SeasonHelpers do
  @moduledoc """
  Shared helper functions for season-based booking logic.

  Provides utilities for:
  - Getting current season date ranges
  - Calculating max booking dates (allowing cross-season bookings)
  - Validating advance booking limits across seasons
  """

  import Ecto.Query, warn: false
  alias Ysc.Bookings.Season

  @doc """
  Gets the current season and its actual date range for a property.

  Returns `{current_season, season_start_date, season_end_date}`.
  """
  def get_current_season_info(property, today \\ Date.utc_today()) do
    current_season = Season.for_date(property, today)

    if current_season do
      {season_start_date, season_end_date} =
        get_season_date_range(current_season, today)

      {current_season, season_start_date, season_end_date}
    else
      {nil, nil, nil}
    end
  end

  @doc """
  Gets the actual date range for a season based on a reference date.

  Handles year-spanning seasons (e.g., Nov 1 - Apr 30).
  Returns `{start_date, end_date}`.
  """
  def get_season_date_range(season, reference_date) do
    start_date = get_season_start_date(season, reference_date)
    end_date = get_season_end_date(season, reference_date)
    {start_date, end_date}
  end

  @doc """
  Calculates the maximum booking date based on the current season's advance booking limit.

  If the current season has no limit, allows dates up to the end of the current season,
  OR up to the next season's advance booking limit (whichever is later), so users can
  start booking the next season when within the advance booking window.
  Individual date validation (checking if dates fall into restricted seasons) is handled
  by date_selectable?/3, which will disable dates in restricted seasons.
  """
  def calculate_max_booking_date(property, today \\ Date.utc_today()) do
    current_season = Season.for_date(property, today)

    if current_season do
      calculate_max_booking_date_with_season(property, current_season, today)
    else
      # No current season found - use a conservative default
      Date.add(today, 365)
    end
  end

  defp calculate_max_booking_date_with_season(property, current_season, today) do
    if current_season.advance_booking_days &&
         current_season.advance_booking_days > 0 do
      # Current season has a limit - apply it
      Date.add(today, current_season.advance_booking_days)
    else
      # Current season has no limit - allow up to the end of current season
      calculate_max_booking_date_no_limit(property, current_season, today)
    end
  end

  defp calculate_max_booking_date_no_limit(property, current_season, today) do
    {_season_start, season_end} = get_season_date_range(current_season, today)

    # Also check if we can book into the next season (if it has a limit)
    next_season = get_next_season(property, today)

    max_date = season_end

    if next_season && next_season.advance_booking_days &&
         next_season.advance_booking_days > 0 do
      # Next season has a limit - we can book up to that limit
      next_season_max = Date.add(today, next_season.advance_booking_days)
      # Use the later of: end of current season or next season's limit
      if Date.compare(next_season_max, max_date) == :gt do
        next_season_max
      else
        max_date
      end
    else
      max_date
    end
  end

  @doc """
  Checks if a specific date is selectable based on season advance booking restrictions.

  Returns true if the date can be selected, false if it should be disabled.
  A date is selectable if:
  - It's in a season with no advance booking limit, OR
  - It's in a season with a limit AND it's within the advance booking window
  """
  def date_selectable?(property, date, today \\ Date.utc_today()) do
    season = Season.for_date(property, date)

    if season && season.advance_booking_days && season.advance_booking_days > 0 do
      # Season has a limit - check if date is within the advance booking window
      max_booking_date = Date.add(today, season.advance_booking_days)
      Date.compare(date, max_booking_date) != :gt
    else
      # No limit for this season - date is selectable
      true
    end
  end

  @doc """
  Validates that check-in and check-out dates are within the current season.

  Returns a map of errors (empty if valid).

  NOTE: This validation is now disabled to allow cross-season bookings.
  Rules should apply for the dates the user is selecting across seasons.
  """
  def validate_season_date_range(
        _property,
        _checkin_date,
        _checkout_date,
        _today \\ Date.utc_today()
      ) do
    # Allow bookings across seasons - no restriction
    %{}
  end

  @doc """
  Validates advance booking limit using rules from the season(s) that the booking dates fall into.

  If a booking extends into a season with a limit, that limit applies to the booking.
  """
  def validate_advance_booking_limit(
        property,
        checkin_date,
        checkout_date,
        today \\ Date.utc_today()
      ) do
    # Check the season for the checkin_date
    checkin_season = Season.for_date(property, checkin_date)

    # Check the season for the checkout_date (might be different if booking spans seasons)
    checkout_season = Season.for_date(property, checkout_date)

    errors = %{}

    # Apply checkin_date season's limit if it exists
    errors =
      if checkin_season && checkin_season.advance_booking_days &&
           checkin_season.advance_booking_days > 0 do
        max_booking_date = Date.add(today, checkin_season.advance_booking_days)

        cond do
          Date.compare(checkin_date, max_booking_date) == :gt ->
            Map.put(
              errors,
              :advance_booking_limit,
              "Bookings can only be made up to #{checkin_season.advance_booking_days} days in advance. Maximum check-in date is #{format_date(max_booking_date)}"
            )

          Date.compare(checkout_date, max_booking_date) == :gt ->
            Map.put(
              errors,
              :advance_booking_limit,
              "Bookings can only be made up to #{checkin_season.advance_booking_days} days in advance. Maximum check-out date is #{format_date(max_booking_date)}"
            )

          true ->
            errors
        end
      else
        errors
      end

    # Apply checkout_date season's limit if it's different from checkin_season and has a limit
    errors =
      if checkout_season && checkin_season &&
           checkout_season.id != checkin_season.id &&
           checkout_season.advance_booking_days &&
           checkout_season.advance_booking_days > 0 do
        max_booking_date = Date.add(today, checkout_season.advance_booking_days)

        cond do
          Date.compare(checkin_date, max_booking_date) == :gt ->
            Map.put(
              errors,
              :advance_booking_limit,
              "Bookings for the #{checkout_season.name} season can only be made up to #{checkout_season.advance_booking_days} days in advance. Maximum check-in date is #{format_date(max_booking_date)}"
            )

          Date.compare(checkout_date, max_booking_date) == :gt ->
            Map.put(
              errors,
              :advance_booking_limit,
              "Bookings for the #{checkout_season.name} season can only be made up to #{checkout_season.advance_booking_days} days in advance. Maximum check-out date is #{format_date(max_booking_date)}"
            )

          true ->
            errors
        end
      else
        errors
      end

    errors
  end

  # Get the start date of the current season occurrence
  defp get_season_start_date(season, today) do
    {today_month, today_day} = {today.month, today.day}
    {start_month, start_day} = {season.start_date.month, season.start_date.day}
    {end_month, end_day} = {season.end_date.month, season.end_date.day}

    # If season spans years (e.g., Nov to Apr)
    if start_month > end_month do
      # Check if we're before the end date in the current year
      if {today_month, today_day} <= {end_month, end_day} do
        # We're in the later part of the season (Jan-Apr), start was last year
        Date.new!(today.year - 1, start_month, start_day)
      else
        # We're in the earlier part (Nov-Dec), start is this year
        Date.new!(today.year, start_month, start_day)
      end
    else
      # Same-year range - start is this year
      Date.new!(today.year, start_month, start_day)
    end
  end

  # Get the end date of the current season occurrence
  defp get_season_end_date(season, today) do
    {today_month, today_day} = {today.month, today.day}
    {start_month, _start_day} = {season.start_date.month, season.start_date.day}
    {end_month, end_day} = {season.end_date.month, season.end_date.day}

    # If season spans years (e.g., Nov to Apr)
    if start_month > end_month do
      # Check if we're before the end date in the current year
      if {today_month, today_day} <= {end_month, end_day} do
        # We're in the later part of the season (Jan-Apr), end is this year
        Date.new!(today.year, end_month, end_day)
      else
        # We're in the earlier part (Nov-Dec), end is next year
        Date.new!(today.year + 1, end_month, end_day)
      end
    else
      # Same-year range - end is this year
      Date.new!(today.year, end_month, end_day)
    end
  end

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  # Gets the next season that comes after the given date
  defp get_next_season(property, reference_date) do
    # Use cached seasons list for better performance
    alias Ysc.Bookings.SeasonCache
    all_seasons = SeasonCache.get_all_for_property(property)
    current_season = Season.for_date(property, reference_date)

    if current_season && length(all_seasons) > 1 do
      # Find the next season by calculating which one starts next
      # We'll check each season's next occurrence and find the earliest one after reference_date
      next_seasons =
        all_seasons
        |> Enum.filter(fn season -> season.id != current_season.id end)
        |> Enum.map(fn season ->
          {season, get_next_season_occurrence_start(season, reference_date)}
        end)
        |> Enum.filter(fn {_season, start_date} -> start_date != nil end)
        |> Enum.sort_by(fn {_season, start_date} -> start_date end)

      case next_seasons do
        [{next_season, _start_date} | _] -> next_season
        _ -> nil
      end
    else
      nil
    end
  end

  # Gets the next occurrence start date for a season after the reference date
  defp get_next_season_occurrence_start(season, reference_date) do
    {ref_month, ref_day} = {reference_date.month, reference_date.day}
    {start_month, start_day} = {season.start_date.month, season.start_date.day}
    {end_month, end_day} = {season.end_date.month, season.end_date.day}

    cond do
      # If season spans years (e.g., Nov to Apr)
      start_month > end_month ->
        # If we're before the end date, next start could be this year or next
        if {ref_month, ref_day} <= {end_month, end_day} do
          # We're in the later part (Jan-Apr), next start is this year
          calculate_next_start_in_later_part(
            reference_date,
            start_month,
            start_day
          )
        else
          # We're in the earlier part (Nov-Dec), next start is next year
          Date.new!(reference_date.year + 1, start_month, start_day)
        end

      # Same-year range
      {ref_month, ref_day} < {start_month, start_day} ->
        # Next start is this year
        Date.new!(reference_date.year, start_month, start_day)

      true ->
        # Next start is next year
        Date.new!(reference_date.year + 1, start_month, start_day)
    end
  end

  defp calculate_next_start_in_later_part(
         reference_date,
         start_month,
         start_day
       ) do
    candidate = Date.new!(reference_date.year, start_month, start_day)

    if Date.compare(candidate, reference_date) == :gt do
      candidate
    else
      Date.new!(reference_date.year + 1, start_month, start_day)
    end
  end
end
