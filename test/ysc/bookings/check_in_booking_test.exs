defmodule Ysc.Bookings.CheckInBookingTest do
  @moduledoc """
  Tests for CheckInBooking join table.

  These tests verify:
  - Many-to-many association between CheckIns and Bookings
  - Foreign key constraints
  - Database operations
  - Join table behavior
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Bookings.{CheckInBooking, CheckIn, Booking}
  alias Ysc.Repo

  # Helper to create a check-in
  defp create_check_in do
    attrs = %{
      rules_agreed: true,
      checked_in_at: DateTime.utc_now()
    }

    {:ok, check_in} =
      %CheckIn{}
      |> CheckIn.changeset(attrs)
      |> Repo.insert()

    check_in
  end

  # Helper to create a booking
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

  describe "join table operations" do
    test "can create a check_in_booking association" do
      check_in = create_check_in()
      booking = create_booking()

      {:ok, check_in_booking} =
        %CheckInBooking{
          check_in_id: check_in.id,
          booking_id: booking.id
        }
        |> Repo.insert()

      assert check_in_booking.check_in_id == check_in.id
      assert check_in_booking.booking_id == booking.id
      assert check_in_booking.inserted_at != nil
      assert check_in_booking.updated_at != nil
    end

    test "can retrieve check_in_booking by id" do
      check_in = create_check_in()
      booking = create_booking()

      {:ok, check_in_booking} =
        %CheckInBooking{
          check_in_id: check_in.id,
          booking_id: booking.id
        }
        |> Repo.insert()

      retrieved = Repo.get(CheckInBooking, check_in_booking.id)

      assert retrieved.check_in_id == check_in.id
      assert retrieved.booking_id == booking.id
    end

    test "can preload check_in from check_in_booking" do
      check_in = create_check_in()
      booking = create_booking()

      {:ok, check_in_booking} =
        %CheckInBooking{
          check_in_id: check_in.id,
          booking_id: booking.id
        }
        |> Repo.insert()

      check_in_booking_with_check_in = Repo.preload(check_in_booking, :check_in)

      assert check_in_booking_with_check_in.check_in.id == check_in.id
    end

    test "can preload booking from check_in_booking" do
      check_in = create_check_in()
      booking = create_booking()

      {:ok, check_in_booking} =
        %CheckInBooking{
          check_in_id: check_in.id,
          booking_id: booking.id
        }
        |> Repo.insert()

      check_in_booking_with_booking = Repo.preload(check_in_booking, :booking)

      assert check_in_booking_with_booking.booking.id == booking.id
    end

    test "can associate multiple bookings with one check-in" do
      check_in = create_check_in()
      booking1 = create_booking()
      booking2 = create_booking()
      booking3 = create_booking()

      {:ok, _} =
        %CheckInBooking{check_in_id: check_in.id, booking_id: booking1.id}
        |> Repo.insert()

      {:ok, _} =
        %CheckInBooking{check_in_id: check_in.id, booking_id: booking2.id}
        |> Repo.insert()

      {:ok, _} =
        %CheckInBooking{check_in_id: check_in.id, booking_id: booking3.id}
        |> Repo.insert()

      # Query all check_in_bookings for this check-in
      check_in_bookings =
        CheckInBooking
        |> Ecto.Query.where(check_in_id: ^check_in.id)
        |> Repo.all()

      assert length(check_in_bookings) == 3
    end

    test "can associate multiple check-ins with one booking" do
      booking = create_booking()
      check_in1 = create_check_in()
      check_in2 = create_check_in()

      {:ok, _} =
        %CheckInBooking{check_in_id: check_in1.id, booking_id: booking.id}
        |> Repo.insert()

      {:ok, _} =
        %CheckInBooking{check_in_id: check_in2.id, booking_id: booking.id}
        |> Repo.insert()

      # Query all check_in_bookings for this booking
      check_in_bookings =
        CheckInBooking
        |> Ecto.Query.where(booking_id: ^booking.id)
        |> Repo.all()

      assert length(check_in_bookings) == 2
    end
  end

  describe "foreign key constraints" do
    test "enforces foreign key constraint on check_in_id" do
      booking = create_booking()
      invalid_check_in_id = Ecto.ULID.generate()

      assert_raise Ecto.ConstraintError, fn ->
        %CheckInBooking{
          check_in_id: invalid_check_in_id,
          booking_id: booking.id
        }
        |> Repo.insert!()
      end
    end

    test "enforces foreign key constraint on booking_id" do
      check_in = create_check_in()
      invalid_booking_id = Ecto.ULID.generate()

      assert_raise Ecto.ConstraintError, fn ->
        %CheckInBooking{
          check_in_id: check_in.id,
          booking_id: invalid_booking_id
        }
        |> Repo.insert!()
      end
    end
  end

  describe "cascading deletes" do
    test "deleting check-in deletes associated check_in_bookings" do
      check_in = create_check_in()
      booking1 = create_booking()
      booking2 = create_booking()

      {:ok, cib1} =
        %CheckInBooking{check_in_id: check_in.id, booking_id: booking1.id}
        |> Repo.insert()

      {:ok, cib2} =
        %CheckInBooking{check_in_id: check_in.id, booking_id: booking2.id}
        |> Repo.insert()

      # Delete the check-in
      Repo.delete(check_in)

      # Verify check_in_bookings are deleted
      assert Repo.get(CheckInBooking, cib1.id) == nil
      assert Repo.get(CheckInBooking, cib2.id) == nil

      # Verify bookings still exist
      assert Repo.get(Booking, booking1.id) != nil
      assert Repo.get(Booking, booking2.id) != nil
    end

    test "cannot delete booking with associated check_in_bookings (RESTRICT)" do
      booking = create_booking()
      check_in1 = create_check_in()
      check_in2 = create_check_in()

      {:ok, _cib1} =
        %CheckInBooking{check_in_id: check_in1.id, booking_id: booking.id}
        |> Repo.insert()

      {:ok, _cib2} =
        %CheckInBooking{check_in_id: check_in2.id, booking_id: booking.id}
        |> Repo.insert()

      # Delete the booking should fail due to RESTRICT constraint
      # Can raise either Postgrex.Error or Ecto.ConstraintError depending on Ecto's internal state
      error =
        try do
          Repo.delete(booking)

          flunk(
            "Expected either Postgrex.Error or Ecto.ConstraintError to be raised"
          )
        rescue
          e in [Postgrex.Error, Ecto.ConstraintError] -> e
        end

      assert error.__struct__ in [Postgrex.Error, Ecto.ConstraintError]
    end
  end

  describe "typical scenarios" do
    test "single booking check-in" do
      check_in = create_check_in()
      booking = create_booking()

      {:ok, _check_in_booking} =
        %CheckInBooking{
          check_in_id: check_in.id,
          booking_id: booking.id
        }
        |> Repo.insert()

      # Verify association
      check_in_with_bookings = Repo.preload(check_in, :bookings)
      assert length(check_in_with_bookings.bookings) == 1
      assert hd(check_in_with_bookings.bookings).id == booking.id
    end

    test "family check-in with multiple bookings" do
      check_in = create_check_in()
      parent_booking = create_booking()
      child_booking = create_booking()

      {:ok, _} =
        %CheckInBooking{check_in_id: check_in.id, booking_id: parent_booking.id}
        |> Repo.insert()

      {:ok, _} =
        %CheckInBooking{check_in_id: check_in.id, booking_id: child_booking.id}
        |> Repo.insert()

      # Verify both bookings are associated
      check_in_with_bookings = Repo.preload(check_in, :bookings)
      assert length(check_in_with_bookings.bookings) == 2

      booking_ids = Enum.map(check_in_with_bookings.bookings, & &1.id)
      assert parent_booking.id in booking_ids
      assert child_booking.id in booking_ids
    end
  end
end
