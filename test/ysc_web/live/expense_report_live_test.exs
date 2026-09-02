defmodule YscWeb.ExpenseReportLiveTest do
  @moduledoc """
  Tests for ExpenseReportLive.
  """
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  setup :register_and_log_in_user

  test "renders expense report form", %{conn: conn} do
    {:ok, _index_live, html} = live(conn, ~p"/expensereport")

    assert html =~ "Expense Report"
    assert html =~ "Amount we will reimburse"
    refute html =~ "Net Total"
  end

  test "mileage items use trip-purpose copy instead of business jargon", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, ~p"/expensereport")

    assert has_element?(view, "#expense-report-form")
    refute html =~ "Business Purpose"

    html =
      view
      |> form("#expense-report-form", %{
        "expense_report" => %{
          "expense_items" => %{"0" => %{"expense_type" => "mileage"}}
        }
      })
      |> render_change()

    assert has_element?(view, "#mileage-help-0")
    assert html =~ "Purpose of trip"
    assert html =~ "Route (from / to)"
    assert html =~ "Amount we will reimburse"
    assert html =~ "why you made the trip"
    refute html =~ "Business Purpose"
    refute html =~ "business purpose"
  end

  test "purchase items without a receipt leave the receipts checklist pending",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/expensereport")

    assert has_element?(
             view,
             "span.text-zinc-600",
             "All expense items have receipts"
           )

    refute has_element?(
             view,
             "span.line-through",
             "All expense items have receipts"
           )
  end

  test "mileage items compute reimbursement live and do not require a receipt",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/expensereport")

    view
    |> form("#expense-report-form", %{
      "expense_report" => %{
        "expense_items" => %{"0" => %{"expense_type" => "mileage"}}
      }
    })
    |> render_change()

    html =
      view
      |> form("#expense-report-form", %{
        "expense_report" => %{
          "expense_items" => %{
            "0" => %{
              "expense_type" => "mileage",
              "date" => Date.to_iso8601(Date.utc_today()),
              "description" => "Board meeting",
              "mileage_from_to" => "Home to YSC Cabin",
              "miles_driven" => "20"
            }
          }
        }
      })
      |> render_change()

    assert html =~ "20 mi ×"
    assert html =~ "$6.00"

    assert has_element?(
             view,
             "span.line-through",
             "All expense items have receipts"
           )
  end

  test "renders expense report list", %{conn: conn} do
    {:ok, _index_live, html} = live(conn, ~p"/expensereports")

    assert html =~ "Expense Report"
  end
end
