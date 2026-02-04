defmodule YscWeb.ImpersonationControllerTest do
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  describe "GET /admin/impersonate/:user_id" do
    test "redirects unauthenticated users to log in", %{conn: conn} do
      target = user_fixture()
      conn = get(conn, ~p"/admin/impersonate/#{target.id}")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "sign in"
    end

    test "redirects non-admin users to / with error", %{conn: conn} do
      member = user_fixture(%{role: "member"})
      target = user_fixture()

      conn =
        conn
        |> log_in_user(member)
        |> get(~p"/admin/impersonate/#{target.id}")

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "do not have permission"
    end

    test "redirects to /admin/users with error when user_id does not exist", %{
      conn: conn
    } do
      admin = user_fixture(%{role: "admin"})
      fake_id = Ecto.ULID.generate()

      conn =
        conn
        |> log_in_user(admin)
        |> get(~p"/admin/impersonate/#{fake_id}")

      assert redirected_to(conn) == ~p"/admin/users"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "User not found."
      refute get_session(conn, :impersonated_user_id)
      refute get_session(conn, :original_admin_id)
    end

    test "sets session and redirects to / when admin impersonates existing user",
         %{
           conn: conn
         } do
      admin = user_fixture(%{role: "admin"})
      target = user_fixture(%{first_name: "Jane", last_name: "Smith"})

      conn =
        conn
        |> log_in_user(admin)
        |> get(~p"/admin/impersonate/#{target.id}")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Impersonating"
      assert get_session(conn, :impersonated_user_id) == target.id
      assert get_session(conn, :original_admin_id) == admin.id
    end

    test "after impersonating, home page shows impersonation banner", %{
      conn: conn
    } do
      admin = user_fixture(%{role: "admin"})
      target = user_fixture(%{first_name: "Jane", last_name: "Smith"})

      conn =
        conn
        |> log_in_user(admin)
        |> get(~p"/admin/impersonate/#{target.id}")

      assert redirected_to(conn) == ~p"/"
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      assert html =~ "IMPERSONATING USER"
      assert html =~ "Jane Smith"
      assert html =~ "Stop Impersonating"
    end
  end

  describe "GET /admin/stop-impersonation" do
    test "redirects to / when not impersonating", %{conn: conn} do
      admin = user_fixture(%{role: "admin"})

      conn =
        conn
        |> log_in_user(admin)
        |> get(~p"/admin/stop-impersonation")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :impersonated_user_id)
      refute get_session(conn, :original_admin_id)
    end

    test "clears impersonation and redirects to /admin when session is valid",
         %{
           conn: conn
         } do
      admin = user_fixture(%{role: "admin"})
      target = user_fixture()
      token = Ysc.Accounts.generate_user_session_token(admin)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:user_token, token)
        |> put_session(:impersonated_user_id, target.id)
        |> put_session(:original_admin_id, admin.id)
        |> get(~p"/admin/stop-impersonation")

      assert redirected_to(conn) == ~p"/admin"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Stopped impersonating"

      refute get_session(conn, :impersonated_user_id)
      refute get_session(conn, :original_admin_id)
    end

    test "clears impersonation and redirects to / when original_admin_id does not match session admin",
         %{conn: conn} do
      admin1 = user_fixture(%{role: "admin"})
      admin2 = user_fixture(%{role: "admin"})
      target = user_fixture()

      # Tampered session: logged in as admin1 but original_admin_id is admin2 (e.g. session tampering)
      token = Ysc.Accounts.generate_user_session_token(admin1)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:user_token, token)
        |> put_session(:impersonated_user_id, target.id)
        |> put_session(:original_admin_id, admin2.id)
        |> get(~p"/admin/stop-impersonation")

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Stopped impersonating"

      refute get_session(conn, :impersonated_user_id)
      refute get_session(conn, :original_admin_id)
    end

    test "unauthenticated user is redirected to log in", %{conn: conn} do
      conn = get(conn, ~p"/admin/stop-impersonation")
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end
