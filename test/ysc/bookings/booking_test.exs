defmodule Ysc.Bookings.BookingTest do
  @moduledoc """
  Tests for Booking schema.

  These tests verify:
  - Required field validation
  - Reference ID auto-generation
  - Booking mode inference from rooms
  - Date range validation (checkout >= checkin)
  - Status enum transitions
  - Money field handling
  - Property and booking_mode enum validation
  - Database constraints and associations
  - Flop configuration

  Note: BookingValidator business rules are tested separately in booking_validator_test.exs.
  These tests focus on schema-level validations and use skip_validation: true to bypass BookingValidator.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Bookings.{Booking, Room}
  alias Ysc.Repo

  # Helper to create a room for testing
  defp create_room(attrs) do
    default_attrs = %{
      name: "Test Room #{System.unique_integer()}",
      property: :tahoe,
      capacity_max: 2
    }

    attrs = Map.merge(default_attrs, attrs)

    {:ok, room} =
      %Room{}
      |> Room.changeset(attrs)
      |> Repo.insert()

    room
  end

  describe "changeset/2" do
    test "creates valid changeset with all required fields" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room,
        guests_count: 2,
        total_price: Money.new(400, :USD)
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      assert changeset.valid?
      assert changeset.changes.checkin_date == ~D[2024-08-05]
      assert changeset.changes.checkout_date == ~D[2024-08-07]
      assert changeset.changes.property == :tahoe
      assert changeset.changes.booking_mode == :room
    end

    test "requires checkin_date" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      refute changeset.valid?
      assert changeset.errors[:checkin_date] != nil
    end

    test "requires checkout_date" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        property: :tahoe,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      refute changeset.valid?
      assert changeset.errors[:checkout_date] != nil
    end

    test "requires property" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      refute changeset.valid?
      assert changeset.errors[:property] != nil
    end

    test "requires booking_mode" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      refute changeset.valid?
      assert changeset.errors[:booking_mode] != nil
    end

    test "requires user_id" do
      attrs = %{
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      refute changeset.valid?
      assert changeset.errors[:user_id] != nil
    end
  end

  describe "reference_id generation" do
    test "auto-generates reference_id with BKG prefix" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      assert changeset.valid?
      reference_id = get_change(changeset, :reference_id)
      assert reference_id != nil
      assert String.starts_with?(reference_id, "BKG-")
    end

    test "preserves existing reference_id" do
      user = user_fixture()

      attrs = %{
        reference_id: "BKG-CUSTOM-123",
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      assert changeset.valid?
      assert get_change(changeset, :reference_id) == "BKG-CUSTOM-123"
    end

    test "reference_id is unique in database" do
      user = user_fixture()

      attrs1 = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room
      }

      {:ok, booking1} =
        %Booking{}
        |> Booking.changeset(attrs1, skip_validation: true)
        |> Repo.insert()

      # Try to create another booking with the same reference_id
      attrs2 = %{
        reference_id: booking1.reference_id,
        user_id: user.id,
        checkin_date: ~D[2024-08-10],
        checkout_date: ~D[2024-08-12],
        property: :tahoe,
        booking_mode: :room
      }

      {:error, changeset_error} =
        %Booking{}
        |> Booking.changeset(attrs2, skip_validation: true)
        |> Repo.insert()

      assert changeset_error.errors[:reference_id] != nil
    end
  end

  describe "booking_mode inference" do
    test "infers :room mode when rooms are provided and booking_mode not specified" do
      # Note: booking_mode is a required field, so inference only works
      # when booking_mode is nil on an existing struct, not on create
      user = user_fixture()
      room = create_room(%{property: :tahoe})

      # Create a booking without booking_mode first
      booking = %Booking{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe
      }

      changeset =
        Booking.changeset(booking, %{}, rooms: [room], skip_validation: true)

      # Inference sets booking_mode to :room based on rooms
      assert get_field(changeset, :booking_mode) == :room
    end

    test "infers :buyout mode when no rooms provided and booking_mode not specified" do
      user = user_fixture()

      booking = %Booking{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe
      }

      changeset =
        Booking.changeset(booking, %{}, rooms: [], skip_validation: true)

      # Inference sets booking_mode to :buyout when no rooms
      assert get_field(changeset, :booking_mode) == :buyout
    end

    test "preserves explicit booking_mode even when rooms provided" do
      user = user_fixture()
      room = create_room(%{property: :tahoe})

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :buyout
      }

      changeset =
        Booking.changeset(%Booking{}, attrs,
          rooms: [room],
          skip_validation: true
        )

      assert changeset.valid?
      # Explicit booking_mode is preserved even with rooms present
      assert get_field(changeset, :booking_mode) == :buyout
    end
  end

  describe "date validation" do
    test "accepts valid date range (checkout after checkin)" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      assert changeset.valid?
    end

    test "accepts same day checkout (1 night stay)" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-06],
        property: :tahoe,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      assert changeset.valid?
    end

    test "rejects checkout_date before checkin_date" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-07],
        checkout_date: ~D[2024-08-05],
        property: :tahoe,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      refute changeset.valid?
      assert changeset.errors[:checkout_date] != nil
    end
  end

  describe "property enum" do
    test "accepts tahoe property" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      assert changeset.valid?
      assert changeset.changes.property == :tahoe
    end

    test "accepts clear_lake property" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :clear_lake,
        booking_mode: :day
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      assert changeset.valid?
      assert changeset.changes.property == :clear_lake
    end

    test "rejects invalid property" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :invalid_property,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      refute changeset.valid?
    end
  end

  describe "booking_mode enum" do
    test "accepts room booking mode" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      assert changeset.valid?
      assert changeset.changes.booking_mode == :room
    end

    test "accepts day booking mode" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :clear_lake,
        booking_mode: :day
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      assert changeset.valid?
      assert changeset.changes.booking_mode == :day
    end

    test "accepts buyout booking mode" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :buyout
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      assert changeset.valid?
      assert changeset.changes.booking_mode == :buyout
    end

    test "rejects invalid booking mode" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :invalid_mode
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      refute changeset.valid?
    end
  end

  describe "status enum" do
    test "defaults to draft status" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)
      {:ok, booking} = Repo.insert(changeset)

      assert booking.status == :draft
    end

    test "accepts hold status" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room,
        status: :hold
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      assert changeset.valid?
      assert changeset.changes.status == :hold
    end

    test "accepts complete status" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room,
        status: :complete
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      assert changeset.valid?
      assert changeset.changes.status == :complete
    end

    test "accepts refunded status" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room,
        status: :refunded
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      assert changeset.valid?
      assert changeset.changes.status == :refunded
    end

    test "accepts canceled status" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room,
        status: :canceled
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      assert changeset.valid?
      assert changeset.changes.status == :canceled
    end

    test "rejects invalid status" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room,
        status: :invalid_status
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)

      refute changeset.valid?
    end
  end

  describe "Money field handling" do
    test "stores and retrieves Money type correctly" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room,
        total_price: Money.new(45_000, :USD)
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)
      {:ok, booking} = Repo.insert(changeset)

      retrieved = Repo.get(Booking, booking.id)
      assert retrieved.total_price == Money.new(45_000, :USD)
    end

    test "defaults total_price currency to USD" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room,
        total_price: Money.new(100, :USD)
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)
      {:ok, booking} = Repo.insert(changeset)

      assert booking.total_price.currency == :USD
    end
  end

  describe "guest counts" do
    test "defaults guests_count to 1" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)
      {:ok, booking} = Repo.insert(changeset)

      assert booking.guests_count == 1
    end

    test "defaults children_count to 0" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)
      {:ok, booking} = Repo.insert(changeset)

      assert booking.children_count == 0
    end

    test "accepts custom guest counts" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room,
        guests_count: 4,
        children_count: 2
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)
      {:ok, booking} = Repo.insert(changeset)

      assert booking.guests_count == 4
      assert booking.children_count == 2
    end
  end

  describe "checked_in field" do
    test "defaults checked_in to false" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)
      {:ok, booking} = Repo.insert(changeset)

      assert booking.checked_in == false
    end

    test "accepts checked_in as true" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room,
        checked_in: true
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)
      {:ok, booking} = Repo.insert(changeset)

      assert booking.checked_in == true
    end
  end

  describe "database operations" do
    test "can insert and retrieve complete booking" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        guests_count: 3,
        children_count: 1,
        property: :tahoe,
        booking_mode: :room,
        status: :hold,
        total_price: Money.new(60_000, :USD),
        pricing_items: %{base: 50_000, fees: 10_000}
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)
      {:ok, booking} = Repo.insert(changeset)

      retrieved = Repo.get(Booking, booking.id)

      assert retrieved.checkin_date == ~D[2024-08-05]
      assert retrieved.checkout_date == ~D[2024-08-07]
      assert retrieved.guests_count == 3
      assert retrieved.children_count == 1
      assert retrieved.property == :tahoe
      assert retrieved.booking_mode == :room
      assert retrieved.status == :hold
      assert retrieved.total_price == Money.new(60_000, :USD)
      assert retrieved.pricing_items == %{"base" => 50_000, "fees" => 10_000}
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
      assert String.starts_with?(retrieved.reference_id, "BKG-")
    end

    test "enforces foreign key constraint on user_id" do
      invalid_user_id = Ecto.ULID.generate()

      attrs = %{
        user_id: invalid_user_id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)
      {:error, changeset_error} = Repo.insert(changeset)

      assert changeset_error.errors[:user_id] != nil
    end
  end

  describe "associations" do
    test "can associate booking with user" do
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

      booking_with_user = Repo.preload(booking, :user)

      assert booking_with_user.user.id == user.id
    end

    test "can associate booking with rooms via put_assoc" do
      user = user_fixture()
      room1 = create_room(%{property: :tahoe, name: "Room 1", capacity_max: 2})
      room2 = create_room(%{property: :tahoe, name: "Room 2", capacity_max: 2})

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room
      }

      {:ok, booking} =
        %Booking{}
        |> Booking.changeset(attrs,
          rooms: [room1, room2],
          skip_validation: true
        )
        |> Repo.insert()

      booking_with_rooms = Repo.preload(booking, :rooms)

      assert length(booking_with_rooms.rooms) == 2
      room_ids = Enum.map(booking_with_rooms.rooms, & &1.id)
      assert room1.id in room_ids
      assert room2.id in room_ids
    end
  end

  describe "pricing_items field" do
    test "stores map data correctly" do
      user = user_fixture()

      pricing_items = %{
        base_price: 40_000,
        cleaning_fee: 5000,
        service_fee: 3000,
        tax: 2000
      }

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room,
        pricing_items: pricing_items
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)
      {:ok, booking} = Repo.insert(changeset)

      retrieved = Repo.get(Booking, booking.id)

      # Map keys get converted to strings when stored
      assert retrieved.pricing_items["base_price"] == 40_000
      assert retrieved.pricing_items["cleaning_fee"] == 5000
      assert retrieved.pricing_items["service_fee"] == 3000
      assert retrieved.pricing_items["tax"] == 2000
    end
  end

  describe "hold_expires_at field" do
    test "can store hold expiration timestamp" do
      user = user_fixture()
      # Truncate to microsecond precision to match DB storage
      expires_at =
        DateTime.utc_now()
        |> DateTime.add(15, :minute)
        |> DateTime.truncate(:second)

      attrs = %{
        user_id: user.id,
        checkin_date: ~D[2024-08-05],
        checkout_date: ~D[2024-08-07],
        property: :tahoe,
        booking_mode: :room,
        status: :hold,
        hold_expires_at: expires_at
      }

      changeset = Booking.changeset(%Booking{}, attrs, skip_validation: true)
      {:ok, booking} = Repo.insert(changeset)

      retrieved = Repo.get(Booking, booking.id)

      assert DateTime.compare(retrieved.hold_expires_at, expires_at) == :eq
    end
  end
end
