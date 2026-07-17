defmodule YscWeb.LegacyRedirectControllerTest do
  use YscWeb.ConnCase, async: true

  describe "GET /register" do
    test "redirects to /users/register with 301", %{conn: conn} do
      conn = get(conn, ~p"/register")

      assert conn.status == 301
      assert redirected_to(conn, 301) == ~p"/users/register"
    end

    test "preserves query string on redirect", %{conn: conn} do
      conn = get(conn, ~p"/register?invite=abc123")

      assert conn.status == 301
      assert redirected_to(conn, 301) == ~p"/users/register?invite=abc123"
    end
  end
end
