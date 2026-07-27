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
    create(conn, params, "Welcome back! 👋 Good to see you again.")
  end

  def auto_login(conn, %{"token" => token, "redirect_to" => redirect_to})
      when is_binary(token) and token != "" do
    render_token_login_form(conn, ~p"/users/log-in/auto", token, redirect_to)
  end

  def auto_login(conn, %{"token" => token})
      when is_binary(token) and token != "" do
    render_token_login_form(conn, ~p"/users/log-in/auto", token, nil)
  end

  def auto_login(conn, _params) do
    # Redirect without setting flash to avoid overwriting a concurrent successful
    # login's session (e.g. prefetch or duplicate request without token).
    redirect(conn, to: ~p"/users/log-in")
  end

  def create_auto_login(conn, %{"token" => token, "redirect_to" => redirect_to}) do
    do_auto_login(conn, token, redirect_to)
  end

  def create_auto_login(conn, %{"token" => token}) do
    do_auto_login(conn, token, nil)
  end

  def create_auto_login(conn, _params) do
    redirect(conn, to: ~p"/users/log-in")
  end

  defp do_auto_login(conn, token, redirect_to) when is_binary(token) do
    case Accounts.verify_and_consume_auto_login_token(token) do
      {:ok, user} ->
        do_auto_login_with_user(conn, user, redirect_to)

      {:error, :invalid_or_expired} ->
        # Use query param instead of session flash so a concurrent successful
        # login response cannot be overwritten by this failure's session cookie.
        redirect(conn, to: ~p"/users/log-in?reason=expired_link")
    end
  end

  defp do_auto_login(conn, _token, _redirect_to),
    do: redirect(conn, to: ~p"/users/log-in")

  defp do_auto_login_with_user(conn, user, redirect_to) do
    if user.state in [:pending_approval, :active] do
      validated_redirect =
        if redirect_to && redirect_to != "" &&
             YscWeb.UserAuth.valid_internal_redirect?(redirect_to) do
          redirect_to
        else
          nil
        end

      conn
      |> delete_session(:failed_login_attempts)
      |> UserAuth.log_in_user(
        user,
        %{"method" => "email_password"},
        validated_redirect
      )
    else
      conn
      |> YscWeb.Flash.put_toast(
        :error,
        "Your account is not currently active.",
        title: "Login"
      )
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
        |> YscWeb.Flash.put_toast(
          :info,
          "Please verify your email address before signing in.",
          title: "Login"
        )
        |> redirect(to: YscWeb.AccountSetupAccess.setup_path(user.id))
      else
        # Check if user is in an allowed state for login
        if user.state in [:pending_approval, :active] do
          # Validate redirect_to is internal before using it
          validated_redirect =
            if redirect_to &&
                 YscWeb.UserAuth.valid_internal_redirect?(redirect_to) do
              redirect_to
            else
              nil
            end

          user_params_with_method =
            user_params
            |> Map.put("method", "email_password")
            |> Map.put("remember_me", "true")

          conn
          |> YscWeb.Flash.put_toast(:info, info, title: "Login")
          |> delete_session(:failed_login_attempts)
          |> delete_session(:user_return_to)
          |> put_session(:just_logged_in, true)
          |> UserAuth.log_in_user(
            user,
            user_params_with_method,
            validated_redirect
          )
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
          |> YscWeb.Flash.put_toast(
            :error,
            "Your account is not currently active. Please contact info@ysc.org for more information.",
            title: "Login"
          )
          |> YscWeb.Flash.put_toast(:email, String.slice(email, 0, 160))
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
      |> YscWeb.Flash.put_toast(:error, "Invalid email or password",
        title: "Login"
      )
      |> YscWeb.Flash.put_toast(:email, String.slice(email, 0, 160))
      |> put_session(:failed_login_attempts, failed_attempts)
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete_with_redirect(conn, params) do
    # Same as delete but supports redirect_to for post-logout navigation (e.g. to registration with invite)
    if current_user = conn.assigns[:current_user] do
      AuthService.log_logout(current_user, conn)
    end

    redirect_to = params["redirect_to"] || conn.query_params["redirect_to"]

    conn
    |> YscWeb.Flash.put_toast(:info, "Signed out successfully.",
      title: "Signed out"
    )
    |> UserAuth.log_out_user(redirect_to)
  end

  def delete(conn, params) do
    # Log sign-out event if user is authenticated
    if current_user = conn.assigns[:current_user] do
      AuthService.log_logout(current_user, conn)
    end

    redirect_to = params["redirect_to"] || conn.query_params["redirect_to"]

    conn
    |> YscWeb.Flash.put_toast(:info, "Signed out successfully.",
      title: "Signed out"
    )
    |> UserAuth.log_out_user(redirect_to)
  end

  def reset_attempts(conn, _params) do
    # Clear failed login attempts from session and redirect back to login page
    conn
    |> delete_session(:failed_login_attempts)
    |> redirect(to: ~p"/users/log-in")
  end

  # sobelow_skip ["XSS.SendResp"]
  def passkey_login(conn, params) do
    require Ysc.Logging

    # Merge query params into params (in case they're not merged automatically)
    merged_params = Map.merge(params || %{}, conn.query_params || %{})

    # Check if query string was malformed (entire query string became a key)
    # This can happen when redirecting from LiveView
    parsed_params =
      case find_malformed_query_key(merged_params) do
        nil ->
          merged_params

        malformed_key ->
          Ysc.Logging.warning(
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

    redact = fn map ->
      Map.filter(map, fn {k, _v} ->
        k = String.downcase(to_string(k))

        not (String.contains?(k, "token") or String.contains?(k, "pass") or
               String.contains?(k, "secret") or k == "redirect_to")
      end)
    end

    Ysc.Logging.info("[UserSessionController] passkey_login called",
      params: redact.(params),
      query_params: redact.(conn.query_params),
      path_params: conn.path_params,
      merged_params: redact.(merged_params),
      parsed_params: redact.(parsed_params),
      has_token: Map.has_key?(parsed_params, "token"),
      has_redirect_to: Map.has_key?(parsed_params, "redirect_to")
    )

    case parsed_params do
      %{"token" => token, "redirect_to" => redirect_to}
      when is_binary(token) and token != "" ->
        render_token_login_form(
          conn,
          ~p"/users/log-in/passkey",
          token,
          redirect_to
        )

      %{"token" => token} when is_binary(token) and token != "" ->
        render_token_login_form(conn, ~p"/users/log-in/passkey", token, nil)

      %{"user_id" => user_id} when is_binary(user_id) and user_id != "" ->
        case Ysc.AuthRateLimit.check_identifier(user_id) do
          :ok ->
            conn
            |> YscWeb.Flash.put_toast(:error, "Invalid login request.",
              title: "Login"
            )
            |> redirect(to: ~p"/users/log-in")

          {:error, :rate_limited, retry_after_sec} ->
            body = """
            <!DOCTYPE html>
            <html><head><title>Too Many Requests</title></head>
            <body><h1>Too many attempts</h1><p>Please try again in #{retry_after_sec} seconds.</p></body>
            </html>
            """

            conn
            |> put_resp_header(
              "retry-after",
              Integer.to_string(retry_after_sec)
            )
            |> put_resp_content_type("text/html")
            |> send_resp(429, body)
            |> halt()
        end

      _ ->
        Ysc.Logging.warning(
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
        |> YscWeb.Flash.put_toast(:error, "Invalid login request.",
          title: "Login"
        )
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # Find a key that looks like a malformed query string (contains & and =)
  defp find_malformed_query_key(params) when is_map(params) do
    Enum.find_value(params, fn {key, _value} ->
      if is_binary(key) && String.contains?(key, "=") &&
           String.contains?(key, "token") do
        key
      else
        nil
      end
    end)
  end

  def create_passkey_login(conn, %{
        "token" => token,
        "redirect_to" => redirect_to
      }) do
    passkey_login_with_token(conn, token, redirect_to)
  end

  def create_passkey_login(conn, %{"token" => token}) do
    passkey_login_with_token(conn, token, "")
  end

  def create_passkey_login(conn, _params) do
    conn
    |> YscWeb.Flash.put_toast(:error, "Invalid login request.", title: "Login")
    |> redirect(to: ~p"/users/log-in")
  end

  defp render_token_login_form(conn, action, token, redirect_to) do
    render(conn, :token_login_form,
      action: action,
      token: token,
      redirect_to: redirect_to,
      layout: false
    )
  end

  # sobelow_skip ["XSS.SendResp"]
  defp passkey_login_with_token(conn, token, redirect_to) do
    require Ysc.Logging

    # Per-identifier rate limit (token is unique per login attempt)
    case Ysc.AuthRateLimit.check_identifier(token) do
      :ok ->
        do_passkey_login_with_token(conn, token, redirect_to)

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

  defp do_passkey_login_with_token(conn, token, redirect_to) do
    require Ysc.Logging

    Ysc.Logging.info(
      "[UserSessionController] passkey_login_with_token called",
      %{
        redirect_to: redirect_to
      }
    )

    # Verify and atomically consume the one-time DB token issued by the LiveView
    # after successful passkey verification. Consuming on first use prevents replay
    # attacks within the token's TTL window.
    case Accounts.verify_and_consume_passkey_login_token(token) do
      {:ok, user} ->
        do_passkey_login_with_user(conn, user, redirect_to)

      {:error, :invalid_or_expired} ->
        Ysc.Logging.warning(
          "[UserSessionController] passkey_login token verification failed",
          %{}
        )

        conn
        |> YscWeb.Flash.put_toast(
          :error,
          "Invalid or expired login link. Please sign in again.",
          title: "Login"
        )
        |> redirect(to: ~p"/users/log-in")
    end
  end

  defp do_passkey_login_with_user(conn, user, redirect_to) do
    require Ysc.Logging

    if user.state in [:pending_approval, :active] do
      validated_redirect =
        if redirect_to && redirect_to != "" &&
             YscWeb.UserAuth.valid_internal_redirect?(redirect_to) do
          redirect_to
        else
          nil
        end

      Ysc.Logging.info(
        "[UserSessionController] Logging in user successfully",
        %{
          user_id: user.id,
          validated_redirect: validated_redirect
        }
      )

      conn
      |> delete_session(:failed_login_attempts)
      |> put_session(:just_logged_in, true)
      |> YscWeb.Flash.put_toast(
        :info,
        "Welcome back! 👋 Good to see you again.",
        title: "Welcome back! 👋"
      )
      |> UserAuth.log_in_user(
        user,
        %{"method" => "passkey", "remember_me" => "true"},
        validated_redirect
      )
    else
      Ysc.Logging.warning(
        "[UserSessionController] User account not active",
        %{
          user_id: user.id,
          user_state: user.state
        }
      )

      conn
      |> YscWeb.Flash.put_toast(
        :error,
        "Your account is not currently active.",
        title: "Login"
      )
      |> redirect(to: ~p"/users/log-in")
    end
  end
end
