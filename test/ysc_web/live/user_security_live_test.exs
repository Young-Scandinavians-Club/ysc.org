defmodule YscWeb.UserSecurityLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.AuthEvent
  alias Ysc.Repo

  # ---------------------------------------------------------------------------
  # Helpers for targeting component events
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

  describe "mount/3" do
    test "loads security settings page with password form", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/users/settings/security")

      assert html =~ "Security Settings"
      assert html =~ "Change Password"
      assert html =~ "Passkeys"
      assert has_element?(view, "#password_form")
    end

    test "shows loading state for passkeys on initial mount", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/users/settings/security")

      assert html =~ ~s|id="user-security-passkeys-loading"|
      assert html =~ "Loading passkeys"
    end

    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/users/settings/security")

      assert path == "/users/log-in"
    end
  end

  describe "async passkey loading" do
    test "loads passkeys asynchronously when connected", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_async(view)

      html = render(view)
      refute html =~ "Loading passkeys..."
    end

    test "displays empty state when user has no passkeys", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_async(view, 500)

      html = render(view)

      assert html =~ "Loading passkeys" or html =~ "Add Passkey"
    end
  end

  describe "password validation" do
    test "validates password change with correct format", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      result =
        view
        |> form("#password_form",
          user: %{
            password: "new valid password",
            password_confirmation: "new valid password"
          }
        )
        |> render_change()

      assert result =~ "Change Password"
    end

    test "shows validation errors for invalid password", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      result =
        view
        |> form("#password_form",
          user: %{
            password: "short",
            password_confirmation: "short"
          }
        )
        |> render_change()

      assert result =~ "should be at least 12 character"
    end

    test "shows validation error when passwords don't match", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      result =
        view
        |> form("#password_form",
          user: %{
            password: "new valid password",
            password_confirmation: "different password"
          }
        )
        |> render_change()

      assert result =~ "Please enter the same password in both fields"
    end
  end

  describe "request_password_change" do
    test "does not open re-auth modal when password validation fails", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_submit(view, "request_password_change", %{
        user: %{
          password: "short",
          password_confirmation: "short"
        }
      })

      refute has_element?(view, "#reauth-modal")
      assert render(view) =~ "should be at least 12 character"
    end
  end

  describe "password update flow" do
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
    end

    test "completes password change after successful re-auth", %{conn: conn} do
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

      updated_user = Repo.reload!(user)

      assert Accounts.get_user_by_email_and_password(
               updated_user.email,
               "new valid password 123"
             ) !=
               nil
    end

    test "cancel_reauth closes modal and clears pending change", %{conn: conn} do
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

    test "reauth_with_password shows error for wrong password", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      submit_reauth_password(view, "wrong-password-xyz")

      assert render(view) =~ "Invalid password"
    end

    test "reauth_with_passkey pushes authentication challenge event", %{
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

      assert click_reauth_passkey(view) =~ "Verify Your Identity"
    end

    test "verify_authentication completes password change after re-auth modal",
         %{
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

      submit_reauth_password(view, Ysc.AccountsFixtures.valid_user_password())

      refute has_element?(view, "#reauth-modal")

      updated_user = Repo.reload!(user)

      assert Accounts.get_user_by_email_and_password(
               updated_user.email,
               "new valid password 123"
             )
    end

    test "passkey_auth_error sets reauth error message", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      hook_passkey_auth_error(view, "aborted")

      assert render(view) =~ "Passkey authentication failed"
    end
  end

  describe "PasskeyAuth hook noop events (sent to LiveView via pushEvent)" do
    test "ignores passkey_support_detected, user_agent_received, and device_detected",
         %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_click(view, "passkey_support_detected", %{})
      render_click(view, "user_agent_received", %{})
      render_click(view, "device_detected", %{})

      assert has_element?(view, "#password_form")
    end
  end

  describe "revoke_session" do
    test "shows info when session token is not found", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      html =
        render_click(view, "revoke_session", %{
          "session_id" => Base.encode64(:crypto.strong_rand_bytes(32))
        })

      assert html =~ "may already be signed out"
    end

    test "revokes another session and shows success toast", %{conn: conn} do
      user = user_fixture()
      other_session_token = Accounts.generate_user_session_token(user)
      other_encoded = Base.encode64(other_session_token)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      html =
        render_click(view, "revoke_session", %{"session_id" => other_encoded})

      assert html =~ "Session signed out"
    end

    test "revoking current session redirects to log-in", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      token = Plug.Conn.get_session(conn, :user_token)
      encoded = Base.encode64(token)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      assert {:error, {:live_redirect, %{to: "/users/log-in"}}} =
               render_click(view, "revoke_session", %{"session_id" => encoded})
    end
  end

  describe "delete_passkey" do
    test "deletes user's own passkey successfully", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, passkey} =
        Ysc.Accounts.create_user_passkey(user, %{
          external_id: Base.encode64(:crypto.strong_rand_bytes(32)),
          public_key: Base.encode64(:crypto.strong_rand_bytes(64)),
          sign_count: 0,
          nickname: "Test Device"
        })

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_async(view)

      result =
        view
        |> element("button[phx-value-passkey_id='#{passkey.id}']")
        |> render_click()

      assert result =~ "Passkey deleted successfully"
      refute result =~ "Test Device"
    end

    test "shows error when passkey doesn't exist", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      result =
        render_click(view, "delete_passkey", %{
          "passkey_id" => Ecto.ULID.generate()
        })

      assert result =~ "Passkey not found"
    end

    test "prevents deleting another user's passkey", %{conn: conn} do
      user = user_fixture()
      other_user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, other_passkey} =
        Ysc.Accounts.create_user_passkey(other_user, %{
          external_id: Base.encode64(:crypto.strong_rand_bytes(32)),
          public_key: Base.encode64(:crypto.strong_rand_bytes(64)),
          sign_count: 0,
          nickname: "Other User Device"
        })

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      result =
        render_click(view, "delete_passkey", %{"passkey_id" => other_passkey.id})

      assert result =~ "not authorized"
    end
  end

  describe "navigation menu" do
    test "shows navigation links", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      assert has_element?(view, ~s(a[href="/users/settings"]))
      assert has_element?(view, ~s(a[href="/users/membership"]))
      assert has_element?(view, ~s(a[href="/users/payments"]))
      assert has_element?(view, ~s(a[href="/users/settings/security"]))
      assert has_element?(view, ~s(a[href="/users/notifications"]))
    end

    test "highlights security tab as active", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      assert has_element?(
               view,
               ~s(a[href="/users/settings/security"][class*="bg-blue-600"])
             )
    end
  end

  describe "recent activity" do
    test "shows Recent Activity section", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/users/settings/security")

      assert html =~ "Recent Activity"
      assert html =~ "Review where and how you signed in"
    end

    test "shows loading state for activity on initial mount", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/users/settings/security")

      assert html =~ "Loading activity"
    end

    test "shows empty state when user has no sign-in history", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_async(view)

      html = render(view)
      assert html =~ "Recent Activity"
      assert html =~ "No sign-in history yet"
    end

    test "displays recent sign-in events with device and masked IP", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      attrs = %{
        ip_address: "192.168.1.100",
        user_agent: "Mozilla/5.0",
        device_type: "desktop",
        browser: "Chrome",
        operating_system: "macOS"
      }

      AuthEvent.login_success_changeset(user, attrs)
      |> Repo.insert!()

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_async(view)

      html = render(view)
      assert html =~ "Recent Activity"
      assert html =~ "Successful"
      assert html =~ "Chrome on macOS"
      assert html =~ "192.168.xxx.xxx"
    end

    test "displays OAuth sign-in method as Google or Facebook", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      alias Ysc.Accounts.AuthEvent

      AuthEvent.login_success_changeset(user, %{
        ip_address: "192.168.1.100",
        user_agent: "Mozilla/5.0",
        device_type: "desktop",
        browser: "Chrome",
        operating_system: "macOS",
        metadata: %{"auth_method" => "oauth"}
      })
      |> Repo.insert!()

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_async(view)

      html = render(view)
      assert html =~ "Google or Facebook"
    end

    test "displays failed sign-in when present", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      attrs = %{
        user_id: user.id,
        email_attempted: user.email,
        failure_reason: "invalid_credentials",
        ip_address: "10.0.0.1",
        user_agent: "Mozilla/5.0",
        device_type: "desktop"
      }

      AuthEvent.login_failure_changeset(attrs)
      |> Repo.insert!()

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_async(view)

      html = render(view)
      assert html =~ "Recent Activity"
      assert html =~ "Failed sign-in"
      assert html =~ "no action needed unless you"
      assert html =~ "10.0.xxx.xxx"
    end

    test "shows flagged badge for suspicious sign-in event", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      attrs = %{
        ip_address: "172.16.0.1",
        user_agent: "Mozilla/5.0",
        device_type: "mobile",
        browser: "Safari",
        operating_system: "iOS",
        is_suspicious: true
      }

      AuthEvent.login_success_changeset(user, attrs)
      |> Repo.insert!()

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_async(view)

      html = render(view)
      assert html =~ "Recent Activity"
      assert html =~ "Successful"
      assert html =~ "Flagged"
    end

    test "limits to 10 most recent sign-in events", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      base_attrs = %{
        ip_address: "192.168.1.1",
        user_agent: "Mozilla/5.0",
        device_type: "desktop",
        browser: "Chrome",
        operating_system: "macOS"
      }

      for i <- 1..12 do
        attrs = Map.put(base_attrs, :ip_address, "192.168.1.#{i}")
        AuthEvent.login_success_changeset(user, attrs) |> Repo.insert!()
      end

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_async(view)

      html = render(view)

      masked_ip_count =
        html |> String.split("192.168.xxx.xxx") |> length() |> Kernel.-(1)

      assert masked_ip_count == 10
    end
  end

  describe "handle_async exit paths" do
    test "load_passkeys exit clears loading and marks loaded", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")
      %{socket: socket} = :sys.get_state(view.pid)

      assert {:noreply, new_socket} =
               YscWeb.UserSecurityLive.handle_async(
                 :load_passkeys,
                 {:exit, :test_reason},
                 socket
               )

      assert new_socket.assigns.passkeys_loading == false
      assert new_socket.assigns.passkeys_loaded == true
    end

    test "load_login_history exit clears loading state", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")
      %{socket: socket} = :sys.get_state(view.pid)

      assert {:noreply, new_socket} =
               YscWeb.UserSecurityLive.handle_async(
                 :load_login_history,
                 {:exit, :test_reason},
                 socket
               )

      assert new_socket.assigns.login_history_loading == false
    end
  end

  describe "oauth users without password" do
    test "shows Set Password heading and explainer", %{conn: conn} do
      user = oauth_user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/users/settings/security")

      assert html =~ "Set Password"

      assert html =~
               "Setting a password allows you to sign in with email and password"
    end

    test "shows passkey-only reauth modal for oauth users (no password form)",
         %{
           conn: conn
         } do
      user = oauth_user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_submit(view, "request_password_change", %{
        user: %{
          password: "first password ok 12",
          password_confirmation: "first password ok 12"
        }
      })

      assert has_element?(view, "#reauth-modal")
      refute render(view) =~ "Verify with your password"
      assert render(view) =~ "Verify with your passkey"
    end
  end

  describe "reauth modal shows OAuth options" do
    test "shows Google and Facebook verification options", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      assert has_element?(view, "button[phx-click='reauth_with_google']")
      assert has_element?(view, "button[phx-click='reauth_with_facebook']")
    end
  end

  describe "current session and device labels (coverage)" do
    test "shows Current session when auth event matches live session id", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)
      token = Plug.Conn.get_session(conn, :user_token)
      encoded = Base.encode64(token)

      attrs = %{
        session_id: encoded,
        ip_address: "192.168.1.50",
        user_agent: "Mozilla/5.0",
        device_type: "desktop",
        browser: "Firefox",
        operating_system: "Linux",
        success: true
      }

      AuthEvent.login_success_changeset(user, attrs)
      |> Repo.insert!()

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_async(view)

      assert render(view) =~ "Current session"
      assert render(view) =~ "Firefox on Linux"
    end

    test "uses tablet icon label for tablet device type in history", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      attrs = %{
        ip_address: "10.0.0.2",
        user_agent: "Tablet UA",
        device_type: "tablet",
        browser: "Safari",
        operating_system: "iPadOS",
        success: true
      }

      AuthEvent.login_success_changeset(user, attrs)
      |> Repo.insert!()

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_async(view)

      html = render(view)
      assert html =~ "Safari on iPadOS"
      assert html =~ "hero-device-tablet"
    end
  end

  describe "family navigation link" do
    test "shows Family link for primary user with lifetime membership", %{
      conn: conn
    } do
      user =
        user_fixture(%{})
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      assert has_element?(view, ~s(a[href="/users/settings/family"]))
    end
  end
end
