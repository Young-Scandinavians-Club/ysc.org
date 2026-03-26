defmodule YscWeb.Emails.ExpenseReportTreasurerNotificationTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.{ExpenseReports, Repo}
  alias Ysc.ExpenseReports.{ExpenseReport, ExpenseReportItem}
  alias Ysc.Events
  alias YscWeb.Emails.ExpenseReportTreasurerNotification

  describe "get_template_name/0 and get_subject/0" do
    test "returns static identifiers" do
      assert ExpenseReportTreasurerNotification.get_template_name() ==
               "expense_report_treasurer_notification"

      assert ExpenseReportTreasurerNotification.get_subject() =~
               "Expense Report"
    end
  end

  describe "prepare_email_data/1 and render/1" do
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
            "purpose" => "Treasurer render test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      {:ok, ev} =
        Events.create_event(%{
          title: "Linked Event",
          description: "X",
          state: :published,
          organizer_id: user.id,
          start_date:
            DateTime.utc_now()
            |> DateTime.add(1, :day)
            |> DateTime.truncate(:second),
          max_attendees: 50,
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      report =
        report
        |> Ecto.Changeset.change(%{event_id: ev.id})
        |> Repo.update!()

      %ExpenseReportItem{}
      |> ExpenseReportItem.changeset(%{
        expense_report_id: report.id,
        date: Date.utc_today(),
        vendor: "Vendor",
        description: "Line",
        amount: Money.new(0, :USD),
        receipt_s3_path: nil
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

    test "includes linked event info, bank account, and renders HTML", %{
      report: report
    } do
      data = ExpenseReportTreasurerNotification.prepare_email_data(report)

      assert data.expense_report.event.title == "Linked Event"
      assert data.expense_report.event.reference_id
      assert data.expense_report.bank_account.last_4 == "7890"

      [row] = data.expense_report.expense_items
      assert row.amount == "$0.00"
      assert row.has_receipt == false

      html = ExpenseReportTreasurerNotification.render(data)
      assert is_binary(html)
      assert html =~ "Expense" or html =~ "Treasurer" or html =~ "report"
    end
  end
end
