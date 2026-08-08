defmodule YscWeb.ExpenseReportDeferredTest do
  @moduledoc """
  Query-count assertions for expense report success page deferred loading.

  Runs with `async: false` so global Ecto telemetry handlers are not polluted
  by parallel LiveView tests in the main suite module.
  """
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  test "dead render skips success page queries and shows loading state", %{
    conn: conn,
    user: user
  } do
    report =
      %Ysc.ExpenseReports.ExpenseReport{
        user_id: user.id,
        purpose: "Static render success page",
        status: "submitted",
        reimbursement_method: "check"
      }
      |> Ysc.Repo.insert!()

    expense_reports_pattern = ~r/FROM "expense_reports"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get(~p"/expensereport/#{report.id}/success")
          |> html_response(200)
        end,
        pattern: expense_reports_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ "Expense Report Submitted!"
    assert html =~ "Loading expense report details"
    refute html =~ "Static render success page"
  end
end
