defmodule YscWeb.Emails.ExpenseReportTreasurerNotification do
  @moduledoc """
  Email template for expense report submission notification to Treasurer.

  Sends an internal notification email to the Treasurer when a new expense report is submitted.
  """
  use MjmlEEx,
    mjml_template: "templates/expense_report_treasurer_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias YscWeb.Emails.ExpenseReportHelpers

  def get_template_name() do
    "expense_report_treasurer_notification"
  end

  def get_subject() do
    "New Expense Report Submitted - Action Required"
  end

  @doc """
  Prepares expense report treasurer notification email data.

  ## Parameters:
  - `expense_report`: The submitted expense report with preloaded associations

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(expense_report) do
    {report, fields} =
      ExpenseReportHelpers.email_payload(expense_report,
        missing: "N/A",
        include_address: true
      )

    %{
      expense_report: fields,
      user: ExpenseReportHelpers.user_info(report.user),
      expense_report_url: ExpenseReportHelpers.member_url(report.id),
      admin_url: ExpenseReportHelpers.admin_url(report.id)
    }
  end
end
