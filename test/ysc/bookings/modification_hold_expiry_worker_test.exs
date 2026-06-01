defmodule Ysc.Bookings.ModificationHoldExpiryWorkerTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Ysc.Bookings.{
    Booking,
    BookingLocker,
    ModificationHoldExpiryWorker
  }

  alias Ysc.Repo

  setup do
    Ysc.Ledgers.ensure_basic_accounts()

    user =
      user_fixture()
      |> Ecto.Changeset.change(state: :active)
      |> Repo.update!()

    {:ok, _} =
      Ysc.Bookings.create_pricing_rule(%{
        amount: Money.new(500, :USD),
        booking_mode: :buyout,
        price_unit: :buyout_fixed,
        property: :tahoe,
        season_id: nil
      })

    %{user: user}
  end

  test "expires stale modification holds", %{user: user} do
    {checkin, checkout} = tahoe_booking_dates(130)
    extended_checkout = Date.add(checkout, 1)

    assert {:ok, total, _} =
             Ysc.Bookings.calculate_booking_price(
               :tahoe,
               checkin,
               checkout,
               :buyout,
               guests_count: 4
             )

    assert {:ok, %Booking{} = booking} =
             BookingLocker.create_admin_booking(
               %{
                 user_id: user.id,
                 property: :tahoe,
                 checkin_date: checkin,
                 checkout_date: checkout,
                 booking_mode: :buyout,
                 guests_count: 4,
                 total_price: total
               },
               skip_email: true,
               skip_reminders: true
             )

    attrs = %{
      checkin_date: checkin,
      checkout_date: extended_checkout,
      guests_count: 4,
      children_count: 0
    }

    assert {:ok, held_booking} =
             Ysc.Bookings.place_modification_hold(booking, attrs)

    held_booking
    |> Ecto.Changeset.change(
      modification_hold_expires_at:
        DateTime.add(
          DateTime.utc_now() |> DateTime.truncate(:second),
          -5,
          :minute
        )
    )
    |> Repo.update!()

    ModificationHoldExpiryWorker.expire_expired_modification_holds()

    reloaded = Repo.get!(Booking, booking.id)
    assert is_nil(reloaded.modification_hold_expires_at)
    assert reloaded.modification_hold_attrs
    assert reloaded.modification_hold_attrs["checkout_date"] ==
             Date.to_iso8601(extended_checkout)
  end
end
