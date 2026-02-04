defmodule YscWeb.ExpenseReportFileControllerTest do
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

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
  end
end
