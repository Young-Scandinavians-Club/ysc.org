defmodule Ysc.ExpenseReports.ExpenseReportIncomeItemTest do
  use Ysc.DataCase, async: true

  alias Ysc.ExpenseReports.ExpenseReportIncomeItem

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      attrs = %{
        date: ~D[2026-01-15],
        description: "Income from event",
        amount: Money.new(10000, :USD)
      }

      changeset =
        ExpenseReportIncomeItem.changeset(%ExpenseReportIncomeItem{}, attrs)

      assert changeset.valid?
    end

    test "valid changeset with optional proof_s3_path" do
      attrs = %{
        date: ~D[2026-01-15],
        description: "Income with proof",
        amount: Money.new(5000, :USD),
        proof_s3_path: "https://s3.amazonaws.com/bucket/file.pdf"
      }

      changeset =
        ExpenseReportIncomeItem.changeset(%ExpenseReportIncomeItem{}, attrs)

      assert changeset.valid?

      assert get_change(changeset, :proof_s3_path) ==
               "https://s3.amazonaws.com/bucket/file.pdf"
    end

    test "parses money from string" do
      attrs = %{
        date: ~D[2026-01-15],
        description: "Income item",
        amount: "150.50"
      }

      changeset =
        ExpenseReportIncomeItem.changeset(%ExpenseReportIncomeItem{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :amount) == Money.new(:USD, "150.50")
    end

    test "requires date" do
      attrs = %{
        description: "Income item",
        amount: Money.new(1000, :USD)
      }

      changeset =
        ExpenseReportIncomeItem.changeset(%ExpenseReportIncomeItem{}, attrs)

      refute changeset.valid?
      assert %{date: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires description" do
      attrs = %{
        date: ~D[2026-01-15],
        amount: Money.new(1000, :USD)
      }

      changeset =
        ExpenseReportIncomeItem.changeset(%ExpenseReportIncomeItem{}, attrs)

      refute changeset.valid?
      assert %{description: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires amount" do
      attrs = %{
        date: ~D[2026-01-15],
        description: "Income item"
      }

      changeset =
        ExpenseReportIncomeItem.changeset(%ExpenseReportIncomeItem{}, attrs)

      refute changeset.valid?
      assert %{amount: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates description max length" do
      long_description = String.duplicate("a", 1001)

      attrs = %{
        date: ~D[2026-01-15],
        description: long_description,
        amount: Money.new(1000, :USD)
      }

      changeset =
        ExpenseReportIncomeItem.changeset(%ExpenseReportIncomeItem{}, attrs)

      refute changeset.valid?

      assert %{description: ["should be at most 1000 character(s)"]} =
               errors_on(changeset)
    end

    test "validates proof_s3_path max length" do
      long_path = "https://s3.amazonaws.com/" <> String.duplicate("a", 2025)

      attrs = %{
        date: ~D[2026-01-15],
        description: "Income item",
        amount: Money.new(1000, :USD),
        proof_s3_path: long_path
      }

      changeset =
        ExpenseReportIncomeItem.changeset(%ExpenseReportIncomeItem{}, attrs)

      refute changeset.valid?

      assert %{proof_s3_path: ["should be at most 2048 character(s)"]} =
               errors_on(changeset)
    end

    test "rejects amount with non-USD currency" do
      attrs = %{
        date: ~D[2026-01-15],
        description: "Income item",
        amount: Money.new(1000, :EUR)
      }

      changeset =
        ExpenseReportIncomeItem.changeset(%ExpenseReportIncomeItem{}, attrs)

      refute changeset.valid?
      assert %{amount: ["must be in USD"]} = errors_on(changeset)
    end

    test "validates positive amounts" do
      attrs = %{
        date: ~D[2026-01-15],
        description: "Income item",
        amount: Money.new(:USD, "0.01")
      }

      changeset =
        ExpenseReportIncomeItem.changeset(%ExpenseReportIncomeItem{}, attrs)

      assert changeset.valid?
    end

    test "accepts valid money amounts" do
      attrs = %{
        date: ~D[2026-01-15],
        description: "Income item",
        amount: Money.new(:USD, "999999.99")
      }

      changeset =
        ExpenseReportIncomeItem.changeset(%ExpenseReportIncomeItem{}, attrs)

      assert changeset.valid?
    end

    test "accepts large description within limit" do
      description = String.duplicate("a", 1000)

      attrs = %{
        date: ~D[2026-01-15],
        description: description,
        amount: Money.new(1000, :USD)
      }

      changeset =
        ExpenseReportIncomeItem.changeset(%ExpenseReportIncomeItem{}, attrs)

      assert changeset.valid?
    end

    test "accepts large proof_s3_path within limit" do
      path = "https://s3.amazonaws.com/" <> String.duplicate("a", 2021)

      attrs = %{
        date: ~D[2026-01-15],
        description: "Income item",
        amount: Money.new(1000, :USD),
        proof_s3_path: path
      }

      changeset =
        ExpenseReportIncomeItem.changeset(%ExpenseReportIncomeItem{}, attrs)

      assert changeset.valid?
    end
  end
end
