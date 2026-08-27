defmodule YscWeb.UserSessionControllerTest do
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts.UserToken
  alias Ysc.Repo

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

      redirect = redirected_to(conn)
      assert redirect =~ "/account/setup/#{user.id}"
      assert redirect =~ "setup_token="

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Please verify your email address before signing in"
    end

    test "logs the user in with a Gmail alias of a legacy dotted stored address",
         %{
           conn: conn
         } do
      tag = Integer.to_string(System.unique_integer([:positive]))
      dotted_email = "session.#{tag}@gmail.com"
      canonical_email = "session#{tag}@gmail.com"

      legacy_gmail_user_fixture(%{email: dotted_email})

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => canonical_email,
            "password" => valid_user_password()
          }
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
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

    test "hands off to the mobile app instead of the normal redirect when mobile_redirect_uri and code_challenge are valid",
         %{conn: conn, user: user} do
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          },
          "mobile_redirect_uri" => "ysc-admin://auth-callback",
          "code_challenge" => String.duplicate("a", 64)
        })

      location = redirected_to(conn, 302)
      assert location =~ ~r{^ysc-admin://auth-callback\?code=}
      assert get_session(conn, :user_token)
    end

    test "does not hand off to the mobile app without a code_challenge", %{
      conn: conn,
      user: user
    } do
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          },
          "mobile_redirect_uri" => "ysc-admin://auth-callback"
        })

      assert redirected_to(conn) == ~p"/"
    end

    test "ignores an unknown mobile_redirect_uri and redirects normally", %{
      conn: conn,
      user: user
    } do
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          },
          "mobile_redirect_uri" => "evil-app://steal-token"
        })

      assert redirected_to(conn) == ~p"/"
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

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Good to see you again."

      assert Phoenix.Flash.get(conn.assigns.flash, "info_toast_title") ==
               "Login"
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

      redirect = redirected_to(conn)
      assert redirect =~ "/account/setup/#{user.id}"
      assert redirect =~ "setup_token="

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
    test "renders auto-submit form for valid token without creating a session",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)
      one_time_token = Ysc.Accounts.generate_auto_login_token(user)

      conn = get(conn, ~p"/users/log-in/auto?#{%{token: one_time_token}}")

      assert html_response(conn, 200) =~ ~s(id="token-login-form")
      refute get_session(conn, :user_token)
    end

    test "GET form CSRF token is accepted by POST (end-to-end auto-submit flow)",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)
      one_time_token = Ysc.Accounts.generate_auto_login_token(user)

      {conn, _csrf} = fetch_conn_csrf(conn)

      conn = get(conn, ~p"/users/log-in/auto?#{%{token: one_time_token}}")
      {conn, form_csrf} = fetch_conn_csrf_from_html(conn)

      conn =
        post(conn, ~p"/users/log-in/auto", %{
          "_csrf_token" => form_csrf,
          "token" => one_time_token
        })

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)
    end

    test "redirects to login when no token is provided", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in/auto")

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/log-in/auto" do
    test "auto-logs in user with valid token and redirects to pending review",
         %{conn: conn} do
      user = user_fixture(%{state: :pending_approval})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)
      one_time_token = Ysc.Accounts.generate_auto_login_token(user)

      conn =
        post_token_login(conn, ~p"/users/log-in/auto", %{
          "token" => one_time_token
        })

      assert redirected_to(conn) == ~p"/pending-review"
      assert get_session(conn, :user_token)
    end

    test "auto-logs in user with valid token and redirects to dashboard for active users",
         %{conn: conn} do
      user = user_fixture(%{state: :active})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)
      one_time_token = Ysc.Accounts.generate_auto_login_token(user)

      conn =
        post_token_login(conn, ~p"/users/log-in/auto", %{
          "token" => one_time_token
        })

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)
    end

    test "second request with the same auto-login token is rejected (replay)",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)
      one_time_token = Ysc.Accounts.generate_auto_login_token(user)

      conn1 =
        post_token_login(conn, ~p"/users/log-in/auto", %{
          "token" => one_time_token
        })

      assert redirected_to(conn1) == ~p"/"
      assert get_session(conn1, :user_token)

      conn2 =
        post_token_login(build_conn(), ~p"/users/log-in/auto", %{
          "token" => one_time_token
        })

      assert redirected_to(conn2) =~ "/users/log-in"
      assert redirected_to(conn2) =~ "reason=expired_link"
    end

    test "redirects to login with invalid token (reason in query to avoid overwriting successful login session)",
         %{
           conn: conn
         } do
      conn =
        post_token_login(conn, ~p"/users/log-in/auto", %{
          "token" => "invalid_token"
        })

      assert redirected_to(conn) =~ "/users/log-in"
      assert redirected_to(conn) =~ "reason=expired_link"
    end

    test "redirects to login for inactive accounts", %{conn: conn} do
      user = user_fixture(%{state: :suspended})
      one_time_token = Ysc.Accounts.generate_auto_login_token(user)

      conn =
        post_token_login(conn, ~p"/users/log-in/auto", %{
          "token" => one_time_token
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Your account is not currently active."
    end

    test "redirects to login when auto-login token is expired", %{conn: conn} do
      user = user_fixture(%{state: :active})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)
      token = Ysc.Accounts.generate_auto_login_token(user)

      Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      conn =
        post_token_login(conn, ~p"/users/log-in/auto", %{
          "token" => token
        })

      assert redirected_to(conn) =~ "/users/log-in"
      assert redirected_to(conn) =~ "reason=expired_link"
    end

    test "redirects to internal path when redirect_to is valid", %{conn: conn} do
      user = user_fixture(%{state: :active})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)
      token = Ysc.Accounts.generate_auto_login_token(user)

      conn =
        post_token_login(conn, ~p"/users/log-in/auto", %{
          "token" => token,
          "redirect_to" => "/events"
        })

      assert redirected_to(conn) == "/events"
      assert get_session(conn, :user_token)
    end
  end

  describe "GET /users/log-in/passkey" do
    test "renders auto-submit form for valid token without creating a session",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)
      token = Ysc.Accounts.generate_passkey_login_token(user)

      conn =
        get(
          conn,
          "/users/log-in/passkey?" <> URI.encode_query(%{"token" => token})
        )

      assert html_response(conn, 200) =~ ~s(id="token-login-form")
      refute get_session(conn, :user_token)
    end

    test "GET form CSRF token is accepted by POST (end-to-end auto-submit flow)",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)
      token = Ysc.Accounts.generate_passkey_login_token(user)

      # Simulate an existing browser session (e.g. user was already browsing the site)
      {conn, _csrf} = fetch_conn_csrf(conn)

      conn =
        get(
          conn,
          "/users/log-in/passkey?" <> URI.encode_query(%{"token" => token})
        )

      {conn, form_csrf} = fetch_conn_csrf_from_html(conn)

      conn =
        post(conn, ~p"/users/log-in/passkey", %{
          "_csrf_token" => form_csrf,
          "token" => token
        })

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)
    end

    test "redirects to login when params are missing token", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in/passkey")

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid login request."
    end
  end

  describe "POST /users/log-in/passkey" do
    test "logs in with valid passkey token for active verified user", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)
      token = Ysc.Accounts.generate_passkey_login_token(user)

      conn =
        post_token_login(conn, ~p"/users/log-in/passkey", %{
          "token" => token
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end

    test "redirects with internal path when valid redirect_to is provided", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)
      token = Ysc.Accounts.generate_passkey_login_token(user)

      conn =
        post_token_login(conn, ~p"/users/log-in/passkey", %{
          "token" => token,
          "redirect_to" => "/contact"
        })

      assert redirected_to(conn) == "/contact"
      assert get_session(conn, :user_token)
    end

    test "rejects a token not present in the DB (e.g. forged Phoenix.Token)", %{
      conn: conn
    } do
      token =
        Phoenix.Token.sign(YscWeb.Endpoint, "passkey_login", "some_user_id")

      conn =
        post_token_login(conn, ~p"/users/log-in/passkey", %{
          "token" => token
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid or expired login link. Please sign in again."
    end

    test "redirects to login when token verification fails", %{conn: conn} do
      conn =
        post_token_login(conn, ~p"/users/log-in/passkey", %{
          "token" => "not-a-valid-token"
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid or expired login link. Please sign in again."
    end

    test "redirects to login when params are missing token", %{conn: conn} do
      {conn, csrf} = fetch_conn_csrf(conn)

      conn =
        post(conn, ~p"/users/log-in/passkey", %{
          "_csrf_token" => csrf
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid login request."
    end

    test "rejects passkey login for inactive accounts", %{conn: conn} do
      user = user_fixture(%{state: :suspended})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)
      token = Ysc.Accounts.generate_passkey_login_token(user)

      conn =
        post_token_login(conn, ~p"/users/log-in/passkey", %{
          "token" => token
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Your account is not currently active."
    end

    test "rejects passkey login when user is deleted after token was issued", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)
      token = Ysc.Accounts.generate_passkey_login_token(user)
      Ysc.Repo.delete!(user)

      conn =
        post_token_login(conn, ~p"/users/log-in/passkey", %{
          "token" => token
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid or expired login link. Please sign in again."
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
