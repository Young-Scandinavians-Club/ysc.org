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

      # Generate a valid session token
      token = Ysc.Accounts.generate_user_session_token(user)
      encoded_token = Base.url_encode64(token)

      # Make request to auto-login
      conn = get(conn, ~p"/users/log-in/auto?#{%{token: encoded_token}}")

      # Should redirect to pending review page for pending approval users
      assert redirected_to(conn) == ~p"/pending-review"

      # Should be logged in
      assert get_session(conn, :user_token)
    end

    test "auto-logs in user with valid token and redirects to dashboard for active users",
         %{
           conn: conn
         } do
      # Create an active user
      user = user_fixture(%{state: :active})

      # Mark email as verified so user can log in without being redirected to account setup
      {:ok, user} = Ysc.Accounts.mark_email_verified(user)

      # Generate a valid session token
      token = Ysc.Accounts.generate_user_session_token(user)
      encoded_token = Base.url_encode64(token)

      # Make request to auto-login
      conn = get(conn, ~p"/users/log-in/auto?#{%{token: encoded_token}}")

      # Should redirect to dashboard for active users
      assert redirected_to(conn) == ~p"/"

      # Should be logged in
      assert get_session(conn, :user_token)
    end

    test "redirects to login with invalid token", %{conn: conn} do
      # Use an invalid base64 token that will decode but not match any user
      invalid_token = Base.url_encode64("invalid_token_data")
      conn = get(conn, ~p"/users/log-in/auto?#{%{token: invalid_token}}")

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid login session."
    end

    test "redirects to login for inactive accounts", %{conn: conn} do
      # Create a user that's suspended (not in allowed states)
      user = user_fixture(%{state: :suspended})

      # Generate a valid session token
      token = Ysc.Accounts.generate_user_session_token(user)
      encoded_token = Base.url_encode64(token)

      # Make request to auto-login
      conn = get(conn, ~p"/users/log-in/auto?#{%{token: encoded_token}}")

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Your account is not currently active."
    end

    test "handles expired tokens", %{conn: conn, user: user} do
      # Generate a token
      token = Ysc.Accounts.generate_user_session_token(user)
      encoded_token = Base.url_encode64(token)

      # Manually expire the token by updating the inserted_at timestamp
      # (In a real scenario, this would happen after 60 days)
      expired_time =
        DateTime.add(DateTime.utc_now(), -61, :day)
        |> DateTime.truncate(:second)

      Ysc.Repo.get_by(Ysc.Accounts.UserToken, token: token)
      |> Ecto.Changeset.change(inserted_at: expired_time)
      |> Ysc.Repo.update()

      # Make request to auto-login
      conn = get(conn, ~p"/users/log-in/auto?#{%{token: encoded_token}}")

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid login session."
    end
  end
end
