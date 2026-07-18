defmodule YscWeb.Plugs.StoreOAuthRedirectTest do
  use YscWeb.ConnCase, async: true

  alias YscWeb.Plugs.StoreOAuthRedirect

  defp run_plug(params) do
    build_conn()
    |> init_test_session(%{})
    |> Map.put(:request_path, "/auth/google")
    |> Map.put(:params, params)
    |> StoreOAuthRedirect.call(StoreOAuthRedirect.init([]))
  end

  describe "call/2 - reauth mode" do
    test "stores reauth_mode and return_to when reauth=true with valid return_to" do
      conn =
        run_plug(%{
          "reauth" => "true",
          "return_to" => "/users/settings/security"
        })

      assert get_session(conn, :reauth_mode) == true
      assert get_session(conn, :reauth_return_to) == "/users/settings/security"
    end

    test "does not store reauth session when return_to is external URL" do
      conn =
        run_plug(%{
          "reauth" => "true",
          "return_to" => "https://evil.com"
        })

      assert get_session(conn, :reauth_mode) == nil
      assert get_session(conn, :reauth_return_to) == nil
    end

    test "defaults return_to to / when not provided in reauth mode" do
      conn = run_plug(%{"reauth" => "true"})

      assert get_session(conn, :reauth_mode) == true
      assert get_session(conn, :reauth_return_to) == "/"
    end
  end

  describe "call/2 - OAuth request phase" do
    test "stores valid internal redirect_to in session" do
      redirect_to = "/events"

      conn = run_plug(%{"redirect_to" => redirect_to})

      assert get_session(conn, :oauth_redirect_to) == redirect_to
    end

    test "does not store external redirect_to in session" do
      conn = run_plug(%{"redirect_to" => "https://evil.com/phishing"})

      assert get_session(conn, :oauth_redirect_to) == nil
    end

    test "does not store redirect_to with javascript protocol" do
      conn = run_plug(%{"redirect_to" => "javascript:alert('xss')"})

      assert get_session(conn, :oauth_redirect_to) == nil
    end

    test "handles request without redirect_to parameter" do
      conn = run_plug(%{})

      assert get_session(conn, :oauth_redirect_to) == nil
    end

    test "stores relative path redirect_to" do
      redirect_to = "/bookings/123"

      conn = run_plug(%{"redirect_to" => redirect_to})

      assert get_session(conn, :oauth_redirect_to) == redirect_to
    end

    test "does not store redirect_to with double slash (protocol-relative URL)" do
      conn = run_plug(%{"redirect_to" => "//evil.com/path"})

      assert get_session(conn, :oauth_redirect_to) == nil
    end

    test "no-ops on OAuth callback paths" do
      conn =
        build_conn()
        |> Map.put(:request_path, "/auth/google/callback")
        |> Map.put(:params, %{"redirect_to" => "/events"})
        |> init_test_session(%{})
        |> StoreOAuthRedirect.call(StoreOAuthRedirect.init([]))

      assert get_session(conn, :oauth_redirect_to) == nil
    end
  end

  describe "integration - router request phase" do
    test "stores redirect_to in session when initiating Google OAuth", %{
      conn: conn
    } do
      conn = get(conn, ~p"/auth/google?#{%{redirect_to: "/events/123"}}")

      assert get_session(conn, :oauth_redirect_to) == "/events/123"
      assert conn.halted
      assert get_resp_header(conn, "location") != []
    end

    test "stores redirect_to in session when initiating Facebook OAuth", %{
      conn: conn
    } do
      conn = get(conn, ~p"/auth/facebook?#{%{redirect_to: "/events/456"}}")

      assert get_session(conn, :oauth_redirect_to) == "/events/456"
      assert conn.halted
    end

    test "does not store external redirect_to when initiating Google OAuth", %{
      conn: conn
    } do
      conn =
        get(
          conn,
          ~p"/auth/google?#{%{redirect_to: "https://evil.com/phishing"}}"
        )

      assert get_session(conn, :oauth_redirect_to) == nil
      assert conn.halted
    end

    test "does not store redirect_to on OAuth callback", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> get(
          ~p"/auth/google/callback?#{%{code: "test-code", state: "test-state"}}"
        )

      assert get_session(conn, :oauth_redirect_to) == nil
    end
  end
end
