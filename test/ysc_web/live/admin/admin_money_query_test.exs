defmodule YscWeb.AdminMoneyQueryTest do
  @moduledoc """
  Query-count assertions for treasurer expense inbox and review loads.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.ExpenseReports
  alias Ysc.ExpenseReports.ExpenseReport
  alias Ysc.Repo

  describe "expense inbox queries" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "dead render does not query expense reports before connect", %{
      conn: conn
    } do
      member = user_fixture(%{first_name: "Dead", last_name: "Inbox"})

      Repo.insert!(%ExpenseReport{
        user_id: member.id,
        status: "submitted",
        purpose: "Dead render purpose XYZ",
        reimbursement_method: "bank_transfer"
      })

      reports_pattern = ~r/FROM "expense_reports"/i

      {html, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/admin/money")
            |> html_response(200)
          end,
          pattern: reports_pattern,
          caller_pids: [self()]
        )

      assert query_count == 0
      refute html =~ "Dead render purpose XYZ"
      refute html =~ "Dead Inbox"
      assert html =~ "Loading recent payments"
    end

    test "connected overview loads submitted inbox once after connect", %{
      conn: conn
    } do
      member =
        user_fixture(%{first_name: "Slim", last_name: "Submitter"})

      Repo.insert!(%ExpenseReport{
        user_id: member.id,
        status: "submitted",
        purpose: "Connected inbox purpose XYZ",
        reimbursement_method: "bank_transfer"
      })

      {{:ok, view, _html}, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} = live(conn, ~p"/admin/money")
            render(view)
            {:ok, view, html}
          end,
          pattern: ~r/FROM "expense_reports"/i
        )

      html = render(view)
      assert query_count == 1
      assert html =~ "Connected inbox purpose XYZ"
      assert html =~ "Slim Submitter"
    end
  end

  describe "expense review modal queries" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(conn, admin)}
    end

    test "opening review does not SELECT password hashes, event HTML, or encrypted bank numbers",
         %{conn: conn} do
      member = user_fixture(%{first_name: "Review", last_name: "Member"})

      event =
        event_fixture(%{
          title: "Review Event XYZ",
          raw_details: "<p>toast body that money review must not load</p>",
          rendered_details: "<p>toast body that money review must not load</p>"
        })

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          member
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => member.id,
            "event_id" => event.id,
            "status" => "draft",
            "purpose" => "Modal review purpose XYZ",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "REI",
                "description" => "Supplies",
                "amount" => "12.00",
                "receipt_s3_path" => "receipts/modal-review.pdf"
              }
            ]
          },
          member
        )

      {:ok, _} =
        ExpenseReports.update_expense_report(report, %{status: "submitted"})

      {:ok, view, _html} = live(conn, ~p"/admin/money")
      assert render(view) =~ "Modal review purpose XYZ"

      {_html, password_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            view
            |> element("#expense-inbox-review-#{report.id}")
            |> render_click()
          end,
          pattern: ~r/hashed_password/i
        )

      {_html, html_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            view
            |> element("#expense-inbox-review-#{report.id}")
            |> render_click()
          end,
          pattern: ~r/raw_details|rendered_details/i
        )

      {_html, encrypted_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            view
            |> element("#expense-inbox-review-#{report.id}")
            |> render_click()
          end,
          pattern: ~r/routing_number|account_number[^_]/i
        )

      html = render(view)
      assert password_cols == 0
      assert html_cols == 0
      assert encrypted_cols == 0
      assert html =~ "Modal review purpose XYZ"
      assert html =~ "Review Event XYZ"
      assert html =~ "account ending 7890"
    end
  end
end
