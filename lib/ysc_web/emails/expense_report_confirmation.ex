defmodule YscWeb.Emails.ExpenseReportConfirmation do
  @moduledoc """
  Email template for expense report submission confirmation.

  Sends a confirmation email to users after they submit an expense report.
  """
  use MjmlEEx,
    mjml_template: "templates/expense_report_confirmation.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [member_greeting_name: 1]

  alias YscWeb.Emails.ExpenseReportHelpers

  def get_template_name() do
    "expense_report_confirmation"
  end

  def get_subject() do
    "We received your expense report"
  end

  @doc """
  Prepares expense report confirmation email data.

  ## Parameters:
  - `expense_report`: The submitted expense report with preloaded associations

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(expense_report) do
    {report, fields} =
      ExpenseReportHelpers.email_payload(expense_report,
        missing: "Not specified",
        bank_missing: "Not on file"
      )

    %{
      first_name: member_greeting_name(report.user),
      expense_report: fields,
      expense_report_url: ExpenseReportHelpers.member_url(report.id)
    }
  end
end
