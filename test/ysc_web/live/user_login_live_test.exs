defmodule YscWeb.UserLoginLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  describe "Log in page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Sign in to your YSC account"
      assert html =~ "Apply for a membership"
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

      html = render(lv)
      assert html =~ "Sign in with Passkey" || html =~ "passkey"
    end

    test "hides passkey button when not supported", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Simulate no passkey support
      lv
      |> element("#auth-methods")
      |> render_hook("passkey_support_detected", %{"supported" => false})

      html = render(lv)
      # Passkey button should not be visible when not supported
      refute html =~ "Sign in with Passkey"
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
end
