defmodule YscWeb.UpControllerTest do
  use YscWeb.ConnCase, async: true

  describe "index/2" do
    test "returns 200 OK", %{conn: conn} do
      conn = get(conn, ~p"/up")
      assert response(conn, 200)
    end
  end

  describe "databases/2" do
    test "returns 200 OK and queries database", %{conn: conn} do
      conn = get(conn, ~p"/up/dbs")
      assert response(conn, 200)
    end
  end
end
