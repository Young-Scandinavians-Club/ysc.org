defmodule YscWeb.MemberDocumentsSecurityTest do
  @moduledoc """
  Regression tests for member-only annual meeting documents and admin exports.
  """
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  @sample_pdf "2026/YSC_ANNUAL_REPORT_FY_2025.pdf"

  describe "annual meeting documents" do
    test "unauthenticated request is redirected to login", %{conn: conn} do
      conn = get(conn, "/annual_meetings/#{@sample_pdf}")
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "authenticated member can download a known annual report PDF", %{
      conn: conn
    } do
      user = oauth_user_fixture(%{state: :active})
      conn = log_in_user(conn, user) |> get("/annual_meetings/#{@sample_pdf}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-disposition") != []
      assert conn.resp_body != ""
    end

    test "path traversal is rejected with 404", %{conn: conn} do
      user = oauth_user_fixture(%{state: :active})

      conn =
        conn
        |> log_in_user(user)
        |> get("/annual_meetings/2026/..%2F..%2Fetc%2Fpasswd")

      assert conn.status == 404
    end
  end

  describe "admin CSV exports" do
    test "unauthenticated export download is redirected to login", %{conn: conn} do
      conn =
        get(
          conn,
          "/admin/exports/ysc-user-export-2026-05-26-01ARZ3NDEKTSV4RRFFQ69G5FAV.csv"
        )

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "non-admin member cannot download admin exports", %{conn: conn} do
      user = user_fixture(%{state: :active, role: :member})

      conn =
        conn
        |> log_in_user(user)
        |> get(
          "/admin/exports/ysc-user-export-2026-05-26-01ARZ3NDEKTSV4RRFFQ69G5FAV.csv"
        )

      assert redirected_to(conn) == ~p"/"
    end
  end
end
