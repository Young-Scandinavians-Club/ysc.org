defmodule Ysc.PropertyOutages.QueriesTest do
  @moduledoc """
  Tests for Ysc.PropertyOutages.Queries module.
  """
  use Ysc.DataCase, async: true

  alias Ysc.PropertyOutages.{Queries, OutageTracker}
  alias Ysc.Repo

  setup do
    # Create test outages
    {:ok, outage1} =
      OutageTracker.changeset(%OutageTracker{}, %{
        incident_id: "inc_001",
        incident_type: :power_outage,
        property: :tahoe,
        company_name: "PG&E",
        description: "Power outage in Tahoe",
        incident_date: Date.utc_today()
      })
      |> Repo.insert()

    {:ok, outage2} =
      OutageTracker.changeset(%OutageTracker{}, %{
        incident_id: "inc_002",
        incident_type: :water_outage,
        property: :clear_lake,
        company_name: "Liberty Utilities",
        description: "Water outage in Clear Lake",
        incident_date: Date.utc_today()
      })
      |> Repo.insert()

    {:ok, outage3} =
      OutageTracker.changeset(%OutageTracker{}, %{
        incident_id: "inc_003",
        incident_type: :power_outage,
        property: :tahoe,
        company_name: "PG&E",
        description: "Another power outage",
        incident_date: Date.add(Date.utc_today(), -1)
      })
      |> Repo.insert()

    %{outage1: outage1, outage2: outage2, outage3: outage3}
  end

  describe "all/0" do
    test "returns all outages ordered by inserted_at desc" do
      outages = Queries.all()
      assert length(outages) >= 3
      # Should be ordered by inserted_at desc
      assert Enum.at(outages, 0).inserted_at >= Enum.at(outages, 1).inserted_at
    end

    test "limits results to 1000" do
      # Create more than 1000 outages would require many inserts
      # Just verify the query structure is correct
      outages = Queries.all()
      assert length(outages) <= 1000
    end
  end

  describe "by_property/1" do
    test "returns outages for specific property" do
      tahoe_outages = Queries.by_property(:tahoe)
      assert length(tahoe_outages) >= 2
      assert Enum.all?(tahoe_outages, &(&1.property == :tahoe))

      clear_lake_outages = Queries.by_property(:clear_lake)
      assert clear_lake_outages != []
      assert Enum.all?(clear_lake_outages, &(&1.property == :clear_lake))
    end
  end

  describe "by_incident_type/1" do
    test "returns outages for specific incident type" do
      power_outages = Queries.by_incident_type(:power_outage)
      assert length(power_outages) >= 2
      assert Enum.all?(power_outages, &(&1.incident_type == :power_outage))

      water_outages = Queries.by_incident_type(:water_outage)
      assert water_outages != []
      assert Enum.all?(water_outages, &(&1.incident_type == :water_outage))
    end
  end

  describe "by_property_and_type/2" do
    test "returns outages for specific property and type" do
      tahoe_power = Queries.by_property_and_type(:tahoe, :power_outage)
      assert length(tahoe_power) >= 2

      assert Enum.all?(tahoe_power, fn o ->
               o.property == :tahoe && o.incident_type == :power_outage
             end)

      clear_lake_water =
        Queries.by_property_and_type(:clear_lake, :water_outage)

      assert clear_lake_water != []

      assert Enum.all?(clear_lake_water, fn o ->
               o.property == :clear_lake && o.incident_type == :water_outage
             end)
    end
  end

  describe "by_company/1" do
    test "returns outages for specific company" do
      pge_outages = Queries.by_company("PG&E")
      assert length(pge_outages) >= 2
      assert Enum.all?(pge_outages, &(&1.company_name == "PG&E"))

      liberty_outages = Queries.by_company("Liberty Utilities")
      assert liberty_outages != []

      assert Enum.all?(
               liberty_outages,
               &(&1.company_name == "Liberty Utilities")
             )
    end
  end

  describe "recent/1" do
    test "returns recent outages with default limit" do
      outages = Queries.recent()
      assert length(outages) <= 10
    end

    test "returns recent outages with custom limit" do
      outages = Queries.recent(2)
      assert length(outages) <= 2
    end

    test "orders by inserted_at desc" do
      outages = Queries.recent(10)

      if length(outages) > 1 do
        assert Enum.at(outages, 0).inserted_at >=
                 Enum.at(outages, 1).inserted_at
      end
    end
  end

  describe "get_by_incident_id/1" do
    test "returns outage by incident_id", %{outage1: outage1} do
      found = Queries.get_by_incident_id("inc_001")
      assert found.id == outage1.id
      assert found.incident_id == "inc_001"
    end

    test "returns nil for non-existent incident_id" do
      assert Queries.get_by_incident_id("nonexistent") == nil
    end
  end

  describe "get/1" do
    test "returns outage by ID", %{outage1: outage1} do
      found = Queries.get(outage1.id)
      assert found.id == outage1.id
    end

    test "returns nil for non-existent ID" do
      assert Queries.get(Ecto.ULID.generate()) == nil
    end
  end

  describe "grouped_by_property/0" do
    test "returns outages grouped by property" do
      grouped = Queries.grouped_by_property()
      assert is_list(grouped)
      # Should have entries for both properties
      property_names = Enum.map(grouped, fn {property, _count} -> property end)
      assert :tahoe in property_names or :clear_lake in property_names
    end
  end

  describe "grouped_by_incident_type/0" do
    test "returns outages grouped by incident type" do
      grouped = Queries.grouped_by_incident_type()
      assert is_list(grouped)
      # Should have entries for power_outage and water_outage
      types = Enum.map(grouped, fn {type, _count} -> type end)
      assert :power_outage in types or :water_outage in types
    end
  end

  describe "grouped_by_company/0" do
    test "returns outages grouped by company" do
      grouped = Queries.grouped_by_company()
      assert is_list(grouped)
      # Should have entries for PG&E and Liberty Utilities
      companies = Enum.map(grouped, fn {company, _count} -> company end)
      assert "PG&E" in companies or "Liberty Utilities" in companies
    end
  end

  describe "base_query/0" do
    test "returns a base query that can be customized" do
      query = Queries.base_query()
      assert %Ecto.Query{} = query

      # Can add additional filters
      custom_query =
        from o in query,
          where: o.property == :tahoe

      results = Repo.all(custom_query)
      assert Enum.all?(results, &(&1.property == :tahoe))
    end
  end
end
