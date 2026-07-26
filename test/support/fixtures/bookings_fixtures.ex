defmodule Ysc.BookingsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ysc.Bookings` context.
  """

  import Ecto.Query

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, Room, Season}
  alias Ysc.Bookings.SeasonHelpers
  alias Ysc.Repo

  @doc """
  Deletes all seasons in the current SQL sandbox and invalidates SeasonCache.

  Committed seasons in the shared test DB are visible inside sandboxed tests;
  never assume an empty seasons table without calling this (or `seed_canonical_seasons!/0`).
  """
  def clear_seasons! do
    Repo.delete_all(Season)
    Ysc.Bookings.SeasonCache.invalidate()
    :ok
  end

  @doc """
  Replaces all seasons with the canonical Tahoe/Clear Lake calendar used in seeds.

  Winter: Nov 1 – Apr 30 (rooms-only buyout rule). Summer: May 1 – Oct 31
  (default, unlimited advance for Tahoe summer). Prefer this over assuming
  leftover seasons in `ysc_test` match production.
  """
  def seed_canonical_seasons! do
    clear_seasons!()

    base_year = 2024
    winter_start = Date.new!(base_year, 11, 1)
    winter_end = Date.new!(base_year + 1, 4, 30)
    summer_start = Date.new!(base_year, 5, 1)
    summer_end = Date.new!(base_year, 10, 31)

    for attrs <- [
          %{
            name: "Winter",
            property: :tahoe,
            start_date: winter_start,
            end_date: winter_end,
            is_default: false,
            advance_booking_days: 45,
            max_nights: 4
          },
          %{
            name: "Summer",
            property: :tahoe,
            start_date: summer_start,
            end_date: summer_end,
            is_default: true,
            advance_booking_days: nil,
            max_nights: 4
          },
          %{
            name: "Winter",
            property: :clear_lake,
            start_date: winter_start,
            end_date: winter_end,
            is_default: false,
            advance_booking_days: nil,
            max_nights: 30
          },
          %{
            name: "Summer",
            property: :clear_lake,
            start_date: summer_start,
            end_date: summer_end,
            is_default: true,
            advance_booking_days: nil,
            max_nights: 30
          }
        ] do
      %Season{}
      |> Season.changeset(attrs)
      |> Repo.insert!()
    end

    Ysc.Bookings.SeasonCache.invalidate()
    :ok
  end

  @doc """
  Widens season advance-booking windows so locker/integration tests can use
  far-future dates for isolation without tripping validation.

  Uses a large day count (not `nil`): `nil` means “no per-date cap” but
  `SeasonHelpers.calculate_max_booking_date/2` still clamps to the end of the
  current season when the next season also has no limit. Prefer ~2 years over
  365 so year+2 isolation dates remain valid.
  """
  def allow_far_future_booking_dates do
    from(s in Season)
    |> Repo.update_all(set: [advance_booking_days: 800])

    Ysc.Bookings.SeasonCache.invalidate()
    :ok
  end

  @doc """
  Returns Tahoe buyout dates within advance-booking and season buyout rules.

  `slot` selects different offsets for test isolation.
  """
  def locker_buyout_dates(slot \\ 0) do
    buyout_monday_stay_at_index(7 + rem(slot, 34))
  end

  @doc """
  Returns Tahoe room booking dates within advance-booking and season rules.

  `slot` selects different offsets for test isolation.
  """
  def locker_room_dates(slot \\ 0, nights \\ 2) do
    {checkin, _} = buyout_monday_stay_at_index(7 + rem(slot, 34))
    {checkin, Date.add(checkin, nights)}
  end

  @doc """
  Returns buyout dates at least `min_days_ahead` days from today.
  """
  def locker_future_buyout_dates(min_days_ahead \\ 14) do
    today = Date.utc_today()
    min_checkin = Date.add(today, min_days_ahead)

    Enum.find(enumerate_buyout_monday_stays(), fn {checkin, _} ->
      Date.compare(checkin, min_checkin) != :lt
    end) || buyout_monday_stay_at_index(14)
  end

  @doc """
  Returns buyout dates starting after `after_date`, separated by at least `gap_days`.
  """
  def locker_buyout_dates_after(%Date{} = after_date, gap_days \\ 7) do
    min_checkin = Date.add(after_date, gap_days)

    Enum.find(enumerate_buyout_monday_stays(), fn {checkin, _} ->
      Date.compare(checkin, min_checkin) != :lt
    end) || buyout_monday_stay_at_index(0)
  end

  defp first_monday_on_or_after(date) do
    case Date.day_of_week(date, :monday) do
      1 -> date
      n -> Date.add(date, 8 - n)
    end
  end

  defp first_monday_on_or_before(date) do
    case Date.day_of_week(date, :monday) do
      1 -> date
      n -> Date.add(date, 1 - n)
    end
  end

  defp clamp_date(date, min_date, max_date) do
    date
    |> then(fn d ->
      if Date.compare(d, min_date) == :lt, do: min_date, else: d
    end)
    |> then(fn d ->
      if Date.compare(d, max_date) == :gt, do: max_date, else: d
    end)
  end

  @doc """
  Returns `{checkin, checkout}` for a Tahoe stay that satisfies weekend and buyout rules.

  Used by tests that call `Bookings.create_booking/1` directly. `offset_days` is added to
  today's date before snapping to the first Monday on or after that day (then adjusted
  onto nights where the configured seasons allow buyout).

  Dates are clamped to the property's advance-booking window so tests stay valid when
  seasons enforce a limit (and when another test temporarily changes season settings).
  """
  def tahoe_booking_dates(offset_days \\ 7) do
    today = Date.utc_today()
    max_booking_date = SeasonHelpers.calculate_max_booking_date(:tahoe, today)

    # Advance-booking validation requires check-in and check-out within the window.
    latest_checkin = Date.add(max_booking_date, -3)
    earliest_checkin = Date.add(today, 1)

    base =
      today
      |> Date.add(offset_days)
      |> clamp_date(earliest_checkin, latest_checkin)

    # Ensure we don't hit the "Saturday must include Sunday" rule:
    # Start on a Monday, stay for 3 nights (checkout Thursday).
    checkin =
      base
      |> first_monday_on_or_after()
      |> then(fn date ->
        if Date.compare(date, latest_checkin) == :gt do
          first_monday_on_or_before(latest_checkin)
        else
          date
        end
      end)

    checkout = Date.add(checkin, 3)

    cond do
      Season.buyout_allowed_for_stay?(:tahoe, checkin, checkout) and
          Date.compare(checkout, max_booking_date) != :gt ->
        {checkin, checkout}

      next =
          next_buyout_allowed_monday_stay(
            earliest_checkin,
            latest_checkin,
            max_booking_date,
            offset_days
          ) ->
        next

      Date.compare(checkout, max_booking_date) == :gt ->
        {Date.add(max_booking_date, -3), max_booking_date}

      true ->
        {checkin, checkout}
    end
  end

  defp buyout_monday_stay_at_index(index) do
    stays = enumerate_buyout_monday_stays()

    case stays do
      [] -> tahoe_booking_dates_fallback(index)
      stays -> Enum.at(stays, rem(max(index, 0), length(stays)))
    end
  end

  defp enumerate_buyout_monday_stays do
    today = Date.utc_today()
    max_booking_date = SeasonHelpers.calculate_max_booking_date(:tahoe, today)
    earliest_checkin = Date.add(today, 1)
    latest_checkin = Date.add(max_booking_date, -3)

    earliest_checkin
    |> first_monday_on_or_after()
    |> Stream.iterate(&Date.add(&1, 7))
    |> Stream.take_while(&(Date.compare(&1, latest_checkin) != :gt))
    |> Enum.reduce([], fn checkin, acc ->
      checkout = Date.add(checkin, 3)

      if Date.compare(checkout, max_booking_date) != :gt and
           Season.buyout_allowed_for_stay?(:tahoe, checkin, checkout) do
        [{checkin, checkout} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp next_buyout_allowed_monday_stay(
         _earliest_checkin,
         _latest_checkin,
         _max_booking_date,
         offset_days
       ) do
    buyout_monday_stay_at_index(offset_days)
  end

  defp tahoe_booking_dates_fallback(offset_days) do
    today = Date.utc_today()
    max_booking_date = SeasonHelpers.calculate_max_booking_date(:tahoe, today)
    latest_checkin = Date.add(max_booking_date, -3)
    earliest_checkin = Date.add(today, 1)

    base =
      today
      |> Date.add(offset_days)
      |> clamp_date(earliest_checkin, latest_checkin)

    checkin =
      base
      |> first_monday_on_or_after()
      |> then(fn date ->
        if Date.compare(date, latest_checkin) == :gt do
          first_monday_on_or_before(latest_checkin)
        else
          date
        end
      end)

    checkout = Date.add(checkin, 3)

    if Date.compare(checkout, max_booking_date) == :gt do
      {Date.add(max_booking_date, -3), max_booking_date}
    else
      {checkin, checkout}
    end
  end

  @doc """
  Returns `{checkin, checkout}` for a Tahoe room stay with a safe Monday check-in.

  `nights` is the number of nights (checkout is `checkin + nights`). Uses
  `tahoe_booking_dates/1` for the check-in so weekend and advance-booking rules hold.
  """
  def tahoe_room_booking_dates(offset_days \\ 7, nights \\ 2) do
    {checkin, _} = tahoe_booking_dates(offset_days)
    {checkin, Date.add(checkin, nights)}
  end

  @doc """
  Ensures inclusive stay dates containing Saturday also include Sunday (Tahoe weekend rule).
  """
  def ensure_sunday_when_saturday_included(checkin, checkout) do
    dates = Date.range(checkin, checkout) |> Enum.to_list()

    has_saturday? = Enum.any?(dates, &(Date.day_of_week(&1, :monday) == 6))
    has_sunday? = Enum.any?(dates, &(Date.day_of_week(&1, :monday) == 7))

    if has_saturday? and not has_sunday? do
      Date.add(checkout, 1)
    else
      checkout
    end
  end

  @doc """
  Adjusts check-in when checkout is fixed so Tahoe's Saturday/Sunday weekend rule holds.

  When the preferred check-in produces a span that includes Saturday but not Sunday
  (typically checkout on Saturday), moves check-in to the preceding Sunday.
  """
  def tahoe_checkin_for_fixed_checkout(checkout, preferred_checkin) do
    cond do
      tahoe_weekend_range_valid?(preferred_checkin, checkout) ->
        preferred_checkin

      Date.day_of_week(checkout, :monday) == 6 ->
        Date.add(checkout, -6)

      true ->
        preferred_checkin
    end
  end

  defp tahoe_weekend_range_valid?(checkin, checkout) do
    dates = Date.range(checkin, checkout) |> Enum.to_list()
    has_saturday? = Enum.any?(dates, &(Date.day_of_week(&1, :monday) == 6))
    has_sunday? = Enum.any?(dates, &(Date.day_of_week(&1, :monday) == 7))
    not has_saturday? or has_sunday?
  end

  def booking_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    user_id = attrs[:user_id] || Ysc.AccountsFixtures.user_fixture().id
    {checkin, checkout} = tahoe_booking_dates(7)

    {refund_forfeited_at, attrs} = Map.pop(attrs, :refund_forfeited_at)
    {rooms, attrs} = Map.pop(attrs, :rooms)

    merged =
      attrs
      |> Enum.into(%{
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: 2,
        property: :tahoe,
        booking_mode: :buyout,
        user_id: user_id,
        status: :draft,
        total_price: Money.new(200, :USD)
      })
      |> ensure_tahoe_winter_room_booking(rooms)

    {rooms, merged} =
      case Map.pop(merged, :rooms) do
        {nil, attrs} -> {rooms, attrs}
        {fixture_rooms, attrs} -> {fixture_rooms, attrs}
      end

    changeset_opts =
      [skip_validation: true] ++
        if(rooms, do: [rooms: List.wrap(rooms)], else: [])

    {:ok, booking} =
      %Booking{}
      |> Booking.changeset(merged, changeset_opts)
      |> Repo.insert()

    booking =
      if refund_forfeited_at do
        booking
        |> Ecto.Changeset.change(refund_forfeited_at: refund_forfeited_at)
        |> Repo.update!()
      else
        booking
      end

    booking
  end

  defp ensure_tahoe_winter_room_booking(attrs, rooms) do
    cond do
      rooms != nil ->
        attrs
        |> Map.put(:rooms, List.wrap(rooms))
        |> Map.put(:booking_mode, :room)

      Map.get(attrs, :property) == :tahoe &&
        Map.get(attrs, :booking_mode, :buyout) == :buyout &&
          not Season.buyout_allowed_for_stay?(
            :tahoe,
            attrs.checkin_date,
            attrs.checkout_date
          ) ->
        attrs
        |> Map.put(:booking_mode, :room)
        |> Map.put(:rooms, [tahoe_room_for_fixture!()])

      true ->
        attrs
    end
  end

  defp tahoe_room_for_fixture! do
    case Bookings.list_rooms(:tahoe) do
      [room | _] ->
        room

      _ ->
        {:ok, room} =
          %Room{}
          |> Room.changeset(%{
            name: "Fixture Tahoe Room",
            property: :tahoe,
            capacity_max: 4,
            is_active: true
          })
          |> Repo.insert()

        room
    end
  end

  @doc """
  Returns `{checkin, checkout}` for a past Mon-Thu stay outside the kiosk/mobile
  bookings index default window (7 days past through 30 days ahead).

  Use when tests assert omitted date params exclude old bookings. Dates satisfy
  Tahoe weekend and buyout-in-summer rules regardless of which weekday "today" is.
  """
  def past_booking_dates_outside_default_window(
        past_days \\ 120,
        today_pst \\ nil
      ) do
    today =
      today_pst ||
        DateTime.now!("America/Los_Angeles")
        |> DateTime.to_date()

    checkin =
      today
      |> Date.add(-past_days)
      |> first_monday_on_or_before()

    # Prefer past dates where configured seasons still allow buyout.
    checkin =
      Enum.find_value(0..400, fn offset ->
        candidate = Date.add(checkin, -offset) |> first_monday_on_or_before()
        checkout = Date.add(candidate, 3)

        if Season.buyout_allowed_for_stay?(:tahoe, candidate, checkout) do
          candidate
        end
      end) || checkin

    checkout =
      checkin
      |> Date.add(3)
      |> then(&ensure_sunday_when_saturday_included(checkin, &1))

    {checkin, checkout}
  end

  @doc """
  Returns `{checkin, checkout}` for a past Mon-Thu stay that satisfies Tahoe rules.

  Use when tests need a confirmed booking that has already ended regardless of
  which weekday "today" falls on (avoids Saturday-without-Sunday and 4-night cap).
  """
  def past_ended_stay_dates(today_pst \\ nil) do
    today =
      today_pst ||
        DateTime.now!("America/Los_Angeles")
        |> DateTime.to_date()

    checkin =
      today
      |> Date.add(-14)
      |> first_monday_on_or_before()

    checkout = Date.add(checkin, 3)
    {checkin, checkout}
  end

  @doc """
  Returns `{checkin, checkout}` for an active stay window (`checkin <= today < checkout`)
  that satisfies Tahoe Saturday/Sunday booking rules regardless of which weekday today falls on.
  """
  def active_stay_dates(today \\ nil, max_nights \\ 4) do
    today =
      today ||
        DateTime.now!("America/Los_Angeles")
        |> DateTime.to_date()

    checkin =
      today
      |> Date.add(-1)
      |> then(fn date ->
        if Date.day_of_week(date, :monday) == 6,
          do: Date.add(date, -1),
          else: date
      end)

    checkout =
      today
      |> Date.add(2)
      |> then(fn date ->
        if Date.day_of_week(date, :monday) == 7,
          do: Date.add(date, 1),
          else: date
      end)
      |> then(&ensure_sunday_when_saturday_included(checkin, &1))

    if Date.diff(checkout, checkin) > max_nights do
      checkin = Date.add(checkout, -max_nights)
      checkout = ensure_sunday_when_saturday_included(checkin, checkout)
      {checkin, checkout}
    else
      {checkin, checkout}
    end
  end

  @doc """
  Creates a confirmed booking in an active stay window for kiosk check-in tests.
  """
  def active_check_in_booking_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    {default_checkin, default_checkout} = active_stay_dates()

    checkin = Map.get(attrs, :checkin_date, default_checkin)
    checkout = Map.get(attrs, :checkout_date, default_checkout)

    attrs
    |> Map.put_new(:status, :complete)
    |> Map.put(:checkin_date, checkin)
    |> Map.put(:checkout_date, checkout)
    |> booking_fixture()
  end
end
