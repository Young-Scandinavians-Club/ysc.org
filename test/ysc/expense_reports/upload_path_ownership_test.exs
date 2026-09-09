defmodule Ysc.ExpenseReports.UploadPathOwnershipTest do
  @moduledoc """
  Leftover Finding 60 edges: re-saving a draft must keep upload keys this
  report already had, even after the delete-and-recreate and even when the
  same legacy key exists on another member's report.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.ExpenseReports

  alias Ysc.ExpenseReports.{
    ExpenseReport,
    ExpenseReportIncomeItem,
    ExpenseReportItem
  }

  alias Ysc.Repo

  test "save_draft re-saves a legacy receipt already on this draft when another member also has it" do
    owner = user_fixture()
    other = user_fixture()

    shared_legacy =
      "receipts/legacy_shared_#{System.unique_integer([:positive])}.pdf"

    {:ok, owner_draft} =
      ExpenseReports.save_draft(owner, %{
        "purpose" => "Owner first",
        "expense_items" => %{
          "0" => %{
            "date" => Date.to_iso8601(~D[2026-01-15]),
            "expense_type" => "purchase",
            "vendor" => "Store",
            "description" => "Mine",
            "amount" => "10.00",
            "receipt_s3_path" => shared_legacy
          }
        }
      })

    other_report =
      Repo.insert!(%ExpenseReport{
        user_id: other.id,
        status: "draft",
        purpose: "Historical duplicate",
        reimbursement_method: "check"
      })

    Repo.insert!(%ExpenseReportItem{
      expense_report_id: other_report.id,
      date: ~D[2026-01-15],
      vendor: "Other store",
      description: "Duplicate key",
      amount: Money.new(:USD, 5),
      receipt_s3_path: shared_legacy
    })

    assert {:ok, updated} =
             ExpenseReports.save_draft(
               owner,
               %{
                 "purpose" => "Owner still editing",
                 "expense_items" => %{
                   "0" => %{
                     "date" => Date.to_iso8601(~D[2026-01-15]),
                     "expense_type" => "purchase",
                     "vendor" => "Store",
                     "description" => "Mine",
                     "amount" => "12.00",
                     "receipt_s3_path" => shared_legacy
                   }
                 }
               },
               owner_draft.id
             )

    assert updated.id == owner_draft.id
    assert updated.purpose == "Owner still editing"
    assert hd(updated.expense_items).receipt_s3_path == shared_legacy
  end

  test "save_draft re-saves a legacy proof already on this draft when another member also has it" do
    owner = user_fixture()
    other = user_fixture()

    shared_legacy =
      "proofs/legacy_shared_#{System.unique_integer([:positive])}.pdf"

    {:ok, owner_draft} =
      ExpenseReports.save_draft(owner, %{
        "purpose" => "Income first",
        "income_items" => %{
          "0" => %{
            "date" => Date.to_iso8601(~D[2026-01-15]),
            "description" => "Cash box",
            "amount" => "20.00",
            "proof_s3_path" => shared_legacy
          }
        }
      })

    other_report =
      Repo.insert!(%ExpenseReport{
        user_id: other.id,
        status: "draft",
        purpose: "Historical duplicate proof",
        reimbursement_method: "check"
      })

    Repo.insert!(%ExpenseReportIncomeItem{
      expense_report_id: other_report.id,
      date: ~D[2026-01-15],
      description: "Duplicate proof",
      amount: Money.new(:USD, 8),
      proof_s3_path: shared_legacy
    })

    assert {:ok, updated} =
             ExpenseReports.save_draft(
               owner,
               %{
                 "purpose" => "Income still editing",
                 "income_items" => %{
                   "0" => %{
                     "date" => Date.to_iso8601(~D[2026-01-15]),
                     "description" => "Cash box",
                     "amount" => "22.00",
                     "proof_s3_path" => shared_legacy
                   }
                 }
               },
               owner_draft.id
             )

    assert updated.id == owner_draft.id
    assert hd(updated.income_items).proof_s3_path == shared_legacy
  end
end
