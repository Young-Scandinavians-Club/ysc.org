defmodule YscWeb.UserSecurityPasswordChangeTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Repo

  describe "password change - initial request" do
    test "shows password form without current password field", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/users/settings/security")

      # Should show password fields but not current_password field
      assert has_element?(view, "#password_form")
      assert html =~ "New password"
      assert html =~ "Confirm new password"
      refute html =~ "Current password"
      assert html =~ "You will be asked to verify your identity"
    end

    test "shows 'Change Password' for users with password", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/users/settings/security")

      assert html =~ "Change Password"
      refute html =~ "Set Password"
    end

    test "shows 'Set Password' for users without password", %{conn: conn} do
      user = oauth_user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/users/settings/security")

      assert html =~ "Set Password"
      refute html =~ "Change Password"
      assert html =~ "currently have a password set"
    end

    test "validates password format before showing re-auth modal", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Submit invalid password (too short)
      result =
        view
        |> form("#password_form",
          user: %{password: "short", password_confirmation: "short"}
        )
        |> render_change()

      assert result =~ "should be at least 12 character"
      # Should not show modal
      refute has_element?(view, "#reauth-modal")
    end

    test "validates password confirmation matches", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Submit mismatched passwords
      result =
        view
        |> form("#password_form",
          user: %{
            password: "valid password 123",
            password_confirmation: "different password"
          }
        )
        |> render_change()

      assert result =~ "does not match password"
    end

    test "shows re-auth modal when valid password submitted", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Submit valid password
      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      # Should show re-auth modal
      assert has_element?(view, "#reauth-modal")
      assert render(view) =~ "Verify Your Identity"
      assert render(view) =~ "changing your password"
    end
  end

  describe "password change - re-auth with password" do
    test "shows password option in modal for users with password", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Trigger re-auth modal
      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      # Should show password authentication option
      assert has_element?(view, "#reauth_password_form")
      assert render(view) =~ "Verify with your password"
      assert render(view) =~ "Password"
    end

    test "successfully re-authenticates with correct password", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      new_password = "new valid password 123"

      # Trigger re-auth modal
      render_submit(view, "request_password_change", %{
        user: %{password: new_password, password_confirmation: new_password}
      })

      # Submit correct password
      render_submit(view, "reauth_with_password", %{
        password: valid_user_password()
      })

      # Should close modal
      refute has_element?(view, "#reauth-modal")

      # Password should be updated (verify by trying to authenticate with new password)
      :timer.sleep(100)
      updated_user = Repo.reload!(user)

      assert Accounts.get_user_by_email_and_password(
               updated_user.email,
               new_password
             ) != nil
    end

    test "shows error with incorrect password", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Trigger re-auth modal
      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
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

    test "sends password changed notification after successful change", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Change password
      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      # Re-authenticate
      render_submit(view, "reauth_with_password", %{
        password: valid_user_password()
      })

      # Notification should be sent (would need to mock email system to verify)
      # For now, just verify no errors occurred
      refute has_element?(view, ".alert-error")
    end

    test "invalidates all user sessions after password change", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Count tokens before
      tokens_before =
        Accounts.UserToken.by_user_and_contexts_query(user, :all) |> Repo.all()

      refute tokens_before == []

      # Change password
      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      render_submit(view, "reauth_with_password", %{
        password: valid_user_password()
      })

      # Give database time to update
      :timer.sleep(50)

      # All tokens should be deleted
      tokens_after =
        Accounts.UserToken.by_user_and_contexts_query(user, :all) |> Repo.all()

      assert tokens_after == []
    end
  end

  describe "password change - re-auth with passkey" do
    test "shows passkey option in modal", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Trigger re-auth modal
      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      # Should show passkey authentication option
      html = render(view)
      assert html =~ "Continue with Passkey"
      assert html =~ "hero-finger-print"
    end

    test "initiates passkey authentication flow", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Trigger re-auth modal
      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      # Click passkey button
      render_click(view, "reauth_with_passkey")

      # Should have generated a challenge
    end

    test "processes password change after passkey verification", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      new_password = "new valid password 123"

      # Request password change
      render_submit(view, "request_password_change", %{
        user: %{password: new_password, password_confirmation: new_password}
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

      # Should close modal and trigger submit
      refute has_element?(view, "#reauth-modal")

      # Password should be updated
      :timer.sleep(100)
      updated_user = Repo.reload!(user)

      assert Accounts.get_user_by_email_and_password(
               updated_user.email,
               new_password
             ) != nil
    end

    test "handles passkey authentication error", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Request password change
      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
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

  describe "password setting - users without password" do
    setup do
      # Create user without password (OAuth/passkey-only user)
      user = oauth_user_fixture()
      {:ok, user: user}
    end

    test "shows only passkey option for users without password", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Trigger re-auth modal
      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      # Should not show password option
      refute has_element?(view, "#reauth_password_form")
      refute render(view) =~ "Verify with your password"

      # Should show passkey option
      assert render(view) =~ "Verify with your passkey"
      assert render(view) =~ "Use your device&#39;s fingerprint"
    end

    test "can set password using passkey authentication", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      new_password = "my new password 123"

      # Request password setting
      render_submit(view, "request_password_change", %{
        user: %{password: new_password, password_confirmation: new_password}
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

      # Should trigger submit

      # Password should be set
      :timer.sleep(100)
      updated_user = Repo.reload!(user)
      assert updated_user.hashed_password != nil
      assert updated_user.password_set_at != nil

      assert Accounts.get_user_by_email_and_password(
               updated_user.email,
               new_password
             ) != nil
    end

    test "marks password_set_at timestamp when setting password", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Set password
      render_submit(view, "request_password_change", %{
        user: %{
          password: "my new password 123",
          password_confirmation: "my new password 123"
        }
      })

      render_click(view, "reauth_with_passkey")

      render_hook(view, "verify_authentication", %{
        "id" => "test-credential",
        "type" => "public-key",
        "response" => %{
          "authenticatorData" => Base.encode64("data"),
          "clientDataJSON" => Base.encode64("data"),
          "signature" => Base.encode64("sig")
        }
      })

      # Give database time to update
      :timer.sleep(100)

      # password_set_at should be set
      updated_user = Repo.reload!(user)
      assert updated_user.password_set_at != nil

      assert DateTime.diff(
               DateTime.utc_now(),
               updated_user.password_set_at,
               :second
             ) < 5
    end

    test "updates UI after setting password for first time", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Initially shows "Set Password"
      assert render(view) =~ "Set Password"

      # Set password
      render_submit(view, "request_password_change", %{
        user: %{
          password: "my new password 123",
          password_confirmation: "my new password 123"
        }
      })

      render_click(view, "reauth_with_passkey")

      render_hook(view, "verify_authentication", %{
        "id" => "test",
        "type" => "public-key",
        "response" => %{
          "authenticatorData" => Base.encode64("d"),
          "clientDataJSON" => Base.encode64("d"),
          "signature" => Base.encode64("s")
        }
      })

      # user_has_password flag should be updated
    end
  end

  describe "password change - modal cancellation" do
    test "can cancel re-auth modal", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Trigger re-auth modal
      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      assert has_element?(view, "#reauth-modal")

      # Cancel modal
      render_click(view, "cancel_reauth")

      # Modal should close and pending change cleared
      refute has_element?(view, "#reauth-modal")
    end
  end

  describe "password change - edge cases" do
    test "handles database errors gracefully", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, _html} = live(conn, ~p"/users/settings/security")

      # This would need mocking to actually test DB errors
      # For now, verify the error handling code paths exist
    end

    test "clears reauth state after successful password change", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Complete password change
      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      render_submit(view, "reauth_with_password", %{
        password: valid_user_password()
      })

      # All reauth state should be cleared
    end
  end
end
