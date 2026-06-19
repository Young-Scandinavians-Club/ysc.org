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
end
