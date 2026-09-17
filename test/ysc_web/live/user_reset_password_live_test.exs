defmodule YscWeb.UserResetPasswordLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts

  setup do
    user =
      user_fixture(%{
        phone_number: "+14159098268",
        first_name: "Test",
        last_name: "User"
      })

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_reset_password_instructions(user, url)
      end)

    %{token: token, user: user}
  end

  describe "Reset password page" do
    test "renders reset password with valid token", %{conn: conn, token: token} do
      {:ok, lv, html} = live(conn, ~p"/users/reset-password/#{token}")

      assert html =~ "Reset Password"
      assert has_element?(lv, "#reset-password-home-logo")
    end

    test "does not render reset password with invalid token", %{conn: conn} do
      {:error, {:redirect, to}} = live(conn, ~p"/users/reset-password/invalid")

      assert to[:to] == ~p"/"

      assert to[:flash]["error"] ==
               "This password reset link no longer works. It may have expired — request a new one from the sign-in page."
    end

    test "renders errors for invalid data", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      result =
        lv
        |> element("#reset_password_form")
        |> render_change(
          user: %{
            "password" => "secret12",
            "password_confirmation" => "secret123456"
          }
        )

      assert result =~ "should be at least 12 character"
      assert result =~ "Please enter the same password in both fields"
    end
  end

  describe "Reset Password" do
    test "resets password once", %{conn: conn, token: token, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      {:ok, conn} =
        lv
        |> form("#reset_password_form",
          user: %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      refute get_session(conn, :user_token)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Password updated. Sign in with your new password."

      assert Accounts.get_user_by_email_and_password(
               user.email,
               "new valid password"
             )
    end

    test "does not reset password on invalid data", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      result =
        lv
        |> form("#reset_password_form",
          user: %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        )
        |> render_submit()

      assert result =~ "Reset Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "Please enter the same password in both fields"
    end

    test "does not reset password after the token is consumed by another submit",
         %{
           conn: conn,
           token: token,
           user: user
         } do
      {:ok, attacker_lv, _html} =
        live(conn, ~p"/users/reset-password/#{token}")

      {:ok, victim_lv, _html} =
        live(build_conn(), ~p"/users/reset-password/#{token}")

      {:ok, _victim_conn} =
        victim_lv
        |> form("#reset_password_form",
          user: %{
            "password" => "victim reset password",
            "password_confirmation" => "victim reset password"
          }
        )
        |> render_submit()
        |> follow_redirect(build_conn(), ~p"/users/log-in")

      {:ok, attacker_conn} =
        attacker_lv
        |> form("#reset_password_form",
          user: %{
            "password" => "attacker takeover password",
            "password_confirmation" => "attacker takeover password"
          }
        )
        |> render_submit()
        |> follow_redirect(build_conn(), ~p"/users/log-in")

      assert Phoenix.Flash.get(attacker_conn.assigns.flash, :error) ==
               "This password reset link no longer works. It may have expired — request a new one from the sign-in page."

      assert Accounts.get_user_by_email_and_password(
               user.email,
               "victim reset password"
             )

      refute Accounts.get_user_by_email_and_password(
               user.email,
               "attacker takeover password"
             )
    end
  end
end
