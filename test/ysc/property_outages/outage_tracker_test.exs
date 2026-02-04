defmodule Ysc.PropertyOutages.OutageTrackerTest do
  @moduledoc """
  Tests for OutageTracker schema.

  These tests verify:
  - Required field validation
  - Property enum validation
  - Incident type enum validation
  - Unique constraint on incident_id
  - Optional field handling
  - Database operations
  """
  use Ysc.DataCase, async: true

  alias Ysc.PropertyOutages.OutageTracker
  alias Ysc.Repo

  describe "changeset/2" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        incident_id: "INC-123",
        incident_type: "power_outage"
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)

      assert changeset.valid?
      assert changeset.changes.incident_id == "INC-123"
      assert changeset.changes.incident_type == :power_outage
    end

    test "creates valid changeset with all fields" do
      attrs = %{
        incident_id: "INC-456",
        incident_type: "water_outage",
        description: "Water main break on Cedar Lane",
        company_name: "Truckee Water Department",
        incident_date: ~D[2024-12-15],
        property: "tahoe",
        raw_response: %{"status" => "active", "eta" => "2024-12-15 18:00"}
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)

      assert changeset.valid?
      assert changeset.changes.incident_id == "INC-456"
      assert changeset.changes.incident_type == :water_outage
      assert changeset.changes.description == "Water main break on Cedar Lane"
      assert changeset.changes.company_name == "Truckee Water Department"
      assert changeset.changes.incident_date == ~D[2024-12-15]
      assert changeset.changes.property == :tahoe

      assert changeset.changes.raw_response == %{
               "status" => "active",
               "eta" => "2024-12-15 18:00"
             }
    end

    test "requires incident_id" do
      attrs = %{
        incident_type: "power_outage"
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).incident_id
    end

    test "requires incident_type" do
      attrs = %{
        incident_id: "INC-123"
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).incident_type
    end

    test "accepts all optional fields as nil" do
      attrs = %{
        incident_id: "INC-789",
        incident_type: "power_outage",
        description: nil,
        company_name: nil,
        incident_date: nil,
        property: nil,
        raw_response: nil
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)

      assert changeset.valid?
    end
  end

  describe "incident_type enum validation" do
    test "accepts power_outage incident type" do
      attrs = %{
        incident_id: "INC-001",
        incident_type: "power_outage"
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)

      assert changeset.valid?
      assert changeset.changes.incident_type == :power_outage
    end

    test "accepts water_outage incident type" do
      attrs = %{
        incident_id: "INC-002",
        incident_type: "water_outage"
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)

      assert changeset.valid?
      assert changeset.changes.incident_type == :water_outage
    end

    test "accepts internet_outage incident type" do
      attrs = %{
        incident_id: "INC-003",
        incident_type: "internet_outage"
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)

      assert changeset.valid?
      assert changeset.changes.incident_type == :internet_outage
    end

    test "rejects invalid incident type" do
      attrs = %{
        incident_id: "INC-999",
        incident_type: "invalid_type"
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:incident_type] != nil
    end
  end

  describe "property enum validation" do
    test "accepts tahoe property" do
      attrs = %{
        incident_id: "INC-TAH-001",
        incident_type: "power_outage",
        property: "tahoe"
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)

      assert changeset.valid?
      assert changeset.changes.property == :tahoe
    end

    test "accepts clear_lake property" do
      attrs = %{
        incident_id: "INC-CL-001",
        incident_type: "power_outage",
        property: "clear_lake"
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)

      assert changeset.valid?
      assert changeset.changes.property == :clear_lake
    end

    test "rejects invalid property" do
      attrs = %{
        incident_id: "INC-INV-001",
        incident_type: "power_outage",
        property: "invalid_property"
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:property] != nil
    end

    test "allows nil property" do
      attrs = %{
        incident_id: "INC-NIL-001",
        incident_type: "power_outage",
        property: nil
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)

      assert changeset.valid?
    end
  end

  describe "database operations" do
    test "can insert and retrieve outage tracker" do
      attrs = %{
        incident_id: "PGE-2024-001",
        incident_type: "power_outage",
        description: "Planned maintenance on Cedar Lane",
        company_name: "PG&E",
        incident_date: ~D[2024-12-20],
        property: "tahoe",
        raw_response: %{
          "incident_id" => "PGE-2024-001",
          "status" => "scheduled",
          "start_time" => "2024-12-20 09:00:00",
          "estimated_end" => "2024-12-20 15:00:00"
        }
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)
      {:ok, outage} = Repo.insert(changeset)

      retrieved = Repo.get(OutageTracker, outage.id)

      assert retrieved.incident_id == "PGE-2024-001"
      assert retrieved.incident_type == :power_outage
      assert retrieved.description == "Planned maintenance on Cedar Lane"
      assert retrieved.company_name == "PG&E"
      assert retrieved.incident_date == ~D[2024-12-20]
      assert retrieved.property == :tahoe
      assert retrieved.raw_response["incident_id"] == "PGE-2024-001"
      assert retrieved.raw_response["status"] == "scheduled"
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "enforces unique constraint on incident_id" do
      attrs = %{
        incident_id: "UNIQUE-001",
        incident_type: "power_outage"
      }

      # Insert first outage
      changeset1 = OutageTracker.changeset(%OutageTracker{}, attrs)
      {:ok, _outage1} = Repo.insert(changeset1)

      # Try to insert duplicate
      changeset2 = OutageTracker.changeset(%OutageTracker{}, attrs)
      {:error, changeset} = Repo.insert(changeset2)

      assert "has already been taken" in errors_on(changeset).incident_id
    end

    test "allows same incident_id after update" do
      attrs = %{
        incident_id: "UPDATE-001",
        incident_type: "power_outage",
        description: "Original description"
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)
      {:ok, outage} = Repo.insert(changeset)

      # Update the same record
      update_attrs = %{description: "Updated description"}
      update_changeset = OutageTracker.changeset(outage, update_attrs)

      {:ok, updated} = Repo.update(update_changeset)

      assert updated.incident_id == "UPDATE-001"
      assert updated.description == "Updated description"
    end

    test "stores complex raw_response map" do
      attrs = %{
        incident_id: "COMPLEX-001",
        incident_type: "power_outage",
        raw_response: %{
          "metadata" => %{
            "source" => "PGE API",
            "fetched_at" => "2024-12-15T10:30:00Z"
          },
          "outage_details" => %{
            "affected_customers" => 150,
            "crews_assigned" => 3,
            "priority" => "high"
          },
          "timeline" => [
            %{"time" => "09:00", "event" => "Outage reported"},
            %{"time" => "09:15", "event" => "Crew dispatched"},
            %{"time" => "10:30", "event" => "Crew on site"}
          ]
        }
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)
      {:ok, outage} = Repo.insert(changeset)

      retrieved = Repo.get(OutageTracker, outage.id)

      assert retrieved.raw_response["metadata"]["source"] == "PGE API"

      assert retrieved.raw_response["outage_details"]["affected_customers"] ==
               150

      assert length(retrieved.raw_response["timeline"]) == 3
    end

    test "handles nil values for optional fields" do
      attrs = %{
        incident_id: "MINIMAL-001",
        incident_type: "water_outage"
      }

      changeset = OutageTracker.changeset(%OutageTracker{}, attrs)
      {:ok, outage} = Repo.insert(changeset)

      retrieved = Repo.get(OutageTracker, outage.id)

      assert retrieved.description == nil
      assert retrieved.company_name == nil
      assert retrieved.incident_date == nil
      assert retrieved.property == nil
      assert retrieved.raw_response == nil
    end
  end

  describe "changeset/1 default attrs" do
    test "creates empty changeset when called with no attrs" do
      changeset = OutageTracker.changeset(%OutageTracker{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).incident_id
      assert "can't be blank" in errors_on(changeset).incident_type
    end
  end
end
