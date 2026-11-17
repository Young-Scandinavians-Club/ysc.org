defmodule YscWeb.UserForgotPasswordRateLimitTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "forgot password identifier rate limiting" do
    setup do
      token =
        Ysc.Test.AuthRateLimitHelper.capture!(
          ip_limit: 10_000,
          identifier_limit: 2
        )

      on_exit(fn -> Ysc.Test.AuthRateLimitHelper.restore!(token) end)

      :ok
    end

    test "shows error and redirects when identifier limit exceeded for same email",
         %{
           conn: conn
         } do
      email =
        "rate_limit_forgot_#{System.unique_integer([:positive])}@example.com"

      # Isolate IP counters from parallel auth rate-limit tests in the full suite.
      conn =
        Map.put(
          conn,
          :remote_ip,
          {127, 0, 0, rem(System.unique_integer([:positive]), 254) + 1}
        )

      # First submit: allowed, redirects to /
      {:ok, lv1, _html} = live(conn, ~p"/users/reset-password")

      {:ok, _conn} =
        lv1
        |> form("#reset_password_form", user: %{"email" => email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      # Second submit: allowed, redirects to /
      {:ok, lv2, _html} = live(conn, ~p"/users/reset-password")

      {:ok, _conn} =
        lv2
        |> form("#reset_password_form", user: %{"email" => email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      # Third submit: rate limited, redirects to /users/reset-password with error
      {:ok, lv3, _html} = live(conn, ~p"/users/reset-password")

      {:ok, conn} =
        lv3
        |> form("#reset_password_form", user: %{"email" => email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/reset-password")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Too many attempts"
    end
  end

  describe "forgot password IP rate limiting" do
    setup do
      token =
        Ysc.Test.AuthRateLimitHelper.capture!(
          ip_limit: 2,
          identifier_limit: 10_000
        )

      on_exit(fn -> Ysc.Test.AuthRateLimitHelper.restore!(token) end)

      :ok
    end

    test "shows the IP toast when the client IP budget is exhausted", %{
      conn: conn
    } do
      ip = {127, 0, 1, rem(System.unique_integer([:positive]), 254) + 1}
      conn = Map.put(conn, :remote_ip, ip)

      # The auth plug also calls check_ip on the HTTP mount. Burn one slot so
      # the mount consumes the last allowed hit, then the LiveView submit arm
      # (not the plug) is what returns the toast.
      assert :ok = Ysc.AuthRateLimit.check_ip(ip)

      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      email =
        "ip_limit_forgot_blocked_#{System.unique_integer([:positive])}@example.com"

      {:ok, conn} =
        lv
        |> form("#reset_password_form", user: %{"email" => email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/reset-password")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Too many password reset attempts"
    end
  end
end
