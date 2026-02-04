defmodule Ysc.Accounts.AuthService do
  @moduledoc """
  Service for handling authentication events and logging.
  """

  import Ecto.Query
  import Plug.Conn
  alias Ysc.Accounts.{AuthEvent, User}
  alias Ysc.Repo

  @doc """
  Logs a successful login attempt.
  """
  def log_login_success(user, conn, params \\ %{}) do
    auth_data = extract_auth_data(conn, params)

    AuthEvent.login_success_changeset(user, auth_data)
    |> Repo.insert()
    |> case do
      {:ok, auth_event} ->
        # Check for suspicious activity after successful login
        check_suspicious_activity(auth_event)
        {:ok, auth_event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Logs a failed login attempt.
  """
  def log_login_failure(
        email,
        conn,
        failure_reason \\ "invalid_credentials",
        params \\ %{}
      ) do
    auth_data = extract_auth_data(conn, params)

    auth_data =
      auth_data
      |> Map.put(:email_attempted, email)
      |> Map.put(:failure_reason, failure_reason)

    AuthEvent.login_failure_changeset(auth_data)
    |> Repo.insert()
    |> case do
      {:ok, auth_event} ->
        # Check for suspicious activity and potential account lockout
        check_suspicious_activity(auth_event)
        check_account_lockout(email, conn)
        {:ok, auth_event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Logs a logout event.
  """
  def log_logout(user, conn, params \\ %{}) do
    auth_data = extract_auth_data(conn, params)

    AuthEvent.logout_changeset(user, auth_data)
    |> Repo.insert()
  end

  @doc """
  Logs a password reset request.
  """
  def log_password_reset_request(user, conn, params \\ %{}) do
    auth_data = extract_auth_data(conn, params)

    AuthEvent.password_reset_request_changeset(user, auth_data)
    |> Repo.insert()
  end

  @doc """
  Logs a successful password reset.
  """
  def log_password_reset_success(user, conn, params \\ %{}) do
    auth_data = extract_auth_data(conn, params)

    AuthEvent.password_reset_success_changeset(user, auth_data)
    |> Repo.insert()
  end

  @doc """
  Logs account lockout.
  """
  def log_account_locked(user, conn, params \\ %{}) do
    auth_data = extract_auth_data(conn, params)

    AuthEvent.account_locked_changeset(user, auth_data)
    |> Repo.insert()
  end

  @doc """
  Logs suspicious activity.
  """
  def log_suspicious_activity(conn, threat_indicators, params \\ %{}) do
    auth_data = extract_auth_data(conn, params)

    auth_data =
      auth_data
      |> Map.put(:threat_indicators, threat_indicators)
      |> Map.put(:is_suspicious, true)
      |> Map.put(:risk_score, AuthEvent.calculate_risk_score(auth_data))

    AuthEvent.suspicious_activity_changeset(auth_data)
    |> Repo.insert()
  end

  @doc """
  Extracts authentication data from the connection or socket.
  """
  def extract_auth_data(conn_or_socket, params \\ %{}) do
    conn =
      case conn_or_socket do
        # LiveView socket
        %{assigns: %{live_socket: %{conn: conn}}} -> conn
        # Regular connection
        conn when is_map(conn) -> conn
      end

    # Extract authentication method from params (google, facebook, passkey, email_password)
    auth_method =
      cond do
        Map.has_key?(params, "method") ->
          Map.get(params, "method")

        Map.has_key?(params, :method) ->
          Map.get(params, :method)

        Map.has_key?(params, "provider") ->
          Map.get(params, "provider") |> to_string()

        Map.has_key?(params, :provider) ->
          Map.get(params, :provider) |> to_string()

        # fallback for oauth without provider
        Map.get(params, "oauth") == true ->
          "oauth"

        # default for email/password login
        true ->
          "email_password"
      end

    base_metadata = %{
      forwarded_for: sanitize_utf8(get_header(conn, "x-forwarded-for")),
      real_ip: sanitize_utf8(get_header(conn, "x-real-ip")),
      origin: sanitize_utf8(get_header(conn, "origin")),
      referer: sanitize_utf8(get_header(conn, "referer")),
      auth_method: auth_method
    }

    %{
      ip_address: get_client_ip(conn),
      user_agent: sanitize_utf8(get_user_agent(conn)),
      session_id: get_session_id(conn),
      remember_me: Map.get(params, "remember_me") == "true",
      metadata: base_metadata
    }
    |> Map.merge(parse_user_agent_data(conn))
  end

  @doc """
  Checks for suspicious activity based on recent events.
  """
  def check_suspicious_activity(auth_event) do
    # Check for rapid failed attempts from same IP
    recent_failed_attempts =
      AuthEvent.recent_failed_attempts_query(auth_event.ip_address, 15)
      |> Repo.all()
      |> length()

    threat_indicators = []

    threat_indicators =
      if recent_failed_attempts > 5,
        do: ["rapid_attempts" | threat_indicators],
        else: threat_indicators

    threat_indicators =
      if recent_failed_attempts > 10,
        do: ["suspicious_ip" | threat_indicators],
        else: threat_indicators

    current_hour_pst =
      DateTime.now!("America/Los_Angeles")
      |> Map.get(:hour)

    threat_indicators =
      if current_hour_pst < 6 or current_hour_pst > 23 do
        ["unusual_time" | threat_indicators]
      else
        threat_indicators
      end

    # Check for new device (simplified - in production you'd want more sophisticated device fingerprinting)
    threat_indicators =
      if auth_event.user_id do
        recent_devices =
          from(ae in AuthEvent,
            where: ae.user_id == ^auth_event.user_id,
            where: ae.success == true,
            where: ae.inserted_at > ago(30, "day"),
            select: ae.device_type,
            distinct: true
          )
          |> Repo.all()

        if auth_event.device_type in recent_devices do
          threat_indicators
        else
          ["new_device" | threat_indicators]
        end
      else
        threat_indicators
      end

    if threat_indicators != [] do
      # Update the auth event with threat indicators
      auth_event
      |> Ecto.Changeset.change(%{
        threat_indicators: threat_indicators,
        is_suspicious: true,
        risk_score:
          AuthEvent.calculate_risk_score(%{
            threat_indicators: threat_indicators
          })
      })
      |> Repo.update()
    end
  end

  @doc """
  Checks if an account should be locked due to too many failed attempts.
  """
  def check_account_lockout(email, conn) do
    ip_address = get_client_ip(conn)

    # Check failed attempts for this email in the last 15 minutes
    recent_failed_attempts =
      AuthEvent.recent_failed_attempts_for_email_query(email, 15)
      |> Repo.all()
      |> length()

    # Check failed attempts from this IP in the last 15 minutes
    recent_ip_attempts =
      AuthEvent.recent_failed_attempts_query(ip_address, 15)
      |> Repo.all()
      |> length()

    # Lock account if too many failed attempts
    if recent_failed_attempts >= 5 or recent_ip_attempts >= 10 do
      if _user = Repo.get_by(User, email: email) do
        # In a real implementation, you'd want to add a locked_at field to User
        # and implement proper account locking logic
        log_suspicious_activity(conn, ["too_many_attempts"], %{})
      end
    end
  end

  @doc """
  Gets recent authentication events for a user.
  """
  def get_user_auth_history(user, limit \\ 50) do
    AuthEvent.user_login_history_query(user, limit)
    |> Repo.all()
  end

  @doc """
  Gets suspicious events for monitoring.
  """
  def get_suspicious_events(limit \\ 100) do
    AuthEvent.suspicious_events_query(limit)
    |> Repo.all()
  end

  @doc """
  Gets failed login attempts for an IP address.
  """
  def get_failed_attempts_for_ip(ip_address, minutes \\ 15) do
    AuthEvent.recent_failed_attempts_query(ip_address, minutes)
    |> Repo.all()
  end

  @doc """
  Gets the datetime of the last successful login for a user.
  Returns nil if no successful login is found.
  """
  def get_last_successful_login_datetime(user) do
    from(ae in AuthEvent,
      where: ae.user_id == ^user.id,
      where: ae.event_type == "login_success",
      where: ae.success == true,
      order_by: [desc: ae.inserted_at],
      limit: 1,
      select: ae.inserted_at
    )
    |> Repo.one()
  end

  @doc """
  Gets the last successful login event for a user.
  Returns nil if no successful login is found.
  """
  def get_last_successful_login_event(user) do
    from(ae in AuthEvent,
      where: ae.user_id == ^user.id,
      where: ae.event_type == "login_success",
      where: ae.success == true,
      order_by: [desc: ae.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets the last time a user was logged in (either login or logout event).
  This helps determine when the user was last active on the site.
  Returns nil if no login/logout events are found.
  """
  def get_last_login_session_datetime(user) do
    from(ae in AuthEvent,
      where: ae.user_id == ^user.id,
      where: ae.event_type in ["login_success", "logout"],
      where: ae.success == true,
      order_by: [desc: ae.inserted_at],
      limit: 1,
      select: ae.inserted_at
    )
    |> Repo.one()
  end

  @doc """
  Gets the last login session event for a user (either login or logout).
  This helps determine when the user was last active on the site.
  Returns nil if no login/logout events are found.
  """
  def get_last_login_session_event(user) do
    from(ae in AuthEvent,
      where: ae.user_id == ^user.id,
      where: ae.event_type in ["login_success", "logout"],
      where: ae.success == true,
      order_by: [desc: ae.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets the time range when the user was last active on the site.
  Returns a map with :session_start and :session_end datetimes.
  This helps determine what content the user might have missed.
  """
  def get_last_session_timeframe(user) do
    # Get the most recent login and logout events
    last_login =
      from(ae in AuthEvent,
        where: ae.user_id == ^user.id,
        where: ae.event_type == "login_success",
        where: ae.success == true,
        order_by: [desc: ae.inserted_at],
        limit: 1,
        select: ae.inserted_at
      )
      |> Repo.one()

    last_logout =
      from(ae in AuthEvent,
        where: ae.user_id == ^user.id,
        where: ae.event_type == "logout",
        where: ae.success == true,
        order_by: [desc: ae.inserted_at],
        limit: 1,
        select: ae.inserted_at
      )
      |> Repo.one()

    case {last_login, last_logout} do
      {nil, nil} ->
        # No session data
        nil

      {login_time, nil} ->
        # User logged in but never logged out (still active or session expired)
        %{session_start: login_time, session_end: nil, is_active: true}

      {nil, logout_time} ->
        # User logged out but no login found (shouldn't happen normally)
        %{session_start: nil, session_end: logout_time, is_active: false}

      {login_time, logout_time} ->
        # Both login and logout found
        if DateTime.compare(login_time, logout_time) == :gt do
          # Login is more recent than logout (user is currently active)
          %{session_start: login_time, session_end: nil, is_active: true}
        else
          # Logout is more recent than login (user's last session ended)
          %{
            session_start: login_time,
            session_end: logout_time,
            is_active: false
          }
        end
    end
  end

  # Private helper functions

  defp get_client_ip(conn_or_socket) do
    case conn_or_socket do
      %Plug.Conn{} = conn ->
        # Check for forwarded IP first (for load balancers/proxies)
        get_conn_client_ip(conn)

      %Phoenix.LiveView.Socket{} ->
        # For LiveView sockets, we don't have direct access to IP
        # Return a default value for now
        "127.0.0.1"

      _ ->
        "127.0.0.1"
    end
  end

  defp get_conn_client_ip(conn) do
    case get_header(conn, "x-forwarded-for") do
      nil ->
        get_real_ip_or_fallback(conn)

      forwarded_for ->
        # Take the first IP from comma-separated list
        forwarded_for
        |> String.split(",")
        |> List.first()
        |> String.trim()
    end
  end

  defp get_real_ip_or_fallback(conn) do
    case get_header(conn, "x-real-ip") do
      nil ->
        # Fall back to remote_ip
        conn.remote_ip
        |> :inet.ntoa()
        |> to_string()

      real_ip ->
        # Take the first IP from comma-separated list
        real_ip
        |> String.split(",")
        |> List.first()
        |> String.trim()
    end
  end

  defp get_user_agent(conn_or_socket) do
    get_header(conn_or_socket, "user-agent")
  end

  defp get_session_id(conn_or_socket) do
    case conn_or_socket do
      %Plug.Conn{} = conn ->
        # Phoenix session ID is not directly accessible, but we can use the session token
        try do
          case get_session(conn, :user_token) do
            nil ->
              nil

            token when is_binary(token) ->
              # Convert binary token to base64 string to avoid null bytes
              Base.encode64(token)

            other ->
              # Handle any other type
              to_string(other)
          end
        rescue
          # Session not fetched
          ArgumentError -> nil
        end

      %Phoenix.LiveView.Socket{} ->
        # For LiveView sockets, we don't have direct access to session
        # Return nil for now
        nil

      _ ->
        nil
    end
  end

  defp get_header(conn_or_socket, header) do
    case conn_or_socket do
      %Plug.Conn{} = conn ->
        case Plug.Conn.get_req_header(conn, header) do
          [value | _] -> value
          [] -> nil
        end

      %Phoenix.LiveView.Socket{} ->
        # LiveView sockets don't have direct access to request headers
        # Return nil for now - this could be enhanced to extract from socket assigns if needed
        nil

      _ ->
        nil
    end
  end

  defp parse_user_agent_data(conn_or_socket) do
    case get_user_agent(conn_or_socket) do
      nil ->
        %{}

      user_agent ->
        sanitized_user_agent = sanitize_utf8(user_agent)
        AuthEvent.parse_user_agent(sanitized_user_agent)
    end
  end

  @doc """
  Sanitizes a string to ensure it's valid UTF-8.
  """
  def sanitize_utf8(nil), do: nil

  def sanitize_utf8(string) when is_binary(string) do
    # First remove null bytes which PostgreSQL doesn't allow
    cleaned_string = String.replace(string, "\x00", "")

    case :unicode.characters_to_binary(cleaned_string, :utf8, :utf8) do
      {:error, _, _} ->
        # If conversion fails, try to clean the string
        cleaned_string
        # Replace non-ASCII with ?
        |> String.replace(~r/[^\x00-\x7F]/, "?")
        # Limit length
        |> String.slice(0, 1000)

      {:incomplete, _, _} ->
        # If incomplete, truncate and clean
        cleaned_string
        |> String.replace(~r/[^\x00-\x7F]/, "?")
        |> String.slice(0, 1000)

      clean_string ->
        # Valid UTF-8, just limit length
        String.slice(clean_string, 0, 1000)
    end
  end

  def sanitize_utf8(other), do: other
end
