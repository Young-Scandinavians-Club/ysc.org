defmodule Ysc.ExpenseReports.ExpenseReportItemTest do
  use Ysc.DataCase, async: true

  alias Ysc.ExpenseReports.ExpenseReportItem

  describe "mileage_rate/0" do
    test "returns the club's per-mile reimbursement rate" do
      assert ExpenseReportItem.mileage_rate() == Money.new(:USD, "0.30")
    end
  end

  describe "changeset/2" do
    test "rejects non-USD currency" do
      cs =
        ExpenseReportItem.changeset(%ExpenseReportItem{}, %{
          date: ~D[2026-01-15],
          vendor: "V",
          description: "D",
          amount: Money.new(1000, :EUR)
        })

      refute cs.valid?
      assert %{amount: ["must be in USD"]} = errors_on(cs)
    end

    test "parses money from binary string" do
      cs =
        ExpenseReportItem.changeset(%ExpenseReportItem{}, %{
          date: ~D[2026-01-15],
          vendor: "V",
          description: "D",
          amount: "12.34"
        })

      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :amount) == Money.new(:USD, "12.34")
    end

    test "accepts valid positive USD money" do
      cs =
        ExpenseReportItem.changeset(%ExpenseReportItem{}, %{
          date: ~D[2026-01-15],
          vendor: "Vendor",
          description: "Description",
          amount: Money.new(500, :USD)
        })

      assert cs.valid?
    end
  end

  describe "changeset/2 mileage expense items" do
    test "computes reimbursement from miles driven at the mileage rate" do
      cs =
        ExpenseReportItem.changeset(%ExpenseReportItem{}, %{
          date: ~D[2026-01-15],
          expense_type: "mileage",
          description: "Board meeting",
          mileage_from_to: "Home to YSC Cabin",
          miles_driven: 20
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :amount) == Money.new(:USD, "6.00")
      assert Ecto.Changeset.get_field(cs, :vendor) == "Mileage"
    end

    test "ignores a user-supplied amount and recomputes it from miles driven" do
      cs =
        ExpenseReportItem.changeset(%ExpenseReportItem{}, %{
          date: ~D[2026-01-15],
          expense_type: "mileage",
          description: "Board meeting",
          mileage_from_to: "Home to YSC Cabin",
          miles_driven: 10,
          amount: Money.new(:USD, "999.00"),
          vendor: "Someone Else"
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :amount) == Money.new(:USD, "3.00")
      assert Ecto.Changeset.get_field(cs, :vendor) == "Mileage"
    end

    test "requires miles driven and a route" do
      cs =
        ExpenseReportItem.changeset(%ExpenseReportItem{}, %{
          date: ~D[2026-01-15],
          expense_type: "mileage",
          description: "Board meeting"
        })

      refute cs.valid?

      assert %{
               miles_driven: ["can't be blank"],
               mileage_from_to: ["can't be blank"]
             } =
               errors_on(cs)
    end

    test "rejects zero or negative miles driven" do
      cs =
        ExpenseReportItem.changeset(%ExpenseReportItem{}, %{
          date: ~D[2026-01-15],
          expense_type: "mileage",
          description: "Board meeting",
          mileage_from_to: "Home to YSC Cabin",
          miles_driven: 0
        })

      refute cs.valid?
      assert %{miles_driven: ["must be greater than 0"]} = errors_on(cs)
    end

    test "rejects miles driven above the per-line cap" do
      cap = ExpenseReportItem.max_miles_driven()
      over_cap = cap + 1
      expected = "must be less than or equal to #{cap}"

      cs =
        ExpenseReportItem.changeset(%ExpenseReportItem{}, %{
          date: ~D[2026-01-15],
          expense_type: "mileage",
          description: "Board meeting",
          mileage_from_to: "Home to YSC Cabin",
          miles_driven: over_cap
        })

      refute cs.valid?
      assert %{miles_driven: [^expected]} = errors_on(cs)
    end

    test "accepts miles driven at the per-line cap" do
      cs =
        ExpenseReportItem.changeset(%ExpenseReportItem{}, %{
          date: ~D[2026-01-15],
          expense_type: "mileage",
          description: "Board meeting",
          mileage_from_to: "Home to YSC Cabin",
          miles_driven: ExpenseReportItem.max_miles_driven()
        })

      assert cs.valid?

      assert Ecto.Changeset.get_field(cs, :amount) ==
               Money.new(:USD, "3000.00")
    end

    test "rejects an unknown expense type" do
      cs =
        ExpenseReportItem.changeset(%ExpenseReportItem{}, %{
          date: ~D[2026-01-15],
          expense_type: "bogus",
          vendor: "V",
          description: "D",
          amount: Money.new(500, :USD)
        })

      refute cs.valid?
      assert %{expense_type: ["is invalid"]} = errors_on(cs)
    end

    test "defaults to a purchase item, unaffected by mileage logic" do
      cs =
        ExpenseReportItem.changeset(%ExpenseReportItem{}, %{
          date: ~D[2026-01-15],
          vendor: "Costco",
          description: "Supplies",
          amount: Money.new(:USD, "42.00")
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :expense_type) == "purchase"
      assert Ecto.Changeset.get_field(cs, :vendor) == "Costco"
      assert Ecto.Changeset.get_field(cs, :amount) == Money.new(:USD, "42.00")
    end
  end
end
