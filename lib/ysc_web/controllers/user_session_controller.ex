defmodule YscWeb.UserSessionController do
  use YscWeb, :controller

  alias Ysc.Accounts
  alias Ysc.Accounts.AuthService
  alias YscWeb.UserAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  def auto_login(conn, %{"token" => encoded_token, "redirect_to" => redirect_to}) do
    # Token-based auto-login from account setup - skip CSRF protection
    token = Base.url_decode64!(encoded_token)

    if user = Accounts.get_user_by_session_token(token) do
      if user.state in [:pending_approval, :active] do
        # Log successful sign-in
        AuthService.log_login_success(user, conn, %{
          token: token,
          method: "email_password"
        })

        # Reset failed sign-in attempts and log in user
        conn
        |> delete_session(:failed_login_attempts)
        |> UserAuth.log_in_user(user, %{}, redirect_to)
      else
        # Account not active
        conn
        |> put_flash(:error, "Your account is not currently active.")
        |> redirect(to: ~p"/users/log-in")
      end
    else
      # Invalid token
      conn
      |> put_flash(:error, "Invalid login session.")
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def auto_login(conn, %{"token" => encoded_token}) do
    # Token-based auto-login from account setup - skip CSRF protection
    token = Base.url_decode64!(encoded_token)

    if user = Accounts.get_user_by_session_token(token) do
      if user.state in [:pending_approval, :active] do
        # Log successful sign-in
        AuthService.log_login_success(user, conn, %{
          token: token,
          method: "email_password"
        })

        # Reset failed sign-in attempts and log in user
        # UserAuth.log_in_user will redirect to the appropriate path based on user state
        conn
        |> delete_session(:failed_login_attempts)
        |> UserAuth.log_in_user(user, %{})
      else
        # Account not active
        conn
        |> put_flash(:error, "Your account is not currently active.")
        |> redirect(to: ~p"/users/log-in")
      end
    else
      # Invalid token
      conn
      |> put_flash(:error, "Invalid login session.")
      |> redirect(to: ~p"/users/log-in")
    end
  end

  # sobelow_skip ["XSS.SendResp"]
  defp create(conn, %{"user" => user_params} = params, info) do
    %{"email" => email, "password" => password} = user_params

    # Per-identifier rate limit (credential stuffing: slow down attacks on one account)
    case Ysc.AuthRateLimit.check_identifier(email) do
      :ok ->
        do_create(conn, params, info, user_params, email, password)

      {:error, :rate_limited, retry_after_sec} ->
        body = """
        <!DOCTYPE html>
        <html><head><title>Too Many Requests</title></head>
        <body><h1>Too many attempts</h1><p>Please try again in #{retry_after_sec} seconds.</p></body>
        </html>
        """

        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_sec))
        |> put_resp_content_type("text/html")
        |> send_resp(429, body)
        |> halt()
    end
  end

  defp do_create(conn, params, info, user_params, email, password) do
    # Get redirect_to from form params (passed as hidden field from LiveView)
    # Also check session as fallback for backwards compatibility
    redirect_to =
      params["redirect_to"] ||
        get_session(conn, :user_return_to)

    if user = Accounts.get_user_by_email_and_password(email, password) do
      # Check if user's email is verified - if not, redirect to account setup
      if is_nil(user.email_verified_at) do
        conn
        |> put_flash(
          :info,
          "Please verify your email address before signing in."
        )
        |> redirect(to: ~p"/account/setup/#{user.id}")
      else
        # Check if user is in an allowed state for login
        if user.state in [:pending_approval, :active] do
          # Log successful sign-in
          AuthService.log_login_success(
            user,
            conn,
            Map.put(user_params, :method, "email_password")
          )

          # Reset failed sign-in attempts on successful sign-in
          # Validate redirect_to is internal before using it
          validated_redirect =
            if redirect_to &&
                 YscWeb.UserAuth.valid_internal_redirect?(redirect_to) do
              redirect_to
            else
              nil
            end

          conn
          |> put_flash(:info, info)
          |> delete_session(:failed_login_attempts)
          |> delete_session(:user_return_to)
          |> put_session(:just_logged_in, true)
          |> UserAuth.log_in_user(user, user_params, validated_redirect)
        else
          # Log failed sign-in attempt due to account state
          AuthService.log_login_failure(
            email,
            conn,
            "account_state_restriction",
            user_params
          )

          # Track failed sign-in attempts in session
          failed_attempts = (get_session(conn, :failed_login_attempts) || 0) + 1

          # Show error message explaining why login is not allowed
          conn
          |> put_flash(
            :error,
            "Your account is not currently active. Please contact info@ysc.org for more information."
          )
          |> put_flash(:email, String.slice(email, 0, 160))
          |> put_session(:failed_login_attempts, failed_attempts)
          |> redirect(to: ~p"/users/log-in")
        end
      end
    else
      # Log failed sign-in attempt
      AuthService.log_login_failure(
        email,
        conn,
        "invalid_credentials",
        user_params
      )

      # Track failed sign-in attempts in session
      failed_attempts = (get_session(conn, :failed_login_attempts) || 0) + 1

      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> put_session(:failed_login_attempts, failed_attempts)
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete(conn, _params) do
    # Log sign-out event if user is authenticated
    if current_user = conn.assigns[:current_user] do
      AuthService.log_logout(current_user, conn)
    end

    conn
    |> put_flash(:info, "Signed out successfully.")
    |> UserAuth.log_out_user()
  end

  def reset_attempts(conn, _params) do
    # Clear failed login attempts from session and redirect back to login page
    conn
    |> delete_session(:failed_login_attempts)
    |> redirect(to: ~p"/users/log-in")
  end

  def passkey_login(conn, params) do
    require Logger

    # Merge query params into params (in case they're not merged automatically)
    merged_params = Map.merge(params || %{}, conn.query_params || %{})

    # Check if query string was malformed (entire query string became a key)
    # This can happen when redirecting from LiveView
    parsed_params =
      case find_malformed_query_key(merged_params) do
        nil ->
          merged_params

        malformed_key ->
          Logger.warning(
            "[UserSessionController] Found malformed query key, parsing manually",
            %{
              malformed_key: malformed_key
            }
          )

          # Parse the query string from the malformed key
          parsed = URI.decode_query(malformed_key)
          # Remove the malformed key and merge parsed params
          Map.delete(merged_params, malformed_key)
          |> Map.merge(parsed)
      end

    Logger.info("[UserSessionController] passkey_login called", %{
      params: params,
      query_params: conn.query_params,
      path_params: conn.path_params,
      merged_params: merged_params,
      parsed_params: parsed_params,
      has_user_id: Map.has_key?(parsed_params, "user_id"),
      has_redirect_to: Map.has_key?(parsed_params, "redirect_to")
    })

    case parsed_params do
      %{"user_id" => encoded_user_id, "redirect_to" => redirect_to} ->
        passkey_login_with_params(conn, encoded_user_id, redirect_to)

      %{"user_id" => encoded_user_id} ->
        passkey_login_with_params(conn, encoded_user_id, "")

      _ ->
        Logger.warning(
          "[UserSessionController] passkey_login called with invalid params",
          %{
            params: params,
            query_params: conn.query_params,
            path_params: conn.path_params,
            merged_params: merged_params,
            parsed_params: parsed_params
          }
        )

        conn
        |> put_flash(:error, "Invalid login request.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # Find a key that looks like a malformed query string (contains & and =)
  defp find_malformed_query_key(params) when is_map(params) do
    Enum.find_value(params, fn {key, _value} ->
      if is_binary(key) && String.contains?(key, "=") &&
           String.contains?(key, "user_id") do
        key
      else
        nil
      end
    end)
  end

  defp find_malformed_query_key(_), do: nil

  # sobelow_skip ["XSS.SendResp"]
  defp passkey_login_with_params(conn, encoded_user_id, redirect_to) do
    require Logger

    # Per-identifier rate limit (same account targeted repeatedly)
    case Ysc.AuthRateLimit.check_identifier(encoded_user_id) do
      :ok ->
        do_passkey_login_with_params(conn, encoded_user_id, redirect_to)

      {:error, :rate_limited, retry_after_sec} ->
        body = """
        <!DOCTYPE html>
        <html><head><title>Too Many Requests</title></head>
        <body><h1>Too many attempts</h1><p>Please try again in #{retry_after_sec} seconds.</p></body>
        </html>
        """

        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_sec))
        |> put_resp_content_type("text/html")
        |> send_resp(429, body)
        |> halt()
    end
  end

  defp do_passkey_login_with_params(conn, encoded_user_id, redirect_to) do
    require Logger

    Logger.info("[UserSessionController] passkey_login_with_params called", %{
      encoded_user_id: encoded_user_id,
      redirect_to: redirect_to
    })

    # Passkey-based login - skip CSRF protection (similar to auto_login)
    # Handle invalid base64 or invalid ULID gracefully
    user_id =
      try do
        Base.url_decode64!(encoded_user_id, padding: false)
      rescue
        ArgumentError ->
          Logger.warning("[UserSessionController] Invalid base64 user_id", %{
            encoded_user_id: encoded_user_id
          })

          nil
      end

    if user_id do
      Logger.debug("[UserSessionController] Decoded user_id", %{
        user_id_hex: Base.encode16(user_id, case: :lower),
        user_id_length: byte_size(user_id)
      })
    end

    # Try to get user, handling invalid ULID gracefully
    user =
      if user_id do
        try do
          Accounts.get_user(user_id)
        rescue
          Ecto.Query.CastError ->
            Logger.warning("[UserSessionController] Invalid ULID format", %{
              user_id: user_id
            })

            nil
        end
      else
        nil
      end

    if user do
      if user.state in [:pending_approval, :active] do
        # Log successful sign-in
        AuthService.log_login_success(user, conn, %{method: "passkey"})

        # Reset failed sign-in attempts and log in user
        validated_redirect =
          if redirect_to && redirect_to != "" &&
               YscWeb.UserAuth.valid_internal_redirect?(redirect_to) do
            redirect_to
          else
            nil
          end

        Logger.info("[UserSessionController] Logging in user successfully", %{
          user_id: user.id,
          user_email: user.email,
          validated_redirect: validated_redirect
        })

        conn
        |> delete_session(:failed_login_attempts)
        |> put_session(:just_logged_in, true)
        |> UserAuth.log_in_user(user, %{}, validated_redirect)
      else
        # Account not active
        Logger.warning("[UserSessionController] User account not active", %{
          user_id: user.id,
          user_state: user.state
        })

        conn
        |> put_flash(:error, "Your account is not currently active.")
        |> redirect(to: ~p"/users/log-in")
      end
    else
      # Invalid user ID
      Logger.warning("[UserSessionController] User not found", %{
        user_id_hex: Base.encode16(user_id, case: :lower),
        encoded_user_id: encoded_user_id
      })

      conn
      |> put_flash(:error, "Invalid login session.")
      |> redirect(to: ~p"/users/log-in")
    end
  end
end
