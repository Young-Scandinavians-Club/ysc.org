defmodule YscWeb.ErrorPageLayoutTest do
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  test "router 404 does not include site nav or footer", %{conn: conn} do
    conn = get(conn, "/no/such/path/here")
    html = html_response(conn, 404)

    assert html =~ "Page not found"
    refute html =~ ~s(id="site-header")
    refute html =~ ~s(id="rootNavbar")
  end

  test "controller-rendered 404 does not include site nav or footer", %{
    conn: conn
  } do
    admin = user_fixture(%{state: :active, role: :admin})

    filename =
      "ysc-user-export-2026-05-31-#{admin.id}-01KSZK7QC7FMFQPBJ17V6RTF6B.csv"

    conn = conn |> log_in_user(admin) |> get("/admin/exports/#{filename}")
    html = html_response(conn, 404)

    assert html =~ "Page not found"
    refute html =~ ~s(id="site-header")
    refute html =~ ~s(id="rootNavbar")
  end
end
