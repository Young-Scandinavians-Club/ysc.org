defmodule Ysc.Accounts.FamilyMemberTest do
  use Ysc.DataCase, async: true

  alias Ysc.Accounts.FamilyMember

  describe "family_member_changeset/3" do
    test "valid changeset with all required fields" do
      attrs = %{
        first_name: "Jane",
        last_name: "Doe",
        type: :spouse
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with optional birth_date" do
      attrs = %{
        first_name: "John",
        last_name: "Smith",
        type: :child,
        birth_date: ~D[2010-05-15]
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset when missing first_name" do
      attrs = %{
        last_name: "Johnson",
        type: :spouse
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).first_name
    end

    test "invalid changeset when missing last_name" do
      attrs = %{
        first_name: "Alice",
        type: :child
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).last_name
    end

    test "invalid changeset when missing type" do
      attrs = %{
        first_name: "Bob",
        last_name: "Williams"
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).type
    end

    test "invalid changeset when first_name is empty string" do
      attrs = %{
        first_name: "",
        last_name: "Brown",
        type: :spouse
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      refute changeset.valid?
      # Empty string triggers validate_required, not validate_length
      assert "can't be blank" in errors_on(changeset).first_name
    end

    test "invalid changeset when last_name is empty string" do
      attrs = %{
        first_name: "Charlie",
        last_name: "",
        type: :child
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      refute changeset.valid?
      # Empty string triggers validate_required, not validate_length
      assert "can't be blank" in errors_on(changeset).last_name
    end

    test "invalid changeset when first_name exceeds max length" do
      attrs = %{
        first_name: String.duplicate("a", 161),
        last_name: "Davis",
        type: :spouse
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      refute changeset.valid?

      assert "should be at most 160 character(s)" in errors_on(changeset).first_name
    end

    test "invalid changeset when last_name exceeds max length" do
      attrs = %{
        first_name: "David",
        last_name: String.duplicate("a", 161),
        type: :child
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      refute changeset.valid?

      assert "should be at most 160 character(s)" in errors_on(changeset).last_name
    end

    test "valid changeset when first_name is at max length" do
      attrs = %{
        first_name: String.duplicate("a", 160),
        last_name: "Miller",
        type: :spouse
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset when last_name is at max length" do
      attrs = %{
        first_name: "Emily",
        last_name: String.duplicate("a", 160),
        type: :child
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset when birth_date is before 1900" do
      attrs = %{
        first_name: "Frank",
        last_name: "Wilson",
        type: :spouse,
        birth_date: ~D[1899-12-31]
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      refute changeset.valid?
      assert "must be after 1900" in errors_on(changeset).birth_date
    end

    test "valid changeset when birth_date is exactly January 1, 1900" do
      attrs = %{
        first_name: "Grace",
        last_name: "Moore",
        type: :spouse,
        birth_date: ~D[1900-01-01]
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset when birth_date is in the future" do
      tomorrow = Date.add(Date.utc_today(), 1)

      attrs = %{
        first_name: "Henry",
        last_name: "Taylor",
        type: :child,
        birth_date: tomorrow
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      refute changeset.valid?
      assert "cannot be in the future" in errors_on(changeset).birth_date
    end

    test "valid changeset when birth_date is today" do
      attrs = %{
        first_name: "Ivy",
        last_name: "Anderson",
        type: :child,
        birth_date: Date.utc_today()
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset without birth_date" do
      attrs = %{
        first_name: "Jack",
        last_name: "Thomas",
        type: :spouse,
        birth_date: nil
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with spouse type" do
      attrs = %{
        first_name: "Karen",
        last_name: "Jackson",
        type: :spouse
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with child type" do
      attrs = %{
        first_name: "Leo",
        last_name: "White",
        type: :child
      }

      changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with various birth dates" do
      test_cases = [
        ~D[1950-06-15],
        ~D[1980-03-20],
        ~D[2000-12-31],
        ~D[2020-01-01]
      ]

      Enum.each(test_cases, fn birth_date ->
        attrs = %{
          first_name: "Maria",
          last_name: "Harris",
          type: :child,
          birth_date: birth_date
        }

        changeset = FamilyMember.family_member_changeset(%FamilyMember{}, attrs)
        assert changeset.valid?
      end)
    end

    test "changeset accepts opts parameter" do
      attrs = %{
        first_name: "Nathan",
        last_name: "Martin",
        type: :spouse
      }

      # opts parameter should be accepted but not used
      changeset =
        FamilyMember.family_member_changeset(%FamilyMember{}, attrs,
          some: :option
        )

      assert changeset.valid?
    end
  end
end
