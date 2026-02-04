defmodule Ysc.Accounts.EmailCategories do
  @moduledoc """
  Maps email templates to notification categories for user preference checking.
  """

  @type category :: :account | :event | :newsletter

  # Map of email template names to their notification categories
  @template_categories %{
    # Account notifications (cannot be disabled)
    "confirm_email" => :account,
    "reset_password" => :account,
    "password_changed" => :account,
    "passkey_added" => :account,
    "change_email" => :account,
    "email_changed" => :account,
    "application_submitted" => :account,
    "application_approved" => :account,
    "application_rejected" => :account,
    "conduct_violation_confirmation" => :account,
    "volunteer_confirmation" => :account,
    "membership_payment_failure" => :account,
    "membership_payment_confirmation" => :account,
    "membership_renewal_success" => :account,
    "membership_payment_reminder_7day" => :account,
    "membership_payment_reminder_30day" => :account,
    "booking_checkin_reminder" => :account,
    "expense_report_confirmation" => :account,
    # Board/admin notifications (always sent, no user preference check)
    "admin_application_submitted" => :account,
    "conduct_violation_board_notification" => :account,
    "volunteer_board_notification" => :account,
    "contact_form_board_notification" => :account,
    "expense_report_treasurer_notification" => :account,
    # Event notifications (can be disabled)
    "ticket_purchase_confirmation" => :account,
    "ticket_order_refund" => :account,
    "outage_notification" => :account,
    "event_notification" => :event,
    # Booking notifications (can be disabled)
    "booking_confirmation" => :account,
    "booking_refund_processed" => :account,
    "booking_refund_pending" => :account,
    "account_setup_verification" => :account
    # Newsletter notifications (can be disabled)
    # Note: Newsletter emails are handled by Keila, not through this system
  }

  @doc """
  Gets the notification category for a given email template.

  ## Examples

      iex> get_category("confirm_email")
      :account

      iex> get_category("ticket_purchase_confirmation")
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
  Checks if a user should receive an email based on their notification preferences.

  Account notifications always return true (cannot be disabled).
  Event and newsletter notifications check user preferences.

  ## Examples

      iex> should_send_email?(user, "confirm_email")
      true

      iex> should_send_email?(%{event_notifications: false}, "ticket_purchase_confirmation")
      false

  """
  @spec should_send_email?(map(), String.t()) :: boolean()
  def should_send_email?(user, template_name) when is_binary(template_name) do
    case get_category(template_name) do
      :account ->
        # Account notifications cannot be disabled
        true

      :event ->
        # Check if user has event notifications enabled
        Map.get(user, :event_notifications, true)

      :newsletter ->
        # Check if user has newsletter notifications enabled
        Map.get(user, :newsletter_notifications, true)
    end
  end

  def should_send_email?(_, _), do: true
end
