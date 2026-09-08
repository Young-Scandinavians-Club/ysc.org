defmodule YscWeb.ExpenseReportFileControllerTest do
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.ExpenseReports
  alias Ysc.Repo

  setup %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    %{conn: conn, user: user}
  end

  describe "show/2" do
    test "returns 403 or redirects to login when user is not authenticated", %{
      conn: _conn
    } do
      # Create an encoded path
      s3_path = "test/receipt.jpg"
      encoded_path = Base.url_encode64(s3_path, padding: false)

      conn = build_conn()
      conn = get(conn, ~p"/expensereport/files/#{encoded_path}")

      # May redirect to login (302) or return 403
      status = conn.status
      assert status == 302 || status == 403
    end

    test "returns 400 for invalid base64 encoded path", %{conn: conn} do
      invalid_path = "invalid-base64!!!"

      conn = get(conn, ~p"/expensereport/files/#{invalid_path}")

      assert response(conn, 400) || response(conn, 404)
    end

    test "returns 404 for file not found in expense reports", %{
      conn: conn,
      user: _user
    } do
      # Create a valid encoded path that doesn't exist in any expense report
      s3_path = "nonexistent/receipt.jpg"
      encoded_path = Base.url_encode64(s3_path, padding: false)

      conn = get(conn, ~p"/expensereport/files/#{encoded_path}")

      assert response(conn, 404)
    end

    test "returns 403 when another user tries to access an owned receipt", %{
      conn: conn
    } do
      owner = user_fixture()
      other = user_fixture()

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          owner
        )

      receipt_path =
        "receipts/ctrl_forbidden_#{System.unique_integer([:positive])}.pdf"

      {:ok, _report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => owner.id,
            "status" => "draft",
            "purpose" => "Test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "V",
                "description" => "D",
                "amount" => "10.00",
                "receipt_s3_path" => receipt_path
              }
            ]
          },
          owner
        )

      encoded_path = Base.url_encode64(receipt_path, padding: false)

      conn =
        conn
        |> log_in_user(other)
        |> get(~p"/expensereport/files/#{encoded_path}")

      assert response(conn, 403)
    end

    test "redirects to presigned URL when user can access the file", %{
      conn: conn,
      user: user
    } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      receipt_path =
        "receipts/ctrl_ok_#{System.unique_integer([:positive])}.pdf"

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "V",
                "description" => "D",
                "amount" => "10.00",
                "receipt_s3_path" => receipt_path
              }
            ]
          },
          user
        )

      report = Repo.preload(report, :expense_items)
      item = hd(report.expense_items)

      if is_nil(item.receipt_s3_path) do
        item
        |> Ecto.Changeset.change(%{receipt_s3_path: receipt_path})
        |> Repo.update!()
      end

      encoded_path = Base.url_encode64(receipt_path, padding: false)

      conn = get(conn, ~p"/expensereport/files/#{encoded_path}")

      assert conn.status == 302
      [location | _] = get_resp_header(conn, "location")
      assert String.starts_with?(location, "http")
    end

    test "redirects when request path includes bucket prefix (normalized for presign)",
         %{
           conn: conn,
           user: user
         } do
      bucket =
        Application.get_env(:ysc, :expense_reports_s3_bucket, "expense-reports")

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      key_only = "receipts/prefixed_#{System.unique_integer([:positive])}.pdf"

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "V",
                "description" => "D",
                "amount" => "10.00",
                "receipt_s3_path" => key_only
              }
            ]
          },
          user
        )

      report = Repo.preload(report, :expense_items)
      item = hd(report.expense_items)

      if is_nil(item.receipt_s3_path) do
        item
        |> Ecto.Changeset.change(%{receipt_s3_path: key_only})
        |> Repo.update!()
      end

      encoded_path = Base.url_encode64("#{bucket}/#{key_only}", padding: false)
      conn = get(conn, ~p"/expensereport/files/#{encoded_path}")

      assert conn.status == 302
    end
  end

  describe "preview/2" do
    setup do
      prev = Application.get_env(:ysc, :expense_reports_file_fetcher)

      on_exit(fn ->
        if prev do
          Application.put_env(:ysc, :expense_reports_file_fetcher, prev)
        else
          Application.delete_env(:ysc, :expense_reports_file_fetcher)
        end
      end)

      Application.put_env(:ysc, :expense_reports_file_fetcher, fn _path ->
        {:ok, "%PDF-1.4 test"}
      end)

      :ok
    end

    test "returns 403 or redirects to login when user is not authenticated" do
      encoded_path = Base.url_encode64("receipts/preview.pdf", padding: false)
      conn = get(build_conn(), ~p"/expensereport/files/#{encoded_path}/preview")
      status = conn.status
      assert status == 302 || status == 403
    end

    test "returns 403 when another user tries to preview an owned receipt", %{
      conn: conn
    } do
      owner = user_fixture()
      other = user_fixture()
      receipt_path = unique_receipt_path("pdf")
      _report = insert_report_with_receipt!(owner, receipt_path)
      encoded_path = Base.url_encode64(receipt_path, padding: false)

      conn =
        conn
        |> log_in_user(other)
        |> get(~p"/expensereport/files/#{encoded_path}/preview")

      assert response(conn, 403)
    end

    test "returns 200 inline PDF for the owner", %{conn: conn, user: user} do
      receipt_path = unique_receipt_path("pdf")
      _report = insert_report_with_receipt!(user, receipt_path)
      encoded_path = Base.url_encode64(receipt_path, padding: false)

      conn = get(conn, ~p"/expensereport/files/#{encoded_path}/preview")

      assert conn.status == 200
      assert conn.resp_body == "%PDF-1.4 test"
      assert get_resp_header(conn, "content-type") == ["application/pdf"]
      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "inline"
      assert disposition =~ Path.basename(receipt_path)
    end

    test "returns 200 inline PDF for an admin reviewing another user's file", %{
      conn: conn
    } do
      owner = user_fixture()
      admin = user_fixture(%{role: "admin"})
      receipt_path = unique_receipt_path("pdf")
      _report = insert_report_with_receipt!(owner, receipt_path)
      encoded_path = Base.url_encode64(receipt_path, padding: false)

      conn =
        conn
        |> log_in_user(admin)
        |> get(~p"/expensereport/files/#{encoded_path}/preview")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/pdf"]
      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "inline"
    end

    test "uses attachment disposition for unknown types", %{
      conn: conn,
      user: user
    } do
      Application.put_env(:ysc, :expense_reports_file_fetcher, fn _path ->
        {:ok, "not a known file"}
      end)

      receipt_path = unique_receipt_path("bin")
      _report = insert_report_with_receipt!(user, receipt_path)
      encoded_path = Base.url_encode64(receipt_path, padding: false)

      conn = get(conn, ~p"/expensereport/files/#{encoded_path}/preview")

      assert conn.status == 200
      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
    end
  end

  defp unique_receipt_path(ext) do
    "receipts/ctrl_preview_#{System.unique_integer([:positive])}.#{ext}"
  end

  defp insert_report_with_receipt!(user, receipt_path) do
    {:ok, bank_account} =
      ExpenseReports.create_bank_account(
        %{"routing_number" => "021000021", "account_number" => "1234567890"},
        user
      )

    {:ok, report} =
      ExpenseReports.create_expense_report(
        %{
          "user_id" => user.id,
          "status" => "draft",
          "purpose" => "Test",
          "reimbursement_method" => "bank_transfer",
          "bank_account_id" => bank_account.id,
          "expense_items" => [
            %{
              "date" => "2024-01-15",
              "vendor" => "V",
              "description" => "D",
              "amount" => "10.00",
              "receipt_s3_path" => receipt_path
            }
          ]
        },
        user
      )

    report = Repo.preload(report, :expense_items)
    item = hd(report.expense_items)

    if is_nil(item.receipt_s3_path) do
      item
      |> Ecto.Changeset.change(%{receipt_s3_path: receipt_path})
      |> Repo.update!()
    end

    report
  end
end
