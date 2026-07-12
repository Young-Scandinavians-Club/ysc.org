defmodule YscWeb.Plugs.TrailingSlashRedirectTest do
  use YscWeb.ConnCase, async: true

  alias YscWeb.Plugs.TrailingSlashRedirect

  describe "call/2" do
    test "redirects GET requests with a trailing slash using 301" do
      conn =
        :get
        |> Plug.Test.conn("/example/123/")
        |> TrailingSlashRedirect.call([])

      assert conn.halted
      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["/example/123"]
    end

    test "redirects HEAD requests with a trailing slash using 301" do
      conn =
        :head
        |> Plug.Test.conn("/history/")
        |> TrailingSlashRedirect.call([])

      assert conn.halted
      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["/history"]
    end

    test "redirects non-GET methods with a trailing slash using 308" do
      for method <- [:post, :put, :patch, :delete] do
        conn =
          method
          |> Plug.Test.conn("/api/v1/mobile/check-in/")
          |> TrailingSlashRedirect.call([])

        assert conn.halted
        assert conn.status == 308
        assert get_resp_header(conn, "location") == ["/api/v1/mobile/check-in"]
      end
    end

    test "preserves the query string on redirect" do
      conn =
        :get
        |> Plug.Test.conn("/events/42/?page=2&sort=asc")
        |> TrailingSlashRedirect.call([])

      assert conn.halted
      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["/events/42?page=2&sort=asc"]
    end

    test "collapses multiple trailing slashes" do
      conn =
        :get
        |> Plug.Test.conn("/board///")
        |> TrailingSlashRedirect.call([])

      assert conn.halted
      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["/board"]
    end

    test "does not redirect the root path" do
      conn =
        :get
        |> Plug.Test.conn("/")
        |> TrailingSlashRedirect.call([])

      refute conn.halted
      assert conn.status == nil
      assert get_resp_header(conn, "location") == []
    end

    test "does not redirect paths without a trailing slash" do
      conn =
        :get
        |> Plug.Test.conn("/privacy-policy")
        |> TrailingSlashRedirect.call([])

      refute conn.halted
      assert conn.status == nil
      assert get_resp_header(conn, "location") == []
    end
  end

  describe "endpoint integration" do
    test "redirects trailing-slash browser paths through the endpoint", %{
      conn: conn
    } do
      conn = get(conn, "/history/")

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/history"
    end

    test "serves the non-slash path without redirecting", %{conn: conn} do
      conn = get(conn, "/history")

      assert conn.status == 200
      refute conn.status == 301
    end

    test "preserves query string through the endpoint redirect", %{conn: conn} do
      conn = get(conn, "/history/?utm_source=test")

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/history?utm_source=test"
    end
  end
end
