defmodule Ysc.BookingsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ysc.Bookings` context.
  """

  alias Ysc.Bookings
  alias Ysc.Bookings.SeasonHelpers

  # Tahoe winter is Nov 1 - Apr 30 (month in 1..4 or 11..12)
  defp tahoe_winter_month?(month), do: month in [1, 2, 3, 4, 11, 12]

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
  Returns `{checkin, checkout}` for a Tahoe stay that satisfies weekend and summer rules.

  Used by tests that call `Bookings.create_booking/1` directly. `offset_days` is added to
  today's date before snapping to the first Monday on or after that day (then summer
  adjustment when the month is Tahoe winter).

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

    # Buyout is only allowed in summer; ensure default checkin is in summer (May–Oct).
    checkin =
      if tahoe_winter_month?(checkin.month) do
        year =
          if checkin.month in [1, 2, 3, 4],
            do: checkin.year,
            else: checkin.year + 1

        may_first = Date.new!(year, 5, 1)
        first_monday_on_or_after(may_first)
      else
        checkin
      end

    checkin = clamp_date(checkin, earliest_checkin, latest_checkin)

    checkout = Date.add(checkin, 3)

    if Date.compare(checkout, max_booking_date) == :gt do
      {Date.add(max_booking_date, -3), max_booking_date}
    else
      {checkin, checkout}
    end
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

  def booking_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    user_id = attrs[:user_id] || Ysc.AccountsFixtures.user_fixture().id
    {checkin, checkout} = tahoe_booking_dates(7)

    {refund_forfeited_at, attrs} = Map.pop(attrs, :refund_forfeited_at)

    {:ok, booking} =
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
      |> Bookings.create_booking()

    if refund_forfeited_at do
      booking
      |> Ecto.Changeset.change(refund_forfeited_at: refund_forfeited_at)
      |> Ysc.Repo.update!()
    else
      booking
    end
  end

  @doc """
  Creates a confirmed booking in an active stay window for kiosk check-in tests.
  """
  def active_check_in_booking_fixture(attrs \\ %{}) do
    today_pst =
      DateTime.now!("America/Los_Angeles")
      |> DateTime.to_date()

    attrs =
      attrs
      |> Map.new()
      |> Map.put_new(:status, :complete)
      |> Map.put_new(:checkin_date, Date.add(today_pst, -1))
      |> Map.put_new(:checkout_date, Date.add(today_pst, 2))

    booking_fixture(attrs)
  end
end
