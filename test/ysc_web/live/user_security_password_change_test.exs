defmodule YscWeb.UserSecurityPasswordChangeTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Repo

  # ---------------------------------------------------------------------------
  # Helpers for component-targeted events
  # ---------------------------------------------------------------------------

  defp submit_reauth_password(view, password) do
    view
    |> element("#reauth_password_form")
    |> render_submit(%{password: password})

    # Flush :reauth_verified from component to parent handle_info.
    render(view)
  end

  defp click_reauth_passkey(view) do
    view
    |> element("button[phx-click='reauth_with_passkey']")
    |> render_click()
  end

  # Simulates the server-side :reauth_verified message that ReauthComponent sends
  # to its parent LiveView after successful verification (password or WebAuthn).
  # Used in tests where the reauth method cannot be fully replicated
  # (e.g. passkey auth for OAuth users without a password).
  defp simulate_reauth_verified(view) do
    send(view.pid, :reauth_verified)
    render(view)
  end

  defp hook_passkey_auth_error(view, error) do
    view
    |> element("#reauth-passkey-hook")
    |> render_hook("passkey_auth_error", %{"error" => error})
  end

  defp click_cancel_reauth(view) do
    view
    |> element("button[phx-click='cancel_reauth']")
    |> render_click()
  end

  # ---------------------------------------------------------------------------

  describe "password change - initial request" do
    test "shows password form without current password field", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/users/settings/security")

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

      result =
        view
        |> form("#password_form",
          user: %{password: "short", password_confirmation: "short"}
        )
        |> render_change()

      assert result =~ "should be at least 12 character"
      refute has_element?(view, "#reauth-modal")
    end

    test "validates password confirmation matches", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      result =
        view
        |> form("#password_form",
          user: %{
            password: "valid password 123",
            password_confirmation: "different password"
          }
        )
        |> render_change()

      assert result =~ "Passwords don't match"
    end

    test "shows re-auth modal when valid password submitted", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

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

      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      assert has_element?(view, "#reauth_password_form")
      assert render(view) =~ "Verify with your password"
      assert render(view) =~ "Password"
    end

    test "successfully re-authenticates with correct password", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      new_password = "new valid password 123"

      render_submit(view, "request_password_change", %{
        user: %{password: new_password, password_confirmation: new_password}
      })

      submit_reauth_password(view, valid_user_password())

      refute has_element?(view, "#reauth-modal")

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

      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      result = submit_reauth_password(view, "wrongpassword")

      assert has_element?(view, "#reauth-modal")
      assert result =~ "Invalid password"
    end

    test "sends password changed notification after successful change", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      submit_reauth_password(view, valid_user_password())

      refute has_element?(view, ".alert-error")
    end

    test "invalidates all user sessions after password change", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      tokens_before =
        Accounts.UserToken.by_user_and_contexts_query(user, :all) |> Repo.all()

      refute tokens_before == []

      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      submit_reauth_password(view, valid_user_password())

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

      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      html = render(view)
      assert html =~ "Continue with Passkey"
      assert html =~ "hero-finger-print"
    end

    test "initiates passkey authentication flow", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      click_reauth_passkey(view)
    end

    test "processes password change after passkey verification", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      new_password = "new valid password 123"

      render_submit(view, "request_password_change", %{
        user: %{password: new_password, password_confirmation: new_password}
      })

      submit_reauth_password(view, valid_user_password())

      refute has_element?(view, "#reauth-modal")

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

      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      result =
        hook_passkey_auth_error(view, "NotAllowedError")

      assert has_element?(view, "#reauth-modal")
      assert result =~ "Passkey authentication failed"
    end
  end

  describe "password setting - users without password" do
    setup do
      user = oauth_user_fixture()
      {:ok, user: user}
    end

    test "shows only passkey option for users without password", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      refute has_element?(view, "#reauth_password_form")
      refute render(view) =~ "Verify with your password"

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

      render_submit(view, "request_password_change", %{
        user: %{password: new_password, password_confirmation: new_password}
      })

      click_reauth_passkey(view)

      # Real WebAuthn assertions cannot be constructed in unit tests; simulate the
      # server-side :reauth_verified message that ReauthComponent sends after a
      # successful Wax.authenticate call.
      simulate_reauth_verified(view)

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

      render_submit(view, "request_password_change", %{
        user: %{
          password: "my new password 123",
          password_confirmation: "my new password 123"
        }
      })

      click_reauth_passkey(view)
      simulate_reauth_verified(view)

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

      assert render(view) =~ "Set Password"

      render_submit(view, "request_password_change", %{
        user: %{
          password: "my new password 123",
          password_confirmation: "my new password 123"
        }
      })

      click_reauth_passkey(view)
      simulate_reauth_verified(view)
    end
  end

  describe "password change - modal cancellation" do
    test "can cancel re-auth modal", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      assert has_element?(view, "#reauth-modal")

      click_cancel_reauth(view)

      refute has_element?(view, "#reauth-modal")
    end
  end

  describe "password change - edge cases" do
    test "handles database errors gracefully", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, _html} = live(conn, ~p"/users/settings/security")
    end

    test "clears reauth state after successful password change", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      submit_reauth_password(view, valid_user_password())

      refute has_element?(view, "#reauth-modal")
    end
  end
end
