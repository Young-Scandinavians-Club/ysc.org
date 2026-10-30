defmodule Ysc.Bookings.BookingFixtureDatesTest do
  @moduledoc """
  Guards Tahoe buyout fixture dates around the summer→winter boundary.

  Winter nights are rooms-only. Once today is late enough that no
  Monday–Thursday buyout stay remains in the current bookable window,
  `locker_buyout_dates/1` and `booking_fixture/1` must still return a
  future stay where buyout is allowed — otherwise checkout, locker, and
  email tests fail as a pack every year from ~Oct 26 through April.

  Kiosk lookup/calendar tests need a stay covering *today*, which cannot
  stay on buyout nights through that same window. Those tests must use
  `active_check_in_booking_fixture/1` (room conversion), not
  `Bookings.create_booking/1` with `:buyout`.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Ysc.Bookings.Season

  test "locker_buyout_dates returns a future stay that allows Tahoe buyout" do
    {checkin, checkout} = locker_buyout_dates()

    assert Date.compare(checkin, Date.utc_today()) == :gt
    assert Date.compare(checkout, checkin) == :gt
    assert Season.buyout_allowed_for_stay?(:tahoe, checkin, checkout)
  end

  test "distinct locker_buyout_dates slots stay on buyout-allowed nights" do
    stays =
      Enum.map(0..3, fn slot ->
        {checkin, checkout} = locker_buyout_dates(slot)
        assert Season.buyout_allowed_for_stay?(:tahoe, checkin, checkout)
        {checkin, checkout}
      end)

    assert Enum.uniq(stays) == stays
  end

  test "booking_fixture keeps buyout mode when the caller asked for buyout" do
    user = user_fixture()
    booking = booking_fixture(%{user_id: user.id, booking_mode: :buyout})

    assert booking.booking_mode == :buyout

    assert Season.buyout_allowed_for_stay?(
             :tahoe,
             booking.checkin_date,
             booking.checkout_date
           )
  end

  test "booking_fixture does not UPDATE shared season rows" do
    before =
      Repo.all(from s in Season, select: {s.id, s.advance_booking_days})

    _booking = booking_fixture()

    after_call =
      Repo.all(from s in Season, select: {s.id, s.advance_booking_days})

    assert after_call == before
  end

  test "active_check_in_booking_fixture inserts when the live window includes winter nights" do
    seed_canonical_seasons!()

    # Same window CI hit on 2026-10-30 (job 124101664265): checkin Oct 29,
    # checkout Nov 2. Nov 1 is a winter night, so create_booking + buyout
    # fails with "entire cabin isn't available for winter nights".
    today = ~D[2026-10-30]
    {checkin, checkout} = active_stay_dates(today)

    assert checkin == ~D[2026-10-29]
    assert checkout == ~D[2026-11-02]
    refute Season.buyout_allowed_for_stay?(:tahoe, checkin, checkout)

    assert {:error, changeset} =
             Ysc.Bookings.create_booking(%{
               checkin_date: checkin,
               checkout_date: checkout,
               guests_count: 2,
               property: :tahoe,
               booking_mode: :buyout,
               user_id: user_fixture().id,
               status: :complete,
               total_price: Money.new(200, :USD)
             })

    assert changeset.errors[:booking_mode]

    booking =
      active_check_in_booking_fixture(%{
        checkin_date: checkin,
        checkout_date: checkout
      })

    assert booking.status == :complete
    assert booking.booking_mode == :room
    assert booking.checkin_date == checkin
    assert booking.checkout_date == checkout
    assert Date.compare(booking.checkin_date, today) != :gt
    assert Date.compare(booking.checkout_date, today) == :gt
  end
end
