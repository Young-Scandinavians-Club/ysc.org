defmodule Ysc.ExpenseReports.ExpenseReportTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.ExpenseReports.{ExpenseReport, ExpenseReportItem}

  setup do
    %{user: user_fixture()}
  end

  describe "changeset/3" do
    test "normalizes string event_id from empty string to nil", %{user: user} do
      cs =
        ExpenseReport.changeset(%ExpenseReport{}, %{
          "user_id" => user.id,
          "purpose" => "Conference",
          "reimbursement_method" => "check",
          "event_id" => ""
        })

      refute Ecto.Changeset.get_field(cs, :event_id)
    end

    test "normalizes atom event_id from empty string to nil", %{user: user} do
      cs =
        ExpenseReport.changeset(%ExpenseReport{}, %{
          :user_id => user.id,
          :purpose => "Conference",
          :reimbursement_method => "check",
          :event_id => ""
        })

      refute Ecto.Changeset.get_field(cs, :event_id)
    end

    test "requires certification when status is submitted", %{user: user} do
      cs =
        ExpenseReport.changeset(%ExpenseReport{}, %{
          user_id: user.id,
          purpose: "Trip",
          reimbursement_method: "check",
          status: "submitted",
          certification_accepted: false
        })

      refute cs.valid?
      assert Keyword.has_key?(cs.errors, :certification_accepted)
    end

    test "requires receipts on all expense items when submitted", %{user: user} do
      cs =
        ExpenseReport.changeset(%ExpenseReport{}, %{
          user_id: user.id,
          purpose: "Trip",
          reimbursement_method: "check",
          status: "submitted",
          certification_accepted: true,
          expense_items: [
            %{
              date: ~D[2024-01-01],
              vendor: "Vendor",
              description: "Item",
              amount: Money.new(:USD, 100),
              receipt_s3_path: nil
            }
          ]
        })

      refute cs.valid?
      assert Keyword.has_key?(cs.errors, :expense_items)
    end

    test "allows submitted report when items have receipts", %{user: user} do
      cs =
        ExpenseReport.changeset(%ExpenseReport{}, %{
          user_id: user.id,
          purpose: "Trip",
          reimbursement_method: "check",
          status: "submitted",
          certification_accepted: true,
          expense_items: [
            %{
              date: ~D[2024-01-01],
              vendor: "Vendor",
              description: "Item",
              amount: Money.new(:USD, 100),
              receipt_s3_path: "receipts/test.pdf"
            }
          ]
        })

      assert cs.valid?
    end

    test "allows submitted report with a mileage item and no receipt", %{
      user: user
    } do
      cs =
        ExpenseReport.changeset(%ExpenseReport{}, %{
          user_id: user.id,
          purpose: "Trip",
          reimbursement_method: "check",
          status: "submitted",
          certification_accepted: true,
          expense_items: [
            %{
              date: ~D[2024-01-01],
              expense_type: "mileage",
              description: "Board meeting",
              mileage_from_to: "Home to YSC Cabin",
              miles_driven: 20,
              receipt_s3_path: nil
            }
          ]
        })

      assert cs.valid?
    end

    test "allows a mileage item with no receipt when expense_items is preloaded as real structs (not a cast_assoc changeset)",
         %{user: user} do
      # Mirrors Ysc.ExpenseReports.submit_expense_report/1, which calls
      # ExpenseReport.changeset(expense_report, %{status: "submitted"}) on an
      # already-loaded report — cast_assoc leaves :expense_items untouched
      # since "expense_items" isn't in the attrs, so the association stays as
      # real %ExpenseReportItem{} structs rather than changesets.
      report = %ExpenseReport{
        user_id: user.id,
        purpose: "Trip",
        reimbursement_method: "check",
        certification_accepted: true,
        expense_items: [
          %ExpenseReportItem{
            date: ~D[2024-01-01],
            expense_type: "mileage",
            vendor: "Mileage",
            description: "Board meeting",
            mileage_from_to: "Home to YSC Cabin",
            miles_driven: 20,
            amount: Money.new(:USD, "6.00"),
            receipt_s3_path: nil
          }
        ],
        income_items: []
      }

      cs = ExpenseReport.changeset(report, %{status: "submitted"})

      assert cs.valid?
    end
  end
end
