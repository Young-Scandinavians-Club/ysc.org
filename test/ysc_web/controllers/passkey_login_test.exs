defmodule YscWeb.PasskeyLoginTest do
  @moduledoc """
  Tests for passkey login endpoint in UserSessionController.
  """
  use YscWeb.ConnCase

  import Ecto.Query
  import Ysc.AccountsFixtures

  alias Ysc.Accounts

  describe "passkey_login/2" do
    setup do
      user = user_fixture()
      {:ok, user} = Accounts.mark_email_verified(user)
      %{user: user}
    end

    test "logs in user with valid encoded user_id", %{conn: conn, user: user} do
      encoded_user_id = Base.url_encode64(user.id, padding: false)

      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{"user_id" => encoded_user_id})

      assert redirected_to(conn) == ~p"/"

      # Verify user is logged in
      assert get_session(conn, :user_token) != nil
      assert get_session(conn, :just_logged_in) == true
    end

    test "logs in user with redirect_to parameter", %{conn: conn, user: user} do
      encoded_user_id = Base.url_encode64(user.id, padding: false)
      redirect_to = ~p"/bookings/tahoe"

      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{
          "user_id" => encoded_user_id,
          "redirect_to" => redirect_to
        })

      assert redirected_to(conn) == redirect_to
      assert get_session(conn, :just_logged_in) == true
    end

    test "stores authentication method in auth event", %{conn: conn, user: user} do
      encoded_user_id = Base.url_encode64(user.id, padding: false)

      _conn =
        conn
        |> get(~p"/users/log-in/passkey", %{"user_id" => encoded_user_id})

      # Check that auth event was created with passkey method
      import Ecto.Query

      auth_events =
        Ysc.Repo.all(
          from ae in Ysc.Accounts.AuthEvent,
            where: ae.user_id == ^user.id,
            where: ae.event_type == "login_success",
            order_by: [desc: ae.inserted_at],
            limit: 1
        )

      assert length(auth_events) == 1
      auth_event = List.first(auth_events)
      assert auth_event.metadata["auth_method"] == "passkey"
    end

    test "redirects to login with error for invalid user_id", %{conn: conn} do
      # Use a valid base64-encoded string that decodes to an invalid ULID
      # Base64 encode a string that's not a valid ULID
      invalid_user_id = Base.url_encode64("invalid_id", padding: false)

      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{"user_id" => invalid_user_id})

      # The controller should handle the invalid ULID gracefully
      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Invalid login session"
    end

    test "redirects to login with error for missing user_id", %{conn: conn} do
      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Invalid login request"
    end

    test "redirects to login for inactive user", %{conn: conn} do
      user = user_fixture(%{state: :suspended})
      {:ok, user} = Accounts.mark_email_verified(user)

      encoded_user_id = Base.url_encode64(user.id, padding: false)

      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{"user_id" => encoded_user_id})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "not currently active"
    end

    test "clears failed login attempts on successful login", %{
      conn: conn,
      user: user
    } do
      encoded_user_id = Base.url_encode64(user.id, padding: false)

      # Set failed attempts in session - must init test session first
      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> put_session(:failed_login_attempts, 3)

      conn =
        conn
        |> get(~p"/users/log-in/passkey", %{"user_id" => encoded_user_id})

      assert get_session(conn, :failed_login_attempts) == nil
    end
  end
end
