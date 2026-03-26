defmodule Ysc.ExpenseReports.ExpenseReportItemTest do
  use Ysc.DataCase, async: true

  alias Ysc.ExpenseReports.ExpenseReportItem

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
end
