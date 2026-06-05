defmodule YscWeb.MemberDocumentsSecurityTest do
  @moduledoc """
  Regression tests for member-only annual meeting documents and admin exports.
  """
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures

  alias YscWeb.AdminExportFiles

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

      assert String.starts_with?(
               hd(get_resp_header(conn, "content-type")),
               "application/pdf"
             )

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

    test "pending_approval member cannot download annual report PDFs", %{
      conn: conn
    } do
      user = oauth_user_fixture(%{state: :pending_approval})

      conn =
        conn
        |> log_in_user(user)
        |> get("/annual_meetings/#{@sample_pdf}")

      assert redirected_to(conn) == ~p"/pending-review"
    end
  end

  describe "financials page" do
    test "pending_approval member cannot view financials", %{conn: conn} do
      user = oauth_user_fixture(%{state: :pending_approval})

      conn =
        conn
        |> log_in_user(user)
        |> get("/financials")

      assert redirected_to(conn) == ~p"/pending-review"
    end

    test "active member can view financials", %{conn: conn} do
      user = oauth_user_fixture(%{state: :active})

      conn =
        conn
        |> log_in_user(user)
        |> get("/financials")

      assert conn.status == 200
      assert html_response(conn, 200) =~ "Financials"
    end
  end

  describe "admin CSV exports" do
    test "unauthenticated export download is redirected to login", %{conn: conn} do
      conn =
        get(
          conn,
          "/admin/exports/ysc-user-export-2026-05-26-01ARZ3NDEKTSV4RRFFQ69G5FAV-01ARZ3NDEKTSV4RRFFQ69G5FAVB.csv"
        )

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "non-admin member cannot download admin exports", %{conn: conn} do
      user = user_fixture(%{state: :active, role: :member})

      conn =
        conn
        |> log_in_user(user)
        |> get(
          "/admin/exports/ysc-user-export-2026-05-26-01ARZ3NDEKTSV4RRFFQ69G5FAV-01ARZ3NDEKTSV4RRFFQ69G5FAVB.csv"
        )

      assert redirected_to(conn) == ~p"/"
    end

    test "admin cannot download another admin's export file", %{conn: conn} do
      owner = user_fixture(%{state: :active, role: :admin})
      other_admin = user_fixture(%{state: :active, role: :admin})

      filename =
        "ysc-user-export-2026-05-26-#{owner.id}-01ARZ3NDEKTSV4RRFFQ69G5FAV.csv"

      exports_root = AdminExportFiles.exports_root()
      File.mkdir_p!(exports_root)
      file_path = Path.join(exports_root, filename)
      File.write!(file_path, "id,email\n1,secret@example.com")
      on_exit(fn -> File.rm(file_path) end)

      conn =
        conn
        |> log_in_user(other_admin)
        |> get("/admin/exports/#{filename}")

      assert conn.status == 403
    end

    test "admin can download export with csv content type", %{conn: conn} do
      user = user_fixture(%{state: :active, role: :admin})

      filename =
        "ysc-user-export-2026-05-26-#{user.id}-01ARZ3NDEKTSV4RRFFQ69G5FAV.csv"

      exports_root = AdminExportFiles.exports_root()
      File.mkdir_p!(exports_root)
      file_path = Path.join(exports_root, filename)
      File.write!(file_path, "id,email\n1,test@example.com")
      on_exit(fn -> File.rm(file_path) end)

      conn =
        conn
        |> log_in_user(user)
        |> get("/admin/exports/#{filename}")

      assert conn.status == 200

      assert String.starts_with?(
               hd(get_resp_header(conn, "content-type")),
               "text/csv"
             )

      assert get_resp_header(conn, "content-disposition") != []
      assert conn.resp_body == "id,email\n1,test@example.com"
    end
  end
end
