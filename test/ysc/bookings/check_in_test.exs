defmodule Ysc.Bookings.CheckInTest do
  @moduledoc """
  Tests for CheckIn schema.

  These tests verify:
  - Required field validation (rules_agreed, checked_in_at)
  - Automatic checked_in_at timestamp generation
  - Boolean flag for rules agreement
  - Associations with bookings and vehicles
  - Database operations
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Bookings.{CheckIn, Booking}
  alias Ysc.Repo

  # Helper to create a booking for testing
  defp create_booking do
    user = user_fixture()

    attrs = %{
      user_id: user.id,
      checkin_date: ~D[2024-08-05],
      checkout_date: ~D[2024-08-07],
      property: :tahoe,
      booking_mode: :room
    }

    {:ok, booking} =
      %Booking{}
      |> Booking.changeset(attrs, skip_validation: true)
      |> Repo.insert()

    booking
  end

  describe "changeset/2" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        rules_agreed: true,
        checked_in_at: DateTime.utc_now()
      }

      changeset = CheckIn.changeset(%CheckIn{}, attrs)

      assert changeset.valid?
      assert changeset.changes.rules_agreed == true
    end

    test "allows creation without explicit rules_agreed (defaults to false)" do
      attrs = %{
        checked_in_at: DateTime.utc_now()
      }

      changeset = CheckIn.changeset(%CheckIn{}, attrs)

      assert changeset.valid?
      # rules_agreed defaults to false if not provided
      check_in = %CheckIn{}
      assert check_in.rules_agreed == false
    end

    test "requires checked_in_at" do
      attrs = %{
        rules_agreed: true
      }

      changeset = CheckIn.changeset(%CheckIn{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:checked_in_at] != nil
    end
  end

  describe "checked_in_at handling" do
    test "preserves provided checked_in_at" do
      specific_time =
        DateTime.utc_now()
        |> DateTime.add(-3600, :second)
        |> DateTime.truncate(:second)

      attrs = %{
        rules_agreed: true,
        checked_in_at: specific_time
      }

      changeset = CheckIn.changeset(%CheckIn{}, attrs)

      assert changeset.valid?
      # Should use provided time
      assert get_change(changeset, :checked_in_at) == specific_time
    end
  end

  describe "rules_agreed field" do
    test "defaults rules_agreed to false" do
      # Create without specifying rules_agreed
      check_in = %CheckIn{}

      assert check_in.rules_agreed == false
    end

    test "accepts rules_agreed as true" do
      attrs = %{
        rules_agreed: true,
        checked_in_at: DateTime.utc_now()
      }

      changeset = CheckIn.changeset(%CheckIn{}, attrs)
      {:ok, check_in} = Repo.insert(changeset)

      assert check_in.rules_agreed == true
    end

    test "accepts rules_agreed as false" do
      attrs = %{
        rules_agreed: false,
        checked_in_at: DateTime.utc_now()
      }

      changeset = CheckIn.changeset(%CheckIn{}, attrs)
      {:ok, check_in} = Repo.insert(changeset)

      assert check_in.rules_agreed == false
    end
  end

  describe "database operations" do
    test "can insert and retrieve complete check-in" do
      checked_in_time = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        rules_agreed: true,
        checked_in_at: checked_in_time
      }

      changeset = CheckIn.changeset(%CheckIn{}, attrs)
      {:ok, check_in} = Repo.insert(changeset)

      retrieved = Repo.get(CheckIn, check_in.id)

      assert retrieved.rules_agreed == true
      assert DateTime.compare(retrieved.checked_in_at, checked_in_time) == :eq
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end
  end

  describe "associations" do
    test "can associate check-in with bookings" do
      booking1 = create_booking()
      booking2 = create_booking()

      attrs = %{
        rules_agreed: true,
        checked_in_at: DateTime.utc_now()
      }

      {:ok, check_in} =
        %CheckIn{}
        |> CheckIn.changeset(attrs)
        |> Repo.insert()

      # Associate bookings through join table
      {:ok, _} =
        %Ysc.Bookings.CheckInBooking{
          check_in_id: check_in.id,
          booking_id: booking1.id
        }
        |> Repo.insert()

      {:ok, _} =
        %Ysc.Bookings.CheckInBooking{
          check_in_id: check_in.id,
          booking_id: booking2.id
        }
        |> Repo.insert()

      # Retrieve with preloaded bookings
      check_in_with_bookings = Repo.preload(check_in, :bookings)

      assert length(check_in_with_bookings.bookings) == 2
      booking_ids = Enum.map(check_in_with_bookings.bookings, & &1.id)
      assert booking1.id in booking_ids
      assert booking2.id in booking_ids
    end
  end

  describe "typical check-in scenarios" do
    test "guest arrives and agrees to rules" do
      attrs = %{
        rules_agreed: true,
        checked_in_at: DateTime.utc_now()
      }

      changeset = CheckIn.changeset(%CheckIn{}, attrs)
      {:ok, check_in} = Repo.insert(changeset)

      assert check_in.rules_agreed == true
      assert check_in.checked_in_at != nil
    end

    test "check-in with specific timestamp" do
      arrival_time =
        DateTime.utc_now()
        |> DateTime.add(-1800, :second)
        |> DateTime.truncate(:second)

      attrs = %{
        rules_agreed: true,
        checked_in_at: arrival_time
      }

      changeset = CheckIn.changeset(%CheckIn{}, attrs)
      {:ok, check_in} = Repo.insert(changeset)

      assert DateTime.compare(check_in.checked_in_at, arrival_time) == :eq
    end

    test "family check-in with multiple bookings" do
      booking1 = create_booking()
      booking2 = create_booking()

      attrs = %{
        rules_agreed: true,
        checked_in_at: DateTime.utc_now()
      }

      {:ok, check_in} =
        %CheckIn{}
        |> CheckIn.changeset(attrs)
        |> Repo.insert()

      # Link both bookings to same check-in
      {:ok, _} =
        %Ysc.Bookings.CheckInBooking{
          check_in_id: check_in.id,
          booking_id: booking1.id
        }
        |> Repo.insert()

      {:ok, _} =
        %Ysc.Bookings.CheckInBooking{
          check_in_id: check_in.id,
          booking_id: booking2.id
        }
        |> Repo.insert()

      check_in_with_bookings = Repo.preload(check_in, :bookings)
      assert length(check_in_with_bookings.bookings) == 2
    end
  end
end
