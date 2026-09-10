defmodule YscWeb.AdminMoneyQueryTest do
  @moduledoc """
  Query-count assertions for treasurer expense inbox, review, and payment loads.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Mox

  alias Ysc.ExpenseReports
  alias Ysc.ExpenseReports.ExpenseReport
  alias Ysc.Ledgers
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

  describe "overview payment queries" do
    setup %{conn: conn} do
      setup_qb_mocks()
      Ledgers.ensure_basic_accounts()
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(conn, admin)}
    end

    test "connected overview does not SELECT event HTML or payment methods",
         %{conn: conn} do
      member =
        user_fixture(%{first_name: "Slim", last_name: "Payer"})

      event =
        event_fixture(%{
          title: "Overview Event XYZ",
          raw_details: "<p>toast body that money overview must not load</p>",
          rendered_details:
            "<p>toast body that money overview must not load</p>"
        })

      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_event_payment_with_donations(%{
          user_id: member.id,
          total_amount: Money.new(10_000, :USD),
          event_amount: Money.new(10_000, :USD),
          donation_amount: Money.new(0, :USD),
          event_id: event.id,
          external_payment_id:
            "pi_overview_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Event tickets",
          payment_method_id: nil
        })

      {:ok, payment_method} =
        Ysc.Payments.insert_payment_method(%{
          user_id: member.id,
          provider: :stripe,
          provider_id: "pm_overview_#{System.unique_integer([:positive])}",
          provider_customer_id: "cus_overview",
          type: :card,
          provider_type: "card",
          last_four: "4242",
          display_brand: "visa",
          payload: %{"card" => %{"brand" => "visa"}}
        })

      payment
      |> Ecto.Changeset.change(%{payment_method_id: payment_method.id})
      |> Repo.update!()

      {{:ok, view, _html}, html_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} = live(conn, ~p"/admin/money")
            render(view)
            {:ok, view, html}
          end,
          pattern: ~r/raw_details|rendered_details/i
        )

      {{:ok, _view, _html}, method_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} = live(conn, ~p"/admin/money")
            render(view)
            {:ok, view, html}
          end,
          pattern: ~r/FROM "payment_methods"/i
        )

      html = render(view)
      assert html_cols == 0
      assert method_queries == 0
      assert html =~ "Slim Payer"
      assert html =~ "Overview Event XYZ"
    end
  end

  defp setup_qb_mocks do
    Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

    Application.put_env(:ysc, :quickbooks,
      client_id: "test_client_id",
      client_secret: "test_client_secret",
      company_id: "test_company_id",
      access_token: "test_access_token",
      refresh_token: "test_refresh_token",
      event_item_id: "event_item_123",
      donation_item_id: "donation_item_123",
      bank_account_id: "bank_account_123",
      stripe_account_id: "stripe_account_123"
    )

    stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params, _opts ->
      {:ok, %{"Id" => "qb_deposit_test", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
      {:ok, %{"Id" => "qb_customer_test"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params, _opts ->
      {:ok, %{"Id" => "qb_sr_test", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _name ->
      {:ok, "revenue_account_test"}
    end)

    stub(Ysc.Quickbooks.ClientMock, :get_or_create_item, fn _name, _opts ->
      {:ok, "qb_item_test"}
    end)

    stub(Ysc.Quickbooks.ClientMock, :get_item_by_id, fn _id ->
      {:ok,
       %{
         "Id" => "qb_item_test",
         "IncomeAccountRef" => %{"value" => "revenue_account_test"}
       }}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_refund_receipt, fn _params, _opts ->
      {:ok, %{"Id" => "qb_rr_test", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :query_class_by_name, fn _name ->
      {:ok, "qb_class_test"}
    end)

    :ok
  end
end
