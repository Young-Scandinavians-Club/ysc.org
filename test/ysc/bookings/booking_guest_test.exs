defmodule Ysc.Bookings.BookingGuestTest do
  @moduledoc """
  Tests for BookingGuest schema.

  These tests verify:
  - Required field validation (first_name, last_name, booking_id)
  - String length validations (max 150 characters)
  - Boolean flags (is_child, is_booking_user)
  - Order index validation (non-negative)
  - Foreign key constraint on booking_id
  - Database operations
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Bookings.{BookingGuest, Booking}
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
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        first_name: "John",
        last_name: "Doe"
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)

      assert changeset.valid?
      assert changeset.changes.first_name == "John"
      assert changeset.changes.last_name == "Doe"
    end

    test "requires first_name" do
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        last_name: "Doe"
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:first_name] != nil
    end

    test "requires last_name" do
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        first_name: "John"
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:last_name] != nil
    end

    test "requires booking_id" do
      attrs = %{
        first_name: "John",
        last_name: "Doe"
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:booking_id] != nil
    end

    test "changeset with default empty attrs" do
      # Test default parameter
      changeset = BookingGuest.changeset(%BookingGuest{})

      refute changeset.valid?
      assert changeset.errors[:first_name] != nil
      assert changeset.errors[:last_name] != nil
      assert changeset.errors[:booking_id] != nil
    end

    test "validates first_name maximum length (150 characters)" do
      booking = create_booking()
      long_name = String.duplicate("a", 151)

      attrs = %{
        booking_id: booking.id,
        first_name: long_name,
        last_name: "Doe"
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:first_name] != nil
    end

    test "accepts first_name with exactly 150 characters" do
      booking = create_booking()
      valid_name = String.duplicate("a", 150)

      attrs = %{
        booking_id: booking.id,
        first_name: valid_name,
        last_name: "Doe"
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)

      assert changeset.valid?
    end

    test "validates last_name maximum length (150 characters)" do
      booking = create_booking()
      long_name = String.duplicate("a", 151)

      attrs = %{
        booking_id: booking.id,
        first_name: "John",
        last_name: long_name
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:last_name] != nil
    end

    test "accepts last_name with exactly 150 characters" do
      booking = create_booking()
      valid_name = String.duplicate("a", 150)

      attrs = %{
        booking_id: booking.id,
        first_name: "John",
        last_name: valid_name
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)

      assert changeset.valid?
    end
  end

  describe "is_child flag" do
    test "defaults is_child to false" do
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        first_name: "John",
        last_name: "Doe"
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)
      {:ok, guest} = Repo.insert(changeset)

      assert guest.is_child == false
    end

    test "accepts is_child as true" do
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        first_name: "Little",
        last_name: "Johnny",
        is_child: true
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)
      {:ok, guest} = Repo.insert(changeset)

      assert guest.is_child == true
    end
  end

  describe "is_booking_user flag" do
    test "defaults is_booking_user to false" do
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        first_name: "Jane",
        last_name: "Smith"
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)
      {:ok, guest} = Repo.insert(changeset)

      assert guest.is_booking_user == false
    end

    test "accepts is_booking_user as true" do
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        first_name: "John",
        last_name: "Doe",
        is_booking_user: true
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)
      {:ok, guest} = Repo.insert(changeset)

      assert guest.is_booking_user == true
    end
  end

  describe "order_index field" do
    test "defaults order_index to 0" do
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        first_name: "John",
        last_name: "Doe"
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)
      {:ok, guest} = Repo.insert(changeset)

      assert guest.order_index == 0
    end

    test "accepts custom order_index" do
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        first_name: "Jane",
        last_name: "Smith",
        order_index: 2
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)
      {:ok, guest} = Repo.insert(changeset)

      assert guest.order_index == 2
    end

    test "rejects negative order_index" do
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        first_name: "John",
        last_name: "Doe",
        order_index: -1
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:order_index] != nil
    end
  end

  describe "database operations" do
    test "can insert and retrieve complete booking guest" do
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        first_name: "John",
        last_name: "Doe",
        is_child: false,
        is_booking_user: true,
        order_index: 1
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)
      {:ok, guest} = Repo.insert(changeset)

      retrieved = Repo.get(BookingGuest, guest.id)

      assert retrieved.first_name == "John"
      assert retrieved.last_name == "Doe"
      assert retrieved.is_child == false
      assert retrieved.is_booking_user == true
      assert retrieved.order_index == 1
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "enforces foreign key constraint on booking_id" do
      invalid_booking_id = Ecto.ULID.generate()

      attrs = %{
        booking_id: invalid_booking_id,
        first_name: "John",
        last_name: "Doe"
      }

      changeset = BookingGuest.changeset(%BookingGuest{}, attrs)

      # Since changeset doesn't have foreign_key_constraint, this raises
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(changeset)
      end
    end

    test "can associate guest with booking" do
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        first_name: "John",
        last_name: "Doe"
      }

      {:ok, guest} =
        %BookingGuest{}
        |> BookingGuest.changeset(attrs)
        |> Repo.insert()

      guest_with_booking = Repo.preload(guest, :booking)

      assert guest_with_booking.booking.id == booking.id
    end
  end

  describe "typical guest scenarios" do
    test "primary booking user" do
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        first_name: "John",
        last_name: "Doe",
        is_booking_user: true,
        is_child: false,
        order_index: 0
      }

      {:ok, guest} =
        %BookingGuest{}
        |> BookingGuest.changeset(attrs)
        |> Repo.insert()

      assert guest.is_booking_user == true
      assert guest.order_index == 0
    end

    test "additional adult guest" do
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        first_name: "Jane",
        last_name: "Smith",
        is_booking_user: false,
        is_child: false,
        order_index: 1
      }

      {:ok, guest} =
        %BookingGuest{}
        |> BookingGuest.changeset(attrs)
        |> Repo.insert()

      assert guest.is_booking_user == false
      assert guest.is_child == false
      assert guest.order_index == 1
    end

    test "child guest" do
      booking = create_booking()

      attrs = %{
        booking_id: booking.id,
        first_name: "Tommy",
        last_name: "Doe",
        is_child: true,
        order_index: 2
      }

      {:ok, guest} =
        %BookingGuest{}
        |> BookingGuest.changeset(attrs)
        |> Repo.insert()

      assert guest.is_child == true
    end

    test "multiple guests for same booking" do
      booking = create_booking()

      guest_attrs = [
        {0, "John", "Doe", false, true},
        {1, "Jane", "Doe", false, false},
        {2, "Bobby", "Doe", true, false},
        {3, "Sally", "Doe", true, false}
      ]

      for {order, first, last, is_child, is_user} <- guest_attrs do
        {:ok, _guest} =
          %BookingGuest{}
          |> BookingGuest.changeset(%{
            booking_id: booking.id,
            first_name: first,
            last_name: last,
            is_child: is_child,
            is_booking_user: is_user,
            order_index: order
          })
          |> Repo.insert()
      end

      # Verify all guests were created
      guests =
        BookingGuest
        |> Ecto.Query.where(booking_id: ^booking.id)
        |> Ecto.Query.order_by(:order_index)
        |> Repo.all()

      assert length(guests) == 4
      assert hd(guests).is_booking_user == true
    end
  end
end
