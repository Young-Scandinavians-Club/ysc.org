defmodule Ysc.Accounts.UserNoteTest do
  use Ysc.DataCase, async: true

  alias Ysc.Accounts.UserNote

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      attrs = %{
        user_id: Ecto.ULID.generate(),
        created_by_user_id: Ecto.ULID.generate(),
        note: "User contacted support about billing issue",
        category: :general
      }

      changeset = UserNote.changeset(%UserNote{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with violation category" do
      attrs = %{
        user_id: Ecto.ULID.generate(),
        created_by_user_id: Ecto.ULID.generate(),
        note: "User violated community guidelines",
        category: :violation
      }

      changeset = UserNote.changeset(%UserNote{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset when missing user_id" do
      attrs = %{
        created_by_user_id: Ecto.ULID.generate(),
        note: "Test note",
        category: :general
      }

      changeset = UserNote.changeset(%UserNote{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).user_id
    end

    test "invalid changeset when missing created_by_user_id" do
      attrs = %{
        user_id: Ecto.ULID.generate(),
        note: "Test note",
        category: :general
      }

      changeset = UserNote.changeset(%UserNote{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).created_by_user_id
    end

    test "invalid changeset when missing note" do
      attrs = %{
        user_id: Ecto.ULID.generate(),
        created_by_user_id: Ecto.ULID.generate(),
        category: :general
      }

      changeset = UserNote.changeset(%UserNote{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).note
    end

    test "invalid changeset when missing category" do
      attrs = %{
        user_id: Ecto.ULID.generate(),
        created_by_user_id: Ecto.ULID.generate(),
        note: "Test note"
      }

      changeset = UserNote.changeset(%UserNote{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).category
    end

    test "invalid changeset when note is empty string" do
      attrs = %{
        user_id: Ecto.ULID.generate(),
        created_by_user_id: Ecto.ULID.generate(),
        note: "",
        category: :general
      }

      changeset = UserNote.changeset(%UserNote{}, attrs)
      refute changeset.valid?
      # Empty string triggers validate_required
      assert "can't be blank" in errors_on(changeset).note
    end

    test "valid changeset when note is at minimum length" do
      attrs = %{
        user_id: Ecto.ULID.generate(),
        created_by_user_id: Ecto.ULID.generate(),
        note: "a",
        category: :general
      }

      changeset = UserNote.changeset(%UserNote{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset when note exceeds max length" do
      attrs = %{
        user_id: Ecto.ULID.generate(),
        created_by_user_id: Ecto.ULID.generate(),
        note: String.duplicate("a", 5001),
        category: :general
      }

      changeset = UserNote.changeset(%UserNote{}, attrs)
      refute changeset.valid?
      assert "should be at most 5000 character(s)" in errors_on(changeset).note
    end

    test "valid changeset when note is at max length" do
      attrs = %{
        user_id: Ecto.ULID.generate(),
        created_by_user_id: Ecto.ULID.generate(),
        note: String.duplicate("a", 5000),
        category: :general
      }

      changeset = UserNote.changeset(%UserNote{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with multiline note" do
      attrs = %{
        user_id: Ecto.ULID.generate(),
        created_by_user_id: Ecto.ULID.generate(),
        note: "First line\nSecond line\nThird line",
        category: :general
      }

      changeset = UserNote.changeset(%UserNote{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with long note" do
      long_note = """
      User reported issue with booking process.
      Timeline:
      - 2024-01-15: Initial contact
      - 2024-01-16: Follow-up call
      - 2024-01-17: Issue resolved

      User was satisfied with resolution.
      """

      attrs = %{
        user_id: Ecto.ULID.generate(),
        created_by_user_id: Ecto.ULID.generate(),
        note: long_note,
        category: :general
      }

      changeset = UserNote.changeset(%UserNote{}, attrs)
      assert changeset.valid?
    end

    test "changeset preserves all cast fields" do
      user_id = Ecto.ULID.generate()
      created_by_id = Ecto.ULID.generate()

      attrs = %{
        user_id: user_id,
        created_by_user_id: created_by_id,
        note: "Important note",
        category: :violation
      }

      changeset = UserNote.changeset(%UserNote{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :user_id) == user_id

      assert Ecto.Changeset.get_change(changeset, :created_by_user_id) ==
               created_by_id

      assert Ecto.Changeset.get_change(changeset, :note) == "Important note"
      assert Ecto.Changeset.get_change(changeset, :category) == :violation
    end
  end
end
