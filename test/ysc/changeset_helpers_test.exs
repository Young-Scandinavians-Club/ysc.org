defmodule Ysc.ChangesetHelpersTest do
  use ExUnit.Case, async: true

  alias Ysc.ChangesetHelpers
  import Ecto.Changeset

  defmodule TestSchema do
    use Ecto.Schema

    schema "test_schema" do
      field :tags, {:array, :string}
      field :categories, {:array, :string}
    end
  end

  describe "trim_array/3" do
    test "removes blank values from array" do
      changeset =
        %TestSchema{}
        |> cast(%{tags: ["tag1", "", "tag2", "   ", "tag3"]}, [:tags])
        |> ChangesetHelpers.trim_array(:tags)

      assert get_change(changeset, :tags) == ["tag1", "tag2", "tag3"]
    end

    test "removes custom blank value from array" do
      changeset =
        %TestSchema{}
        |> cast(%{tags: ["tag1", "NONE", "tag2", "NONE"]}, [:tags])
        |> ChangesetHelpers.trim_array(:tags, "NONE")

      assert get_change(changeset, :tags) == ["tag1", "tag2"]
    end

    test "handles empty array" do
      changeset =
        %TestSchema{}
        |> cast(%{tags: []}, [:tags])
        |> ChangesetHelpers.trim_array(:tags)

      assert get_change(changeset, :tags) == []
    end
  end

  describe "validate_array/3" do
    test "validates all values are in valid set" do
      valid_values = ["tag1", "tag2", "tag3"]

      changeset =
        %TestSchema{}
        |> cast(%{tags: ["tag1", "tag2"]}, [:tags])
        |> ChangesetHelpers.validate_array(:tags, valid_values)

      assert changeset.valid?
      assert changeset.errors == []
    end

    test "rejects values not in valid set" do
      valid_values = ["tag1", "tag2", "tag3"]

      changeset =
        %TestSchema{}
        |> cast(%{tags: ["tag1", "invalid"]}, [:tags])
        |> ChangesetHelpers.validate_array(:tags, valid_values)

      refute changeset.valid?
      assert changeset.errors != []
    end
  end

  describe "sort_array/2" do
    test "sorts array values" do
      changeset =
        %TestSchema{}
        |> cast(%{tags: ["tag3", "tag1", "tag2"]}, [:tags])
        |> ChangesetHelpers.sort_array(:tags)

      assert get_change(changeset, :tags) == ["tag1", "tag2", "tag3"]
    end
  end

  describe "clean_and_validate_array/4" do
    test "trims, sorts, and validates array" do
      valid_values = ["tag1", "tag2", "tag3"]

      changeset =
        %TestSchema{}
        |> cast(%{tags: ["tag3", "", "tag1", "tag2"]}, [:tags])
        |> ChangesetHelpers.clean_and_validate_array(:tags, valid_values)

      assert changeset.valid?
      assert get_change(changeset, :tags) == ["tag1", "tag2", "tag3"]
    end

    test "rejects invalid values after cleaning" do
      valid_values = ["tag1", "tag2", "tag3"]

      changeset =
        %TestSchema{}
        |> cast(%{tags: ["tag1", "invalid", ""]}, [:tags])
        |> ChangesetHelpers.clean_and_validate_array(:tags, valid_values)

      refute changeset.valid?
    end
  end
end
