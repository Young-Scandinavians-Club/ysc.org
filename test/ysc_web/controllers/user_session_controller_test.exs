defmodule YscWeb.UserSessionControllerTest do
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /users/log-in" do
    test "renders log in page", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in")
      response = html_response(conn, 200)
      assert response =~ "Sign in to your YSC account"
      assert response =~ ~p"/users/register"
      assert response =~ "Forgot your password?"
      # Check for new authentication methods
      assert response =~ "Sign in with Google"
      assert response =~ "Sign in with Facebook"
      assert response =~ "or"
    end

    test "redirects if already logged in", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> get(~p"/users/log-in")
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /users/log-in" do
    test "redirects to account setup for unverified email users", %{
      conn: conn,
      user: user
    } do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == ~p"/account/setup/#{user.id}"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Please verify your email address before signing in"
    end

    test "logs the user in with verified email", %{conn: conn, user: user} do
      # Mark email as verified
      {:ok, _} = Ysc.Accounts.mark_email_verified(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "logs the user in with remember me and verified email", %{
      conn: conn,
      user: user
    } do
      # Mark email as verified
      {:ok, _} = Ysc.Accounts.mark_email_verified(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_ysc_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "logs the user in with return to and verified email", %{
      conn: conn,
      user: user
    } do
      # Mark email as verified
      {:ok, _} = Ysc.Accounts.mark_email_verified(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "login following registration redirects to account setup", %{
      conn: conn,
      user: user
    } do
      conn =
        post(conn, ~p"/users/log-in", %{
          "_action" => "registered",
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == ~p"/account/setup/#{user.id}"

      # The email verification message takes precedence over the registration message
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Please verify your email address before signing in"
    end

    test "login following password update with verified email", %{
      conn: conn,
      user: user
    } do
      # Mark email as verified (password update flow assumes email is verified)
      {:ok, _} = Ysc.Accounts.mark_email_verified(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "_action" => "password_updated",
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == ~p"/users/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Password updated successfully"
    end

    test "redirects to login page with invalid credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => "invalid@email.com",
            "password" => "invalid_password"
          }
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid email or password"

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Signed out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Signed out successfully"
    end
  end

  describe "GET /users/log-in/auto" do
    test "auto-logs in user with valid token and redirects to pending review",
         %{conn: conn} do
      # Create a pending approval user (like after account setup)
      user = user_fixture(%{state: :pending_approval})

      # Mark email as verified so user can log in without being redirected to account setup
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      # Short-lived one-time token (same as account setup flow)
      one_time_token =
        Phoenix.Token.sign(YscWeb.Endpoint, "auto_login", user.id)

      conn = get(conn, ~p"/users/log-in/auto?#{%{token: one_time_token}}")

      assert redirected_to(conn) == ~p"/pending-review"
      assert get_session(conn, :user_token)
    end

    test "auto-logs in user with valid token and redirects to dashboard for active users",
         %{conn: conn} do
      user = user_fixture(%{state: :active})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      one_time_token =
        Phoenix.Token.sign(YscWeb.Endpoint, "auto_login", user.id)

      conn = get(conn, ~p"/users/log-in/auto?#{%{token: one_time_token}}")

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)
    end

    test "redirects to login with invalid token (reason in query to avoid overwriting successful login session)",
         %{
           conn: conn
         } do
      conn = get(conn, ~p"/users/log-in/auto?#{%{token: "invalid_token"}}")

      assert redirected_to(conn) =~ "/users/log-in"
      assert redirected_to(conn) =~ "reason=expired_link"
    end

    test "redirects to login for inactive accounts", %{conn: conn} do
      user = user_fixture(%{state: :suspended})

      one_time_token =
        Phoenix.Token.sign(YscWeb.Endpoint, "auto_login", user.id)

      conn = get(conn, ~p"/users/log-in/auto?#{%{token: one_time_token}}")

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Your account is not currently active."
    end

    test "redirects to login when no token is provided", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in/auto")

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "redirects with invalid session when user id in token does not exist",
         %{
           conn: conn
         } do
      missing_id = Ecto.ULID.generate()

      token =
        Phoenix.Token.sign(YscWeb.Endpoint, "auto_login", missing_id)

      conn =
        get(
          conn,
          "/users/log-in/auto?" <> URI.encode_query(%{"token" => token})
        )

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid login session."
    end

    test "redirects to internal path when redirect_to is valid", %{conn: conn} do
      user = user_fixture(%{state: :active})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      token =
        Phoenix.Token.sign(YscWeb.Endpoint, "auto_login", user.id)

      conn =
        get(
          conn,
          "/users/log-in/auto?" <>
            URI.encode_query(%{"token" => token, "redirect_to" => "/events"})
        )

      assert redirected_to(conn) == "/events"
      assert get_session(conn, :user_token)
    end
  end

  describe "GET /users/log-in/passkey" do
    test "logs in with valid passkey token for active verified user", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      token =
        Phoenix.Token.sign(YscWeb.Endpoint, "passkey_login", user.id)

      conn =
        get(
          conn,
          "/users/log-in/passkey?" <> URI.encode_query(%{"token" => token})
        )

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end

    test "redirects with internal path when valid redirect_to is provided", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      token =
        Phoenix.Token.sign(YscWeb.Endpoint, "passkey_login", user.id)

      conn =
        get(
          conn,
          "/users/log-in/passkey?" <>
            URI.encode_query(%{"token" => token, "redirect_to" => "/contact"})
        )

      assert redirected_to(conn) == "/contact"
      assert get_session(conn, :user_token)
    end

    test "rejects token whose payload is not a binary user id", %{conn: conn} do
      token =
        Phoenix.Token.sign(YscWeb.Endpoint, "passkey_login", 12_345)

      conn =
        get(
          conn,
          "/users/log-in/passkey?" <> URI.encode_query(%{"token" => token})
        )

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid login session."
    end

    test "redirects to login when token verification fails", %{conn: conn} do
      conn =
        get(
          conn,
          "/users/log-in/passkey?" <>
            URI.encode_query(%{"token" => "not-a-valid-token"})
        )

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid or expired login link. Please sign in again."
    end

    test "redirects to login when params are missing token", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in/passkey")

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid login request."
    end

    test "rejects passkey login for inactive accounts", %{conn: conn} do
      user = user_fixture(%{state: :suspended})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      token =
        Phoenix.Token.sign(YscWeb.Endpoint, "passkey_login", user.id)

      conn =
        get(
          conn,
          "/users/log-in/passkey?" <> URI.encode_query(%{"token" => token})
        )

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Your account is not currently active."
    end

    test "rejects passkey login when user no longer exists", %{conn: conn} do
      missing_id = Ecto.ULID.generate()

      token =
        Phoenix.Token.sign(YscWeb.Endpoint, "passkey_login", missing_id)

      conn =
        get(
          conn,
          "/users/log-in/passkey?" <> URI.encode_query(%{"token" => token})
        )

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid login session."
    end
  end

  describe "POST /users/log-in — account state" do
    test "rejects login for suspended account with verified email", %{
      conn: conn
    } do
      user = user_fixture(%{state: :suspended})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Your account is not currently active"
    end
  end

  describe "GET /users/log-in/reset-attempts" do
    test "clears failed login attempts and redirects to login", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{failed_login_attempts: 5})
        |> get(~p"/users/log-in/reset-attempts")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :failed_login_attempts) == nil
    end
  end

  describe "POST /users/log-out with redirect" do
    test "redirects to redirect_to after sign out", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/users/log-out", %{"redirect_to" => "/events"})

      assert redirected_to(conn) == "/events"
      refute get_session(conn, :user_token)
    end
  end
end
