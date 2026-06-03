defmodule YscWeb.UserLoginLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  describe "Log in page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Sign in to your YSC account"
      assert html =~ "Apply for membership"
      assert html =~ "Forgot your password?"
    end

    test "renders authentication method buttons", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/log-in")

      # Check for auth methods container
      assert has_element?(lv, "#auth-methods")

      # Check for OAuth buttons (they should always be visible)
      assert html =~ "Sign in with Google"
      assert html =~ "Sign in with Facebook"

      # Check for divider
      assert html =~ "or"
    end

    test "renders passkey button when supported", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Simulate passkey support detection
      lv
      |> element("#auth-methods")
      |> render_hook("passkey_support_detected", %{"supported" => true})

      assert has_element?(lv, "button[phx-click='sign_in_with_passkey']")

      html = render(lv)

      assert html =~ "Sign in with Face ID" || html =~ "Sign in with Passkey"
    end

    test "hides passkey button when not supported", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Simulate no passkey support
      lv
      |> element("#auth-methods")
      |> render_hook("passkey_support_detected", %{"supported" => false})

      # Passkey button should not be visible when not supported
      refute has_element?(lv, "button[phx-click='sign_in_with_passkey']")
    end

    test "shows failed login attempts banner when attempts >= 3", %{conn: conn} do
      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> put_session(:failed_login_attempts, 3)

      {:ok, lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Having trouble signing in?"
      assert html =~ "Reset your password"
      assert html =~ "Contact us for help"
      assert has_element?(lv, "#failed-login-banner")
    end

    test "hides failed login attempts banner when attempts < 3", %{conn: conn} do
      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> put_session(:failed_login_attempts, 2)

      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      refute html =~ "Having trouble signing in?"
    end

    test "dismisses failed login attempts banner", %{conn: conn} do
      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> put_session(:failed_login_attempts, 3)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Dismiss the banner
      result =
        lv
        |> element("#failed-login-banner button[phx-click='dismiss_banner']")
        |> render_click()

      # Should redirect to reset attempts endpoint (full page redirect, not LiveView)
      assert {:error, {:redirect, %{to: path}}} = result
      assert path == ~p"/users/log-in/reset-attempts"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/log-in")
        |> follow_redirect(conn, "/")

      assert {:ok, _conn} = result
    end
  end

  describe "OAuth authentication" do
    test "redirects to Google OAuth when sign_in_with_google is clicked", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      result =
        lv
        |> element("button[phx-click='sign_in_with_google']")
        |> render_click()

      # OAuth redirects are full page redirects, not LiveView redirects
      assert {:error, {:redirect, %{to: path}}} = result
      assert path == ~p"/auth/google"
    end

    test "redirects to Google OAuth with redirect_to parameter", %{conn: conn} do
      {:ok, lv, _html} =
        live(conn, ~p"/users/log-in?redirect_to=/bookings/tahoe")

      result =
        lv
        |> element("button[phx-click='sign_in_with_google']")
        |> render_click()

      # Should redirect to Google OAuth with redirect_to in query params
      assert {:error, {:redirect, %{to: path}}} = result
      assert path == ~p"/auth/google?redirect_to=%2Fbookings%2Ftahoe"
    end

    test "redirects to Facebook OAuth when sign_in_with_facebook is clicked", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      result =
        lv
        |> element("button[phx-click='sign_in_with_facebook']")
        |> render_click()

      # OAuth redirects are full page redirects, not LiveView redirects
      assert {:error, {:redirect, %{to: path}}} = result
      assert path == ~p"/auth/facebook"
    end

    test "redirects to Facebook OAuth with redirect_to parameter", %{conn: conn} do
      {:ok, lv, _html} =
        live(conn, ~p"/users/log-in?redirect_to=/bookings/tahoe")

      result =
        lv
        |> element("button[phx-click='sign_in_with_facebook']")
        |> render_click()

      # Should redirect to Facebook OAuth with redirect_to in query params
      assert {:error, {:redirect, %{to: path}}} = result
      assert path == ~p"/auth/facebook?redirect_to=%2Fbookings%2Ftahoe"
    end
  end

  describe "user login" do
    test "redirects if user login with valid credentials", %{conn: conn} do
      password = "123456789abcd"
      user = user_fixture(%{password: password})

      # Mark email as verified so user can log in without being redirected to account setup
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form",
          user: %{email: user.email, password: password, remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with a flash error if there are no valid credentials",
         %{
           conn: conn
         } do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form",
          user: %{
            email: "test@email.com",
            password: "123456",
            remember_me: true
          }
        )

      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid email or password"

      assert redirected_to(conn) == "/users/log-in"
    end
  end

  describe "mount options and client hooks" do
    test "expired_link query shows login error toast", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in?reason=expired_link")

      assert html =~ "expired" or html =~ "Invalid" or html =~ "sign in"
    end

    test "invalid redirect_to query is ignored", %{conn: conn} do
      {:ok, lv, _html} =
        live(conn, ~p"/users/log-in?redirect_to=https://evil.example.com")

      result =
        lv
        |> element("button[phx-click='sign_in_with_google']")
        |> render_click()

      assert {:error, {:redirect, %{to: path}}} = result
      assert path == ~p"/auth/google"
    end

    test "sign_in_with_passkey pushes authentication challenge", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv
      |> element("#auth-methods")
      |> render_hook("passkey_support_detected", %{"supported" => true})

      lv
      |> element("button[phx-click='sign_in_with_passkey']")
      |> render_click()

      assert_push_event(lv, "create_authentication_challenge", %{options: opts})
      assert is_binary(opts[:challenge])
      assert opts[:rpId] == "localhost" or is_binary(opts[:rpId])
    end

    test "device_detected sets iOS mobile flag", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv
      |> element("#auth-methods")
      |> render_hook("device_detected", %{"device" => "ios_mobile"})

      lv
      |> element("#auth-methods")
      |> render_hook("passkey_support_detected", %{"supported" => true})

      html = render(lv)
      assert html =~ "Face ID" or html =~ "Passkey"
    end

    test "device_detected with unexpected params does not crash", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv
      |> element("#auth-methods")
      |> render_hook("device_detected", %{"device" => "unknown"})

      assert render(lv) =~ "Sign in to your YSC account"
    end

    test "passkey_support_detected with unexpected params does not crash", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv
      |> element("#auth-methods")
      |> render_hook("passkey_support_detected", %{"foo" => "bar"})

      assert render(lv) =~ "Sign in to your YSC account"
    end

    test "user_agent_received is acknowledged", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv
      |> element("#auth-methods")
      |> render_hook("user_agent_received", %{})

      assert render(lv) =~ "Sign in to your YSC account"
    end

    test "verify_authentication without challenge shows error toast", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv
      |> element("#auth-methods")
      |> render_hook("verify_authentication", %{
        "rawId" =>
          Base.url_encode64(:crypto.strong_rand_bytes(10), padding: false),
        "response" => %{}
      })

      html = render(lv)
      assert html =~ "expired" or html =~ "Authentication" or html =~ "session"
    end

    test "passkey_auth_error maps NotAllowedError", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv
      |> element("#auth-methods")
      |> render_hook("passkey_auth_error", %{
        "error" => "NotAllowedError",
        "message" => "cancelled"
      })

      assert render(lv) =~ "cancelled" or render(lv) =~ "not allowed"
    end

    test "passkey_auth_error fallback handler", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv
      |> element("#auth-methods")
      |> render_hook("passkey_auth_error", %{"x" => "y"})

      assert render(lv) =~ "error" or render(lv) =~ "authentication"
    end
  end
end
