defmodule Ysc.Bookings.ModificationHoldTest do
  use ExUnit.Case, async: true

  alias Ysc.Bookings.{Booking, BookingLocker}

  defp hold_booking(overrides \\ %{}) do
    checkin = ~D[2026-07-01]
    checkout = ~D[2026-07-05]

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(30, :minute)
      |> DateTime.truncate(:second)

    defaults = %{
      modification_hold_expires_at: expires_at,
      modification_hold_attrs: %{
        "checkin_date" => Date.to_iso8601(checkin),
        "checkout_date" => Date.to_iso8601(checkout),
        "guests_count" => 2,
        "children_count" => 0,
        "held_days" => []
      }
    }

    struct(Booking, Map.merge(defaults, overrides))
  end

  defp hold_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        checkin_date: ~D[2026-07-01],
        checkout_date: ~D[2026-07-05],
        guests_count: 2,
        children_count: 0
      },
      overrides
    )
  end

  describe "modification_hold_active?/1 and modification_hold_matches?/2" do
    test "active hold matches identical modification attrs" do
      booking = hold_booking()

      assert BookingLocker.modification_hold_active?(booking)
      assert BookingLocker.modification_hold_matches?(booking, hold_attrs())
    end

    test "expired hold is inactive and does not match" do
      expired_at =
        DateTime.utc_now()
        |> DateTime.add(-1, :minute)
        |> DateTime.truncate(:second)

      booking = hold_booking(%{modification_hold_expires_at: expired_at})

      refute BookingLocker.modification_hold_active?(booking)
      refute BookingLocker.modification_hold_matches?(booking, hold_attrs())
    end

    test "hold does not match when guest count differs" do
      booking = hold_booking()

      refute BookingLocker.modification_hold_matches?(
               booking,
               hold_attrs(%{guests_count: 3})
             )
    end

    test "hold does not match when checkout date differs" do
      booking = hold_booking()

      refute BookingLocker.modification_hold_matches?(
               booking,
               hold_attrs(%{checkout_date: ~D[2026-07-06]})
             )
    end

    test "hold without attrs is inactive" do
      booking =
        hold_booking(%{
          modification_hold_attrs: nil
        })

      refute BookingLocker.modification_hold_active?(booking)
    end
  end
end
