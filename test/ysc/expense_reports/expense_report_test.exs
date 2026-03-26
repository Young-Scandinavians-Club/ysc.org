defmodule Ysc.ExpenseReports.ExpenseReportTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.ExpenseReports.ExpenseReport

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
  end
end
