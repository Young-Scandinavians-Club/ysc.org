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

  describe "draft_changeset/2" do
    test "is valid with only user_id so an empty form can autosave", %{
      user: user
    } do
      cs =
        ExpenseReport.draft_changeset(%ExpenseReport{}, %{
          "user_id" => user.id
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :status) == "draft"
      refute Ecto.Changeset.get_field(cs, :purpose)
      refute Ecto.Changeset.get_field(cs, :reimbursement_method)
    end

    test "forces status to draft even when attrs forge a privileged status", %{
      user: user
    } do
      for status <- ["submitted", "approved", "rejected", "paid"] do
        cs =
          ExpenseReport.draft_changeset(%ExpenseReport{}, %{
            "user_id" => user.id,
            "purpose" => "Conference",
            "status" => status
          })

        assert cs.valid?
        assert Ecto.Changeset.get_field(cs, :status) == "draft"
      end
    end

    test "does not cast QuickBooks sync fields from the member form", %{
      user: user
    } do
      cs =
        ExpenseReport.draft_changeset(%ExpenseReport{}, %{
          "user_id" => user.id,
          "quickbooks_bill_id" => "bill-forged",
          "quickbooks_sync_status" => "synced"
        })

      assert cs.valid?
      refute Ecto.Changeset.get_change(cs, :quickbooks_bill_id)
      refute Ecto.Changeset.get_change(cs, :quickbooks_sync_status)
    end

    test "treats an empty reimbursement method as unset", %{user: user} do
      cs =
        ExpenseReport.draft_changeset(%ExpenseReport{}, %{
          "user_id" => user.id,
          "reimbursement_method" => ""
        })

      assert cs.valid?
      refute Ecto.Changeset.get_field(cs, :reimbursement_method)
    end

    test "still rejects an invalid reimbursement method once one is set", %{
      user: user
    } do
      cs =
        ExpenseReport.draft_changeset(%ExpenseReport{}, %{
          "user_id" => user.id,
          "reimbursement_method" => "wire"
        })

      refute cs.valid?
      assert %{reimbursement_method: [_ | _]} = errors_on(cs)
    end

    test "keeps a half-filled income item valid", %{user: user} do
      cs =
        ExpenseReport.draft_changeset(%ExpenseReport{}, %{
          "user_id" => user.id,
          "income_items" => [
            %{
              "description" => "Door sales",
              "amount" => "",
              "date" => ""
            }
          ]
        })

      assert cs.valid?

      [item_cs] = Ecto.Changeset.get_assoc(cs, :income_items)
      assert Ecto.Changeset.get_field(item_cs, :description) == "Door sales"
      refute Ecto.Changeset.get_field(item_cs, :amount)
      refute Ecto.Changeset.get_field(item_cs, :date)
    end
  end
end
