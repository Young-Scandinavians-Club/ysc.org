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
    html = render(view)

    # Root mount must not produce protocol-relative "//queries/new" links.
    assert html =~ ~s(href="/queries/new")
    refute html =~ ~s(href="//queries/new")
    # Logo / home must be "/" (not empty href from prefix "").
    assert html =~ ~s(title="Lotus Web")
    assert html =~ ~s(href="/")
    refute html =~ ~s(href="" title="Lotus Web")

    {:ok, editor, editor_html} = live(conn, "/queries/new")
    assert editor_html =~ "New Query"
    assert render(editor) =~ "New Query"
    # Back to queries list
    assert render(editor) =~ ~s(href="/")
  end

  test "dashboard editor back link goes to /?tab=dashboards", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, "/dashboards/new")
    html = render(view)
    assert html =~ ~s(href="/?tab=dashboards")
    refute html =~ ~s(href="?tab=dashboards")
  end
end
