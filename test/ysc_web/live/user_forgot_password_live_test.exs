defmodule YscWeb.UserForgotPasswordLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Repo

  describe "Forgot password page" do
    test "renders email page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/reset-password")

      assert html =~ "Forgot your password?"
      assert html =~ "email you a link to reset your password"
      assert html =~ "Email me a reset link"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/reset-password")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end
  end

  describe "Reset link" do
    setup do
      %{user: user_fixture()}
    end

    test "sends reset token when user enters Gmail alias of legacy dotted address",
         %{
           conn: conn,
           user: _default_user
         } do
      tag = Integer.to_string(System.unique_integer([:positive]))
      dotted_email = "forgot.#{tag}@gmail.com"
      canonical_email = "forgot#{tag}@gmail.com"

      %{id: id} = legacy_gmail_user_fixture(%{email: dotted_email})

      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", user: %{"email" => canonical_email})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "password reset link"

      assert Repo.get_by!(Accounts.UserToken, user_id: id).context ==
               "reset_password"
    end

    test "sends a new reset password token", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", user: %{"email" => user.email})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "password reset link"

      assert Repo.get_by!(Accounts.UserToken, user_id: user.id).context ==
               "reset_password"
    end

    test "does not send reset password token if email is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, conn} =
        lv
        |> form("#reset_password_form",
          user: %{"email" => "unknown@example.com"}
        )
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "password reset link"

      assert Repo.all(Accounts.UserToken) == []
    end
  end
end
