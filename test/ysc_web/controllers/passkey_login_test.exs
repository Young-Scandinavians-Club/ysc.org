defmodule YscWeb.PasskeyLoginTest do
  @moduledoc """
  Tests for passkey login endpoint in UserSessionController.

  The endpoint accepts a one-time signed token (issued by the login LiveView after
  successful WebAuthn verification). It must not accept a raw user_id, so that
  knowing a user's ID cannot be used to log in as that user.
  """
  use YscWeb.ConnCase, async: true

  import Ecto.Query
  import Ysc.AccountsFixtures

  alias Ysc.Accounts

  defp valid_passkey_token(user, opts \\ []) do
    max_age = Keyword.get(opts, :max_age, 120)

    Phoenix.Token.sign(YscWeb.Endpoint, "passkey_login", user.id,
      max_age: max_age
    )
  end

  describe "passkey_login/2 with valid token" do
    setup do
      user = user_fixture()
      {:ok, user} = Accounts.mark_email_verified(user)
      %{user: user}
    end

    test "logs in user and redirects to default path", %{conn: conn, user: user} do
      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{
          "token" => valid_passkey_token(user)
        })

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token) != nil
      assert get_session(conn, :just_logged_in) == true
    end

    test "logs in user with valid redirect_to and redirects there", %{
      conn: conn,
      user: user
    } do
      redirect_to = ~p"/bookings/tahoe"

      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{
          "token" => valid_passkey_token(user),
          "redirect_to" => redirect_to
        })

      assert redirected_to(conn) == redirect_to
      assert get_session(conn, :just_logged_in) == true
    end

    test "ignores invalid redirect_to and redirects to default path", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{
          "token" => valid_passkey_token(user),
          "redirect_to" => "https://evil.example.com/phishing"
        })

      # External redirect must not be followed
      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token) != nil
    end

    test "records login_success auth event with passkey method", %{
      conn: conn,
      user: user
    } do
      _conn =
        conn
        |> get(~p"/users/log-in/passkey", %{
          "token" => valid_passkey_token(user)
        })

      auth_events =
        Ysc.Repo.all(
          from ae in Ysc.Accounts.AuthEvent,
            where: ae.user_id == ^user.id,
            where: ae.event_type == "login_success",
            order_by: [desc: ae.inserted_at],
            limit: 1
        )

      assert length(auth_events) == 1
      assert List.first(auth_events).metadata["auth_method"] == "passkey"
    end

    test "clears failed login attempts on successful login", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> put_session(:failed_login_attempts, 3)
        |> get(~p"/users/log-in/passkey", %{
          "token" => valid_passkey_token(user)
        })

      assert get_session(conn, :failed_login_attempts) == nil
    end

    test "logs in user in pending_approval state", %{conn: conn} do
      user = user_fixture(%{state: :pending_approval})
      {:ok, user} = Accounts.mark_email_verified(user)

      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{
          "token" => valid_passkey_token(user)
        })

      assert redirected_to(conn) == ~p"/pending-review"
      assert get_session(conn, :user_token) != nil
    end
  end

  describe "passkey_login/2 security: rejects login without proof of passkey" do
    setup do
      user = user_fixture()
      {:ok, user} = Accounts.mark_email_verified(user)
      %{user: user}
    end

    test "rejects request with raw user_id only (no token) - prevents login-by-user-id attack",
         %{conn: conn, user: user} do
      # Simulates the previously vulnerable URL: anyone with a user's ID could log in.
      # The endpoint must require a signed token from the LiveView after passkey verification.
      encoded_user_id = Base.url_encode64(user.id, padding: false)

      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{"user_id" => encoded_user_id})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Invalid login request"

      assert get_session(conn, :user_token) == nil
    end

    test "rejects request with user_id and redirect_to but no token", %{
      conn: conn,
      user: user
    } do
      encoded_user_id = Base.url_encode64(user.id, padding: false)

      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{
          "user_id" => encoded_user_id,
          "redirect_to" => ~p"/bookings/tahoe"
        })

      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :user_token) == nil
    end

    test "rejects token signed with wrong salt", %{conn: conn, user: user} do
      # Token verifies with a different purpose; must not be accepted for passkey_login
      wrong_salt_token =
        Phoenix.Token.sign(YscWeb.Endpoint, "other_purpose", user.id,
          max_age: 120
        )

      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{"token" => wrong_salt_token})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Invalid or expired login link"

      assert get_session(conn, :user_token) == nil
    end

    test "rejects invalid or tampered token", %{conn: conn} do
      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{"token" => "invalid_or_tampered"})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Invalid or expired login link"

      assert get_session(conn, :user_token) == nil
    end

    test "rejects empty token", %{conn: conn} do
      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{"token" => ""})

      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :user_token) == nil
    end

    test "rejects token with non-binary payload", %{conn: conn} do
      # Payload is valid for verify but not a user_id binary (e.g. integer)
      token =
        Phoenix.Token.sign(YscWeb.Endpoint, "passkey_login", 99_999,
          max_age: 120
        )

      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{"token" => token})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Invalid login session"

      assert get_session(conn, :user_token) == nil
    end
  end

  describe "passkey_login/2 invalid or missing params" do
    test "redirects to login with error for missing token", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in/passkey")

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Invalid login request"
    end

    test "redirects to login when token is the only param but missing", %{
      conn: conn
    } do
      conn = get(conn, ~p"/users/log-in/passkey", %{"redirect_to" => ~p"/"})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Invalid login request"
    end
  end

  describe "passkey_login/2 user and token edge cases" do
    test "redirects to login for suspended user with valid token", %{conn: conn} do
      user = user_fixture(%{state: :suspended})
      {:ok, user} = Accounts.mark_email_verified(user)

      token = valid_passkey_token(user)

      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{"token" => token})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "not currently active"

      assert get_session(conn, :user_token) == nil
    end

    test "redirects to login when token is valid but user no longer exists", %{
      conn: conn
    } do
      # Token signed with a valid ULID that is not in the database (e.g. user deleted after token issued)
      user_id = Ecto.ULID.generate()

      token =
        Phoenix.Token.sign(YscWeb.Endpoint, "passkey_login", user_id,
          max_age: 120
        )

      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{"token" => token})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Invalid login session"

      assert get_session(conn, :user_token) == nil
    end
  end
end
