defmodule Ysc.Events.AgendaItemTest do
  @moduledoc """
  Tests for Ysc.Events.AgendaItem schema.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Events.AgendaItem

  describe "changeset/2" do
    test "validates required fields" do
      changeset = AgendaItem.changeset(%AgendaItem{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).title
      assert "can't be blank" in errors_on(changeset).agenda_id
    end

    test "validates lengths" do
      long_title = String.duplicate("a", 257)
      long_desc = String.duplicate("a", 1025)

      attrs = %{
        title: long_title,
        description: long_desc
      }

      changeset =
        AgendaItem.changeset(
          %AgendaItem{agenda_id: Ecto.ULID.generate()},
          attrs
        )

      refute changeset.valid?
      assert "should be at most 256 character(s)" in errors_on(changeset).title

      assert "should be at most 1024 character(s)" in errors_on(changeset).description
    end

    test "ignores client-supplied agenda_id (Finding 75)" do
      owned = Ecto.ULID.generate()
      forged = Ecto.ULID.generate()

      changeset =
        AgendaItem.changeset(%AgendaItem{agenda_id: owned}, %{
          title: "Talk",
          agenda_id: forged
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :agenda_id) == owned
      assert is_nil(Ecto.Changeset.get_change(changeset, :agenda_id))
    end
  end
end
