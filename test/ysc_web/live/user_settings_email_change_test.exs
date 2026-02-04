defmodule YscWeb.UserSettingsEmailChangeTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Repo

  describe "email change - initial request" do
    test "shows email form without current password field", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/users/settings")

      # Should show email field but not current_password field
      assert has_element?(view, "#email_form")
      refute html =~ "Current password"
      assert html =~ "You will be asked to verify your identity"
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
      assert result =~ "Email address is the same"
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

      # Trigger re-auth modal
      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      # Submit correct password
      render_submit(view, "reauth_with_password", %{
        password: valid_user_password()
      })

      # Should close modal and redirect to email verification
      refute has_element?(view, "#reauth-modal")
    end

    test "shows error with incorrect password", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      # Trigger re-auth modal
      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      # Submit wrong password
      result =
        render_submit(view, "reauth_with_password", %{
          password: "wrongpassword"
        })

      # Should still show modal with error
      assert has_element?(view, "#reauth-modal")
      assert result =~ "Invalid password"
    end

    test "sends verification code to new email after successful re-auth", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      new_email = "newemail@example.com"

      # Request email change
      render_submit(view, "request_email_change", %{
        user: %{email: new_email}
      })

      # Re-authenticate with password
      render_submit(view, "reauth_with_password", %{
        password: valid_user_password()
      })

      # Verify code was stored
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

      # Trigger re-auth modal
      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      # Click passkey button
      render_click(view, "reauth_with_passkey")

      # Should have generated a challenge
    end

    test "processes email change after passkey verification", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      new_email = "newemail@example.com"

      # Request email change
      render_submit(view, "request_email_change", %{
        user: %{email: new_email}
      })

      # Initiate passkey auth
      render_click(view, "reauth_with_passkey")

      # Simulate successful passkey verification
      render_hook(view, "verify_authentication", %{
        "id" => "test-credential-id",
        "rawId" => Base.encode64("test-raw-id"),
        "type" => "public-key",
        "response" => %{
          "authenticatorData" => Base.encode64("test-auth-data"),
          "clientDataJSON" => Base.encode64("test-client-data"),
          "signature" => Base.encode64("test-signature")
        }
      })

      # Should redirect to email verification
      refute has_element?(view, "#reauth-modal")
    end

    test "handles passkey authentication error", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      # Request email change
      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      # Simulate passkey error
      result =
        render_hook(view, "passkey_auth_error", %{
          "error" => "NotAllowedError",
          "message" => "User cancelled"
        })

      # Should still show modal with error
      assert has_element?(view, "#reauth-modal")
      assert result =~ "Passkey authentication failed"
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

    test "can change email using passkey authentication", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      # Request email change
      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      # Use passkey
      render_click(view, "reauth_with_passkey")

      # Simulate passkey success
      render_hook(view, "verify_authentication", %{
        "id" => "test-credential-id",
        "type" => "public-key",
        "response" => %{
          "authenticatorData" => Base.encode64("test-data"),
          "clientDataJSON" => Base.encode64("test-data"),
          "signature" => Base.encode64("test-sig")
        }
      })

      # Should redirect to verification
    end
  end

  describe "email change - modal cancellation" do
    test "can cancel re-auth modal", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      # Trigger re-auth modal
      render_submit(view, "request_email_change", %{
        user: %{email: "newemail@example.com"}
      })

      assert has_element?(view, "#reauth-modal")

      # Cancel modal
      render_click(view, "cancel_reauth")

      # Modal should close and pending change cleared
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

      # Complete email change request with re-auth
      render_submit(view, "request_email_change", %{user: %{email: new_email}})

      render_submit(view, "reauth_with_password", %{
        password: valid_user_password()
      })

      # Should show email verification modal
      assert has_element?(view, "#email-verification-modal")
      assert render(view) =~ "Verify Your New Email Address"
      assert render(view) =~ new_email
    end

    test "completes email change after code verification", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      new_email = "newemail@example.com"

      # Complete re-auth
      render_submit(view, "request_email_change", %{user: %{email: new_email}})

      render_submit(view, "reauth_with_password", %{
        password: valid_user_password()
      })

      # Get verification code
      code = Accounts.get_email_verification_code(user)

      # Submit verification code
      render_submit(view, "verify_email_code", %{verification_code: code})

      # Email should be updated
      updated_user = Repo.reload!(user)
      assert updated_user.email == new_email
      assert updated_user.email_verified_at != nil
    end
  end
end
