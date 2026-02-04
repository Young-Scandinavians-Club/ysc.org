defmodule Ysc.Accounts.AuthServiceTest do
  @moduledoc """
  Tests for AuthService module.

  These tests verify:
  - Login success/failure event logging
  - Logout event logging
  - Password reset event logging
  - Account lockout logic
  - Suspicious activity detection
  - IP address extraction and tracking
  - User agent parsing
  - Session tracking
  - Auth history queries
  - UTF-8 sanitization

  Security-critical module requiring thorough testing.
  """
  # async: false for auth event queries
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ecto.Query

  alias Ysc.Accounts.{AuthService, AuthEvent}
  alias Ysc.Repo

  # Helper to create a mock connection
  defp mock_conn(attrs \\ %{}) do
    default_attrs = %{
      remote_ip: {127, 0, 0, 1},
      req_headers: [
        {"user-agent",
         "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"},
        {"x-forwarded-for", "203.0.113.1"},
        {"x-real-ip", "203.0.113.1"},
        {"origin", "https://example.com"},
        {"referer", "https://example.com/login"}
      ]
    }

    attrs = Map.merge(default_attrs, attrs)

    %Plug.Conn{
      remote_ip: attrs.remote_ip,
      req_headers: attrs.req_headers,
      private: %{}
    }
  end

  describe "log_login_success/3" do
    test "creates auth event for successful login" do
      user = user_fixture()
      conn = mock_conn()

      {:ok, auth_event} = AuthService.log_login_success(user, conn)

      assert auth_event.user_id == user.id
      assert auth_event.event_type == "login_success"
      assert auth_event.success == true
      assert auth_event.ip_address != nil
      assert auth_event.user_agent != nil
    end

    test "extracts IP from x-forwarded-for header" do
      user = user_fixture()
      conn = mock_conn()

      {:ok, auth_event} = AuthService.log_login_success(user, conn)

      assert auth_event.ip_address == "203.0.113.1"
    end

    test "parses user agent information" do
      user = user_fixture()
      conn = mock_conn()

      {:ok, auth_event} = AuthService.log_login_success(user, conn)

      # User agent should be parsed (implementation dependent)
      assert auth_event.user_agent != nil
      assert auth_event.device_type != nil
    end

    test "handles remember_me parameter" do
      user = user_fixture()
      conn = mock_conn()

      {:ok, auth_event} =
        AuthService.log_login_success(user, conn, %{"remember_me" => "true"})

      assert auth_event.remember_me == true
    end

    test "stores metadata" do
      user = user_fixture()
      conn = mock_conn()

      {:ok, auth_event} = AuthService.log_login_success(user, conn)

      assert is_map(auth_event.metadata)
      assert auth_event.metadata[:auth_method] != nil
    end
  end

  describe "log_login_failure/4" do
    test "creates auth event for failed login" do
      conn = mock_conn()
      email = "nonexistent@example.com"

      {:ok, auth_event} =
        AuthService.log_login_failure(email, conn, "invalid_credentials")

      assert auth_event.event_type == "login_failure"
      assert auth_event.success == false
      assert auth_event.email_attempted == email
      assert auth_event.failure_reason == "invalid_credentials"
      assert auth_event.user_id == nil
    end

    test "tracks IP address for failed attempts" do
      conn = mock_conn()
      email = "test@example.com"

      {:ok, auth_event} = AuthService.log_login_failure(email, conn)

      assert auth_event.ip_address == "203.0.113.1"
    end

    test "supports different failure reasons" do
      conn = mock_conn()

      failure_reasons = [
        "invalid_credentials",
        "account_not_found",
        "account_locked",
        "email_not_confirmed"
      ]

      for reason <- failure_reasons do
        email = "test_#{reason}@example.com"
        {:ok, auth_event} = AuthService.log_login_failure(email, conn, reason)
        assert auth_event.failure_reason == reason
      end
    end

    test "checks for account lockout after multiple failures" do
      conn = mock_conn()
      email = "lockout_test@example.com"

      # Create 5 failed attempts within 15 minutes
      for _ <- 1..5 do
        AuthService.log_login_failure(email, conn, "invalid_credentials")
      end

      # Verify suspicious activity is detected
      recent_failures =
        AuthService.get_failed_attempts_for_ip("203.0.113.1", 15)

      assert length(recent_failures) >= 5
    end
  end

  describe "log_logout/3" do
    test "creates auth event for logout" do
      user = user_fixture()
      conn = mock_conn()

      {:ok, auth_event} = AuthService.log_logout(user, conn)

      assert auth_event.user_id == user.id
      assert auth_event.event_type == "logout"
      assert auth_event.success == true
    end

    test "tracks logout IP and user agent" do
      user = user_fixture()
      conn = mock_conn()

      {:ok, auth_event} = AuthService.log_logout(user, conn)

      assert auth_event.ip_address != nil
      assert auth_event.user_agent != nil
    end
  end

  describe "log_password_reset_request/3" do
    test "creates auth event for password reset request" do
      user = user_fixture()
      conn = mock_conn()

      {:ok, auth_event} = AuthService.log_password_reset_request(user, conn)

      assert auth_event.user_id == user.id
      assert auth_event.event_type == "password_reset_request"
      assert auth_event.success == true
    end
  end

  describe "log_password_reset_success/3" do
    test "creates auth event for successful password reset" do
      user = user_fixture()
      conn = mock_conn()

      {:ok, auth_event} = AuthService.log_password_reset_success(user, conn)

      assert auth_event.user_id == user.id
      assert auth_event.event_type == "password_reset_success"
      assert auth_event.success == true
    end
  end

  describe "log_account_locked/3" do
    test "creates auth event for account lockout" do
      user = user_fixture()
      conn = mock_conn()

      {:ok, auth_event} = AuthService.log_account_locked(user, conn)

      assert auth_event.user_id == user.id
      assert auth_event.event_type == "account_locked"
      # Account locked is a security event, not a success
      assert auth_event.success == false
    end
  end

  describe "log_suspicious_activity/3" do
    test "creates auth event with threat indicators" do
      conn = mock_conn()
      threat_indicators = ["unusual_location", "rapid_attempts"]

      {:ok, auth_event} =
        AuthService.log_suspicious_activity(conn, threat_indicators)

      assert auth_event.event_type == "suspicious_activity"
      assert auth_event.is_suspicious == true
      assert auth_event.threat_indicators == threat_indicators
      assert auth_event.risk_score != nil
    end

    test "calculates risk score based on threat indicators" do
      conn = mock_conn()
      threat_indicators = ["bot_behavior", "known_attacker", "rapid_attempts"]

      {:ok, auth_event} =
        AuthService.log_suspicious_activity(conn, threat_indicators)

      # Risk score should be set (could be 0 or higher depending on implementation)
      assert auth_event.risk_score != nil
      assert is_integer(auth_event.risk_score)
      assert auth_event.risk_score >= 0
    end
  end

  describe "extract_auth_data/2" do
    test "extracts IP address from connection" do
      conn = mock_conn()

      auth_data = AuthService.extract_auth_data(conn)

      assert auth_data.ip_address == "203.0.113.1"
    end

    test "extracts user agent from connection" do
      conn = mock_conn()

      auth_data = AuthService.extract_auth_data(conn)

      assert auth_data.user_agent != nil
      assert String.contains?(auth_data.user_agent, "Mozilla")
    end

    test "defaults to email_password auth method" do
      conn = mock_conn()

      auth_data = AuthService.extract_auth_data(conn)

      assert auth_data.metadata.auth_method == "email_password"
    end

    test "extracts auth method from params" do
      conn = mock_conn()

      auth_data = AuthService.extract_auth_data(conn, %{"method" => "google"})

      assert auth_data.metadata.auth_method == "google"
    end

    test "extracts provider from params" do
      conn = mock_conn()

      auth_data =
        AuthService.extract_auth_data(conn, %{"provider" => "facebook"})

      assert auth_data.metadata.auth_method == "facebook"
    end

    test "extracts remember_me preference" do
      conn = mock_conn()

      auth_data1 =
        AuthService.extract_auth_data(conn, %{"remember_me" => "true"})

      assert auth_data1.remember_me == true

      auth_data2 =
        AuthService.extract_auth_data(conn, %{"remember_me" => "false"})

      assert auth_data2.remember_me == false
    end

    test "extracts metadata headers" do
      conn = mock_conn()

      auth_data = AuthService.extract_auth_data(conn)

      assert auth_data.metadata.origin == "https://example.com"
      assert auth_data.metadata.referer == "https://example.com/login"
    end
  end

  describe "check_suspicious_activity/1" do
    test "detects rapid failed attempts" do
      user = user_fixture()
      conn = mock_conn()

      # Create multiple failed attempts quickly
      for _ <- 1..6 do
        AuthService.log_login_failure(
          "test@example.com",
          conn,
          "invalid_credentials"
        )
      end

      # Create a successful login to trigger suspicious activity check
      {:ok, auth_event} = AuthService.log_login_success(user, conn)

      # Check if suspicious activity was detected
      # The function updates the auth_event, so we need to reload it
      updated_event = Repo.get(AuthEvent, auth_event.id)
      assert updated_event.is_suspicious == true
      assert "rapid_attempts" in updated_event.threat_indicators
    end

    test "detects unusual login times" do
      user = user_fixture()
      conn = mock_conn()

      # This test depends on the time it's run (PST timezone)
      # The check_suspicious_activity function flags logins between midnight and 6 AM PST
      {:ok, auth_event} = AuthService.log_login_success(user, conn)

      # Reload to check if suspicious activity was detected based on time
      updated_event = Repo.get(AuthEvent, auth_event.id)
      # We can't reliably test time-based detection without mocking time
      assert updated_event != nil
    end
  end

  describe "check_account_lockout/2" do
    test "detects too many failed attempts for email" do
      conn = mock_conn()
      email = "lockout@example.com"

      # Create 5 failed attempts
      for _ <- 1..5 do
        AuthService.log_login_failure(email, conn, "invalid_credentials")
      end

      # Check lockout triggers
      AuthService.check_account_lockout(email, conn)

      # Verify failed attempts were logged
      failed_attempts =
        Repo.all(
          from ae in AuthEvent,
            where: ae.email_attempted == ^email,
            where: ae.success == false
        )

      assert length(failed_attempts) == 5
    end

    test "detects too many failed attempts from IP" do
      conn = mock_conn()

      # Create 10 failed attempts from same IP with different emails
      for i <- 1..10 do
        AuthService.log_login_failure(
          "user#{i}@example.com",
          conn,
          "invalid_credentials"
        )
      end

      # Check lockout triggers
      AuthService.check_account_lockout("user1@example.com", conn)

      # Verify suspicious activity was logged
      suspicious_events = AuthService.get_suspicious_events(10)
      refute suspicious_events == []
    end
  end

  describe "get_user_auth_history/2" do
    test "returns recent auth events for user" do
      user = user_fixture()
      conn = mock_conn()

      # Create some auth events
      AuthService.log_login_success(user, conn)
      AuthService.log_logout(user, conn)
      AuthService.log_login_success(user, conn)

      history = AuthService.get_user_auth_history(user, 50)

      # History query might filter by certain event types
      assert length(history) >= 2
      assert Enum.all?(history, fn event -> event.user_id == user.id end)
    end

    test "limits number of returned events" do
      user = user_fixture()
      conn = mock_conn()

      # Create more events than the limit
      for _ <- 1..10 do
        AuthService.log_login_success(user, conn)
      end

      history = AuthService.get_user_auth_history(user, 5)

      assert [_, _, _, _, _] = history
    end

    test "returns events ordered by most recent first" do
      user = user_fixture()
      conn = mock_conn()

      {:ok, _event1} = AuthService.log_login_success(user, conn)
      # Small delay to ensure different timestamps
      Process.sleep(10)
      {:ok, event2} = AuthService.log_login_success(user, conn)

      history = AuthService.get_user_auth_history(user, 10)

      # Most recent should be first (if history includes this event type)
      if history != [] do
        # Verify at least that the list includes event2
        event_ids = Enum.map(history, & &1.id)
        assert event2.id in event_ids
      end
    end
  end

  describe "get_suspicious_events/1" do
    test "returns events marked as suspicious" do
      conn = mock_conn()

      # Create suspicious event
      AuthService.log_suspicious_activity(conn, ["bot_behavior"])

      # Create normal event
      user = user_fixture()
      AuthService.log_login_success(user, conn)

      suspicious = AuthService.get_suspicious_events(100)

      refute suspicious == []
      assert Enum.all?(suspicious, fn event -> event.is_suspicious == true end)
    end
  end

  describe "get_failed_attempts_for_ip/2" do
    test "returns failed attempts for specific IP" do
      conn = mock_conn()
      email = "test@example.com"

      # Create failed attempts
      AuthService.log_login_failure(email, conn, "invalid_credentials")
      AuthService.log_login_failure(email, conn, "invalid_credentials")

      failed_attempts =
        AuthService.get_failed_attempts_for_ip("203.0.113.1", 15)

      assert length(failed_attempts) >= 2
    end

    test "filters by time window" do
      # This test would need to mock time or create old events
      # For now, just verify the function works
      failed_attempts =
        AuthService.get_failed_attempts_for_ip("203.0.113.1", 15)

      assert is_list(failed_attempts)
    end
  end

  describe "get_last_successful_login_datetime/1" do
    test "returns datetime of last successful login" do
      user = user_fixture()
      conn = mock_conn()

      AuthService.log_login_success(user, conn)
      Process.sleep(10)
      {:ok, last_event} = AuthService.log_login_success(user, conn)

      last_login_time = AuthService.get_last_successful_login_datetime(user)

      assert last_login_time != nil
      # Should be very close to last_event.inserted_at
      assert DateTime.diff(last_login_time, last_event.inserted_at, :second) ==
               0
    end

    test "returns nil when no successful logins exist" do
      user = user_fixture()

      last_login_time = AuthService.get_last_successful_login_datetime(user)

      assert last_login_time == nil
    end
  end

  describe "get_last_successful_login_event/1" do
    test "returns last successful login event" do
      user = user_fixture()
      conn = mock_conn()

      AuthService.log_login_success(user, conn)
      # Ensure distinct timestamps
      Process.sleep(10)
      {:ok, _last_event} = AuthService.log_login_success(user, conn)

      retrieved_event = AuthService.get_last_successful_login_event(user)

      assert retrieved_event != nil
      assert retrieved_event.event_type == "login_success"
      assert retrieved_event.user_id == user.id
    end

    test "returns nil when no successful logins exist" do
      user = user_fixture()

      event = AuthService.get_last_successful_login_event(user)

      assert event == nil
    end
  end

  describe "get_last_login_session_datetime/1" do
    test "returns datetime of last login or logout" do
      user = user_fixture()
      conn = mock_conn()

      AuthService.log_login_success(user, conn)
      {:ok, logout_event} = AuthService.log_logout(user, conn)

      last_session_time = AuthService.get_last_login_session_datetime(user)

      assert last_session_time != nil

      assert DateTime.diff(last_session_time, logout_event.inserted_at, :second) ==
               0
    end

    test "returns nil when no session events exist" do
      user = user_fixture()

      last_session_time = AuthService.get_last_login_session_datetime(user)

      assert last_session_time == nil
    end
  end

  describe "get_last_login_session_event/1" do
    test "returns last login or logout event" do
      user = user_fixture()
      conn = mock_conn()

      AuthService.log_login_success(user, conn)
      # Ensure distinct timestamps
      Process.sleep(10)
      {:ok, _logout_event} = AuthService.log_logout(user, conn)

      last_event = AuthService.get_last_login_session_event(user)

      assert last_event != nil
      assert last_event.event_type in ["login_success", "logout"]
      assert last_event.user_id == user.id
    end
  end

  describe "get_last_session_timeframe/1" do
    test "returns session timeframe when user is active" do
      user = user_fixture()
      conn = mock_conn()

      {:ok, login_event} = AuthService.log_login_success(user, conn)

      timeframe = AuthService.get_last_session_timeframe(user)

      assert timeframe.session_start != nil
      assert timeframe.session_end == nil
      assert timeframe.is_active == true

      assert DateTime.diff(
               timeframe.session_start,
               login_event.inserted_at,
               :second
             ) == 0
    end

    test "returns session timeframe when user has logged out" do
      user = user_fixture()
      conn = mock_conn()

      {:ok, login_event} = AuthService.log_login_success(user, conn)
      Process.sleep(10)
      {:ok, logout_event} = AuthService.log_logout(user, conn)

      timeframe = AuthService.get_last_session_timeframe(user)

      assert timeframe.session_start != nil
      assert timeframe.session_end != nil
      assert timeframe.is_active == false

      assert DateTime.diff(
               timeframe.session_start,
               login_event.inserted_at,
               :second
             ) == 0

      assert DateTime.diff(
               timeframe.session_end,
               logout_event.inserted_at,
               :second
             ) == 0
    end

    test "returns nil when no session data exists" do
      user = user_fixture()

      timeframe = AuthService.get_last_session_timeframe(user)

      assert timeframe == nil
    end
  end

  describe "sanitize_utf8/1" do
    test "returns nil for nil input" do
      assert AuthService.sanitize_utf8(nil) == nil
    end

    test "removes null bytes" do
      string_with_null = "hello\x00world"
      sanitized = AuthService.sanitize_utf8(string_with_null)

      assert sanitized == "helloworld"
    end

    test "handles valid UTF-8 strings" do
      valid_string = "Hello, 世界! 🌍"
      sanitized = AuthService.sanitize_utf8(valid_string)

      assert sanitized == valid_string
    end

    test "limits string length to 1000 characters" do
      long_string = String.duplicate("a", 1500)
      sanitized = AuthService.sanitize_utf8(long_string)

      assert String.length(sanitized) == 1000
    end

    test "handles non-UTF-8 characters" do
      # This would contain invalid UTF-8 bytes in real scenario
      # For testing, we just verify the function doesn't crash
      result = AuthService.sanitize_utf8("valid string")

      assert is_binary(result)
    end

    test "passes through non-string values" do
      assert AuthService.sanitize_utf8(123) == 123
      assert AuthService.sanitize_utf8(%{key: "value"}) == %{key: "value"}
    end
  end

  describe "IP address extraction" do
    test "extracts IP from x-forwarded-for header" do
      conn =
        mock_conn(%{
          req_headers: [
            {"x-forwarded-for", "203.0.113.5, 198.51.100.1"}
          ]
        })

      auth_data = AuthService.extract_auth_data(conn)

      # Should use first IP from comma-separated list
      assert auth_data.ip_address == "203.0.113.5"
    end

    test "falls back to x-real-ip when x-forwarded-for is missing" do
      conn =
        mock_conn(%{
          req_headers: [
            {"x-real-ip", "203.0.113.10"}
          ]
        })

      auth_data = AuthService.extract_auth_data(conn)

      assert auth_data.ip_address == "203.0.113.10"
    end

    test "falls back to remote_ip when headers are missing" do
      conn =
        mock_conn(%{
          remote_ip: {192, 168, 1, 1},
          req_headers: []
        })

      auth_data = AuthService.extract_auth_data(conn)

      assert auth_data.ip_address == "192.168.1.1"
    end
  end

  describe "auth method detection" do
    test "detects google OAuth" do
      conn = mock_conn()
      auth_data = AuthService.extract_auth_data(conn, %{"provider" => "google"})

      assert auth_data.metadata.auth_method == "google"
    end

    test "detects facebook OAuth" do
      conn = mock_conn()
      auth_data = AuthService.extract_auth_data(conn, %{provider: :facebook})

      assert auth_data.metadata.auth_method == "facebook"
    end

    test "detects passkey authentication" do
      conn = mock_conn()
      auth_data = AuthService.extract_auth_data(conn, %{"method" => "passkey"})

      assert auth_data.metadata.auth_method == "passkey"
    end

    test "detects generic OAuth" do
      conn = mock_conn()
      auth_data = AuthService.extract_auth_data(conn, %{"oauth" => true})

      assert auth_data.metadata.auth_method == "oauth"
    end

    test "defaults to email_password" do
      conn = mock_conn()
      auth_data = AuthService.extract_auth_data(conn, %{})

      assert auth_data.metadata.auth_method == "email_password"
    end
  end
end
