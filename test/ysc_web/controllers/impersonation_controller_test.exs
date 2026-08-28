defmodule YscWeb.ImpersonationControllerTest do
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  describe "POST /admin/impersonate/:user_id" do
    test "redirects unauthenticated users to log in", %{conn: conn} do
      target_id = Ecto.ULID.generate()
      {conn, token} = fetch_conn_csrf(conn)

      conn =
        post(conn, ~p"/admin/impersonate/#{target_id}", %{
          "_csrf_token" => token
        })

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "sign in"
    end

    test "redirects non-admin users to / with error", %{conn: conn} do
      member = user_fixture_fast(%{role: "member"})
      target = user_fixture_fast()

      conn = log_in_user(conn, member)
      {conn, token} = fetch_conn_csrf(conn)

      conn =
        post(conn, ~p"/admin/impersonate/#{target.id}", %{
          "_csrf_token" => token
        })

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "do not have permission"
    end

    test "redirects to /admin/users with error when user_id does not exist", %{
      conn: conn
    } do
      admin = user_fixture_fast(%{role: "admin"})
      fake_id = Ecto.ULID.generate()

      conn = log_in_user(conn, admin)
      {conn, token} = fetch_conn_csrf(conn)

      conn =
        post(conn, ~p"/admin/impersonate/#{fake_id}", %{"_csrf_token" => token})

      assert redirected_to(conn) == ~p"/admin/users"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "User not found."
      refute get_session(conn, :impersonated_user_id)
      refute get_session(conn, :original_admin_id)
    end

    test "sets session and redirects to / when admin impersonates existing user",
         %{
           conn: conn
         } do
      admin = user_fixture_fast(%{role: "admin"})
      target = user_fixture_fast(%{first_name: "Jane", last_name: "Smith"})

      conn = log_in_user(conn, admin)
      {conn, token} = fetch_conn_csrf(conn)

      conn =
        post(conn, ~p"/admin/impersonate/#{target.id}", %{
          "_csrf_token" => token
        })

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Impersonating"
      assert get_session(conn, :impersonated_user_id) == target.id
      assert get_session(conn, :original_admin_id) == admin.id
    end

    test "clears post-login reauth grace period when starting impersonation (Finding 47)",
         %{conn: conn} do
      admin = user_fixture_fast(%{role: "admin"})
      target = user_fixture_fast()

      # Production log_in_user/6 stamps :reauth_verified_at; the ConnCase helper
      # only sets :user_token, so seed the grace period explicitly.
      conn =
        conn
        |> log_in_user(admin)
        |> put_session(
          :reauth_verified_at,
          DateTime.utc_now() |> DateTime.to_unix()
        )

      assert is_integer(get_session(conn, :reauth_verified_at))

      {conn, token} = fetch_conn_csrf(conn)

      conn =
        post(conn, ~p"/admin/impersonate/#{target.id}", %{
          "_csrf_token" => token
        })

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :impersonated_user_id) == target.id
      refute get_session(conn, :reauth_verified_at)
    end

    test "after impersonating, home page shows impersonation banner", %{
      conn: conn
    } do
      admin = user_fixture_fast(%{role: "admin"})
      target = user_fixture_fast(%{first_name: "Jane", last_name: "Smith"})

      conn = log_in_user(conn, admin)
      {conn, token} = fetch_conn_csrf(conn)

      conn =
        post(conn, ~p"/admin/impersonate/#{target.id}", %{
          "_csrf_token" => token
        })

      assert redirected_to(conn) == ~p"/"
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      assert html =~ "IMPERSONATING USER"
      assert html =~ "Jane Smith"
      assert html =~ "Stop Impersonating"
    end
  end

  describe "POST /admin/stop-impersonation" do
    test "redirects to / when not impersonating", %{conn: conn} do
      admin = user_fixture_fast(%{role: "admin"})

      conn = log_in_user(conn, admin)
      {conn, token} = fetch_conn_csrf(conn)

      conn =
        post(conn, ~p"/admin/stop-impersonation", %{"_csrf_token" => token})

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :impersonated_user_id)
      refute get_session(conn, :original_admin_id)
    end

    test "clears impersonation and redirects to impersonated user's admin detail page when session is valid",
         %{
           conn: conn
         } do
      admin = user_fixture_fast(%{role: "admin"})
      target = user_fixture_fast()
      token = Ysc.Accounts.generate_user_session_token(admin)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:user_token, token)
        |> put_session(:impersonated_user_id, target.id)
        |> put_session(:original_admin_id, admin.id)

      {conn, csrf} = fetch_conn_csrf(conn)

      conn =
        post(conn, ~p"/admin/stop-impersonation", %{"_csrf_token" => csrf})

      assert redirected_to(conn) == ~p"/admin/users/#{target.id}/details"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Stopped impersonating"

      refute get_session(conn, :impersonated_user_id)
      refute get_session(conn, :original_admin_id)
    end

    test "clears impersonation and redirects to /admin when session is valid but impersonated_user_id is missing",
         %{
           conn: conn
         } do
      admin = user_fixture_fast(%{role: "admin"})
      token = Ysc.Accounts.generate_user_session_token(admin)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:user_token, token)
        |> put_session(:original_admin_id, admin.id)

      {conn, csrf} = fetch_conn_csrf(conn)

      conn =
        post(conn, ~p"/admin/stop-impersonation", %{"_csrf_token" => csrf})

      assert redirected_to(conn) == ~p"/admin"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Stopped impersonating"

      refute get_session(conn, :impersonated_user_id)
      refute get_session(conn, :original_admin_id)
    end

    test "clears impersonation and redirects to / when original_admin_id does not match session admin",
         %{conn: conn} do
      admin1 = user_fixture_fast(%{role: "admin"})
      admin2 = user_fixture_fast(%{role: "admin"})
      target = user_fixture_fast()

      # Tampered session: logged in as admin1 but original_admin_id is admin2 (e.g. session tampering)
      token = Ysc.Accounts.generate_user_session_token(admin1)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:user_token, token)
        |> put_session(:impersonated_user_id, target.id)
        |> put_session(:original_admin_id, admin2.id)

      {conn, csrf} = fetch_conn_csrf(conn)

      conn =
        post(conn, ~p"/admin/stop-impersonation", %{"_csrf_token" => csrf})

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Stopped impersonating"

      refute get_session(conn, :impersonated_user_id)
      refute get_session(conn, :original_admin_id)
    end

    test "unauthenticated user is redirected to log in", %{conn: conn} do
      {conn, token} = fetch_conn_csrf(conn)

      conn =
        post(conn, ~p"/admin/stop-impersonation", %{"_csrf_token" => token})

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end
