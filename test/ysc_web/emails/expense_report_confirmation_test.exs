defmodule YscWeb.Emails.ExpenseReportConfirmationTest do
  @moduledoc """
  Tests for ExpenseReportConfirmation email module.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.ExpenseReports
  alias Ysc.ExpenseReports.{ExpenseReport, ExpenseReportItem}
  alias Ysc.Repo
  alias YscWeb.Emails.ExpenseReportConfirmation

  describe "get_template_name/0" do
    test "returns correct template name" do
      assert ExpenseReportConfirmation.get_template_name() ==
               "expense_report_confirmation"
    end
  end

  describe "get_subject/0" do
    test "returns correct subject" do
      assert ExpenseReportConfirmation.get_subject() ==
               "Expense Report Submitted - Confirmation"
    end
  end

  describe "prepare_email_data/1" do
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

      full = ExpenseReports.get_expense_report!(report.id, user)
      bare = Repo.get(ExpenseReport, report.id)

      %{user: user, report: full, bare_report: bare}
    end

    test "builds data from a fully loaded expense report", %{
      report: report,
      user: user
    } do
      data = ExpenseReportConfirmation.prepare_email_data(report)

      assert data.first_name == (user.first_name || "Valued Member")
      assert data.expense_report.purpose == "Conference travel"
      assert data.expense_report.reimbursement_method == "Bank Transfer"
      assert data.expense_report.bank_account.last_4 == "7890"
      assert data.expense_report_url =~ to_string(report.id)
    end

    test "reloads associations when given a bare struct", %{bare_report: bare} do
      refute Ecto.assoc_loaded?(bare.user)

      data = ExpenseReportConfirmation.prepare_email_data(bare)

      assert data.expense_report.purpose == "Conference travel"
      assert is_binary(data.expense_report.submitted_date)
    end
  end

  describe "mileage expense items" do
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
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Mileage render test",
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

      %{report: report}
    end

    test "shows the route and miles, and does not warn about a missing receipt",
         %{report: report} do
      data = ExpenseReportConfirmation.prepare_email_data(report)

      [row] = data.expense_report.expense_items
      assert row.vendor == "Mileage"
      assert row.mileage == true
      assert row.mileage_info == "Home to YSC Cabin — 20 mi"
      assert row.has_receipt == false

      html = ExpenseReportConfirmation.render(data)
      assert html =~ "Home to YSC Cabin — 20 mi"
      assert html =~ "Mileage — no receipt required"
      assert html =~ "Amount we will reimburse"
      refute html =~ "Net Total"
      refute html =~ "No receipt attached"
    end
  end
end
