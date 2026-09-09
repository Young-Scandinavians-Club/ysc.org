defmodule Ysc.Events.CabinBlackoutTest do
  use ExUnit.Case, async: true

  alias Ysc.Events.CabinBlackout

  describe "property_for_event/1" do
    test "detects Clear Lake from the location name" do
      assert CabinBlackout.property_for_event(%{
               location_name: "Clear Lake Cabin",
               address: nil
             }) == :clear_lake
    end

    test "detects Clear Lake from the cabin address" do
      assert CabinBlackout.property_for_event(%{
               location_name: "YSC Retreat",
               address: "9325 Bass Road, Kelseyville, CA 95451"
             }) == :clear_lake
    end

    test "detects Tahoe from the location name" do
      assert CabinBlackout.property_for_event(%{
               location_name: "Lake Tahoe Cabin",
               address: nil
             }) == :tahoe
    end

    test "detects Tahoe from the cabin address" do
      assert CabinBlackout.property_for_event(%{
               location_name: "Cabin Weekend",
               address: "2685 Cedar Lane, Homewood, CA 96141"
             }) == :tahoe
    end

    test "returns nil for a non-cabin location" do
      assert CabinBlackout.property_for_event(%{
               location_name: "Swedish American Hall",
               address: "2174 Market St, San Francisco, CA 94114"
             }) == nil
    end

    test "returns nil when the event has no location" do
      assert CabinBlackout.property_for_event(%{
               location_name: nil,
               address: nil
             }) == nil

      assert CabinBlackout.property_for_event(nil) == nil
    end
  end

  describe "blackout_range/1" do
    test "spans the event start and end calendar days" do
      event = %{
        start_date: ~U[2026-05-01 07:00:00Z],
        end_date: ~U[2026-05-03 07:00:00Z]
      }

      assert CabinBlackout.blackout_range(event) ==
               {~D[2026-05-01], ~D[2026-05-03]}
    end

    test "collapses to a single day when there is no end date" do
      event = %{start_date: ~U[2026-05-01 07:00:00Z], end_date: nil}

      assert CabinBlackout.blackout_range(event) ==
               {~D[2026-05-01], ~D[2026-05-01]}
    end

    test "clamps an end date that precedes the start" do
      event = %{
        start_date: ~U[2026-05-05 07:00:00Z],
        end_date: ~U[2026-05-01 07:00:00Z]
      }

      assert CabinBlackout.blackout_range(event) ==
               {~D[2026-05-05], ~D[2026-05-05]}
    end

    test "returns nil without a start date" do
      assert CabinBlackout.blackout_range(%{start_date: nil}) == nil
    end
  end

  describe "blackout_attrs/1" do
    test "builds create_blackout attrs for a cabin event" do
      event = %{
        title: "Crab Feed",
        reference_id: "EVT-1234",
        location_name: "Clear Lake Cabin",
        address: nil,
        start_date: ~U[2026-05-01 07:00:00Z],
        end_date: ~U[2026-05-03 07:00:00Z]
      }

      assert {:ok, attrs} = CabinBlackout.blackout_attrs(event)

      assert attrs == %{
               "property" => :clear_lake,
               "reason" => "Event: Crab Feed (EVT-1234)",
               "start_date" => ~D[2026-05-01],
               "end_date" => ~D[2026-05-03]
             }
    end

    test "falls back to a generic reason when the event has no title" do
      event = %{
        title: nil,
        reference_id: nil,
        location_name: "Lake Tahoe Cabin",
        start_date: ~U[2026-05-01 07:00:00Z],
        end_date: nil
      }

      assert {:ok, %{"reason" => "Club event"}} =
               CabinBlackout.blackout_attrs(event)
    end

    test "returns :error for a non-cabin event" do
      event = %{
        title: "Mixer",
        location_name: "Norwegian Club",
        start_date: ~U[2026-05-01 07:00:00Z]
      }

      assert CabinBlackout.blackout_attrs(event) == :error
    end

    test "returns :error for a cabin event without a start date" do
      event = %{
        title: "TBD",
        location_name: "Clear Lake Cabin",
        start_date: nil
      }

      assert CabinBlackout.blackout_attrs(event) == :error
    end
  end
end
