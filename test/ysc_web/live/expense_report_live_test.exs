defmodule YscWeb.ExpenseReportLiveTest do
  @moduledoc """
  Tests for ExpenseReportLive.
  """
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  setup :register_and_log_in_user

  test "renders expense report form", %{conn: conn} do
    {:ok, _index_live, html} = live(conn, ~p"/expensereport")

    assert html =~ "Expense Report"
  end

  test "renders expense report list", %{conn: conn} do
    {:ok, _index_live, html} = live(conn, ~p"/expensereports")

    assert html =~ "Expense Report"
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
        pattern: expense_reports_pattern
      )

    assert query_count == 0
    assert html =~ "Expense Report Submitted!"
    assert html =~ "Loading expense report details"
    refute html =~ "Static render success page"
  end
end
