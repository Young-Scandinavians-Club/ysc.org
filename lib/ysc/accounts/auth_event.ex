defmodule Ysc.Accounts.AuthEvent do
  @moduledoc """
  Authentication event schema and changesets.

  Defines the AuthEvent database schema for tracking user authentication events,
  including login attempts, device information, and suspicious activity detection.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Ysc.Accounts.User

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  @event_types [
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

  @failure_reasons [
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

  @device_types ["desktop", "mobile", "tablet", "unknown"]
  @threat_indicators [
    "unusual_location",
    "new_device",
    "rapid_attempts",
    "suspicious_ip",
    "bot_behavior",
    "known_attacker",
    "geolocation_mismatch",
    "unusual_time"
  ]

  schema "auth_events" do
    # User reference (nullable for failed login attempts with non-existent users)
    belongs_to :user, User, foreign_key: :user_id, references: :id

    # Authentication attempt details
    field :event_type, :string
    field :success, :boolean
    field :failure_reason, :string

    # User identification (for failed attempts where user_id might be null)
    field :email_attempted, :string

    # Network and device information
    field :ip_address, :string
    field :user_agent, :string
    field :device_type, :string
    field :browser, :string
    field :browser_version, :string
    field :operating_system, :string
    field :os_version, :string

    # Geographic information (if available)
    field :country, :string
    field :region, :string
    field :city, :string
    field :latitude, :float
    field :longitude, :float

    # Security and risk assessment
    field :is_suspicious, :boolean, default: false
    field :risk_score, :integer
    field :threat_indicators, {:array, :string}, default: []

    # Session information
    field :session_id, :string
    field :remember_me, :boolean, default: false

    # Additional metadata
    field :metadata, :map, default: %{}

    timestamps()
  end

  @doc """
  Creates a changeset for an authentication event.
  """
  def changeset(auth_event, attrs) do
    auth_event
    |> cast(attrs, [
      :user_id,
      :event_type,
      :success,
      :failure_reason,
      :email_attempted,
      :ip_address,
      :user_agent,
      :device_type,
      :browser,
      :browser_version,
      :operating_system,
      :os_version,
      :country,
      :region,
      :city,
      :latitude,
      :longitude,
      :is_suspicious,
      :risk_score,
      :threat_indicators,
      :session_id,
      :remember_me,
      :metadata
    ])
    |> sanitize_string_fields()
    |> validate_required([:event_type, :success])
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:failure_reason, @failure_reasons,
      message: "is not a valid failure reason"
    )
    |> validate_inclusion(:device_type, @device_types,
      message: "is not a valid device type"
    )
    |> validate_number(:risk_score,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> validate_length(:email_attempted, max: 160)
    # IPv6 max length
    |> validate_length(:ip_address, max: 45)
    |> validate_length(:user_agent, max: 1000)
    |> validate_length(:browser, max: 100)
    |> validate_length(:browser_version, max: 50)
    |> validate_length(:operating_system, max: 100)
    |> validate_length(:os_version, max: 50)
    # ISO country code
    |> validate_length(:country, max: 2)
    |> validate_length(:region, max: 100)
    |> validate_length(:city, max: 100)
    |> validate_length(:session_id, max: 255)
    |> validate_threat_indicators()
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates a changeset for a successful login event.
  """
  def login_success_changeset(user, attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(
      attrs
      |> Map.put(:user_id, user.id)
      |> Map.put(:event_type, "login_success")
      |> Map.put(:success, true)
      |> Map.put(:email_attempted, user.email)
    )
  end

  @doc """
  Creates a changeset for a failed login event.
  """
  def login_failure_changeset(attrs) do
    %__MODULE__{}
    |> changeset(
      attrs
      |> Map.put(:event_type, "login_failure")
      |> Map.put(:success, false)
    )
  end

  @doc """
  Creates a changeset for a logout event.
  """
  def logout_changeset(user, attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(
      attrs
      |> Map.put(:user_id, user.id)
      |> Map.put(:event_type, "logout")
      |> Map.put(:success, true)
      |> Map.put(:email_attempted, user.email)
    )
  end

  @doc """
  Creates a changeset for a password reset request event.
  """
  def password_reset_request_changeset(user, attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(
      attrs
      |> Map.put(:user_id, user.id)
      |> Map.put(:event_type, "password_reset_request")
      |> Map.put(:success, true)
      |> Map.put(:email_attempted, user.email)
    )
  end

  @doc """
  Creates a changeset for a password reset success event.
  """
  def password_reset_success_changeset(user, attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(
      attrs
      |> Map.put(:user_id, user.id)
      |> Map.put(:event_type, "password_reset_success")
      |> Map.put(:success, true)
      |> Map.put(:email_attempted, user.email)
    )
  end

  @doc """
  Creates a changeset for an account locked event.
  """
  def account_locked_changeset(user, attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(
      attrs
      |> Map.put(:user_id, user.id)
      |> Map.put(:event_type, "account_locked")
      |> Map.put(:success, false)
      |> Map.put(:failure_reason, "too_many_attempts")
      |> Map.put(:email_attempted, user.email)
    )
  end

  @doc """
  Creates a changeset for a suspicious activity event.
  """
  def suspicious_activity_changeset(attrs) do
    %__MODULE__{}
    |> changeset(
      attrs
      |> Map.put(:event_type, "suspicious_activity")
      |> Map.put(:success, false)
      |> Map.put(:is_suspicious, true)
    )
  end

  @doc """
  Parses user agent string to extract device information.
  """
  def parse_user_agent(user_agent) when is_binary(user_agent) do
    # Ensure the user agent is valid UTF-8 and not too long
    safe_user_agent =
      user_agent
      # Limit length
      |> String.slice(0, 1000)
      # Replace non-ASCII with ?
      |> String.replace(~r/[^\x00-\x7F]/, "?")

    # Basic user agent parsing - you might want to use a library like ua_parser
    cond do
      String.contains?(safe_user_agent, "Mobile") or
          String.contains?(safe_user_agent, "Android") ->
        %{
          device_type: "mobile",
          browser: extract_browser(safe_user_agent),
          operating_system: extract_os(safe_user_agent)
        }

      String.contains?(safe_user_agent, "Tablet") or
          String.contains?(safe_user_agent, "iPad") ->
        %{
          device_type: "tablet",
          browser: extract_browser(safe_user_agent),
          operating_system: extract_os(safe_user_agent)
        }

      true ->
        %{
          device_type: "desktop",
          browser: extract_browser(safe_user_agent),
          operating_system: extract_os(safe_user_agent)
        }
    end
  end

  def parse_user_agent(_),
    do: %{device_type: "unknown", browser: nil, operating_system: nil}

  @doc """
  Calculates risk score based on various factors.
  """
  def calculate_risk_score(attrs) do
    base_score = 0

    score =
      base_score
      |> add_risk_for_new_device(attrs)
      |> add_risk_for_unusual_location(attrs)
      |> add_risk_for_rapid_attempts(attrs)
      |> add_risk_for_suspicious_ip(attrs)
      |> add_risk_for_unusual_time(attrs)

    min(max(score, 0), 100)
  end

  @doc """
  Determines if an event is suspicious based on various factors.
  """
  def suspicious?(attrs) do
    risk_score = calculate_risk_score(attrs)
    risk_score > 70
  end

  @doc """
  Gets recent failed login attempts for an IP address.
  """
  def recent_failed_attempts_query(ip_address, minutes \\ 15) do
    from ae in __MODULE__,
      where: ae.ip_address == ^ip_address,
      where: ae.success == false,
      where: ae.inserted_at > ago(^minutes, "minute"),
      order_by: [desc: ae.inserted_at]
  end

  @doc """
  Gets recent failed login attempts for an email.
  """
  def recent_failed_attempts_for_email_query(email, minutes \\ 15) do
    from ae in __MODULE__,
      where: ae.email_attempted == ^email,
      where: ae.success == false,
      where: ae.inserted_at > ago(^minutes, "minute"),
      order_by: [desc: ae.inserted_at]
  end

  @doc """
  Gets user's recent login history.
  """
  def user_login_history_query(user, limit \\ 50) do
    from ae in __MODULE__,
      where: ae.user_id == ^user.id,
      where: ae.event_type in ["login_success", "login_failure"],
      order_by: [desc: ae.inserted_at],
      limit: ^limit
  end

  @doc """
  Gets suspicious events for monitoring.
  """
  def suspicious_events_query(limit \\ 100) do
    from ae in __MODULE__,
      where: ae.is_suspicious == true,
      order_by: [desc: ae.inserted_at],
      limit: ^limit
  end

  # Private helper functions

  defp sanitize_string_fields(changeset) do
    string_fields = [
      :email_attempted,
      :ip_address,
      :user_agent,
      :device_type,
      :browser,
      :browser_version,
      :operating_system,
      :os_version,
      :country,
      :region,
      :city,
      :session_id,
      :failure_reason
    ]

    Enum.reduce(string_fields, changeset, fn field, acc ->
      case get_change(acc, field) do
        nil ->
          acc

        value when is_binary(value) ->
          sanitized = sanitize_utf8_string(value)
          put_change(acc, field, sanitized)

        _ ->
          acc
      end
    end)
  end

  defp sanitize_utf8_string(string) when is_binary(string) do
    # First remove null bytes which PostgreSQL doesn't allow
    cleaned_string = String.replace(string, "\x00", "")

    case :unicode.characters_to_binary(cleaned_string, :utf8, :utf8) do
      {:error, _, _} ->
        # If conversion fails, clean the string
        cleaned_string
        |> String.replace(~r/[^\x00-\x7F]/, "?")
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

  defp validate_threat_indicators(changeset) do
    case get_field(changeset, :threat_indicators) do
      nil ->
        changeset

      indicators when is_list(indicators) ->
        invalid_indicators = indicators -- @threat_indicators

        if Enum.empty?(invalid_indicators) do
          changeset
        else
          add_error(
            changeset,
            :threat_indicators,
            "contains invalid indicators: #{Enum.join(invalid_indicators, ", ")}"
          )
        end

      _ ->
        add_error(changeset, :threat_indicators, "must be a list")
    end
  end

  defp extract_browser(user_agent) do
    cond do
      String.contains?(user_agent, "Chrome") -> "Chrome"
      String.contains?(user_agent, "Firefox") -> "Firefox"
      String.contains?(user_agent, "Safari") -> "Safari"
      String.contains?(user_agent, "Edge") -> "Edge"
      String.contains?(user_agent, "Opera") -> "Opera"
      true -> "Unknown"
    end
  end

  defp extract_os(user_agent) do
    cond do
      String.contains?(user_agent, "Windows") -> "Windows"
      String.contains?(user_agent, "Mac OS") -> "macOS"
      String.contains?(user_agent, "Linux") -> "Linux"
      String.contains?(user_agent, "Android") -> "Android"
      String.contains?(user_agent, "iOS") -> "iOS"
      true -> "Unknown"
    end
  end

  defp add_risk_for_new_device(score, attrs) do
    if "new_device" in (attrs[:threat_indicators] || []) do
      score + 20
    else
      score
    end
  end

  defp add_risk_for_unusual_location(score, attrs) do
    if "unusual_location" in (attrs[:threat_indicators] || []) do
      score + 25
    else
      score
    end
  end

  defp add_risk_for_rapid_attempts(score, attrs) do
    if "rapid_attempts" in (attrs[:threat_indicators] || []) do
      score + 30
    else
      score
    end
  end

  defp add_risk_for_suspicious_ip(score, attrs) do
    if "suspicious_ip" in (attrs[:threat_indicators] || []) do
      score + 35
    else
      score
    end
  end

  defp add_risk_for_unusual_time(score, attrs) do
    if "unusual_time" in (attrs[:threat_indicators] || []) do
      score + 15
    else
      score
    end
  end
end
