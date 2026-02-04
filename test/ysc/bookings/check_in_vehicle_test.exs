defmodule Ysc.Bookings.CheckInVehicleTest do
  @moduledoc """
  Tests for CheckInVehicle schema.

  These tests verify:
  - Required field validation (type, color, make, check_in_id)
  - String length validations (max 100 characters)
  - Foreign key constraint on check_in_id
  - Database operations
  - Vehicle information tracking
  """
  use Ysc.DataCase, async: true

  alias Ysc.Bookings.{CheckInVehicle, CheckIn}
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

  describe "changeset/2" do
    test "creates valid changeset with all required fields" do
      check_in = create_check_in()

      attrs = %{
        check_in_id: check_in.id,
        type: "SUV",
        color: "Blue",
        make: "Toyota"
      }

      changeset = CheckInVehicle.changeset(%CheckInVehicle{}, attrs)

      assert changeset.valid?
      assert changeset.changes.type == "SUV"
      assert changeset.changes.color == "Blue"
      assert changeset.changes.make == "Toyota"
    end

    test "requires type" do
      check_in = create_check_in()

      attrs = %{
        check_in_id: check_in.id,
        color: "Blue",
        make: "Toyota"
      }

      changeset = CheckInVehicle.changeset(%CheckInVehicle{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:type] != nil
    end

    test "requires color" do
      check_in = create_check_in()

      attrs = %{
        check_in_id: check_in.id,
        type: "SUV",
        make: "Toyota"
      }

      changeset = CheckInVehicle.changeset(%CheckInVehicle{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:color] != nil
    end

    test "requires make" do
      check_in = create_check_in()

      attrs = %{
        check_in_id: check_in.id,
        type: "SUV",
        color: "Blue"
      }

      changeset = CheckInVehicle.changeset(%CheckInVehicle{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:make] != nil
    end

    test "requires check_in_id" do
      attrs = %{
        type: "SUV",
        color: "Blue",
        make: "Toyota"
      }

      changeset = CheckInVehicle.changeset(%CheckInVehicle{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:check_in_id] != nil
    end

    test "changeset with default empty attrs" do
      # Test default parameter
      changeset = CheckInVehicle.changeset(%CheckInVehicle{})

      refute changeset.valid?
      assert changeset.errors[:type] != nil
      assert changeset.errors[:color] != nil
      assert changeset.errors[:make] != nil
      assert changeset.errors[:check_in_id] != nil
    end

    test "validates type maximum length (100 characters)" do
      check_in = create_check_in()
      long_type = String.duplicate("a", 101)

      attrs = %{
        check_in_id: check_in.id,
        type: long_type,
        color: "Blue",
        make: "Toyota"
      }

      changeset = CheckInVehicle.changeset(%CheckInVehicle{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:type] != nil
    end

    test "accepts type with exactly 100 characters" do
      check_in = create_check_in()
      valid_type = String.duplicate("a", 100)

      attrs = %{
        check_in_id: check_in.id,
        type: valid_type,
        color: "Blue",
        make: "Toyota"
      }

      changeset = CheckInVehicle.changeset(%CheckInVehicle{}, attrs)

      assert changeset.valid?
    end

    test "validates color maximum length (100 characters)" do
      check_in = create_check_in()
      long_color = String.duplicate("a", 101)

      attrs = %{
        check_in_id: check_in.id,
        type: "SUV",
        color: long_color,
        make: "Toyota"
      }

      changeset = CheckInVehicle.changeset(%CheckInVehicle{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:color] != nil
    end

    test "accepts color with exactly 100 characters" do
      check_in = create_check_in()
      valid_color = String.duplicate("a", 100)

      attrs = %{
        check_in_id: check_in.id,
        type: "SUV",
        color: valid_color,
        make: "Toyota"
      }

      changeset = CheckInVehicle.changeset(%CheckInVehicle{}, attrs)

      assert changeset.valid?
    end

    test "validates make maximum length (100 characters)" do
      check_in = create_check_in()
      long_make = String.duplicate("a", 101)

      attrs = %{
        check_in_id: check_in.id,
        type: "SUV",
        color: "Blue",
        make: long_make
      }

      changeset = CheckInVehicle.changeset(%CheckInVehicle{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:make] != nil
    end

    test "accepts make with exactly 100 characters" do
      check_in = create_check_in()
      valid_make = String.duplicate("a", 100)

      attrs = %{
        check_in_id: check_in.id,
        type: "SUV",
        color: "Blue",
        make: valid_make
      }

      changeset = CheckInVehicle.changeset(%CheckInVehicle{}, attrs)

      assert changeset.valid?
    end
  end

  describe "database operations" do
    test "can insert and retrieve complete vehicle" do
      check_in = create_check_in()

      attrs = %{
        check_in_id: check_in.id,
        type: "Truck",
        color: "Red",
        make: "Ford"
      }

      changeset = CheckInVehicle.changeset(%CheckInVehicle{}, attrs)
      {:ok, vehicle} = Repo.insert(changeset)

      retrieved = Repo.get(CheckInVehicle, vehicle.id)

      assert retrieved.type == "Truck"
      assert retrieved.color == "Red"
      assert retrieved.make == "Ford"
      assert retrieved.check_in_id == check_in.id
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "enforces foreign key constraint on check_in_id" do
      invalid_check_in_id = Ecto.ULID.generate()

      attrs = %{
        check_in_id: invalid_check_in_id,
        type: "SUV",
        color: "Blue",
        make: "Toyota"
      }

      changeset = CheckInVehicle.changeset(%CheckInVehicle{}, attrs)

      # Foreign key constraint is caught by foreign_key_constraint/2 in changeset
      assert_raise Ecto.InvalidChangesetError, fn ->
        Repo.insert!(changeset)
      end
    end

    test "can associate vehicle with check-in" do
      check_in = create_check_in()

      attrs = %{
        check_in_id: check_in.id,
        type: "Sedan",
        color: "Black",
        make: "Honda"
      }

      {:ok, vehicle} =
        %CheckInVehicle{}
        |> CheckInVehicle.changeset(attrs)
        |> Repo.insert()

      vehicle_with_check_in = Repo.preload(vehicle, :check_in)

      assert vehicle_with_check_in.check_in.id == check_in.id
    end
  end

  describe "typical vehicle scenarios" do
    test "registers single vehicle" do
      check_in = create_check_in()

      attrs = %{
        check_in_id: check_in.id,
        type: "SUV",
        color: "Silver",
        make: "Jeep"
      }

      {:ok, vehicle} =
        %CheckInVehicle{}
        |> CheckInVehicle.changeset(attrs)
        |> Repo.insert()

      assert vehicle.type == "SUV"
      assert vehicle.color == "Silver"
      assert vehicle.make == "Jeep"
    end

    test "registers multiple vehicles for same check-in" do
      check_in = create_check_in()

      vehicle_data = [
        {"Sedan", "White", "Toyota"},
        {"Truck", "Blue", "Ford"},
        {"SUV", "Black", "Chevrolet"}
      ]

      for {type, color, make} <- vehicle_data do
        {:ok, _vehicle} =
          %CheckInVehicle{}
          |> CheckInVehicle.changeset(%{
            check_in_id: check_in.id,
            type: type,
            color: color,
            make: make
          })
          |> Repo.insert()
      end

      # Verify all vehicles were created
      vehicles =
        CheckInVehicle
        |> Ecto.Query.where(check_in_id: ^check_in.id)
        |> Repo.all()

      assert length(vehicles) == 3
    end

    test "common vehicle types" do
      check_in = create_check_in()

      vehicle_types = ["Sedan", "SUV", "Truck", "Van", "Motorcycle", "RV"]

      for vehicle_type <- vehicle_types do
        {:ok, vehicle} =
          %CheckInVehicle{}
          |> CheckInVehicle.changeset(%{
            check_in_id: check_in.id,
            type: vehicle_type,
            color: "Test Color",
            make: "Test Make"
          })
          |> Repo.insert()

        assert vehicle.type == vehicle_type
      end
    end

    test "vehicles with various color descriptions" do
      check_in = create_check_in()

      colors = [
        "Red",
        "Blue",
        "Black",
        "White",
        "Silver",
        "Gray",
        "Green",
        "Burgundy"
      ]

      for color <- colors do
        {:ok, vehicle} =
          %CheckInVehicle{}
          |> CheckInVehicle.changeset(%{
            check_in_id: check_in.id,
            type: "Sedan",
            color: color,
            make: "Generic"
          })
          |> Repo.insert()

        assert vehicle.color == color
      end
    end
  end
end
