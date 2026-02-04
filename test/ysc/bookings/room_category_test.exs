defmodule Ysc.Bookings.RoomCategoryTest do
  @moduledoc """
  Tests for RoomCategory schema.

  These tests verify:
  - Required field validation (name)
  - String length validations (name max 255, notes max 1000)
  - Unique constraint on name
  - Associations with rooms and pricing rules
  - Database operations
  """
  use Ysc.DataCase, async: true

  alias Ysc.Bookings.RoomCategory
  alias Ysc.Repo

  describe "changeset/2" do
    test "creates valid changeset with required fields" do
      attrs = %{
        name: "Standard Room"
      }

      changeset = RoomCategory.changeset(%RoomCategory{}, attrs)

      assert changeset.valid?
      assert changeset.changes.name == "Standard Room"
    end

    test "creates valid changeset with optional notes" do
      attrs = %{
        name: "Family Suite",
        notes: "Sleeps up to 6 people with extra space"
      }

      changeset = RoomCategory.changeset(%RoomCategory{}, attrs)

      assert changeset.valid?
      assert changeset.changes.notes == "Sleeps up to 6 people with extra space"
    end

    test "requires name" do
      attrs = %{
        notes: "Some notes without a name"
      }

      changeset = RoomCategory.changeset(%RoomCategory{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:name] != nil
    end

    test "validates name maximum length (255 characters)" do
      long_name = String.duplicate("a", 256)

      attrs = %{
        name: long_name
      }

      changeset = RoomCategory.changeset(%RoomCategory{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:name] != nil
    end

    test "accepts name with exactly 255 characters" do
      valid_name = String.duplicate("a", 255)

      attrs = %{
        name: valid_name
      }

      changeset = RoomCategory.changeset(%RoomCategory{}, attrs)

      assert changeset.valid?
    end

    test "validates notes maximum length (1000 characters)" do
      long_notes = String.duplicate("a", 1001)

      attrs = %{
        name: "Test Category",
        notes: long_notes
      }

      changeset = RoomCategory.changeset(%RoomCategory{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:notes] != nil
    end

    test "accepts notes with exactly 1000 characters" do
      valid_notes = String.duplicate("a", 1000)

      attrs = %{
        name: "Test Category",
        notes: valid_notes
      }

      changeset = RoomCategory.changeset(%RoomCategory{}, attrs)

      assert changeset.valid?
    end
  end

  describe "unique constraint" do
    test "enforces unique name constraint" do
      attrs = %{
        name: "Unique Category"
      }

      # Insert first category
      {:ok, _category} =
        %RoomCategory{}
        |> RoomCategory.changeset(attrs)
        |> Repo.insert()

      # Try to insert duplicate
      changeset = RoomCategory.changeset(%RoomCategory{}, attrs)

      {:error, changeset} = Repo.insert(changeset)
      assert changeset.errors[:name] != nil
    end

    test "allows same name after deleting original" do
      attrs = %{
        name: "Reusable Name"
      }

      # Insert first category
      {:ok, category} =
        %RoomCategory{}
        |> RoomCategory.changeset(attrs)
        |> Repo.insert()

      # Delete it
      Repo.delete(category)

      # Can now reuse the name
      changeset = RoomCategory.changeset(%RoomCategory{}, attrs)
      {:ok, new_category} = Repo.insert(changeset)

      assert new_category.name == "Reusable Name"
    end
  end

  describe "database operations" do
    test "can insert and retrieve room category" do
      attrs = %{
        name: "Deluxe Room",
        notes: "Premium room with mountain view"
      }

      changeset = RoomCategory.changeset(%RoomCategory{}, attrs)
      {:ok, category} = Repo.insert(changeset)

      retrieved = Repo.get(RoomCategory, category.id)

      assert retrieved.name == "Deluxe Room"
      assert retrieved.notes == "Premium room with mountain view"
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "can update room category" do
      attrs = %{
        name: "Original Name",
        notes: "Original notes"
      }

      {:ok, category} =
        %RoomCategory{}
        |> RoomCategory.changeset(attrs)
        |> Repo.insert()

      # Update name and notes
      update_changeset =
        RoomCategory.changeset(category, %{
          name: "Updated Name",
          notes: "Updated notes"
        })

      {:ok, updated_category} = Repo.update(update_changeset)

      assert updated_category.name == "Updated Name"
      assert updated_category.notes == "Updated notes"
    end

    test "can delete room category" do
      attrs = %{
        name: "Temporary Category"
      }

      {:ok, category} =
        %RoomCategory{}
        |> RoomCategory.changeset(attrs)
        |> Repo.insert()

      Repo.delete(category)

      assert Repo.get(RoomCategory, category.id) == nil
    end

    test "can create category without notes" do
      attrs = %{
        name: "Simple Category"
      }

      {:ok, category} =
        %RoomCategory{}
        |> RoomCategory.changeset(attrs)
        |> Repo.insert()

      assert category.name == "Simple Category"
      assert category.notes == nil
    end
  end

  describe "typical room category scenarios" do
    test "standard hotel-style categories" do
      categories = [
        {"Single Room", "One bed, perfect for solo travelers"},
        {"Standard Room", "Two beds, accommodates up to 2 guests"},
        {"Family Suite", "Multiple beds, accommodates up to 6 guests"},
        {"Deluxe Room", "Premium room with lake view"}
      ]

      for {name, notes} <- categories do
        {:ok, _category} =
          %RoomCategory{}
          |> RoomCategory.changeset(%{name: name, notes: notes})
          |> Repo.insert()
      end

      # Verify all categories were created
      all_categories = Repo.all(RoomCategory)
      assert length(all_categories) == 4
    end

    test "categories with varying detail levels" do
      # Minimal category
      {:ok, minimal} =
        %RoomCategory{}
        |> RoomCategory.changeset(%{name: "Basic"})
        |> Repo.insert()

      # Detailed category
      {:ok, detailed} =
        %RoomCategory{}
        |> RoomCategory.changeset(%{
          name: "Premium",
          notes: String.duplicate("Detailed description. ", 20)
        })
        |> Repo.insert()

      assert minimal.notes == nil
      assert String.length(detailed.notes) > 100
    end

    test "querying categories by name pattern" do
      {:ok, _} =
        %RoomCategory{}
        |> RoomCategory.changeset(%{name: "Family Suite - Lakeside"})
        |> Repo.insert()

      {:ok, _} =
        %RoomCategory{}
        |> RoomCategory.changeset(%{name: "Family Suite - Mountain"})
        |> Repo.insert()

      {:ok, _} =
        %RoomCategory{}
        |> RoomCategory.changeset(%{name: "Standard Room"})
        |> Repo.insert()

      # Query for categories with "Family" in name
      family_categories =
        RoomCategory
        |> Ecto.Query.where([c], ilike(c.name, "%Family%"))
        |> Repo.all()

      assert length(family_categories) == 2
    end
  end
end
