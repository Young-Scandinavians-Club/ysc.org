defmodule Ysc.Bookings.PricingHelpersTest do
  @moduledoc """
  Tests for Ysc.Bookings.PricingHelpers.
  """
  use Ysc.DataCase, async: false

  import Phoenix.Component, only: [assign: 2]

  alias Ysc.Bookings
  alias Ysc.Bookings.PricingHelpers

  @checkin ~D[2026-07-01]
  @checkout ~D[2026-07-03]

  defp lv_socket(assigns) when is_map(assigns) do
    assign(%Phoenix.LiveView.Socket{}, assigns)
  end

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    Ysc.Bookings.SeasonCache.invalidate()
    Cachex.clear(:ysc_cache)

    {:ok, category} =
      %Ysc.Bookings.RoomCategory{}
      |> Ysc.Bookings.RoomCategory.changeset(%{
        name: "PricingHelpers #{System.unique_integer()}"
      })
      |> Ysc.Repo.insert()

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(:USD, 500),
        booking_mode: :buyout,
        price_unit: :buyout_fixed,
        property: :tahoe,
        season_id: nil
      })

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(:USD, 30),
        booking_mode: :day,
        price_unit: :per_guest_per_day,
        property: :clear_lake,
        season_id: nil
      })

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(:USD, 45),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        room_category_id: category.id,
        season_id: nil
      })

    {:ok, room} =
      Bookings.create_room(%{
        name: "PH Room #{System.unique_integer()}",
        property: :tahoe,
        room_category_id: category.id,
        capacity_max: 8,
        min_billable_occupancy: 1
      })

    {:ok, room2} =
      Bookings.create_room(%{
        name: "PH Room2 #{System.unique_integer()}",
        property: :tahoe,
        room_category_id: category.id,
        capacity_max: 8,
        min_billable_occupancy: 2
      })

    %{category: category, room: room, room2: room2}
  end

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

    test "returns true for room mode with single room id" do
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

    test "returns true for room mode with non-empty selected_room_ids list" do
      socket = %{
        assigns: %{
          checkin_date: Date.utc_today(),
          checkout_date: Date.utc_today(),
          selected_booking_mode: :room,
          selected_room_ids: ["a", "b"]
        }
      }

      assert PricingHelpers.ready_for_price_calculation?(socket, :tahoe)
    end

    test "returns true for day mode with positive guest count" do
      socket = %{
        assigns: %{
          checkin_date: Date.utc_today(),
          checkout_date: Date.utc_today(),
          selected_booking_mode: :day,
          guests_count: 2
        }
      }

      assert PricingHelpers.ready_for_price_calculation?(socket, :clear_lake)
    end

    test "returns false for day mode with zero guests" do
      socket = %{
        assigns: %{
          checkin_date: Date.utc_today(),
          checkout_date: Date.utc_today(),
          selected_booking_mode: :day,
          guests_count: 0
        }
      }

      refute PricingHelpers.ready_for_price_calculation?(socket, :clear_lake)
    end
  end

  describe "calculate_price_if_ready/3" do
    test "calculates buyout price and assigns breakdown" do
      socket =
        lv_socket(%{
          checkin_date: @checkin,
          checkout_date: @checkout,
          selected_booking_mode: :buyout,
          guests_count: 2,
          children_count: 0
        })

      updated = PricingHelpers.calculate_price_if_ready(socket, :tahoe)

      assert updated.assigns.calculated_price == Money.new(:USD, 1000)
      assert updated.assigns.price_error == nil
      assert updated.assigns.price_breakdown.guests_count == 2
    end

    test "calculates room price for selected room", %{room: room} do
      socket =
        lv_socket(%{
          checkin_date: @checkin,
          checkout_date: @checkout,
          selected_booking_mode: :room,
          selected_room_id: room.id,
          guests_count: 2,
          children_count: 0
        })

      updated = PricingHelpers.calculate_price_if_ready(socket, :tahoe)

      assert updated.assigns.price_error == nil
      assert Money.positive?(updated.assigns.calculated_price)
      assert updated.assigns.price_breakdown.room_count == 1
    end

    test "returns error when multi-room mode has empty selected_room_ids", %{
      room: room
    } do
      # ready_for_price_calculation? is true via selected_room_id, but when
      # can_select_multiple_rooms_fn is true only selected_room_ids is used.
      socket =
        lv_socket(%{
          checkin_date: @checkin,
          checkout_date: @checkout,
          selected_booking_mode: :room,
          selected_room_id: room.id,
          selected_room_ids: [],
          guests_count: 2,
          children_count: 0
        })

      updated =
        PricingHelpers.calculate_price_if_ready(
          socket,
          :tahoe,
          can_select_multiple_rooms_fn: fn _ -> true end
        )

      assert updated.assigns.price_error =~ "Please select at least one room"
    end

    test "calculates day mode price for Clear Lake" do
      socket =
        lv_socket(%{
          checkin_date: @checkin,
          checkout_date: @checkout,
          selected_booking_mode: :day,
          guests_count: 3,
          children_count: 0
        })

      updated = PricingHelpers.calculate_price_if_ready(socket, :clear_lake)

      assert updated.assigns.price_error == nil
      assert updated.assigns.calculated_price == Money.new(:USD, 180)
    end

    test "clears price assigns when not ready" do
      socket = lv_socket(%{selected_booking_mode: :buyout})

      updated = PricingHelpers.calculate_price_if_ready(socket, :tahoe)

      assert updated.assigns.calculated_price == nil
      assert updated.assigns.price_breakdown == nil
      assert updated.assigns.price_error == nil
    end

    test "uses custom guest parsing when provided" do
      socket =
        lv_socket(%{
          checkin_date: @checkin,
          checkout_date: @checkout,
          selected_booking_mode: :day,
          guests_count: "4",
          children_count: 0
        })

      updated =
        PricingHelpers.calculate_price_if_ready(socket, :clear_lake,
          parse_guests_fn: fn v -> String.to_integer(v) end
        )

      assert updated.assigns.price_error == nil
    end

    test "applies minimum billable occupancy across multiple rooms", %{
      room: room,
      room2: room2
    } do
      socket =
        lv_socket(%{
          checkin_date: @checkin,
          checkout_date: @checkout,
          selected_booking_mode: :room,
          selected_room_ids: [room.id, room2.id],
          guests_count: 1,
          children_count: 0,
          available_rooms: [
            %{id: room.id, min_billable_occupancy: 1},
            %{id: room2.id, min_billable_occupancy: 2}
          ]
        })

      updated =
        PricingHelpers.calculate_price_if_ready(
          socket,
          :tahoe,
          can_select_multiple_rooms_fn: fn _ -> true end
        )

      assert updated.assigns.price_error == nil
      assert updated.assigns.price_breakdown.billable_people >= 1
      assert updated.assigns.price_breakdown.room_count == 2
    end

    test "returns error when date range is invalid for pricing" do
      socket =
        lv_socket(%{
          checkin_date: @checkin,
          checkout_date: @checkin,
          selected_booking_mode: :day,
          guests_count: 2,
          children_count: 0
        })

      updated = PricingHelpers.calculate_price_if_ready(socket, :clear_lake)

      assert updated.assigns.price_error =~ "Unable to calculate price"
    end
  end
end
