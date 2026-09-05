defmodule Ysc.ExpenseReports.DraftAuthorizationTest do
  @moduledoc """
  Guards for `save_draft/3` / `submit_draft/3` so autosave cannot mutate
  another member's draft or a already-submitted report.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.ExpenseReports
  alias Ysc.ExpenseReports.{ExpenseReport, ExpenseReportItem}
  alias Ysc.Repo

  test "save_draft/3 does not mutate another user's draft when their id is passed" do
    owner = user_fixture()
    attacker = user_fixture()

    {:ok, owner_draft} =
      ExpenseReports.save_draft(owner, %{
        "purpose" => "Secret retreat",
        "expense_items" => %{"0" => %{"vendor" => "OwnerVendor"}}
      })

    {:ok, attacker_draft} =
      ExpenseReports.save_draft(
        attacker,
        %{"purpose" => "Attacker purpose"},
        owner_draft.id
      )

    reloaded = Repo.get!(ExpenseReport, owner_draft.id)
    assert reloaded.user_id == owner.id
    assert reloaded.purpose == "Secret retreat"
    assert reloaded.status == "draft"

    assert [%{vendor: "OwnerVendor"}] =
             Repo.all(
               from i in ExpenseReportItem,
                 where: i.expense_report_id == ^owner_draft.id
             )

    assert attacker_draft.id != owner_draft.id
    assert attacker_draft.user_id == attacker.id
    assert attacker_draft.purpose == "Attacker purpose"
  end

  test "save_draft/3 does not convert a submitted report back into a draft" do
    user = user_fixture()

    submitted =
      Repo.insert!(%ExpenseReport{
        user_id: user.id,
        status: "submitted",
        purpose: "Already submitted",
        reimbursement_method: "check"
      })

    Repo.insert!(%ExpenseReportItem{
      expense_report_id: submitted.id,
      date: ~D[2026-01-15],
      vendor: "Delta",
      description: "Flight",
      amount: Money.new(:USD, 250)
    })

    {:ok, draft} =
      ExpenseReports.save_draft(
        user,
        %{
          "purpose" => "Hacked",
          "expense_items" => %{"0" => %{"vendor" => "Nope"}}
        },
        submitted.id
      )

    reloaded = Repo.get!(ExpenseReport, submitted.id)
    assert reloaded.status == "submitted"
    assert reloaded.purpose == "Already submitted"

    assert [%{vendor: "Delta"}] =
             Repo.all(
               from i in ExpenseReportItem,
                 where: i.expense_report_id == ^submitted.id
             )

    assert draft.id != submitted.id
    assert draft.status == "draft"
    assert draft.purpose == "Hacked"
  end

  test "submit_draft/3 rolls back when the draft belongs to another user" do
    owner = user_fixture()
    attacker = user_fixture()

    {:ok, bank_account} =
      ExpenseReports.create_bank_account(
        %{"routing_number" => "021000021", "account_number" => "1234567890"},
        attacker
      )

    {:ok, owner_draft} =
      ExpenseReports.save_draft(owner, %{"purpose" => "Owner draft"})

    attrs = %{
      "purpose" => "Stolen submit",
      "reimbursement_method" => "bank_transfer",
      "bank_account_id" => bank_account.id,
      "certification_accepted" => true,
      "status" => "submitted",
      "expense_items" => %{
        "0" => %{
          "date" => "2026-01-15",
          "vendor" => "Delta",
          "description" => "Flight",
          "amount" => "250.00",
          "receipt_s3_path" => "receipts/u/x.pdf"
        }
      }
    }

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:error, %Ecto.Changeset{} = changeset} =
               ExpenseReports.submit_draft(owner_draft.id, attrs, attacker)

      assert changeset.errors[:base]
    end)

    assert Repo.get!(ExpenseReport, owner_draft.id).purpose == "Owner draft"

    submitted =
      Repo.all(
        from r in ExpenseReport,
          where: r.user_id == ^attacker.id and r.status == "submitted"
      )

    assert submitted == []
  end
end
