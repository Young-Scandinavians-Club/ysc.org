defmodule YscWeb.Emails.ExpenseReportHelpersTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.ExpenseReports
  alias Ysc.ExpenseReports.{ExpenseReport, ExpenseReportItem}
  alias Ysc.Repo
  alias YscWeb.Emails.ExpenseReportHelpers

  describe "reimbursement_method_label/1" do
    test "maps known methods and capitalizes unknown binaries" do
      assert ExpenseReportHelpers.reimbursement_method_label("bank_transfer") ==
               "Bank Transfer"

      assert ExpenseReportHelpers.reimbursement_method_label("check") == "Check"

      assert ExpenseReportHelpers.reimbursement_method_label("venmo") ==
               "Venmo"

      assert ExpenseReportHelpers.reimbursement_method_label("custom_method") ==
               "Custom_method"
    end

    test "returns Not specified for nil and non-strings" do
      assert ExpenseReportHelpers.reimbursement_method_label(nil) ==
               "Not specified"

      assert ExpenseReportHelpers.reimbursement_method_label(:check) ==
               "Not specified"
    end
  end

  describe "present_or/2" do
    test "returns trimmed binaries and the fallback for blank values" do
      assert ExpenseReportHelpers.present_or("  Paint  ", "N/A") == "Paint"
      assert ExpenseReportHelpers.present_or("", "N/A") == "N/A"
      assert ExpenseReportHelpers.present_or("   ", "N/A") == "N/A"

      assert ExpenseReportHelpers.present_or(nil, "Not specified") ==
               "Not specified"
    end
  end

  describe "user_info/1" do
    test "joins first and last name and trims missing parts" do
      assert ExpenseReportHelpers.user_info(%{
               first_name: "Ada",
               last_name: "Lovelace",
               email: "ada@example.com"
             }) == %{name: "Ada Lovelace", email: "ada@example.com"}

      assert ExpenseReportHelpers.user_info(%{
               first_name: nil,
               last_name: "TreasurerCase",
               email: "board@example.com"
             }) == %{name: "TreasurerCase", email: "board@example.com"}
    end
  end

  describe "member_url/1 and admin_url/1" do
    test "build absolute paths from the endpoint origin" do
      origin = YscWeb.Endpoint.url()
      id = "exp-id-123"

      assert ExpenseReportHelpers.member_url(id) ==
               origin <> "/expensereport/#{id}/success"

      assert ExpenseReportHelpers.admin_url(id) ==
               origin <> "/admin/expense_reports/#{id}"
    end
  end

  describe "load!/1" do
    test "raises for nil and missing id" do
      assert_raise ArgumentError, "Expense report cannot be nil", fn ->
        Ysc.Test.Invoke.call(ExpenseReportHelpers, :load!, [nil])
      end

      assert_raise ArgumentError, fn ->
        Ysc.Test.Invoke.call(ExpenseReportHelpers, :load!, [
          %ExpenseReport{id: nil, user_id: Ecto.ULID.generate()}
        ])
      end
    end
  end

  describe "email_payload/2" do
    setup do
      user = user_fixture()

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "1234567890"
          },
          user
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "status" => "draft",
            "purpose" => "Conference travel",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      %ExpenseReportItem{}
      |> ExpenseReportItem.changeset(%{
        expense_report_id: report.id,
        date: Date.utc_today(),
        expense_type: "mileage",
        description: "Board meeting",
        mileage_from_to: "Home to YSC Cabin",
        miles_driven: 20
      })
      |> Repo.insert!()

      report =
        Repo.get!(ExpenseReport, report.id)
        |> Repo.preload([
          :user,
          :expense_items,
          :income_items,
          :event,
          :bank_account,
          :address
        ])

      %{user: user, report: report}
    end

    test "builds shared fields and preserves member vs treasurer fallbacks", %{
      report: report
    } do
      {loaded, member_fields} =
        ExpenseReportHelpers.email_payload(report,
          missing: "Not specified",
          bank_missing: "Not on file"
        )

      {_loaded, treasurer_fields} =
        ExpenseReportHelpers.email_payload(report,
          missing: "N/A",
          include_address: true
        )

      assert loaded.id == report.id
      refute Map.has_key?(member_fields, :address)
      assert treasurer_fields.address == nil
      assert member_fields.purpose == "Conference travel"
      assert member_fields.reimbursement_method == "Bank Transfer"
      assert member_fields.bank_account.last_4 == "7890"
      assert treasurer_fields.purpose == "Conference travel"

      [row] = member_fields.expense_items
      assert row.vendor == "Mileage"
      assert row.mileage == true
      assert row.mileage_info == "Home to YSC Cabin — 20 mi"
      assert row.has_receipt == false
    end

    test "uses missing fallbacks for blank purpose and vendor", %{
      report: report
    } do
      report
      |> Ecto.Changeset.change(%{purpose: nil})
      |> Repo.update!()

      %ExpenseReportItem{}
      |> ExpenseReportItem.draft_changeset(%{
        expense_report_id: report.id,
        date: Date.utc_today(),
        expense_type: "purchase",
        amount: Money.new(:USD, "10.00")
      })
      |> Repo.insert!()

      report =
        Repo.get!(ExpenseReport, report.id)
        |> Repo.preload([
          :user,
          :expense_items,
          :income_items,
          :event,
          :bank_account,
          :address
        ])

      {_loaded, fields} =
        ExpenseReportHelpers.email_payload(report, missing: "Not specified")

      purchase =
        Enum.find(fields.expense_items, &(&1.mileage == false))

      assert fields.purpose == "Not specified"
      assert purchase.vendor == "Not specified"
      assert purchase.description == "Not specified"
    end

    test "reloads associations from a bare struct", %{report: report} do
      bare = Repo.get!(ExpenseReport, report.id)
      refute Ecto.assoc_loaded?(bare.user)

      {loaded, fields} = ExpenseReportHelpers.email_payload(bare)

      assert loaded.user.id == report.user_id
      assert fields.purpose == "Conference travel"
      assert is_binary(fields.submitted_date)
    end
  end
end
