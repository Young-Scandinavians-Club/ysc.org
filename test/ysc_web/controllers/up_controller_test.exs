defmodule YscWeb.UpControllerTest do
  use YscWeb.ConnCase, async: false

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

    test "is rate limited per IP", %{conn: conn} do
      Application.put_env(:ysc, Ysc.HealthCheckRateLimit, ip_limit: 1)
      on_exit(fn -> Application.delete_env(:ysc, Ysc.HealthCheckRateLimit) end)

      conn = %{conn | remote_ip: {127, 0, 0, 212}}

      assert conn |> get(~p"/up/dbs") |> response(200)
      limited = get(conn, ~p"/up/dbs")
      assert response(limited, 429)
      assert [_] = get_resp_header(limited, "retry-after")
    end
  end
end
