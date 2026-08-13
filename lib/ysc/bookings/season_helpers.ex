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

  @cabin_timezone "America/Los_Angeles"

  # When no season anywhere in a property's chain has an advance-booking
  # limit, the calendar has no natural cutoff. A LiveView calendar still
  # needs a finite window to render, so "no limit" is translated into this
  # practical horizon instead of literally forever.
  @unlimited_horizon_days 730

  @doc """
  Today's calendar date in the cabin timezone (`America/Los_Angeles`).

  Use this for advance-booking cutoffs and other cabin-local date rules so
  behavior matches the booking calendars.
  """
  def cabin_today do
    DateTime.now!(@cabin_timezone) |> DateTime.to_date()
  end

  @doc """
  Gets the current season and its actual date range for a property.

  When `seasons` is a preloaded list (e.g. from `SeasonCache`), no DB query is made.

  Returns `{current_season, season_start_date, season_end_date}`.
  """
  def get_current_season_info(
        property,
        today \\ cabin_today(),
        seasons \\ nil
      )

  def get_current_season_info(_property, today, seasons)
      when is_list(seasons) do
    current_season = Season.find_season_for_date(seasons, today)
    season_info_for_current(current_season, today)
  end

  def get_current_season_info(property, today, nil) do
    current_season = Season.for_date(property, today)
    season_info_for_current(current_season, today)
  end

  defp season_info_for_current(current_season, today) do
    if current_season do
      {season_start_date, season_end_date} =
        get_season_date_range(current_season, today)

      {current_season, season_start_date, season_end_date}
    else
      {nil, nil, nil}
    end
  end

  @doc """
  Whether the (recurring) Winter season's current-or-next occurrence has
  entered the bookable window yet, plus a "start year/end year" label for it
  (e.g. `"2025/2026"`) derived from the resolved dates.

  A season named `"Winter"` is treated as not buyout-eligible elsewhere
  (`Season.buyout_allowed_on_date?/2`); this mirrors that convention to decide
  when a "winter reservations are open" notice should be shown at all, so it
  only appears once at least the season's start date is actually selectable
  (given `max_booking_date`, e.g. from `calculate_max_booking_date/3`) and
  disappears again once the season has passed and the next occurrence isn't
  yet in reach.

  `max_booking_date` reflects the *current* season's own advance rule (only
  extended by the *next* season's rule when the current season has no limit
  of its own — see `calculate_max_booking_date_no_limit/3`). If some other
  season's numeric limit happens to reach past Winter's start, that alone
  doesn't mean Winter's own booking window has opened, so Winter's own
  `advance_booking_days` (when set) is checked independently as well.
  """
  def winter_booking_window(seasons, today, max_booking_date)
      when is_list(seasons) do
    case Enum.find(seasons, &(&1.name == "Winter")) do
      nil ->
        {false, nil}

      winter ->
        {winter_start, winter_end} = get_season_date_range(winter, today)

        within_global_window? =
          Date.compare(winter_start, max_booking_date) != :gt

        within_winter_own_limit? =
          if winter.advance_booking_days && winter.advance_booking_days > 0 do
            winter_own_max = Date.add(today, winter.advance_booking_days)
            Date.compare(winter_start, winter_own_max) != :gt
          else
            true
          end

        open? = within_global_window? and within_winter_own_limit?

        {open?, "#{winter_start.year}/#{winter_end.year}"}
    end
  end

  @doc """
  Finds the first "whole weekend" (Friday check-in, Sunday check-out — the
  shape required by Tahoe's Saturday/Sunday rule, see
  `Ysc.Bookings.BookingValidator.validate_weekend_requirement/1`) of the named
  season's current-or-next occurrence, and whether it's actually bookable
  right now.

  "Bookable right now" requires all of:
  - The weekend hasn't already started (`weekend_checkin >= today`). Without
    this, a season already well underway when this check first runs (e.g.
    deploying partway through Summer) would compute a check-in date back near
    the season's start — already in the past — which trivially satisfies both
    checks below and would fire immediately for a weekend nobody can book
    anymore. This also means a season occurrence that's already mostly over
    by the time this ships is correctly skipped entirely rather than
    misfiring — the next real notification is simply the *next* occurrence.
  - The property's overall calendar reach (`calculate_max_booking_date/3`,
    driven by *today's* current season) has extended far enough to include
    the weekend's check-in date — this is what stops e.g. a Summer weekend
    from being reported open while still deep in Winter, even though Summer
    itself may have no advance-booking limit of its own.
  - The weekend's own season doesn't independently restrict it further
    (`date_selectable?/4`, checked for both check-in and check-out in case a
    season boundary falls inside the weekend).

  Returns `nil` when no season with that name is configured, otherwise a map
  with `:season`, `:weekend_checkin`, `:weekend_checkout`, `:cycle_year`
  (the resolved occurrence's start year — a stable dedup key across the
  season's annual recurrence), and `:open?`.
  """
  def first_weekend_booking_window(property, seasons, today, season_name)
      when is_list(seasons) do
    case Enum.find(seasons, &(&1.name == season_name)) do
      nil ->
        nil

      season ->
        {season_start, _season_end} = get_season_date_range(season, today)
        weekend_checkin = next_friday_on_or_after(season_start)
        weekend_checkout = Date.add(weekend_checkin, 2)

        max_booking_date = calculate_max_booking_date(property, today, seasons)

        open? =
          Date.compare(weekend_checkin, today) != :lt and
            Date.compare(weekend_checkin, max_booking_date) != :gt and
            date_selectable?(property, weekend_checkin, today, seasons) and
            date_selectable?(property, weekend_checkout, today, seasons)

        %{
          season: season,
          weekend_checkin: weekend_checkin,
          weekend_checkout: weekend_checkout,
          cycle_year: season_start.year,
          open?: open?
        }
    end
  end

  defp next_friday_on_or_after(date) do
    case Date.day_of_week(date, :monday) do
      5 -> date
      dow when dow < 5 -> Date.add(date, 5 - dow)
      dow -> Date.add(date, 5 - dow + 7)
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
  def calculate_max_booking_date(
        property,
        today \\ cabin_today(),
        seasons \\ nil
      )

  def calculate_max_booking_date(_property, today, seasons)
      when is_list(seasons) do
    current_season = Season.find_season_for_date(seasons, today)
    max_booking_date_for_current_season(current_season, today, seasons)
  end

  def calculate_max_booking_date(property, today, nil) do
    current_season = Season.for_date(property, today)
    max_booking_date_for_current_season(current_season, today, nil)
  end

  defp max_booking_date_for_current_season(current_season, today, seasons) do
    if current_season do
      calculate_max_booking_date_with_season(current_season, today, seasons)
    else
      Date.add(today, 365)
    end
  end

  defp calculate_max_booking_date_with_season(current_season, today, seasons) do
    if current_season.advance_booking_days &&
         current_season.advance_booking_days > 0 do
      # Current season has a limit - apply it
      Date.add(today, current_season.advance_booking_days)
    else
      calculate_max_booking_date_no_limit(current_season, today, seasons)
    end
  end

  defp calculate_max_booking_date_no_limit(current_season, today, seasons) do
    {_season_start, season_end} = get_season_date_range(current_season, today)

    resolve_unlimited_chain(
      current_season,
      current_season,
      today,
      seasons,
      season_end
    )
  end

  # Walks forward through the season chain starting after `current_season`,
  # extending `max_date` past each season's own end while that season also
  # has no advance-booking limit of its own. Stops (and applies the limit)
  # at the first season with a real `advance_booking_days`. If the chain
  # loops back to `origin_season` without ever finding one, no season in the
  # property's rotation restricts advance booking at all, so the calendar is
  # capped at a practical horizon (`@unlimited_horizon_days`) instead of
  # literally forever.
  defp resolve_unlimited_chain(
         origin_season,
         current_season,
         today,
         seasons,
         max_date
       ) do
    next_season = get_next_season(current_season, today, seasons)

    cond do
      next_season == nil ->
        Date.add(today, @unlimited_horizon_days)

      next_season.id == origin_season.id ->
        Date.add(today, @unlimited_horizon_days)

      next_season.advance_booking_days && next_season.advance_booking_days > 0 ->
        next_season_max = Date.add(today, next_season.advance_booking_days)

        if Date.compare(next_season_max, max_date) == :gt,
          do: next_season_max,
          else: max_date

      true ->
        {_next_start, next_end} = get_season_date_range(next_season, today)

        new_max =
          if Date.compare(next_end, max_date) == :gt,
            do: next_end,
            else: max_date

        resolve_unlimited_chain(
          origin_season,
          next_season,
          today,
          seasons,
          new_max
        )
    end
  end

  @doc """
  Checks if a specific date is selectable based on season advance booking restrictions.

  Returns true if the date can be selected, false if it should be disabled.
  A date is selectable if:
  - It's in a season with no advance booking limit, OR
  - It's in a season with a limit AND it's within the advance booking window
  """
  def date_selectable?(
        property,
        date,
        today \\ cabin_today(),
        seasons \\ nil
      )

  def date_selectable?(_property, date, today, seasons) when is_list(seasons) do
    season = Season.find_season_for_date(seasons, date)
    date_selectable_for_season?(season, date, today)
  end

  def date_selectable?(property, date, today, nil) do
    season = Season.for_date(property, date)
    date_selectable_for_season?(season, date, today)
  end

  defp date_selectable_for_season?(season, date, today) do
    if season && season.advance_booking_days && season.advance_booking_days > 0 do
      max_booking_date = Date.add(today, season.advance_booking_days)
      Date.compare(date, max_booking_date) != :gt
    else
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
        _today \\ cabin_today()
      ) do
    # Allow bookings across seasons - no restriction
    %{}
  end

  @doc """
  Validates advance booking limit using rules from the season(s) that the booking dates fall into.

  If a booking extends into a season with a limit, that limit applies to the booking.

  `today` defaults to the cabin timezone (`America/Los_Angeles`). Checkout day
  must also fall within the advance window.
  """
  def validate_advance_booking_limit(
        property,
        checkin_date,
        checkout_date,
        today \\ cabin_today()
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
  defp get_next_season(current_season, reference_date, seasons) do
    alias Ysc.Bookings.SeasonCache

    all_seasons =
      if is_list(seasons) do
        seasons
      else
        SeasonCache.get_all_for_property(current_season.property)
      end

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
