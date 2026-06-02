defmodule YscWeb.AdminGooglePhotosAuthControllerTest do
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures

  setup {Req.Test, :set_req_test_from_context}

  setup %{conn: conn} do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  describe "GET /admin/integrations/google-photos/connect" do
    test "redirects to Google when configured", %{conn: conn} do
      conn = get(conn, ~p"/admin/integrations/google-photos/connect")

      assert redirected_to(conn, 302) =~ "accounts.google.com/o/oauth2"
      assert get_session(conn, :google_photos_oauth_state)
    end
  end

  describe "GET /admin/integrations/google-photos/callback" do
    test "rejects invalid state", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{google_photos_oauth_state: "expected"})
        |> get(
          ~p"/admin/integrations/google-photos/callback?code=abc&state=wrong"
        )

      assert redirected_to(conn) == ~p"/admin/settings"
    end

    test "rejects missing code", %{conn: conn} do
      state = "valid-state"

      conn =
        conn
        |> init_test_session(%{google_photos_oauth_state: state})
        |> get(~p"/admin/integrations/google-photos/callback?state=#{state}")

      assert redirected_to(conn) == ~p"/admin/settings"
    end

    test "handles provider error", %{conn: conn} do
      conn =
        get(
          conn,
          ~p"/admin/integrations/google-photos/callback?error=access_denied"
        )

      assert redirected_to(conn) == ~p"/admin/settings"
    end

    test "connects when code exchange and API checks succeed", %{conn: conn} do
      import Ysc.GooglePhotos.OAuth.ReqTestHelper

      alias Ysc.GooglePhotos
      alias Ysc.GooglePhotos.OAuth

      stub = stub()

      Req.Test.stub(stub, fn conn ->
        cond do
          token_url?(conn) ->
            ok_token_response(conn,
              access_token: "callback-access",
              refresh_token: "callback-refresh",
              expires_in: 3600,
              scope: OAuth.scope_string()
            )

          userinfo_url?(conn) ->
            ok_userinfo(conn, "org-photos@example.com")

          albums_url?(conn) ->
            ok_albums(conn)

          true ->
            Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      state = "callback-state"

      conn =
        conn
        |> init_test_session(%{google_photos_oauth_state: state})
        |> get(
          ~p"/admin/integrations/google-photos/callback?code=auth-code&state=#{state}"
        )

      assert redirected_to(conn) == ~p"/admin/settings"

      assert %{connected: true, account_email: "org-photos@example.com"} =
               GooglePhotos.connection_status()

      assert GooglePhotos.get_connection().refresh_token == "callback-refresh"
    end

    test "rejects callback when granted scopes are incomplete", %{conn: conn} do
      import Ysc.GooglePhotos.OAuth.ReqTestHelper

      alias Ysc.GooglePhotos
      alias Ysc.GooglePhotos.OAuth

      stub = stub()

      Req.Test.stub(stub, fn conn ->
        if token_url?(conn) do
          ok_token_response(conn,
            access_token: "callback-access",
            refresh_token: "callback-refresh",
            expires_in: 3600,
            scope: "https://www.googleapis.com/auth/userinfo.email"
          )
        else
          Plug.Conn.send_resp(conn, 404, "unexpected")
        end
      end)

      state = "callback-state"

      conn =
        conn
        |> init_test_session(%{google_photos_oauth_state: state})
        |> get(
          ~p"/admin/integrations/google-photos/callback?code=auth-code&state=#{state}"
        )

      assert redirected_to(conn) == ~p"/admin/settings"
      refute GooglePhotos.get_connection()
    end
  end

  describe "DELETE /admin/integrations/google-photos" do
    test "disconnects and redirects to settings", %{conn: conn} do
      user = user_fixture()

      Ysc.GooglePhotos.connect!(
        %{
          access_token: "access",
          refresh_token: "refresh",
          expires_in: 3600
        },
        user.id,
        "photos@example.com"
      )

      conn = delete(conn, ~p"/admin/integrations/google-photos")

      assert redirected_to(conn) == ~p"/admin/settings"
      assert Ysc.GooglePhotos.get_connection() == nil
    end
  end
end
