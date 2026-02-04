defmodule YscWeb.Emails.ExpenseReportConfirmationTest do
  @moduledoc """
  Tests for ExpenseReportConfirmation email module.
  """
  use Ysc.DataCase, async: true

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
end
