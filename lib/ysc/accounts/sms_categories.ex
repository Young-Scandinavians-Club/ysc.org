defmodule Ysc.Accounts.SmsCategories do
  @moduledoc """
  Maps SMS templates to notification categories for user preference checking.
  """

  @type category :: :account | :event

  # Map of SMS template names to their notification categories
  @template_categories %{
    # Account notifications (can be disabled via account_notifications_sms)
    "booking_checkin_reminder" => :account,
    # Security notifications (should always be sent, bypassing notification preferences)
    "two_factor_verification" => :account,
    "email_changed" => :account,
    "password_changed" => :account,
    "phone_verification" => :account
  }

  # Security-critical templates that should always be sent regardless of notification preferences
  @security_templates ["phone_verification", "two_factor_verification"]

  @doc """
  Gets the notification category for a given SMS template.

  ## Examples

      iex> get_category("booking_confirmation")
      :account

      iex> get_category("event_notification")
      :event

      iex> get_category("unknown_template")
      :account

  """
  @spec get_category(String.t()) :: category()
  def get_category(template_name) when is_binary(template_name) do
    Map.get(@template_categories, template_name, :account)
  end

  def get_category(_), do: :account

  @doc """
  Checks if a user should receive an SMS based on their notification preferences.

  Security-critical templates (like verification codes) always return true,
  bypassing notification preferences. Other templates respect user preferences:
  - Account notifications check `account_notifications_sms` preference.
  - Event notifications check `event_notifications_sms` preference.

  ## Examples

      iex> should_send_sms?(%{account_notifications_sms: false}, "phone_verification")
      true

      iex> should_send_sms?(%{account_notifications_sms: true}, "booking_confirmation")
      true

      iex> should_send_sms?(%{event_notifications_sms: false}, "event_notification")
      false

  """
  @spec should_send_sms?(map(), String.t()) :: boolean()
  def should_send_sms?(user, template_name) when is_binary(template_name) do
    # Security-critical templates (verification codes) should always be sent
    # regardless of notification preferences
    if template_name in @security_templates do
      true
    else
      case get_category(template_name) do
        :account ->
          # Check if user has account SMS notifications enabled
          Map.get(user, :account_notifications_sms, true)

        :event ->
          # Check if user has event SMS notifications enabled
          Map.get(user, :event_notifications_sms, true)
      end
    end
  end

  def should_send_sms?(_, _), do: true

  @doc """
  Checks if a user has a phone number configured for SMS.

  ## Examples

      iex> has_phone_number?(%{phone_number: "12065551234"})
      true

      iex> has_phone_number?(%{phone_number: nil})
      false

  """
  @spec has_phone_number?(map()) :: boolean()
  def has_phone_number?(user) do
    case Map.get(user, :phone_number) do
      nil -> false
      "" -> false
      phone when is_binary(phone) -> String.trim(phone) != ""
      _ -> false
    end
  end
end
