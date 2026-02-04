defmodule Ysc.Bookings.PricingHelpersTest do
  @moduledoc """
  Tests for Ysc.Bookings.PricingHelpers.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Bookings.PricingHelpers

  describe "ready_for_price_calculation?/2" do
    test "returns false if dates are missing" do
      socket = %{assigns: %{}}
      refute PricingHelpers.ready_for_price_calculation?(socket, :tahoe)
    end

    test "returns true for buyout with dates" do
      socket = %{
        assigns: %{
          checkin_date: Date.utc_today(),
          checkout_date: Date.utc_today(),
          selected_booking_mode: :buyout
        }
      }

      assert PricingHelpers.ready_for_price_calculation?(socket, :tahoe)
    end

    test "returns false for room mode without selection" do
      socket = %{
        assigns: %{
          checkin_date: Date.utc_today(),
          checkout_date: Date.utc_today(),
          selected_booking_mode: :room
        }
      }

      refute PricingHelpers.ready_for_price_calculation?(socket, :tahoe)
    end

    test "returns true for room mode with selection" do
      socket = %{
        assigns: %{
          checkin_date: Date.utc_today(),
          checkout_date: Date.utc_today(),
          selected_booking_mode: :room,
          selected_room_id: "room_123"
        }
      }

      assert PricingHelpers.ready_for_price_calculation?(socket, :tahoe)
    end
  end
end
