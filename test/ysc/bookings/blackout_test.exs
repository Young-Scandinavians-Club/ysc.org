defmodule Ysc.Bookings.BlackoutTest do
  @moduledoc """
  Tests for Blackout schema.

  These tests verify:
  - Required field validation (reason, property, start_date, end_date)
  - String length validation (reason max 500)
  - Date range validation (end_date >= start_date)
  - Property enum validation
  - Database operations
  """
  use Ysc.DataCase, async: true

  alias Ysc.Bookings.Blackout
  alias Ysc.Repo

  describe "changeset/2" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        reason: "Annual maintenance",
        property: :tahoe,
        start_date: ~D[2024-09-01],
        end_date: ~D[2024-09-07]
      }

      changeset = Blackout.changeset(%Blackout{}, attrs)

      assert changeset.valid?
      assert changeset.changes.reason == "Annual maintenance"
      assert changeset.changes.property == :tahoe
      assert changeset.changes.start_date == ~D[2024-09-01]
      assert changeset.changes.end_date == ~D[2024-09-07]
    end

    test "requires reason" do
      attrs = %{
        property: :tahoe,
        start_date: ~D[2024-09-01],
        end_date: ~D[2024-09-07]
      }

      changeset = Blackout.changeset(%Blackout{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:reason] != nil
    end

    test "requires property" do
      attrs = %{
        reason: "Maintenance",
        start_date: ~D[2024-09-01],
        end_date: ~D[2024-09-07]
      }

      changeset = Blackout.changeset(%Blackout{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:property] != nil
    end

    test "requires start_date" do
      attrs = %{
        reason: "Maintenance",
        property: :tahoe,
        end_date: ~D[2024-09-07]
      }

      changeset = Blackout.changeset(%Blackout{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:start_date] != nil
    end

    test "requires end_date" do
      attrs = %{
        reason: "Maintenance",
        property: :tahoe,
        start_date: ~D[2024-09-01]
      }

      changeset = Blackout.changeset(%Blackout{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:end_date] != nil
    end

    test "validates reason maximum length (500 characters)" do
      long_reason = String.duplicate("a", 501)

      attrs = %{
        reason: long_reason,
        property: :tahoe,
        start_date: ~D[2024-09-01],
        end_date: ~D[2024-09-07]
      }

      changeset = Blackout.changeset(%Blackout{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:reason] != nil
    end

    test "accepts reason with exactly 500 characters" do
      valid_reason = String.duplicate("a", 500)

      attrs = %{
        reason: valid_reason,
        property: :tahoe,
        start_date: ~D[2024-09-01],
        end_date: ~D[2024-09-07]
      }

      changeset = Blackout.changeset(%Blackout{}, attrs)

      assert changeset.valid?
    end

    test "validates end_date is after or equal to start_date" do
      attrs = %{
        reason: "Maintenance",
        property: :tahoe,
        start_date: ~D[2024-09-07],
        end_date: ~D[2024-09-01]
      }

      changeset = Blackout.changeset(%Blackout{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:end_date] != nil

      assert changeset.errors[:end_date] ==
               {"must be on or after start date", []}
    end

    test "accepts single-day blackout (same start and end date)" do
      attrs = %{
        reason: "One day event",
        property: :tahoe,
        start_date: ~D[2024-09-01],
        end_date: ~D[2024-09-01]
      }

      changeset = Blackout.changeset(%Blackout{}, attrs)

      assert changeset.valid?
    end

    test "accepts all property enum values" do
      for property <- [:tahoe, :clear_lake] do
        attrs = %{
          reason: "Maintenance for #{property}",
          property: property,
          start_date: ~D[2024-09-01],
          end_date: ~D[2024-09-07]
        }

        changeset = Blackout.changeset(%Blackout{}, attrs)

        assert changeset.valid?
        assert changeset.changes.property == property
      end
    end

    test "rejects invalid property value" do
      attrs = %{
        reason: "Maintenance",
        property: :invalid_property,
        start_date: ~D[2024-09-01],
        end_date: ~D[2024-09-07]
      }

      changeset = Blackout.changeset(%Blackout{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:property] != nil
    end
  end

  describe "database operations" do
    test "can insert and retrieve blackout period" do
      attrs = %{
        reason: "Summer maintenance",
        property: :tahoe,
        start_date: ~D[2024-09-01],
        end_date: ~D[2024-09-14]
      }

      changeset = Blackout.changeset(%Blackout{}, attrs)
      {:ok, blackout} = Repo.insert(changeset)

      retrieved = Repo.get(Blackout, blackout.id)

      assert retrieved.reason == "Summer maintenance"
      assert retrieved.property == :tahoe
      assert retrieved.start_date == ~D[2024-09-01]
      assert retrieved.end_date == ~D[2024-09-14]
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "can update blackout period" do
      attrs = %{
        reason: "Original reason",
        property: :tahoe,
        start_date: ~D[2024-09-01],
        end_date: ~D[2024-09-07]
      }

      {:ok, blackout} =
        %Blackout{}
        |> Blackout.changeset(attrs)
        |> Repo.insert()

      # Update the reason
      update_changeset =
        Blackout.changeset(blackout, %{reason: "Updated reason"})

      {:ok, updated_blackout} = Repo.update(update_changeset)

      assert updated_blackout.reason == "Updated reason"
    end

    test "can delete blackout period" do
      attrs = %{
        reason: "Temporary blackout",
        property: :tahoe,
        start_date: ~D[2024-09-01],
        end_date: ~D[2024-09-07]
      }

      {:ok, blackout} =
        %Blackout{}
        |> Blackout.changeset(attrs)
        |> Repo.insert()

      Repo.delete(blackout)

      assert Repo.get(Blackout, blackout.id) == nil
    end
  end

  describe "typical blackout scenarios" do
    test "week-long maintenance blackout" do
      attrs = %{
        reason: "Roof repair and exterior painting",
        property: :tahoe,
        start_date: ~D[2024-09-15],
        end_date: ~D[2024-09-21]
      }

      {:ok, blackout} =
        %Blackout{}
        |> Blackout.changeset(attrs)
        |> Repo.insert()

      assert Date.diff(blackout.end_date, blackout.start_date) == 6
    end

    test "extended winter closure" do
      attrs = %{
        reason: "Closed for winter season - reopening in spring",
        property: :clear_lake,
        start_date: ~D[2024-11-01],
        end_date: ~D[2025-03-31]
      }

      {:ok, blackout} =
        %Blackout{}
        |> Blackout.changeset(attrs)
        |> Repo.insert()

      assert blackout.property == :clear_lake
      # Year-spanning blackout
      assert blackout.start_date.year == 2024
      assert blackout.end_date.year == 2025
    end

    test "special event blackout" do
      attrs = %{
        reason: "Reserved for annual members-only retreat",
        property: :tahoe,
        start_date: ~D[2024-10-10],
        end_date: ~D[2024-10-12]
      }

      {:ok, blackout} =
        %Blackout{}
        |> Blackout.changeset(attrs)
        |> Repo.insert()

      assert String.contains?(blackout.reason, "members-only")
    end

    test "multiple blackouts for same property" do
      blackout_periods = [
        {~D[2024-09-01], ~D[2024-09-07], "Spring maintenance"},
        {~D[2024-12-20], ~D[2025-01-05], "Holiday closure"},
        {~D[2024-06-15], ~D[2024-06-15], "One-day event"}
      ]

      for {start_date, end_date, reason} <- blackout_periods do
        {:ok, _blackout} =
          %Blackout{}
          |> Blackout.changeset(%{
            reason: reason,
            property: :tahoe,
            start_date: start_date,
            end_date: end_date
          })
          |> Repo.insert()
      end

      # Verify all blackouts were created
      blackouts =
        Blackout
        |> Ecto.Query.where(property: :tahoe)
        |> Repo.all()

      assert length(blackouts) == 3
    end

    test "blackouts for different properties" do
      {:ok, tahoe_blackout} =
        %Blackout{}
        |> Blackout.changeset(%{
          reason: "Tahoe maintenance",
          property: :tahoe,
          start_date: ~D[2024-09-01],
          end_date: ~D[2024-09-07]
        })
        |> Repo.insert()

      {:ok, clear_lake_blackout} =
        %Blackout{}
        |> Blackout.changeset(%{
          reason: "Clear Lake maintenance",
          property: :clear_lake,
          start_date: ~D[2024-09-01],
          end_date: ~D[2024-09-07]
        })
        |> Repo.insert()

      assert tahoe_blackout.property == :tahoe
      assert clear_lake_blackout.property == :clear_lake
      # Same dates but different properties
      assert tahoe_blackout.start_date == clear_lake_blackout.start_date
    end
  end
end
