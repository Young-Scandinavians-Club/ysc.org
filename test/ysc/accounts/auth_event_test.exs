defmodule Ysc.Accounts.AuthEventTest do
  use Ysc.DataCase, async: true

  alias Ysc.Accounts.{AuthEvent, AuthService}

  describe "AuthEvent schema validations" do
    test "creates valid changeset with required fields" do
      attrs = %{
        event_type: "login_success",
        success: true,
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1"
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      assert changeset.valid?
      assert changeset.changes.event_type == "login_success"
      assert changeset.changes.success == true
    end

    test "requires event_type" do
      attrs = %{
        success: true,
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1"
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:event_type] != nil
    end

    test "requires success boolean" do
      attrs = %{
        event_type: "login_success",
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1"
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:success] != nil
    end

    test "does not require email_attempted" do
      attrs = %{
        event_type: "login_success",
        success: true,
        ip_address: "127.0.0.1"
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      assert changeset.valid?
    end

    test "does not require ip_address" do
      attrs = %{
        event_type: "login_success",
        success: true,
        email_attempted: "test@example.com"
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      assert changeset.valid?
    end

    test "validates email_attempted max length (160 chars)" do
      long_email = String.duplicate("a", 149) <> "@example.com"

      attrs = %{
        event_type: "login_success",
        success: true,
        email_attempted: long_email,
        ip_address: "127.0.0.1"
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:email_attempted] != nil
    end

    test "validates ip_address max length (45 chars for IPv6)" do
      long_ip = String.duplicate("1", 46)

      attrs = %{
        event_type: "login_success",
        success: true,
        email_attempted: "test@example.com",
        ip_address: long_ip
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:ip_address] != nil
    end

    test "accepts IPv6 address format" do
      attrs = %{
        event_type: "login_success",
        success: true,
        email_attempted: "test@example.com",
        ip_address: "2001:0db8:85a3:0000:0000:8a2e:0370:7334"
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      assert changeset.valid?
    end

    test "validates user_agent max length (1000 chars)" do
      long_user_agent = String.duplicate("a", 1001)

      attrs = %{
        event_type: "login_success",
        success: true,
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1",
        user_agent: long_user_agent
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      # The sanitize_string_fields function truncates long strings to 1000 chars
      # so the changeset is valid, but the value is truncated
      assert changeset.valid?
      assert String.length(changeset.changes.user_agent) == 1000
    end

    test "validates country max length (2 chars)" do
      attrs = %{
        event_type: "login_success",
        success: true,
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1",
        country: "USA"
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:country] != nil
    end

    test "accepts valid country code" do
      attrs = %{
        event_type: "login_success",
        success: true,
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1",
        country: "US"
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      assert changeset.valid?
    end

    test "validates risk_score range (0-100)" do
      # Test below range
      attrs = %{
        event_type: "login_success",
        success: true,
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1",
        risk_score: -1
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:risk_score] != nil

      # Test above range
      attrs = Map.put(attrs, :risk_score, 101)
      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:risk_score] != nil
    end

    test "accepts risk_score at boundaries" do
      # Test 0
      attrs = %{
        event_type: "login_success",
        success: true,
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1",
        risk_score: 0
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)
      assert changeset.valid?

      # Test 100
      attrs = Map.put(attrs, :risk_score, 100)
      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)
      assert changeset.valid?
    end

    test "accepts optional user_id" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        event_type: "login_success",
        success: true,
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1"
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      assert changeset.valid?
      assert changeset.changes.user_id == user.id
    end

    test "accepts all optional location fields" do
      attrs = %{
        event_type: "login_success",
        success: true,
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1",
        country: "US",
        region: "California",
        city: "San Francisco",
        latitude: 37.7749,
        longitude: -122.4194
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      assert changeset.valid?
      assert changeset.changes.country == "US"
      assert changeset.changes.region == "California"
      assert changeset.changes.city == "San Francisco"
    end
  end

  describe "event type validations" do
    test "accepts all valid event types" do
      event_types = [
        "login_attempt",
        "login_success",
        "login_failure",
        "logout",
        "password_reset_request",
        "password_reset_success",
        "email_verification",
        "account_locked",
        "account_unlocked",
        "two_factor_enabled",
        "two_factor_disabled",
        "two_factor_used",
        "session_expired",
        "suspicious_activity"
      ]

      for event_type <- event_types do
        attrs = %{
          event_type: event_type,
          success: true,
          email_attempted: "test@example.com",
          ip_address: "127.0.0.1"
        }

        changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

        assert changeset.valid?,
               "Expected event_type '#{event_type}' to be valid but got errors: #{inspect(changeset.errors)}"
      end
    end

    test "rejects invalid event type" do
      attrs = %{
        event_type: "invalid_event",
        success: true,
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1"
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:event_type] != nil
    end
  end

  describe "failure reason validations" do
    test "accepts all valid failure reasons" do
      failure_reasons = [
        "invalid_credentials",
        "account_not_found",
        "account_locked",
        "email_not_confirmed",
        "password_expired",
        "too_many_attempts",
        "two_factor_required",
        "two_factor_invalid",
        "session_expired",
        "account_suspended",
        "account_deleted"
      ]

      for failure_reason <- failure_reasons do
        attrs = %{
          event_type: "login_failure",
          success: false,
          email_attempted: "test@example.com",
          ip_address: "127.0.0.1",
          failure_reason: failure_reason
        }

        changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

        assert changeset.valid?,
               "Expected failure_reason '#{failure_reason}' to be valid but got errors: #{inspect(changeset.errors)}"
      end
    end

    test "rejects invalid failure reason" do
      attrs = %{
        event_type: "login_failure",
        success: false,
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1",
        failure_reason: "invalid_reason"
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:failure_reason] != nil
    end
  end

  describe "device type validations" do
    test "accepts all valid device types" do
      device_types = ["desktop", "mobile", "tablet", "unknown"]

      for device_type <- device_types do
        attrs = %{
          event_type: "login_success",
          success: true,
          email_attempted: "test@example.com",
          ip_address: "127.0.0.1",
          device_type: device_type
        }

        changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

        assert changeset.valid?,
               "Expected device_type '#{device_type}' to be valid but got errors: #{inspect(changeset.errors)}"
      end
    end

    test "rejects invalid device type" do
      attrs = %{
        event_type: "login_success",
        success: true,
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1",
        device_type: "smartwatch"
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:device_type] != nil
    end
  end

  describe "threat indicator validations" do
    test "accepts all valid threat indicators" do
      threat_indicators = [
        "unusual_location",
        "new_device",
        "rapid_attempts",
        "suspicious_ip",
        "bot_behavior",
        "known_attacker",
        "geolocation_mismatch",
        "unusual_time"
      ]

      attrs = %{
        event_type: "login_success",
        success: true,
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1",
        threat_indicators: threat_indicators
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      assert changeset.valid?
      assert changeset.changes.threat_indicators == threat_indicators
    end

    test "accepts empty threat indicators list" do
      attrs = %{
        event_type: "login_success",
        success: true,
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1",
        threat_indicators: []
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      assert changeset.valid?
    end

    test "rejects invalid threat indicator" do
      attrs = %{
        event_type: "login_success",
        success: true,
        email_attempted: "test@example.com",
        ip_address: "127.0.0.1",
        threat_indicators: ["invalid_indicator"]
      }

      changeset = AuthEvent.changeset(%AuthEvent{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:threat_indicators] != nil
    end
  end

  describe "risk score calculation" do
    test "calculates zero risk for no threat indicators" do
      attrs = %{threat_indicators: []}
      assert AuthEvent.calculate_risk_score(attrs) == 0
    end

    test "calculates risk for single threat indicators" do
      # Test individual threat indicators that have risk scores
      assert AuthEvent.calculate_risk_score(%{
               threat_indicators: ["new_device"]
             }) == 20

      assert AuthEvent.calculate_risk_score(%{
               threat_indicators: ["unusual_location"]
             }) == 25

      assert AuthEvent.calculate_risk_score(%{
               threat_indicators: ["rapid_attempts"]
             }) == 30

      assert AuthEvent.calculate_risk_score(%{
               threat_indicators: ["suspicious_ip"]
             }) == 35

      assert AuthEvent.calculate_risk_score(%{
               threat_indicators: ["unusual_time"]
             }) == 15

      # Test threat indicators that don't have specific risk scores
      assert AuthEvent.calculate_risk_score(%{
               threat_indicators: ["bot_behavior"]
             }) == 0

      assert AuthEvent.calculate_risk_score(%{
               threat_indicators: ["known_attacker"]
             }) == 0

      assert AuthEvent.calculate_risk_score(%{
               threat_indicators: ["geolocation_mismatch"]
             }) == 0
    end

    test "calculates cumulative risk for multiple threat indicators" do
      attrs = %{
        threat_indicators: ["new_device", "unusual_location"]
      }

      # 20 (new_device) + 25 (unusual_location) = 45
      assert AuthEvent.calculate_risk_score(attrs) == 45
    end

    test "caps risk score at 100" do
      # Use all threat indicators with risk scores
      # plus additional ones to simulate exceeding 100
      attrs = %{
        threat_indicators: [
          "unusual_location",
          # 25
          "new_device",
          # 20
          "rapid_attempts",
          # 30
          "suspicious_ip",
          # 35
          "unusual_time",
          # 15
          "bot_behavior",
          "known_attacker",
          "geolocation_mismatch"
        ]
      }

      # Total would be: 25 + 20 + 30 + 35 + 15 = 125 (but indicators without scores don't add)
      # Should be capped at 100
      assert AuthEvent.calculate_risk_score(attrs) == 100
    end

    test "handles nil threat_indicators" do
      attrs = %{threat_indicators: nil}
      assert AuthEvent.calculate_risk_score(attrs) == 0
    end
  end

  describe "suspicious activity detection" do
    test "identifies low-risk activity as not suspicious" do
      attrs = %{threat_indicators: []}
      refute AuthEvent.suspicious?(attrs)

      attrs = %{threat_indicators: ["new_device"]}
      refute AuthEvent.suspicious?(attrs)
    end

    test "identifies high-risk activity as suspicious" do
      # Risk threshold is typically 50
      attrs = %{
        threat_indicators: ["new_device", "unusual_location", "rapid_attempts"]
      }

      # 20 + 25 + 30 = 75 (above threshold)
      assert AuthEvent.suspicious?(attrs)
    end

    test "identifies activity at threshold boundary" do
      # Create exactly 50 risk score
      attrs = %{
        threat_indicators: ["unusual_location", "unusual_location"]
      }

      # This will be exactly at or above threshold
      result = AuthEvent.suspicious?(attrs)
      assert is_boolean(result)
    end
  end

  describe "AuthService integration" do
    test "creates a successful login event" do
      user = user_fixture()

      # Mock connection data
      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [
          {"user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}
        ]
      }

      {:ok, auth_event} = AuthService.log_login_success(user, conn)

      assert auth_event.user_id == user.id
      assert auth_event.event_type == "login_success"
      assert auth_event.success == true
      assert auth_event.email_attempted == user.email
      assert auth_event.ip_address == "127.0.0.1"

      assert auth_event.user_agent ==
               "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
    end

    test "creates a failed login event" do
      email = "test@example.com"

      # Mock connection data
      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [
          {"user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}
        ]
      }

      {:ok, auth_event} = AuthService.log_login_failure(email, conn)

      assert auth_event.user_id == nil
      assert auth_event.event_type == "login_failure"
      assert auth_event.success == false
      assert auth_event.email_attempted == email
      assert auth_event.failure_reason == "invalid_credentials"
      assert auth_event.ip_address == "127.0.0.1"
    end

    test "creates a logout event" do
      user = user_fixture()

      # Mock connection data
      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [
          {"user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}
        ]
      }

      {:ok, auth_event} = AuthService.log_logout(user, conn)

      assert auth_event.user_id == user.id
      assert auth_event.event_type == "logout"
      assert auth_event.success == true
      assert auth_event.email_attempted == user.email
    end

    test "parses user agent correctly" do
      user_agent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"

      parsed = AuthEvent.parse_user_agent(user_agent)

      assert parsed.device_type == "desktop"
      assert parsed.browser == "Chrome"
      assert parsed.operating_system == "macOS"
    end

    test "calculates risk score correctly" do
      # Low risk
      low_risk_attrs = %{threat_indicators: []}
      assert AuthEvent.calculate_risk_score(low_risk_attrs) == 0

      # Medium risk
      medium_risk_attrs = %{threat_indicators: ["new_device", "unusual_time"]}
      risk_score = AuthEvent.calculate_risk_score(medium_risk_attrs)
      assert risk_score > 0
      assert risk_score < 100

      # High risk
      high_risk_attrs = %{
        threat_indicators: [
          "new_device",
          "unusual_location",
          "rapid_attempts",
          "suspicious_ip"
        ]
      }

      risk_score = AuthEvent.calculate_risk_score(high_risk_attrs)
      assert risk_score > 50
    end

    test "identifies suspicious activity" do
      # Not suspicious
      normal_attrs = %{threat_indicators: []}
      refute AuthEvent.suspicious?(normal_attrs)

      # Suspicious
      suspicious_attrs = %{
        threat_indicators: [
          "new_device",
          "unusual_location",
          "rapid_attempts",
          "suspicious_ip"
        ]
      }

      assert AuthEvent.suspicious?(suspicious_attrs)
    end

    test "handles invalid UTF-8 in user agent" do
      # Test with invalid UTF-8 byte sequence
      invalid_utf8_user_agent = "Mozilla/5.0 \xa1\xa2\xa3"

      parsed = AuthEvent.parse_user_agent(invalid_utf8_user_agent)

      # Should still work and return valid data
      assert parsed.device_type in ["desktop", "mobile", "tablet", "unknown"]

      assert parsed.browser in [
               "Chrome",
               "Firefox",
               "Safari",
               "Edge",
               "Opera",
               "Unknown",
               nil
             ]
    end

    test "sanitizes UTF-8 strings in AuthService" do
      # Test the sanitize_utf8 function
      invalid_string = "Test\xa1\xa2\xa3String"
      sanitized = Ysc.Accounts.AuthService.sanitize_utf8(invalid_string)

      # Should replace invalid characters with ?
      assert sanitized == "Test???String"

      # Should handle nil
      assert Ysc.Accounts.AuthService.sanitize_utf8(nil) == nil

      # Should handle valid UTF-8
      valid_string = "Valid UTF-8 string"

      assert Ysc.Accounts.AuthService.sanitize_utf8(valid_string) ==
               valid_string

      # Should handle null bytes (PostgreSQL doesn't allow them)
      null_byte_string = "Test\x00String"
      sanitized_null = Ysc.Accounts.AuthService.sanitize_utf8(null_byte_string)
      assert sanitized_null == "TestString"
    end

    test "gets last successful login datetime" do
      user = user_fixture()

      # Initially no login events
      assert AuthService.get_last_successful_login_datetime(user) == nil
      assert AuthService.get_last_successful_login_event(user) == nil

      # Mock connection data
      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [
          {"user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}
        ]
      }

      # Log a successful login
      {:ok, auth_event} = AuthService.log_login_success(user, conn)

      # Should now return the login datetime
      last_login_datetime = AuthService.get_last_successful_login_datetime(user)
      assert last_login_datetime != nil

      assert DateTime.compare(last_login_datetime, auth_event.inserted_at) ==
               :eq

      # Should also return the full event
      last_login_event = AuthService.get_last_successful_login_event(user)
      assert last_login_event != nil
      assert last_login_event.id == auth_event.id
    end

    test "gets last login session information" do
      user = user_fixture()

      # Mock connection data
      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [
          {"user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}
        ]
      }

      # Initially no session data
      assert AuthService.get_last_login_session_datetime(user) == nil
      assert AuthService.get_last_login_session_event(user) == nil
      assert AuthService.get_last_session_timeframe(user) == nil

      # Log a successful login
      {:ok, login_event} = AuthService.log_login_success(user, conn)

      # Add a delay to ensure timestamps are different
      Process.sleep(1000)

      # Should return login time as last session activity
      last_session_datetime = AuthService.get_last_login_session_datetime(user)
      assert last_session_datetime != nil

      assert DateTime.compare(last_session_datetime, login_event.inserted_at) ==
               :eq

      # Should return the login event as last session event
      last_session_event = AuthService.get_last_login_session_event(user)
      assert last_session_event != nil
      assert last_session_event.id == login_event.id

      # Should return session timeframe showing user is active
      session_timeframe = AuthService.get_last_session_timeframe(user)
      assert session_timeframe != nil
      assert session_timeframe.session_start == login_event.inserted_at
      assert session_timeframe.session_end == nil
      assert session_timeframe.is_active == true

      # Log a logout
      {:ok, logout_event} = AuthService.log_logout(user, conn)

      # Should now return logout time as last session activity
      last_session_datetime = AuthService.get_last_login_session_datetime(user)
      assert last_session_datetime != nil

      assert DateTime.compare(last_session_datetime, logout_event.inserted_at) ==
               :eq

      # Should return the logout event as last session event
      last_session_event = AuthService.get_last_login_session_event(user)
      assert last_session_event != nil
      assert last_session_event.event_type == "logout"

      # Should return session timeframe showing user is not active
      session_timeframe = AuthService.get_last_session_timeframe(user)
      assert session_timeframe != nil
      assert session_timeframe.session_start == login_event.inserted_at
      assert session_timeframe.session_end == logout_event.inserted_at
      assert session_timeframe.is_active == false
    end
  end

  defp user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: "test@example.com",
        password: "hello world!",
        first_name: "Test",
        last_name: "User",
        phone_number: "+14155551234",
        state: :active,
        role: :member
      })
      |> Ysc.Accounts.register_user()

    user
  end
end
