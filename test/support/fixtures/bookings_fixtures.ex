defmodule Ysc.BookingsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ysc.Bookings` context.
  """

  alias Ysc.Bookings

  # Tahoe winter is Nov 1 - Apr 30 (month in 1..4 or 11..12)
  defp tahoe_winter_month?(month), do: month in [1, 2, 3, 4, 11, 12]

  defp first_monday_on_or_after(date) do
    case Date.day_of_week(date, :monday) do
      1 -> date
      n -> Date.add(date, 8 - n)
    end
  end

  def booking_fixture(attrs \\ %{}) do
    user_id = attrs[:user_id] || Ysc.AccountsFixtures.user_fixture().id
    today = Date.utc_today()
    base = Date.add(today, 7)

    # Ensure we don't hit the "Saturday must include Sunday" rule:
    # Start on a Monday, stay for 3 nights (checkout Thursday).
    checkin = first_monday_on_or_after(base)

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

    checkout = Date.add(checkin, 3)

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

    booking
  end
end
