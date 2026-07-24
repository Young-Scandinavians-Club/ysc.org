defmodule Ysc.BookingsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ysc.Bookings` context.
  """

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, Room, Season}
  alias Ysc.Bookings.SeasonHelpers
  alias Ysc.Repo

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
            max_booking_date
          ) ->
        next

      Date.compare(checkout, max_booking_date) == :gt ->
        {Date.add(max_booking_date, -3), max_booking_date}

      true ->
        {checkin, checkout}
    end
  end

  defp next_buyout_allowed_monday_stay(
         earliest_checkin,
         latest_checkin,
         max_booking_date
       ) do
    Enum.find_value(0..520, fn offset ->
      candidate =
        earliest_checkin
        |> Date.add(offset)
        |> first_monday_on_or_after()

      if Date.compare(candidate, latest_checkin) != :gt do
        checkout = Date.add(candidate, 3)

        if Date.compare(checkout, max_booking_date) != :gt and
             Season.buyout_allowed_for_stay?(:tahoe, candidate, checkout) do
          {candidate, checkout}
        end
      end
    end)
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

    changeset_opts = if rooms, do: [rooms: List.wrap(rooms)], else: []

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
  Creates a confirmed booking in an active stay window for kiosk check-in tests.
  """
  def active_check_in_booking_fixture(attrs \\ %{}) do
    today_pst =
      DateTime.now!("America/Los_Angeles")
      |> DateTime.to_date()

    attrs = Map.new(attrs)

    checkin = Map.get(attrs, :checkin_date, Date.add(today_pst, -1))
    checkout = Map.get(attrs, :checkout_date, Date.add(today_pst, 2))
    checkout = ensure_sunday_when_saturday_included(checkin, checkout)

    attrs
    |> Map.put_new(:status, :complete)
    |> Map.put(:checkin_date, checkin)
    |> Map.put(:checkout_date, checkout)
    |> booking_fixture()
  end
end
