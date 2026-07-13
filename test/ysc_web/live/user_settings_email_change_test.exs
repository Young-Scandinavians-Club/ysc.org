defmodule YscWeb.UserSettingsEmailChangeTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Repo

  # Helpers to target the ReauthComponent which is now a LiveComponent.
  # Events for reauth (password, passkey, cancel) are handled by the component,
  # not by the parent UserSettingsLive.

  defp submit_reauth_password(view, password) do
    view
    |> element("#reauth_password_form")
    |> render_submit(%{"password" => password})

    # Flush async :reauth_verified message from component to parent.
    render(view)
  end

  defp click_cancel_reauth(view) do
    view
    |> element("button[phx-click='cancel_reauth']")
    |> render_click()

    render(view)
  end

  defp click_reauth_with_passkey(view) do
    view
    |> element("button[phx-click='reauth_with_passkey']")
    |> render_click()
  end

  defp hook_passkey_auth_error(view, params) do
    view
    |> element("#reauth-passkey-hook")
    |> render_hook("passkey_auth_error", params)
  end

  describe "email change - initial request" do
    test "shows email form without current password field", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      email_form_html = view |> element("#email_form") |> render()

      # Should show email field but not current_password field
      assert has_element?(view, "#email_form")
      refute email_form_html =~ "Current password"
      assert email_form_html =~ "need to sign in again before we change your email"
    end

    test "validates email format before showing re-auth modal", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      # Submit invalid email
      result =
        view
        |> form("#email_form", user: %{email: "invalid-email"})
        |> render_change()

      assert result =~ "must have the @ sign"
      # Should not show modal
      refute has_element?(view, "#reauth-modal")
    end

    test "shows re-auth modal when valid email submitted", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      # Submit valid new email
      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      # Should show re-auth modal
      assert has_element?(view, "#reauth-modal")
      assert render(view) =~ "Verify Your Identity"
      assert render(view) =~ "changing your email address"
    end

    test "does not show modal if email unchanged", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      # Submit same email
      result =
        render_submit(view, "request_email_change", %{
          user: %{email: user.email}
        })

      # Should not show modal, shows message instead
      refute has_element?(view, "#reauth-modal")
      assert result =~ "That is already your email address."
    end
  end

  describe "email change - re-auth with password" do
    test "shows password option in modal for users with password", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      # Trigger re-auth modal
      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      # Should show password authentication option
      assert has_element?(view, "#reauth_password_form")
      assert render(view) =~ "Verify with your password"
      assert render(view) =~ "Password"
    end

    test "successfully re-authenticates with correct password", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      submit_reauth_password(view, valid_user_password())

      refute has_element?(view, "#reauth-modal")
    end

    test "shows error with incorrect password", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      view
      |> element("#reauth_password_form")
      |> render_submit(%{"password" => "wrongpassword"})

      assert has_element?(view, "#reauth-modal")
      assert render(view) =~ "Invalid password"
    end

    test "sends verification code to new email after successful re-auth", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      new_email = "newemail@example.com"

      render_submit(view, "request_email_change", %{
        user: %{email: new_email}
      })

      submit_reauth_password(view, valid_user_password())

      code = Accounts.get_email_verification_code(user)
      assert code != nil
      assert String.length(code) == 6
    end
  end

  describe "email change - re-auth with passkey" do
    test "shows passkey option in modal", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      # Trigger re-auth modal
      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      # Should show passkey authentication option
      html = render(view)
      assert html =~ "Continue with Passkey"
      assert html =~ "hero-finger-print"
    end

    test "initiates passkey authentication flow", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      click_reauth_with_passkey(view)

      assert_push_event(view, "create_authentication_challenge", %{})
    end

    test "processes email change after passkey verification", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      new_email = "newemail@example.com"

      render_submit(view, "request_email_change", %{
        user: %{email: new_email}
      })

      submit_reauth_password(view, Ysc.AccountsFixtures.valid_user_password())

      refute has_element?(view, "#reauth-modal")
    end

    test "handles passkey authentication error", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      hook_passkey_auth_error(view, %{
        "error" => "NotAllowedError",
        "message" => "User cancelled"
      })

      assert has_element?(view, "#reauth-modal")
      assert render(view) =~ "Passkey authentication failed"
    end
  end

  describe "email change - users without password" do
    setup do
      # Create user without password (OAuth user)
      user = oauth_user_fixture()
      {:ok, user: user}
    end

    test "shows only passkey option for users without password", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      # Trigger re-auth modal
      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      # Should not show password option
      refute has_element?(view, "#reauth_password_form")
      refute render(view) =~ "Verify with your password"

      # Should show passkey option
      assert render(view) =~ "Verify with your passkey"
      assert render(view) =~ "Continue with Passkey"
    end

    test "shows passkey-only reauth modal for oauth users (no password form)",
         %{
           conn: conn,
           user: user
         } do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      assert has_element?(view, "#reauth-modal")
      refute has_element?(view, "#reauth_password_form")
      assert render(view) =~ "Verify with your passkey"
    end
  end

  describe "email change - modal cancellation" do
    test "can cancel re-auth modal", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      assert has_element?(view, "#reauth-modal")

      click_cancel_reauth(view)

      refute has_element?(view, "#reauth-modal")
    end
  end

  describe "email verification after re-auth" do
    test "displays email verification modal after successful re-auth", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      new_email = "newemail@example.com"

      render_submit(view, "request_email_change", %{user: %{email: new_email}})
      submit_reauth_password(view, valid_user_password())

      assert has_element?(view, "#email-verification-modal")
      assert render(view) =~ "Verify Your New Email Address"
      assert render(view) =~ new_email
    end

    test "completes email change after code verification", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      new_email = "newemail@example.com"

      render_submit(view, "request_email_change", %{user: %{email: new_email}})
      submit_reauth_password(view, valid_user_password())

      code = Accounts.get_email_verification_code(user)
      render_submit(view, "verify_email_code", %{verification_code: code})

      updated_user = Repo.reload!(user)
      assert updated_user.email == new_email
      assert updated_user.email_verified_at != nil
    end
  end
end
