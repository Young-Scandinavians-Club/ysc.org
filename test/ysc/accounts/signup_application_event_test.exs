defmodule Ysc.Accounts.SignupApplicationEventTest do
  use Ysc.DataCase, async: true

  alias Ysc.Accounts.SignupApplicationEvent

  describe "new_event_changeset/3" do
    test "valid changeset with all required fields" do
      attrs = %{
        event: :review_started,
        application_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        reviewer_user_id: Ecto.ULID.generate(),
        result: "approved"
      }

      changeset =
        SignupApplicationEvent.new_event_changeset(
          %SignupApplicationEvent{},
          attrs
        )

      assert changeset.valid?
    end

    test "valid changeset without optional result field" do
      attrs = %{
        event: :review_started,
        application_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        reviewer_user_id: Ecto.ULID.generate()
      }

      changeset =
        SignupApplicationEvent.new_event_changeset(
          %SignupApplicationEvent{},
          attrs
        )

      assert changeset.valid?
    end

    test "invalid changeset when missing event" do
      attrs = %{
        application_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate(),
        reviewer_user_id: Ecto.ULID.generate()
      }

      changeset =
        SignupApplicationEvent.new_event_changeset(
          %SignupApplicationEvent{},
          attrs
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).event
    end

    test "invalid changeset when missing application_id" do
      attrs = %{
        event: :review_started,
        user_id: Ecto.ULID.generate(),
        reviewer_user_id: Ecto.ULID.generate()
      }

      changeset =
        SignupApplicationEvent.new_event_changeset(
          %SignupApplicationEvent{},
          attrs
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).application_id
    end

    test "invalid changeset when missing user_id" do
      attrs = %{
        event: :review_started,
        application_id: Ecto.ULID.generate(),
        reviewer_user_id: Ecto.ULID.generate()
      }

      changeset =
        SignupApplicationEvent.new_event_changeset(
          %SignupApplicationEvent{},
          attrs
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).user_id
    end

    test "invalid changeset when missing reviewer_user_id" do
      attrs = %{
        event: :review_started,
        application_id: Ecto.ULID.generate(),
        user_id: Ecto.ULID.generate()
      }

      changeset =
        SignupApplicationEvent.new_event_changeset(
          %SignupApplicationEvent{},
          attrs
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).reviewer_user_id
    end

    test "casts all valid event types" do
      application_id = Ecto.ULID.generate()
      user_id = Ecto.ULID.generate()
      reviewer_id = Ecto.ULID.generate()

      for event <- [:review_started, :review_completed, :review_updated] do
        attrs = %{
          event: event,
          application_id: application_id,
          user_id: user_id,
          reviewer_user_id: reviewer_id
        }

        changeset =
          SignupApplicationEvent.new_event_changeset(
            %SignupApplicationEvent{},
            attrs
          )

        assert changeset.valid?
        assert Ecto.Changeset.get_change(changeset, :event) == event
      end
    end
  end
end
