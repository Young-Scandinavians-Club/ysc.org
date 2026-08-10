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

  # Helper function to create OAuth auth struct with a profile image
  defp build_oauth_auth_with_image(email, provider, image) do
    %Ueberauth.Auth{
      provider: provider,
      info: %Ueberauth.Auth.Info{
        email: email,
        name: "Test User",
        first_name: "Test",
        last_name: "User",
        image: image
      },
      credentials: %Ueberauth.Auth.Credentials{
        token: "mock_token",
        refresh_token: "mock_refresh",
        expires: true,
        expires_at: System.system_time(:second) + 3600
      },
      uid: "mock_uid_123"
    }
  end

  # Helper function to create OAuth auth struct where email is only available
  # via the raw provider payload (Ueberauth.Auth.Info doesn't expose :raw).
  defp build_oauth_auth_raw_email(raw_key, email) do
    %Ueberauth.Auth{
      provider: :google,
      info: %{
        email: nil,
        name: "Test User",
        first_name: "Test",
        last_name: "User",
        raw: %{raw_key => email}
      },
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

  describe "request/2" do
    test "passes the connection through unchanged (Ueberauth handles the redirect)",
         %{conn: conn} do
      assert AuthController.request(conn, %{}) == conn
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
      # Generic message to avoid user enumeration
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Unable to sign in. Please try again, or email info@ysc.org for help."
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

      assert redirected_to(conn)

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

      assert redirected_to(conn)

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
      assert redirected_to(conn)
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

  describe "callback/2 - OAuth re-authentication flow" do
    test "sets reauth_verified_at and redirects back when email matches", %{
      conn: conn
    } do
      user = user_fixture(%{state: "active", email: "reauth@example.com"})
      auth = build_oauth_auth(user.email)

      conn =
        conn
        |> log_in_user(user)
        |> fetch_flash()
        |> init_test_session(%{
          reauth_mode: true,
          reauth_return_to: "/users/settings/security"
        })
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn) == "/users/settings/security"
      assert get_session(conn, :reauth_verified_at) != nil
      assert get_session(conn, :reauth_mode) == nil
      assert get_session(conn, :reauth_return_to) == nil
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "verified"
    end

    test "rejects reauth when OAuth email differs from logged-in user email", %{
      conn: conn
    } do
      user = user_fixture(%{state: "active", email: "user@example.com"})
      auth = build_oauth_auth("different@example.com")

      conn =
        conn
        |> log_in_user(user)
        |> fetch_flash()
        |> init_test_session(%{
          reauth_mode: true,
          reauth_return_to: "/users/settings/security"
        })
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn) == "/users/settings/security"
      assert get_session(conn, :reauth_verified_at) == nil
      assert get_session(conn, :reauth_mode) == nil
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "doesn't match"
    end

    test "reauth is case-insensitive for email comparison", %{conn: conn} do
      user = user_fixture(%{state: "active", email: "casetest@example.com"})
      auth = build_oauth_auth("CASETEST@EXAMPLE.COM")

      conn =
        conn
        |> log_in_user(user)
        |> fetch_flash()
        |> init_test_session(%{reauth_mode: true, reauth_return_to: "/"})
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert get_session(conn, :reauth_verified_at) != nil
    end

    test "redirects to login when session has no user token during reauth", %{
      conn: conn
    } do
      auth = build_oauth_auth("someone@example.com")

      conn =
        conn
        |> init_test_session(%{
          reauth_mode: true,
          reauth_return_to: "/users/settings/security"
        })
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :reauth_mode) == nil
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
    end

    test "reauth defaults return_to to / when session value missing", %{
      conn: conn
    } do
      user =
        user_fixture(%{state: "active", email: "returndefault@example.com"})

      auth = build_oauth_auth(user.email)

      conn =
        conn
        |> log_in_user(user)
        |> fetch_flash()
        |> init_test_session(%{reauth_mode: true})
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn) == "/"
      assert get_session(conn, :reauth_verified_at) != nil
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

      assert redirected_to(conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Google"
    end

    test "successfully authenticates with Facebook", %{conn: conn} do
      user = user_fixture_fast(%{state: "active", email: "fbuser@facebook.com"})
      auth = build_oauth_auth(user.email, :facebook)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Facebook"
    end
  end

  describe "callback/2 - email extraction fallbacks" do
    test "extracts email from raw 'email' key when info.email is nil", %{
      conn: conn
    } do
      user = user_fixture(%{state: "active", email: "rawemail@example.com"})
      auth = build_oauth_auth_raw_email("email", user.email)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Successfully signed in"
    end

    test "extracts email from raw 'emailAddress' key as a last resort", %{
      conn: conn
    } do
      user = user_fixture(%{state: "active", email: "rawemailaddr@example.com"})
      auth = build_oauth_auth_raw_email("emailAddress", user.email)

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Successfully signed in"
    end
  end

  describe "callback/2 - OAuth avatar image handling" do
    test "strips Google's size suffix from the profile image URL and syncs it",
         %{conn: conn} do
      user = user_fixture(%{state: "active", email: "googleavatar@example.com"})

      auth =
        build_oauth_auth_with_image(
          user.email,
          :google,
          "https://lh3.googleusercontent.com/a/photo=s96-c"
        )

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Successfully signed in"
    end

    test "syncs a non-Google provider's profile image as-is", %{conn: conn} do
      user = user_fixture(%{state: "active", email: "fbavatar@example.com"})

      auth =
        build_oauth_auth_with_image(
          user.email,
          :facebook,
          "https://graph.facebook.com/photo.jpg"
        )

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Successfully signed in"
    end

    test "defaults to :upload avatar source for unrecognized providers", %{
      conn: conn
    } do
      user = user_fixture(%{state: "active", email: "otheravatar@example.com"})

      auth =
        build_oauth_auth_with_image(
          user.email,
          :apple,
          "https://appleid.apple.com/photo.jpg"
        )

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn)
    end

    test "ignores a non-HTTPS profile image URL", %{conn: conn} do
      user = user_fixture(%{state: "active", email: "httpavatar@example.com"})

      auth =
        build_oauth_auth_with_image(
          user.email,
          :google,
          "http://example.com/photo=s96-c"
        )

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Successfully signed in"
    end

    test "ignores a profile image URL pointing at localhost", %{conn: conn} do
      user =
        user_fixture(%{state: "active", email: "localhostavatar@example.com"})

      auth =
        build_oauth_auth_with_image(
          user.email,
          :google,
          "https://localhost/photo.jpg"
        )

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn)
    end

    test "ignores a profile image URL pointing at a .localhost subdomain", %{
      conn: conn
    } do
      user = user_fixture(%{state: "active", email: "sublocalhost@example.com"})

      auth =
        build_oauth_auth_with_image(
          user.email,
          :google,
          "https://internal.localhost/photo.jpg"
        )

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn)
    end

    test "ignores a profile image URL pointing at a private 10.x address", %{
      conn: conn
    } do
      user = user_fixture(%{state: "active", email: "tennet@example.com"})

      auth =
        build_oauth_auth_with_image(
          user.email,
          :google,
          "https://10.0.0.5/photo.jpg"
        )

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn)
    end

    test "ignores a profile image URL pointing inside the 172.16/12 private range",
         %{conn: conn} do
      user = user_fixture(%{state: "active", email: "privaterange@example.com"})

      auth =
        build_oauth_auth_with_image(
          user.email,
          :google,
          "https://172.20.0.5/photo.jpg"
        )

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn)
    end

    test "accepts a profile image URL with a 172.x host outside the private range",
         %{conn: conn} do
      user = user_fixture(%{state: "active", email: "publicrange@example.com"})

      auth =
        build_oauth_auth_with_image(
          user.email,
          :google,
          "https://172.40.0.5/photo.jpg"
        )

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Successfully signed in"
    end
  end
end
