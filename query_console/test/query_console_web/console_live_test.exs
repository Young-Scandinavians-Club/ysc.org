defmodule QueryConsoleWeb.ConsoleLiveTest do
  use QueryConsoleWeb.ConnCase, async: true

  test "redirects unauthenticated users to SSO without an error flash", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/auth/ysc"
    refute Phoenix.Flash.get(conn.assigns.flash, :error)
  end

  test "authenticated user sees console controls and can manage owned workbooks", %{conn: conn} do
    user = user_fixture()
    other = user_fixture()
    other_wb = workbook_fixture(other, %{title: "Secret"})

    conn = log_in_user(conn, user)

    {:ok, view, _html} =
      conn
      |> live(~p"/")
      |> follow_redirect(conn)

    assert has_element?(view, "#workbook-list")
    assert has_element?(view, "#back-to-admin")
    assert has_element?(view, "#sql-editor")
    assert has_element?(view, "#run-all")
    assert has_element?(view, "#run-current")
    assert has_element?(view, "#run-selection")
    assert has_element?(view, "#cancel-run")
    assert has_element?(view, "#run-status")
    assert has_element?(view, "#results-panel")
    assert has_element?(view, "#results-grid")

    # Cannot open another user's workbook
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/workbooks/#{other_wb.id}")
  end

  test "owner workbook appears in sidebar stream", %{conn: conn} do
    user = user_fixture()
    workbook = workbook_fixture(user, %{title: "My Query"})

    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/workbooks/#{workbook.id}")

    assert has_element?(view, "#workbook-list")
    assert render(view) =~ "My Query"
    assert has_element?(view, "#run-status")
  end
end
