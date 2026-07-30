defmodule QueryConsoleWeb.AuthControllerTest do
  use QueryConsoleWeb.ConnCase, async: true

  test "GET /auth/ysc redirects to authorize URL", %{conn: conn} do
    conn = get(conn, ~p"/auth/ysc")
    assert redirected_to(conn, 302) =~ "oauth/authorize"
    assert get_session(conn, :oauth_state)
    assert get_session(conn, :oauth_code_verifier)
  end

  test "GET /auth/logout clears session and redirects to YSC logout", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user) |> get(~p"/auth/logout")

    location = redirected_to(conn, 302)
    assert location =~ "oauth/logout"
    assert location =~ "client_id="
    assert location =~ "post_logout_redirect_uri="
    assert location =~ URI.encode_www_form("http://localhost:4001/auth/signed-out")
    refute get_session(conn, :user_id)
  end

  test "DELETE /auth/logout also clears session and redirects to YSC logout", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user) |> delete(~p"/auth/logout")

    assert redirected_to(conn, 302) =~ "oauth/logout"
    refute get_session(conn, :user_id)
  end

  test "GET /auth/signed-out renders confirmation", %{conn: conn} do
    conn = get(conn, ~p"/auth/signed-out")
    assert html_response(conn, 200) =~ "Signed out"
    assert html_response(conn, 200) =~ ~s(id="sign-in-again")
  end
end
