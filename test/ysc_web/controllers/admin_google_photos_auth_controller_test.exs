defmodule YscWeb.AdminGooglePhotosAuthControllerTest do
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures

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
