defmodule YscWeb.Emails.ExpenseReportRejected do
  @moduledoc """
  Email template notifying a member that their expense report was rejected.

  Includes the treasurer's note explaining what needs to change and a link to
  start a corrected expense report.
  """
  use MjmlEEx,
    mjml_template: "templates/expense_report_rejected.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      absolute_url: 1,
      member_greeting_name: 1
    ]

  alias Ysc.Repo
  alias Ysc.ExpenseReports.ExpenseReport

  def get_template_name() do
    "expense_report_rejected"
  end

  def get_subject() do
    "Your expense report needs changes before it can be reimbursed"
  end

  @doc """
  Prepares the rejection email data.

  ## Parameters
  - `expense_report`: the rejected report; `:user` is preloaded if needed.

  ## Returns
  - Map with the greeting name, report summary, rejection note, and the URL to
    submit a new expense report.
  """
  def prepare_email_data(%ExpenseReport{} = expense_report) do
    expense_report = ensure_user_loaded(expense_report)

    %{
      first_name: member_greeting_name(expense_report.user),
      expense_report: %{
        id: expense_report.id,
        purpose: presence(expense_report.purpose) || "N/A"
      },
      rejection_note:
        presence(expense_report.rejection_note) || "No note was provided.",
      new_expense_report_url: absolute_url("/expensereport")
    }
  end

  defp ensure_user_loaded(%ExpenseReport{} = expense_report) do
    if Ecto.assoc_loaded?(expense_report.user) do
      expense_report
    else
      Repo.preload(expense_report, [:user])
    end
  end

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_value), do: nil
end
