defmodule YscWeb.UserForgotPasswordRateLimitTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "forgot password identifier rate limiting" do
    setup do
      Application.put_env(:ysc, Ysc.AuthRateLimit,
        ip_limit: 10_000,
        identifier_limit: 2
      )

      on_exit(fn ->
        Application.put_env(:ysc, Ysc.AuthRateLimit,
          ip_limit: 10_000,
          identifier_limit: 10_000
        )
      end)

      :ok
    end

    test "shows error and redirects when identifier limit exceeded for same email",
         %{
           conn: conn
         } do
      email =
        "rate_limit_forgot_#{System.unique_integer([:positive])}@example.com"

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
end
