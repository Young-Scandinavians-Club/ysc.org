defmodule Ysc.Bookings.DoorCodeTest do
  @moduledoc """
  Tests for DoorCode schema.

  These tests verify:
  - Required field validation (code, property, active_from)
  - Code format validation (4-5 alphanumeric characters)
  - Active/inactive status tracking
  - Property enum validation
  - Database operations
  """
  use Ysc.DataCase, async: true

  alias Ysc.Bookings.DoorCode
  alias Ysc.Repo

  describe "changeset/2" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        code: "1234",
        property: :tahoe,
        active_from: DateTime.utc_now()
      }

      changeset = DoorCode.changeset(%DoorCode{}, attrs)

      assert changeset.valid?
      assert changeset.changes.code == "1234"
      assert changeset.changes.property == :tahoe
    end

    test "requires code" do
      attrs = %{
        property: :tahoe,
        active_from: DateTime.utc_now()
      }

      changeset = DoorCode.changeset(%DoorCode{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:code] != nil
    end

    test "requires property" do
      attrs = %{
        code: "1234",
        active_from: DateTime.utc_now()
      }

      changeset = DoorCode.changeset(%DoorCode{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:property] != nil
    end

    test "requires active_from" do
      attrs = %{
        code: "1234",
        property: :tahoe
      }

      changeset = DoorCode.changeset(%DoorCode{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:active_from] != nil
    end

    test "does not require active_to (defaults to nil for active codes)" do
      attrs = %{
        code: "1234",
        property: :tahoe,
        active_from: DateTime.utc_now()
      }

      changeset = DoorCode.changeset(%DoorCode{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :active_to) == nil
    end

    test "accepts 4-character alphanumeric code" do
      attrs = %{
        code: "AB12",
        property: :tahoe,
        active_from: DateTime.utc_now()
      }

      changeset = DoorCode.changeset(%DoorCode{}, attrs)

      assert changeset.valid?
    end

    test "accepts 5-character alphanumeric code" do
      attrs = %{
        code: "XY789",
        property: :tahoe,
        active_from: DateTime.utc_now()
      }

      changeset = DoorCode.changeset(%DoorCode{}, attrs)

      assert changeset.valid?
    end

    test "rejects code shorter than 4 characters" do
      attrs = %{
        code: "123",
        property: :tahoe,
        active_from: DateTime.utc_now()
      }

      changeset = DoorCode.changeset(%DoorCode{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:code] != nil
    end

    test "rejects code longer than 5 characters" do
      attrs = %{
        code: "123456",
        property: :tahoe,
        active_from: DateTime.utc_now()
      }

      changeset = DoorCode.changeset(%DoorCode{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:code] != nil
    end

    test "rejects code with special characters" do
      attrs = %{
        code: "12#4",
        property: :tahoe,
        active_from: DateTime.utc_now()
      }

      changeset = DoorCode.changeset(%DoorCode{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:code] != nil

      assert changeset.errors[:code] ==
               {"must be 4 or 5 alphanumeric characters", []}
    end

    test "rejects code with spaces" do
      attrs = %{
        code: "12 4",
        property: :tahoe,
        active_from: DateTime.utc_now()
      }

      changeset = DoorCode.changeset(%DoorCode{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:code] != nil
    end

    test "accepts all property enum values" do
      for property <- [:tahoe, :clear_lake] do
        attrs = %{
          code: "1234",
          property: property,
          active_from: DateTime.utc_now()
        }

        changeset = DoorCode.changeset(%DoorCode{}, attrs)

        assert changeset.valid?
        assert changeset.changes.property == property
      end
    end

    test "rejects invalid property value" do
      attrs = %{
        code: "1234",
        property: :invalid_property,
        active_from: DateTime.utc_now()
      }

      changeset = DoorCode.changeset(%DoorCode{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:property] != nil
    end
  end

  describe "active?/1" do
    test "returns true when active_to is nil" do
      door_code = %DoorCode{
        code: "1234",
        property: :tahoe,
        active_from: DateTime.utc_now(),
        active_to: nil
      }

      assert DoorCode.active?(door_code) == true
    end

    test "returns false when active_to is set" do
      door_code = %DoorCode{
        code: "1234",
        property: :tahoe,
        active_from: DateTime.utc_now() |> DateTime.add(-30, :day),
        active_to: DateTime.utc_now()
      }

      assert DoorCode.active?(door_code) == false
    end
  end

  describe "database operations" do
    test "can insert and retrieve door code" do
      active_from = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        code: "5678",
        property: :clear_lake,
        active_from: active_from
      }

      changeset = DoorCode.changeset(%DoorCode{}, attrs)
      {:ok, door_code} = Repo.insert(changeset)

      retrieved = Repo.get(DoorCode, door_code.id)

      assert retrieved.code == "5678"
      assert retrieved.property == :clear_lake
      assert DateTime.compare(retrieved.active_from, active_from) == :eq
      assert retrieved.active_to == nil
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "can deactivate door code by setting active_to" do
      attrs = %{
        code: "ABCD",
        property: :tahoe,
        active_from: DateTime.utc_now()
      }

      {:ok, door_code} =
        %DoorCode{}
        |> DoorCode.changeset(attrs)
        |> Repo.insert()

      assert DoorCode.active?(door_code)

      # Deactivate by setting active_to
      deactivated_at = DateTime.utc_now() |> DateTime.truncate(:second)

      update_changeset =
        DoorCode.changeset(door_code, %{active_to: deactivated_at})

      {:ok, updated_door_code} = Repo.update(update_changeset)

      refute DoorCode.active?(updated_door_code)

      assert DateTime.compare(updated_door_code.active_to, deactivated_at) ==
               :eq
    end

    test "can update door code" do
      attrs = %{
        code: "1234",
        property: :tahoe,
        active_from: DateTime.utc_now()
      }

      {:ok, door_code} =
        %DoorCode{}
        |> DoorCode.changeset(attrs)
        |> Repo.insert()

      # Update the code
      update_changeset = DoorCode.changeset(door_code, %{code: "5678"})
      {:ok, updated_door_code} = Repo.update(update_changeset)

      assert updated_door_code.code == "5678"
    end

    test "can delete door code" do
      attrs = %{
        code: "TEMP",
        property: :tahoe,
        active_from: DateTime.utc_now()
      }

      {:ok, door_code} =
        %DoorCode{}
        |> DoorCode.changeset(attrs)
        |> Repo.insert()

      Repo.delete(door_code)

      assert Repo.get(DoorCode, door_code.id) == nil
    end
  end

  describe "typical door code scenarios" do
    test "activating a new door code" do
      attrs = %{
        code: "9876",
        property: :tahoe,
        active_from: DateTime.utc_now()
      }

      {:ok, door_code} =
        %DoorCode{}
        |> DoorCode.changeset(attrs)
        |> Repo.insert()

      assert DoorCode.active?(door_code)
      assert door_code.active_to == nil
    end

    test "rotating door codes for security" do
      # Old code
      {:ok, old_code} =
        %DoorCode{}
        |> DoorCode.changeset(%{
          code: "OLD1",
          property: :tahoe,
          active_from: DateTime.utc_now() |> DateTime.add(-30, :day)
        })
        |> Repo.insert()

      # Deactivate old code
      deactivated_at = DateTime.utc_now()

      {:ok, old_code_deactivated} =
        old_code
        |> DoorCode.changeset(%{active_to: deactivated_at})
        |> Repo.update()

      # Activate new code
      {:ok, new_code} =
        %DoorCode{}
        |> DoorCode.changeset(%{
          code: "NEW1",
          property: :tahoe,
          active_from: deactivated_at
        })
        |> Repo.insert()

      refute DoorCode.active?(old_code_deactivated)
      assert DoorCode.active?(new_code)
    end

    test "different properties have separate active codes" do
      {:ok, tahoe_code} =
        %DoorCode{}
        |> DoorCode.changeset(%{
          code: "T123",
          property: :tahoe,
          active_from: DateTime.utc_now()
        })
        |> Repo.insert()

      {:ok, clear_lake_code} =
        %DoorCode{}
        |> DoorCode.changeset(%{
          code: "CL45",
          property: :clear_lake,
          active_from: DateTime.utc_now()
        })
        |> Repo.insert()

      assert DoorCode.active?(tahoe_code)
      assert DoorCode.active?(clear_lake_code)
      assert tahoe_code.property != clear_lake_code.property
    end

    test "code format variations" do
      code_examples = ["1234", "ABCD", "12AB", "A1B2", "XYZ89"]

      for code <- code_examples do
        {:ok, door_code} =
          %DoorCode{}
          |> DoorCode.changeset(%{
            code: code,
            property: :tahoe,
            active_from: DateTime.utc_now()
          })
          |> Repo.insert()

        assert door_code.code == code
      end

      # Verify all codes were created
      door_codes = Repo.all(DoorCode)
      assert length(door_codes) >= 5
    end

    test "scheduled code activation (future active_from)" do
      future_activation =
        DateTime.utc_now()
        |> DateTime.add(7, :day)
        |> DateTime.truncate(:second)

      attrs = %{
        code: "FUTR",
        property: :tahoe,
        active_from: future_activation
      }

      {:ok, door_code} =
        %DoorCode{}
        |> DoorCode.changeset(attrs)
        |> Repo.insert()

      # Code is created but activation is scheduled for future
      assert DateTime.compare(door_code.active_from, future_activation) == :eq
    end
  end
end
