defmodule QueryConsoleWeb.UserAuthTest do
  use QueryConsoleWeb.ConnCase, async: true

  alias QueryConsoleWeb.UserAuth

  defp session_conn(conn, session) do
    conn = Phoenix.ConnTest.init_test_session(conn, session)
    UserAuth.fetch_current_user(conn, [])
  end

  test "a fresh session resolves the user", %{conn: conn} do
    user = user_fixture()

    conn =
      session_conn(conn, %{user_id: user.id, authenticated_at: System.os_time(:second)})

    assert conn.assigns.current_user.id == user.id
  end

  test "a session older than the TTL no longer resolves the user", %{conn: conn} do
    user = user_fixture()
    stale = System.os_time(:second) - UserAuth.session_ttl_seconds() - 1

    conn = session_conn(conn, %{user_id: user.id, authenticated_at: stale})

    assert is_nil(conn.assigns.current_user)
  end

  test "a session without authenticated_at is treated as expired", %{conn: conn} do
    user = user_fixture()

    conn = session_conn(conn, %{user_id: user.id})

    assert is_nil(conn.assigns.current_user)
  end

  test "a session stamped in the future is rejected", %{conn: conn} do
    user = user_fixture()

    conn =
      session_conn(conn, %{user_id: user.id, authenticated_at: System.os_time(:second) + 3600})

    assert is_nil(conn.assigns.current_user)
  end

  test "an expired session is redirected to SSO by the router", %{conn: conn} do
    user = user_fixture()
    stale = System.os_time(:second) - UserAuth.session_ttl_seconds() - 1

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{user_id: user.id, authenticated_at: stale})
      |> get("/")

    assert redirected_to(conn) == "/auth/ysc"
  end

  test "an open LiveView is bounced through SSO when the session TTL fires", %{
    conn: conn
  } do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, "/")
    send(view.pid, :query_console_session_expired)

    assert_redirect(view, "/auth/ysc")
  end
end
