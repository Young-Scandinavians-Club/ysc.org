defmodule QueryConsoleWeb.LotusDashboardTest do
  use QueryConsoleWeb.ConnCase, async: true

  test "redirects unauthenticated users to SSO without an error flash", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/auth/ysc"
    refute Phoenix.Flash.get(conn.assigns.flash, :error)
  end

  test "authenticated user sees Lotus shell with Admin and Sign out", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ ~s(id="back-to-admin")
    assert html =~ ~s(id="sign-out")
    assert html =~ ~s(id="signed-in-as")
    assert html =~ user.display_name || html =~ user.email
    assert html =~ "YSC Query Console" || html =~ "Lotus"

    {:ok, _view, _live_html} = live(conn, ~p"/")
  end

  test "new query editor mounts at /queries/new (not /new)", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/")

    # Root mount must not produce protocol-relative "//queries/new" links.
    assert render(view) =~ ~s(href="/queries/new")
    refute render(view) =~ ~s(href="//queries/new")

    {:ok, editor, html} = live(conn, "/queries/new")
    assert html =~ "New Query"
    assert render(editor) =~ "New Query"
  end
end
