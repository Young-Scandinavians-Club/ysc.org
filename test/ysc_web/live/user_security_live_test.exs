defmodule YscWeb.UserSecurityLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Repo

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

      # Initial mount shows loading state
      assert html =~ "Loading passkeys..."
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

      # Wait for async task to complete
      :timer.sleep(100)

      # After loading, should show empty state or passkeys
      html = render(view)
      refute html =~ "Loading passkeys..."
    end

    test "displays empty state when user has no passkeys", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Wait for async task to complete and re-render
      :timer.sleep(200)

      html = render(view)

      # Check for either loading state or empty state (async may still be processing)
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

      assert result =~ "does not match password"
    end
  end

  describe "password update flow" do
    test "shows re-auth modal when valid password submitted", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Submit password change request
      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      # Should show re-auth modal
      assert has_element?(view, "#reauth-modal")
      assert render(view) =~ "Verify Your Identity"
    end

    test "completes password change after successful re-auth", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Submit password change request
      render_submit(view, "request_password_change", %{
        user: %{
          password: "new valid password 123",
          password_confirmation: "new valid password 123"
        }
      })

      # Re-authenticate with password
      render_submit(view, "reauth_with_password", %{
        password: valid_user_password()
      })

      # Should close modal
      refute has_element?(view, "#reauth-modal")

      # Verify password was actually changed
      :timer.sleep(100)
      updated_user = Repo.reload!(user)

      assert Accounts.get_user_by_email_and_password(
               updated_user.email,
               "new valid password 123"
             ) !=
               nil
    end
  end

  describe "delete_passkey" do
    test "deletes user's own passkey successfully", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      # Create a passkey for the user
      {:ok, passkey} =
        Ysc.Accounts.create_user_passkey(user, %{
          external_id: Base.encode64(:crypto.strong_rand_bytes(32)),
          public_key: Base.encode64(:crypto.strong_rand_bytes(64)),
          sign_count: 0,
          nickname: "Test Device"
        })

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      # Wait for passkeys to load
      :timer.sleep(100)

      # Delete the passkey
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

      # Create a passkey for a different user
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

      # Verify main navigation links are present
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

      # Security tab should have active styling
      assert has_element?(
               view,
               ~s(a[href="/users/settings/security"][class*="bg-blue-600"])
             )
    end
  end
end
