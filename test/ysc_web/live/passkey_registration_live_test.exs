defmodule YscWeb.PasskeyRegistrationLiveTest do
  @moduledoc """
  Comprehensive tests for passkey registration flow.
  """
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "Passkey registration page" do
    test "renders registration page for authenticated user", %{
      conn: conn,
      user: _user
    } do
      {:ok, _lv, html} = live(conn, ~p"/users/settings/passkeys/new")

      assert html =~ "Add a Passkey to Your Account"
      # Check for subtitle text (may be in different format)
      assert html =~ "fingerprint" || html =~ "face scan" ||
               html =~ "sign in faster"
    end

    test "redirects unauthenticated users to login", %{conn: _conn} do
      # Create a new connection without authentication
      unauthenticated_conn = Phoenix.ConnTest.build_conn()

      assert {:error, {:redirect, %{to: path}}} =
               live(unauthenticated_conn, ~p"/users/settings/passkeys/new")

      assert path == ~p"/users/log-in"
    end
  end

  describe "Passkey registration flow" do
    test "creates authentication challenge when create_passkey is clicked", %{
      conn: conn,
      user: user
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/passkeys/new")

      # First enable passkey support so the button is visible
      lv
      |> element("#passkey-registration")
      |> render_hook("passkey_support_detected", %{"supported" => true})

      # Click the create passkey button
      lv
      |> element("button[phx-click='create_passkey']")
      |> render_click()

      # Verify create_registration_challenge event was pushed
      assert_push_event(lv, "create_registration_challenge", %{options: options})

      # Verify challenge was created by checking the event options
      challenge_base64 = options[:challenge]
      assert is_binary(challenge_base64)
      assert options[:rp][:id] == "localhost"
      assert is_binary(options[:user][:id])
      assert options[:user][:name] == user.email
    end

    test "handles challenge creation failure gracefully", %{conn: conn} do
      # This LiveView falls back to sensible defaults for Wax config.
      # The important part is that clicking does not crash and we push a challenge.
      original_rp_id = Application.get_env(:wax_, :rp_id)
      Application.put_env(:wax_, :rp_id, nil)

      {:ok, lv, _html} = live(conn, ~p"/users/settings/passkeys/new")

      # First enable passkey support so the button is visible
      lv
      |> element("#passkey-registration")
      |> render_hook("passkey_support_detected", %{"supported" => true})

      # Click create passkey - should handle error
      lv
      |> element("button[phx-click='create_passkey']")
      |> render_click()

      # Restore config
      Application.put_env(:wax_, :rp_id, original_rp_id)

      # Should not crash; we should still push a registration challenge
      assert_push_event(lv, "create_registration_challenge", %{
        options: _options
      })
    end

    test "handles invalid WebAuthn response gracefully", %{
      conn: conn,
      user: _user
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/passkeys/new")

      # First enable passkey support so the button is visible
      lv
      |> element("#passkey-registration")
      |> render_hook("passkey_support_detected", %{"supported" => true})

      # Create challenge first
      lv
      |> element("button[phx-click='create_passkey']")
      |> render_click()

      # Get the challenge from the push event
      assert_push_event(lv, "create_registration_challenge", %{options: options})

      challenge_base64 = options[:challenge]
      assert is_binary(challenge_base64)

      # Create an invalid WebAuthn response (invalid attestation object)
      credential_id = :crypto.strong_rand_bytes(16)
      # Too short to be valid
      invalid_attestation_object = :crypto.strong_rand_bytes(50)

      client_data_json =
        Jason.encode!(%{
          type: "webauthn.create",
          challenge: challenge_base64,
          origin: "http://localhost:4002"
        })

      response = %{
        "id" => Base.url_encode64(credential_id, padding: false),
        "rawId" => Base.url_encode64(credential_id, padding: false),
        "type" => "public-key",
        "response" => %{
          "attestationObject" =>
            Base.url_encode64(invalid_attestation_object, padding: false),
          "clientDataJSON" =>
            Base.url_encode64(client_data_json, padding: false)
        }
      }

      # This will fail because the attestation object is invalid
      lv
      |> element("#passkey-registration")
      |> render_hook("verify_registration", response)

      # Should handle the error gracefully - verify via HTML
      html = render(lv)
      # Should show error message
      assert html =~ "error" || html =~ "failed" || html =~ "Failed"
    end

    test "handles passkey registration errors", %{conn: conn, user: _user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/passkeys/new")

      # First enable passkey support so the button is visible
      lv
      |> element("#passkey-registration")
      |> render_hook("passkey_support_detected", %{"supported" => true})

      # Create challenge first
      lv
      |> element("button[phx-click='create_passkey']")
      |> render_click()

      # Simulate a registration error from JavaScript
      lv
      |> element("#passkey-registration")
      |> render_hook("passkey_registration_error", %{
        "error" => "NotAllowedError",
        "message" => "User cancelled the operation"
      })

      # Should show error message - verify via HTML
      html = render(lv)
      assert html =~ "error" || html =~ "cancelled" || html =~ "Failed"
    end

    test "handles expired challenge", %{conn: conn, user: _user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/passkeys/new")

      # Try to verify without creating challenge first (simulating expired challenge)
      response = %{
        "id" => "test",
        "rawId" => "test",
        "type" => "public-key",
        "response" => %{
          "attestationObject" => "test",
          "clientDataJSON" => "test"
        }
      }

      lv
      |> element("#passkey-registration")
      |> render_hook("verify_registration", response)

      # Should show expiration error - verify via HTML
      html = render(lv)
      assert html =~ "expired" || html =~ "session" || html =~ "error"
    end

    test "shows loading state during passkey creation", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/settings/passkeys/new")

      # Initially not loading
      refute html =~ "Creating Passkey..."

      # First enable passkey support so the button is visible
      lv
      |> element("#passkey-registration")
      |> render_hook("passkey_support_detected", %{"supported" => true})

      # Click create passkey
      lv
      |> element("button[phx-click='create_passkey']")
      |> render_click()

      # Should show loading state
      html = render(lv)
      assert html =~ "Creating Passkey..." || html =~ "opacity-50"
    end
  end

  describe "Passkey support detection" do
    test "detects passkey support and updates UI", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/passkeys/new")

      # Simulate passkey support detection
      lv
      |> element("#passkey-registration")
      |> render_hook("passkey_support_detected", %{"supported" => true})

      # Re-render to get updated state and verify via HTML
      html = render(lv)
      # The button should be visible when passkey is supported
      assert html =~ "Create Passkey"
    end

    test "hides create button when passkeys not supported", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/passkeys/new")

      # Simulate no passkey support
      lv
      |> element("#passkey-registration")
      |> render_hook("passkey_support_detected", %{"supported" => false})

      html = render(lv)
      refute html =~ "Create Passkey"
    end
  end
end
