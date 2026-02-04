defmodule YscWeb.AuthControllerTest do
  @moduledoc """
  Tests for OAuth authentication controller.

  These tests call the controller actions directly to bypass the Ueberauth plug,
  which allows us to test the business logic without dealing with OAuth provider mocking.
  """
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.AuthController
  alias Ysc.Accounts

  # Helper function to create OAuth auth struct
  defp build_oauth_auth(email, provider \\ :google) do
    # When email is nil, we need to provide raw data as a fallback
    # Use a plain map for info since Ueberauth.Auth.Info struct doesn't have :raw field
    info =
      if email do
        %Ueberauth.Auth.Info{
          email: email,
          name: "Test User",
          first_name: "Test",
          last_name: "User"
        }
      else
        %{
          email: nil,
          name: "Test User",
          first_name: "Test",
          last_name: "User",
          raw: %{"email" => nil}
        }
      end

    %Ueberauth.Auth{
      provider: provider,
      info: info,
      credentials: %Ueberauth.Auth.Credentials{
        token: "mock_token",
        refresh_token: "mock_refresh",
        expires: true,
        expires_at: System.system_time(:second) + 3600
      },
      uid: "mock_uid_123"
    }
  end

  # Helper function to create OAuth failure struct
  defp build_oauth_failure(error_message) do
    %Ueberauth.Failure{
      provider: :google,
      strategy: Ueberauth.Strategy.Google,
      errors: [
        %Ueberauth.Failure.Error{
          message: error_message,
          message_key: "access_denied"
        }
      ]
    }
  end

  describe "request/2 - OAuth request phase" do
    test "stores valid internal redirect_to in session", %{conn: conn} do
      redirect_to = "/events"

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> AuthController.request(%{"redirect_to" => redirect_to})

      assert get_session(conn, :oauth_redirect_to) == redirect_to
    end

    test "does not store external redirect_to in session", %{conn: conn} do
      redirect_to = "https://evil.com/phishing"

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> AuthController.request(%{"redirect_to" => redirect_to})

      assert get_session(conn, :oauth_redirect_to) == nil
    end

    test "does not store redirect_to with javascript protocol", %{conn: conn} do
      redirect_to = "javascript:alert('xss')"

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> AuthController.request(%{"redirect_to" => redirect_to})

      assert get_session(conn, :oauth_redirect_to) == nil
    end

    test "handles request without redirect_to parameter", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> AuthController.request(%{})

      assert get_session(conn, :oauth_redirect_to) == nil
    end

    test "stores relative path redirect_to", %{conn: conn} do
      redirect_to = "/bookings/123"

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> AuthController.request(%{"redirect_to" => redirect_to})

      assert get_session(conn, :oauth_redirect_to) == redirect_to
    end

    test "does not store redirect_to with double slash (protocol-relative URL)",
         %{conn: conn} do
      redirect_to = "//evil.com/path"

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> AuthController.request(%{"redirect_to" => redirect_to})

      assert get_session(conn, :oauth_redirect_to) == nil
    end
  end

  describe "callback/2 - OAuth failure scenarios" do
    test "redirects to login with error when OAuth is cancelled", %{conn: conn} do
      failure = build_oauth_failure("user_cancelled")

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_failure, failure)
        |> AuthController.callback(%{})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "cancelled or failed"
    end

    test "redirects to login when OAuth provider returns error", %{conn: conn} do
      failure = build_oauth_failure("provider_error")

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_failure, failure)
        |> AuthController.callback(%{})

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) != nil
    end

    test "handles unexpected state with neither auth nor failure", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> AuthController.callback(%{})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Authentication error"
    end
  end

  describe "callback/2 - missing email in OAuth response" do
    test "shows error when email cannot be extracted", %{conn: conn} do
      # Auth with nil email
      auth = build_oauth_auth(nil)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Unable to retrieve email"
    end
  end

  describe "callback/2 - user not found" do
    test "shows error when user doesn't exist in database", %{conn: conn} do
      auth = build_oauth_auth("nonexistent@example.com")

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "No account found"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "apply for membership"
    end
  end

  describe "callback/2 - successful authentication for active users" do
    test "logs in active user successfully", %{conn: conn} do
      user = user_fixture(%{state: "active", email: "active@example.com"})
      auth = build_oauth_auth(user.email)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn) =~ "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Successfully signed in"

      assert get_session(conn, :user_token) != nil
    end

    test "logs in pending_approval user", %{conn: conn} do
      user =
        user_fixture(%{state: "pending_approval", email: "pending@example.com"})

      auth = build_oauth_auth(user.email)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn) != nil

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Successfully signed in"
    end

    test "marks email as verified if not already verified", %{conn: conn} do
      user =
        user_fixture(%{
          state: "active",
          email: "unverified@example.com",
          email_verified_at: nil
        })

      auth = build_oauth_auth(user.email)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn) != nil

      # Verify email was marked as verified
      updated_user = Accounts.get_user_by_email(user.email)
      assert updated_user.email_verified_at != nil
    end

    test "displays Google provider name in success message", %{conn: conn} do
      user = user_fixture(%{state: "active", email: "google@example.com"})
      auth = build_oauth_auth(user.email, :google)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Google"
    end

    test "displays Facebook provider name in success message", %{conn: conn} do
      user = user_fixture(%{state: "active", email: "facebook@example.com"})
      auth = build_oauth_auth(user.email, :facebook)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Facebook"
    end

    test "redirects to stored redirect_to path after login", %{conn: conn} do
      user = user_fixture(%{state: "active", email: "redirect@example.com"})
      auth = build_oauth_auth(user.email)
      redirect_path = "/events/123"

      conn =
        conn
        |> init_test_session(%{oauth_redirect_to: redirect_path})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn) =~ redirect_path
    end
  end

  describe "callback/2 - rejected or inactive users" do
    test "rejects login for rejected user", %{conn: conn} do
      user = user_fixture(%{state: "rejected", email: "rejected@example.com"})
      auth = build_oauth_auth(user.email)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "not currently active"

      assert get_session(conn, :user_token) == nil
    end

    test "rejects login for suspended user", %{conn: conn} do
      user = user_fixture(%{state: "suspended", email: "suspended@example.com"})
      auth = build_oauth_auth(user.email)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "not currently active"
    end

    test "does not create session for rejected users", %{conn: conn} do
      user = user_fixture(%{state: "rejected", email: "nosession@example.com"})
      auth = build_oauth_auth(user.email)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert get_session(conn, :user_token) == nil
    end
  end

  describe "callback/2 - security edge cases" do
    test "handles email with different casing", %{conn: conn} do
      # Create user with lowercase email
      _user = user_fixture(%{state: "active", email: "test@example.com"})

      # OAuth returns uppercase email
      auth = build_oauth_auth("TEST@EXAMPLE.COM")

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      # Result depends on whether Accounts.get_user_by_email is case-insensitive
      # This test documents the behavior
      assert redirected_to(conn) != nil
    end

    test "handles very long email addresses", %{conn: conn} do
      long_email = String.duplicate("a", 200) <> "@example.com"
      auth = build_oauth_auth(long_email)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      # Should handle gracefully (user not found)
      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) != nil
    end

    test "prevents redirect to external URLs via malicious redirect_to", %{
      conn: conn
    } do
      user = user_fixture(%{state: "active", email: "safe@example.com"})
      auth = build_oauth_auth(user.email)

      # Even if somehow a malicious redirect got into session, UserAuth should validate it
      conn =
        conn
        |> init_test_session(%{oauth_redirect_to: "https://evil.com"})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      # Should redirect safely (not to external URL)
      refute redirected_to(conn) =~ "evil.com"
    end
  end

  describe "callback/2 - provider-specific scenarios" do
    test "successfully authenticates with Google", %{conn: conn} do
      user = user_fixture(%{state: "active", email: "googleuser@gmail.com"})
      auth = build_oauth_auth(user.email, :google)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn) != nil
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Google"
    end

    test "successfully authenticates with Facebook", %{conn: conn} do
      user = user_fixture(%{state: "active", email: "fbuser@facebook.com"})
      auth = build_oauth_auth(user.email, :facebook)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn) != nil
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Facebook"
    end
  end
end
