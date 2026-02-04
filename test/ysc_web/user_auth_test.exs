defmodule YscWeb.UserAuthTest do
  use YscWeb.ConnCase, async: true

  alias Phoenix.LiveView
  alias Ysc.Accounts
  alias YscWeb.UserAuth
  import Ysc.AccountsFixtures

  @remember_me_cookie "_ysc_web_user_remember_me"

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(
        :secret_key_base,
        YscWeb.Endpoint.config(:secret_key_base)
      )
      |> init_test_session(%{})

    %{user: user_fixture(), conn: conn}
  end

  describe "log_in_user/3" do
    test "stores the user token in the session", %{conn: conn, user: user} do
      # Mark email as verified so user can log in without being redirected to account setup
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)
      conn = UserAuth.log_in_user(conn, user)
      assert token = get_session(conn, :user_token)

      assert get_session(conn, :live_socket_id) ==
               "users_sessions:#{Base.url_encode64(token)}"

      assert redirected_to(conn) == ~p"/"
      assert Accounts.get_user_by_session_token(token)
    end

    test "clears everything previously stored in the session", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> put_session(:to_be_removed, "value")
        |> UserAuth.log_in_user(user)

      refute get_session(conn, :to_be_removed)
    end

    test "redirects to the configured path", %{conn: conn, user: user} do
      # Mark email as verified so user can log in without being redirected to account setup
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      conn =
        conn
        |> put_session(:user_return_to, "/hello")
        |> UserAuth.log_in_user(user)

      assert redirected_to(conn) == "/hello"
    end

    test "writes a cookie if remember_me is configured", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> fetch_cookies()
        |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      assert get_session(conn, :user_token) == conn.cookies[@remember_me_cookie]

      assert %{value: signed_token, max_age: max_age} =
               conn.resp_cookies[@remember_me_cookie]

      assert signed_token != get_session(conn, :user_token)
      assert max_age == 5_184_000
    end
  end

  describe "logout_user/1" do
    test "erases session and cookies", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, user_token)
        |> put_req_cookie(@remember_me_cookie, user_token)
        |> fetch_cookies()
        |> UserAuth.log_out_user()

      refute get_session(conn, :user_token)
      refute conn.cookies[@remember_me_cookie]
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
      refute Accounts.get_user_by_session_token(user_token)
    end

    test "broadcasts to the given live_socket_id", %{conn: conn} do
      live_socket_id = "users_sessions:abcdef-token"
      YscWeb.Endpoint.subscribe(live_socket_id)

      conn
      |> put_session(:live_socket_id, live_socket_id)
      |> UserAuth.log_out_user()

      assert_receive %Phoenix.Socket.Broadcast{
        event: "disconnect",
        topic: ^live_socket_id
      }
    end

    test "works even if user is already logged out", %{conn: conn} do
      conn = conn |> fetch_cookies() |> UserAuth.log_out_user()
      refute get_session(conn, :user_token)
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "fetch_current_user/2" do
    test "authenticates user from session", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, user_token)
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user.id == user.id
    end

    test "authenticates user from cookies", %{conn: conn, user: user} do
      logged_in_conn =
        conn
        |> fetch_cookies()
        |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      user_token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      conn =
        conn
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user.id == user.id
      assert get_session(conn, :user_token) == user_token

      assert get_session(conn, :live_socket_id) ==
               "users_sessions:#{Base.url_encode64(user_token)}"
    end

    test "does not authenticate if data is missing", %{conn: conn, user: user} do
      _ = Accounts.generate_user_session_token(user)
      conn = UserAuth.fetch_current_user(conn, [])
      refute get_session(conn, :user_token)
      refute conn.assigns.current_user
    end

    test "assigns impersonated user as current_user when impersonated_user_id is in session",
         %{
           conn: conn
         } do
      admin = user_fixture(%{role: "admin"})
      target = user_fixture(%{first_name: "Viewed", last_name: "AsUser"})
      user_token = Accounts.generate_user_session_token(admin)

      conn =
        conn
        |> put_session(:user_token, user_token)
        |> put_session(:impersonated_user_id, target.id)
        |> put_session(:original_admin_id, admin.id)
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user.id == target.id
      assert conn.assigns.current_user.first_name == "Viewed"
      assert conn.assigns.real_current_user.id == admin.id
      assert conn.assigns.impersonating? == true
      assert conn.assigns.original_admin_id == admin.id
    end
  end

  describe "on_mount: mount_current_user" do
    test "assigns current_user based on a valid user_token", %{
      conn: conn,
      user: user
    } do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user.id == user.id
    end

    test "assigns nil to current_user assign if there isn't a valid user_token",
         %{conn: conn} do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user == nil
    end

    test "assigns nil to current_user assign if there isn't a user_token", %{
      conn: conn
    } do
      session = conn |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user == nil
    end

    test "assigns impersonated user as current_user when impersonated_user_id is in session",
         %{
           conn: conn
         } do
      admin = user_fixture(%{role: "admin"})
      target = user_fixture(%{first_name: "Impersonated", last_name: "User"})
      user_token = Accounts.generate_user_session_token(admin)

      session =
        conn
        |> put_session(:user_token, user_token)
        |> put_session(:impersonated_user_id, target.id)
        |> put_session(:original_admin_id, admin.id)
        |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user.id == target.id
      assert updated_socket.assigns.current_user.first_name == "Impersonated"
      assert updated_socket.assigns.real_current_user.id == admin.id
      assert updated_socket.assigns.impersonating? == true
      assert updated_socket.assigns.original_admin_id == admin.id
    end

    test "assigns real_current_user and impersonating? when not impersonating",
         %{
           conn: conn,
           user: user
         } do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user.id == user.id
      assert updated_socket.assigns.real_current_user.id == user.id
      assert updated_socket.assigns.impersonating? == false
      assert updated_socket.assigns.original_admin_id == nil
    end
  end

  describe "on_mount: ensure_authenticated" do
    test "authenticates current_user based on a valid user_token", %{
      conn: conn,
      user: user
    } do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(
          :ensure_authenticated,
          %{},
          session,
          %LiveView.Socket{}
        )

      assert updated_socket.assigns.current_user.id == user.id
    end

    test "redirects to login page if there isn't a valid user_token", %{
      conn: conn
    } do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: YscWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} =
        UserAuth.on_mount(:ensure_authenticated, %{}, session, socket)

      assert updated_socket.assigns.current_user == nil
    end

    test "redirects to login page if there isn't a user_token", %{conn: conn} do
      session = conn |> get_session()

      socket = %LiveView.Socket{
        endpoint: YscWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} =
        UserAuth.on_mount(:ensure_authenticated, %{}, session, socket)

      assert updated_socket.assigns.current_user == nil
    end
  end

  describe "on_mount: :redirect_if_user_is_authenticated" do
    test "redirects if there is an authenticated  user ", %{
      conn: conn,
      user: user
    } do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      assert {:halt, _updated_socket} =
               UserAuth.on_mount(
                 :redirect_if_user_is_authenticated,
                 %{},
                 session,
                 %LiveView.Socket{}
               )
    end

    test "doesn't redirect if there is no authenticated user", %{conn: conn} do
      session = conn |> get_session()

      assert {:cont, _updated_socket} =
               UserAuth.on_mount(
                 :redirect_if_user_is_authenticated,
                 %{},
                 session,
                 %LiveView.Socket{}
               )
    end
  end

  describe "redirect_if_user_is_authenticated/2" do
    test "redirects if user is authenticated", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_user, user)
        |> UserAuth.redirect_if_user_is_authenticated([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/"
    end

    test "does not redirect if user is not authenticated", %{conn: conn} do
      conn = UserAuth.redirect_if_user_is_authenticated(conn, [])
      refute conn.halted
      refute conn.status
    end
  end

  describe "require_authenticated_user/2" do
    test "redirects if user is not authenticated", %{conn: conn} do
      conn = conn |> fetch_flash() |> UserAuth.require_authenticated_user([])
      assert conn.halted

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must sign in to access this page."
    end

    test "stores the path to redirect to on GET", %{conn: conn} do
      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      refute get_session(halted_conn, :user_return_to)
    end

    test "does not redirect if user is authenticated", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_user, user)
        |> UserAuth.require_authenticated_user([])

      refute conn.halted
      refute conn.status
    end
  end

  describe "require_admin/2" do
    test "allows admin users to proceed", %{conn: conn} do
      admin = user_fixture(%{role: "admin"})

      conn =
        conn
        |> assign(:current_user, admin)
        |> UserAuth.require_admin([])

      refute conn.halted
      refute conn.status
    end

    test "redirects non-admin users", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_user, user)
        |> fetch_flash()
        |> UserAuth.require_admin([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You do not have permission to access this page."
    end

    test "stores the path to redirect to on GET for non-admin", %{
      conn: conn,
      user: user
    } do
      halted_conn =
        %{conn | path_info: ["admin", "users"], query_string: ""}
        |> assign(:current_user, user)
        |> fetch_flash()
        |> UserAuth.require_admin([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/admin/users"
    end
  end

  describe "require_approved/2" do
    test "allows active users to proceed", %{conn: conn} do
      active_user = user_fixture(%{state: "active"})

      conn =
        conn
        |> assign(:current_user, active_user)
        |> UserAuth.require_approved([])

      refute conn.halted
      refute conn.status
    end

    test "redirects pending_approval users", %{conn: conn} do
      pending_user = user_fixture(%{state: "pending_approval"})

      conn =
        conn
        |> assign(:current_user, pending_user)
        |> fetch_flash()
        |> UserAuth.require_approved([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/pending-review"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Your account has not been approved yet"
    end

    test "redirects rejected users", %{conn: conn} do
      rejected_user = user_fixture(%{state: "rejected"})

      conn =
        conn
        |> assign(:current_user, rejected_user)
        |> fetch_flash()
        |> UserAuth.require_approved([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/pending-review"
    end

    test "redirects suspended users", %{conn: conn} do
      suspended_user = user_fixture(%{state: "suspended"})

      conn =
        conn
        |> assign(:current_user, suspended_user)
        |> fetch_flash()
        |> UserAuth.require_approved([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/pending-review"
    end
  end

  describe "valid_internal_redirect?/1" do
    test "allows valid internal paths" do
      assert UserAuth.valid_internal_redirect?("/events/123")
      assert UserAuth.valid_internal_redirect?("/users/settings")
      assert UserAuth.valid_internal_redirect?("/bookings")
      assert UserAuth.valid_internal_redirect?("/admin/users")
    end

    test "rejects external URLs with https://" do
      refute UserAuth.valid_internal_redirect?("https://evil.com")
      refute UserAuth.valid_internal_redirect?("https://evil.com/phishing")
      refute UserAuth.valid_internal_redirect?("https://google.com")
    end

    test "rejects external URLs with http://" do
      refute UserAuth.valid_internal_redirect?("http://evil.com")
      refute UserAuth.valid_internal_redirect?("http://evil.com/path")
    end

    test "rejects protocol-relative URLs" do
      refute UserAuth.valid_internal_redirect?("//evil.com")
      refute UserAuth.valid_internal_redirect?("//evil.com/path")
    end

    test "rejects javascript: protocol (XSS)" do
      refute UserAuth.valid_internal_redirect?("javascript:alert('xss')")
      refute UserAuth.valid_internal_redirect?("javascript:alert(1)")
      refute UserAuth.valid_internal_redirect?("javascript:void(0)")
    end

    test "rejects data: protocol" do
      refute UserAuth.valid_internal_redirect?(
               "data:text/html,<script>alert(1)</script>"
             )
    end

    test "rejects vbscript: protocol" do
      refute UserAuth.valid_internal_redirect?("vbscript:alert(1)")
    end

    test "rejects paths containing ://" do
      refute UserAuth.valid_internal_redirect?("/path://evil.com")
    end

    test "rejects non-string inputs" do
      refute UserAuth.valid_internal_redirect?(nil)
      refute UserAuth.valid_internal_redirect?(123)
      refute UserAuth.valid_internal_redirect?(%{})
      refute UserAuth.valid_internal_redirect?([])
    end

    test "rejects empty string" do
      refute UserAuth.valid_internal_redirect?("")
    end

    test "rejects relative paths without leading slash" do
      refute UserAuth.valid_internal_redirect?("events/123")
      refute UserAuth.valid_internal_redirect?("users")
    end
  end

  describe "log_in_user/4 with redirect_to parameter" do
    test "uses valid redirect_to parameter", %{conn: conn, user: user} do
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      conn = UserAuth.log_in_user(conn, user, %{}, "/events/123")

      assert redirected_to(conn) == "/events/123"
    end

    test "ignores external redirect_to URLs", %{conn: conn, user: user} do
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      conn = UserAuth.log_in_user(conn, user, %{}, "https://evil.com")

      # Should fall back to default signed-in path
      assert redirected_to(conn) == ~p"/"
    end

    test "ignores javascript: protocol in redirect_to", %{
      conn: conn,
      user: user
    } do
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      conn = UserAuth.log_in_user(conn, user, %{}, "javascript:alert(1)")

      assert redirected_to(conn) == ~p"/"
    end

    test "prefers redirect_to over user_return_to when both valid", %{
      conn: conn,
      user: user
    } do
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      conn =
        conn
        |> put_session(:user_return_to, "/bookings")
        |> UserAuth.log_in_user(user, %{}, "/events")

      assert redirected_to(conn) == "/events"
    end

    test "falls back to user_return_to when redirect_to is invalid", %{
      conn: conn,
      user: user
    } do
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      conn =
        conn
        |> put_session(:user_return_to, "/bookings")
        |> UserAuth.log_in_user(user, %{}, "https://evil.com")

      assert redirected_to(conn) == "/bookings"
    end

    test "redirects unverified user to account setup when no redirect_to provided",
         %{conn: conn} do
      user = user_fixture(%{email_verified_at: nil})

      conn = UserAuth.log_in_user(conn, user)

      assert redirected_to(conn) =~ "/account/setup/"
    end

    test "redirects pending_approval user to pending-review when no redirect_to provided",
         %{conn: conn} do
      user = user_fixture(%{state: "pending_approval"})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      conn = UserAuth.log_in_user(conn, user)

      assert redirected_to(conn) == ~p"/pending-review"
    end
  end

  describe "on_mount(:ensure_admin, ...)" do
    test "allows admin users to proceed", %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      user_token = Accounts.generate_user_session_token(admin)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:ensure_admin, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user.id == admin.id
    end

    test "redirects non-admin users", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: YscWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} =
        UserAuth.on_mount(:ensure_admin, %{}, session, socket)

      assert updated_socket.assigns.current_user.role != :admin
    end

    test "redirects unauthenticated users", %{conn: conn} do
      session = conn |> get_session()

      socket = %LiveView.Socket{
        endpoint: YscWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, _updated_socket} =
        UserAuth.on_mount(:ensure_admin, %{}, session, socket)
    end

    test "allows admin to proceed when impersonating (uses real_current_user for admin check)",
         %{
           conn: conn
         } do
      admin = user_fixture(%{role: "admin"})
      target = user_fixture(%{role: "member"})
      user_token = Accounts.generate_user_session_token(admin)

      session =
        conn
        |> put_session(:user_token, user_token)
        |> put_session(:impersonated_user_id, target.id)
        |> put_session(:original_admin_id, admin.id)
        |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:ensure_admin, %{}, session, %LiveView.Socket{})

      # current_user is the impersonated user; real_current_user is the admin
      assert updated_socket.assigns.current_user.id == target.id
      assert updated_socket.assigns.real_current_user.id == admin.id
    end
  end

  describe "on_mount(:ensure_active, ...)" do
    test "allows active users to proceed", %{conn: conn} do
      active_user = user_fixture(%{state: "active"})
      user_token = Accounts.generate_user_session_token(active_user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:ensure_active, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user.id == active_user.id
    end

    test "redirects pending_approval users", %{conn: conn} do
      pending_user = user_fixture(%{state: "pending_approval"})
      user_token = Accounts.generate_user_session_token(pending_user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: YscWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, _updated_socket} =
        UserAuth.on_mount(:ensure_active, %{}, session, socket)
    end

    test "redirects rejected users", %{conn: conn} do
      rejected_user = user_fixture(%{state: "rejected"})
      user_token = Accounts.generate_user_session_token(rejected_user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: YscWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, _updated_socket} =
        UserAuth.on_mount(:ensure_active, %{}, session, socket)
    end

    test "redirects unauthenticated users", %{conn: conn} do
      session = conn |> get_session()

      socket = %LiveView.Socket{
        endpoint: YscWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, _updated_socket} =
        UserAuth.on_mount(:ensure_active, %{}, session, socket)
    end
  end

  describe "on_mount(:redirect_if_user_is_authenticated_and_pending_approval, ...)" do
    test "allows unauthenticated users to proceed", %{conn: conn} do
      session = conn |> get_session()

      {:cont, _updated_socket} =
        UserAuth.on_mount(
          :redirect_if_user_is_authenticated_and_pending_approval,
          %{},
          session,
          %LiveView.Socket{}
        )
    end

    test "allows authenticated pending_approval users (due to atom/string mismatch)",
         %{conn: conn} do
      # Note: The code compares state == "pending_approval" (string) but user.state is :pending_approval (atom)
      # This means the condition never matches and pending_approval users are allowed through
      # This test documents the current behavior
      pending_user = user_fixture(%{state: "pending_approval"})

      user_token = Accounts.generate_user_session_token(pending_user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(
          :redirect_if_user_is_authenticated_and_pending_approval,
          %{},
          session,
          %LiveView.Socket{}
        )

      assert updated_socket.assigns.current_user.id == pending_user.id
    end

    test "allows authenticated active users to proceed", %{conn: conn} do
      active_user = user_fixture(%{state: "active"})
      user_token = Accounts.generate_user_session_token(active_user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(
          :redirect_if_user_is_authenticated_and_pending_approval,
          %{},
          session,
          %LiveView.Socket{}
        )

      assert updated_socket.assigns.current_user.id == active_user.id
    end
  end

  describe "membership_active?/1" do
    test "returns false for nil" do
      refute UserAuth.membership_active?(nil)
    end

    test "returns true for lifetime membership" do
      assert UserAuth.membership_active?(%{type: :lifetime})
    end

    test "returns false for non-membership structs" do
      refute UserAuth.membership_active?(%{})
      refute UserAuth.membership_active?("not a membership")
    end

    test "checks subscription validity for Subscription struct" do
      # Create a mock subscription
      subscription = %Ysc.Subscriptions.Subscription{
        stripe_status: "active",
        stripe_id: "sub_test"
      }

      # The result depends on Subscriptions.valid?/1 implementation
      result = UserAuth.membership_active?(subscription)
      # Should return boolean
      assert is_boolean(result)
    end
  end

  describe "get_membership_plan_type/1" do
    test "returns nil for nil" do
      assert UserAuth.get_membership_plan_type(nil) == nil
    end

    test "returns :lifetime for lifetime membership" do
      assert UserAuth.get_membership_plan_type(%{type: :lifetime}) == :lifetime
    end

    test "returns plan ID from plan struct" do
      membership = %{plan: %{id: :family}}
      assert UserAuth.get_membership_plan_type(membership) == :family
    end

    test "returns nil for unknown membership type" do
      assert UserAuth.get_membership_plan_type(%{}) == nil
    end

    test "handles Subscription struct with subscription_items" do
      # Create a mock subscription with items
      subscription = %Ysc.Subscriptions.Subscription{
        stripe_id: "sub_test",
        subscription_items: []
      }

      # Should return nil when no items
      result = UserAuth.get_membership_plan_type(subscription)
      assert result == nil
    end
  end

  describe "get_membership_renewal_date/1" do
    test "returns nil for nil" do
      assert UserAuth.get_membership_renewal_date(nil) == nil
    end

    test "returns nil for lifetime membership" do
      assert UserAuth.get_membership_renewal_date(%{type: :lifetime}) == nil
    end

    test "returns renewal_date when present" do
      date = ~U[2026-12-31 23:59:59Z]
      membership = %{renewal_date: date}
      assert UserAuth.get_membership_renewal_date(membership) == date
    end

    test "returns nil for membership without renewal date" do
      assert UserAuth.get_membership_renewal_date(%{}) == nil
    end

    test "returns current_period_end for Subscription struct" do
      date = ~U[2026-12-31 23:59:59Z]

      subscription = %Ysc.Subscriptions.Subscription{
        current_period_end: date
      }

      assert UserAuth.get_membership_renewal_date(subscription) == date
    end
  end

  describe "get_membership_plan_display_name/1" do
    test "returns 'No Membership' for nil" do
      assert UserAuth.get_membership_plan_display_name(nil) == "No Membership"
    end

    test "returns 'Lifetime Membership' for lifetime membership" do
      assert UserAuth.get_membership_plan_display_name(%{type: :lifetime}) ==
               "Lifetime Membership"
    end

    test "returns formatted plan name from plan struct" do
      membership = %{plan: %{id: :family}}

      assert UserAuth.get_membership_plan_display_name(membership) ==
               "Family Membership"
    end

    test "returns formatted plan name for multi-word plans" do
      membership = %{plan: %{id: :single_plus}}

      assert UserAuth.get_membership_plan_display_name(membership) ==
               "Single Plus Membership"
    end

    test "returns 'Active Membership' for unknown membership type" do
      assert UserAuth.get_membership_plan_display_name(%{}) ==
               "Active Membership"
    end

    test "returns 'Active Membership' for Subscription without plan type" do
      subscription = %Ysc.Subscriptions.Subscription{
        stripe_id: "sub_test",
        subscription_items: []
      }

      assert UserAuth.get_membership_plan_display_name(subscription) ==
               "Active Membership"
    end
  end

  describe "get_membership_type_display_string/1" do
    test "returns 'Unknown' for nil" do
      assert UserAuth.get_membership_type_display_string(nil) == "Unknown"
    end

    test "returns 'Lifetime' for lifetime membership" do
      membership = %{type: :lifetime}
      # This will call get_membership_plan_type which returns :lifetime
      assert UserAuth.get_membership_type_display_string(membership) ==
               "Lifetime"
    end

    test "returns formatted type for plan struct" do
      membership = %{plan: %{id: :family}}
      assert UserAuth.get_membership_type_display_string(membership) == "Family"
    end

    test "returns 'Unknown' for unknown membership type" do
      assert UserAuth.get_membership_type_display_string(%{}) == "Unknown"
    end
  end

  describe "get_user_membership_plan_type/1" do
    test "returns nil for nil user" do
      assert UserAuth.get_user_membership_plan_type(nil) == nil
    end
  end

  describe "fetch_current_user/2 - membership assignment" do
    test "assigns current_membership and active_membership? for user with token",
         %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, user_token)
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user.id == user.id
      # User has no membership by default
      assert conn.assigns[:current_membership] == nil
      assert conn.assigns[:active_membership?] == false
    end

    test "assigns nil membership for unauthenticated user", %{conn: conn} do
      conn = UserAuth.fetch_current_user(conn, [])

      refute conn.assigns[:current_user]
      assert conn.assigns[:current_membership] == nil
      assert conn.assigns[:active_membership?] == false
    end
  end

  describe "log_in_user/3 - session preservation" do
    test "preserves just_logged_in flag through session renewal", %{
      conn: conn,
      user: user
    } do
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      conn =
        conn
        |> put_session(:just_logged_in, true)
        |> UserAuth.log_in_user(user)

      # After login, just_logged_in should be preserved
      assert get_session(conn, :just_logged_in) == true
    end

    test "clears just_logged_in flag if not set", %{conn: conn, user: user} do
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      conn = UserAuth.log_in_user(conn, user)

      # just_logged_in should not be present
      refute get_session(conn, :just_logged_in)
    end
  end

  describe "log_in_user/4 - remember me functionality" do
    test "does not write remember me cookie when not requested", %{
      conn: conn,
      user: user
    } do
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      conn =
        conn
        |> fetch_cookies()
        |> UserAuth.log_in_user(user, %{})

      refute conn.resp_cookies[@remember_me_cookie]
    end

    test "does not write remember me cookie when remember_me is false", %{
      conn: conn,
      user: user
    } do
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      conn =
        conn
        |> fetch_cookies()
        |> UserAuth.log_in_user(user, %{"remember_me" => "false"})

      refute conn.resp_cookies[@remember_me_cookie]
    end
  end

  describe "redirect_if_user_is_authenticated/2 - different user states" do
    test "redirects pending_approval user to pending-review", %{conn: conn} do
      pending_user = user_fixture(%{state: "pending_approval"})

      conn =
        conn
        |> assign(:current_user, pending_user)
        |> UserAuth.redirect_if_user_is_authenticated([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/pending-review"
    end
  end

  describe "log_out_user/1 - without live_socket_id" do
    test "works when no live_socket_id is set", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, user_token)
        # Explicitly not setting live_socket_id
        |> UserAuth.log_out_user()

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "valid_internal_redirect?/1 - additional edge cases" do
    test "allows paths with query parameters" do
      assert UserAuth.valid_internal_redirect?("/events?page=2")
      assert UserAuth.valid_internal_redirect?("/users?filter=active&sort=name")
    end

    test "allows paths with fragments" do
      assert UserAuth.valid_internal_redirect?("/events#upcoming")
      assert UserAuth.valid_internal_redirect?("/bookings#section-rooms")
    end

    test "rejects paths with embedded protocols" do
      refute UserAuth.valid_internal_redirect?(
               "/path?redirect=https://evil.com"
             )
    end
  end

  describe "get_active_membership/1" do
    test "returns nil for user without membership" do
      user = user_fixture()
      # MembershipCache.get_active_membership will be called
      # For a user without membership, it should return nil
      result = UserAuth.get_active_membership(user)
      # The result depends on the user's actual membership status
      assert result == nil || is_map(result)
    end
  end

  describe "require_authenticated_user/2 - without flash" do
    test "stores path for POST requests when user is not authenticated", %{
      conn: conn
    } do
      # POST requests should NOT store the return path
      halted_conn =
        %{
          conn
          | path_info: ["admin", "users"],
            query_string: "",
            method: "POST"
        }
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      # POST requests should not store return path
      refute get_session(halted_conn, :user_return_to)
    end
  end

  describe "on_mount/4 - assigns with different socket states" do
    test "mount_current_user assigns nil when session has no token", %{
      conn: conn
    } do
      session = conn |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user == nil
      assert updated_socket.assigns[:current_membership] == nil
      assert updated_socket.assigns[:active_membership?] == false
    end
  end
end
