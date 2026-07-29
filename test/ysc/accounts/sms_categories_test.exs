defmodule Ysc.Accounts.SmsCategoriesTest do
  @moduledoc """
  Tests for Ysc.Accounts.SmsCategories.
  """
  use ExUnit.Case, async: true

  alias Ysc.Accounts.SmsCategories

  describe "get_category/1" do
    test "maps known templates and defaults unknown to :account" do
      assert SmsCategories.get_category("booking_checkin_reminder") == :account
      assert SmsCategories.get_category("event_notification") == :event
      assert SmsCategories.get_category("unknown_sms_template") == :account
    end

    test "returns :account for non-binary template names" do
      assert SmsCategories.get_category(:booking_checkin_reminder) == :account
    end
  end

  describe "should_send_sms?/2" do
    test "respects account sms preferences" do
      user_enabled = %{account_notifications_sms: true}
      user_disabled = %{account_notifications_sms: false}

      # Security templates like "two_factor_verification" always return true
      # regardless of notification preferences
      assert SmsCategories.should_send_sms?(
               user_enabled,
               "two_factor_verification"
             )

      assert SmsCategories.should_send_sms?(
               user_disabled,
               "two_factor_verification"
             )
    end

    test "respects account sms preferences for non-security templates" do
      assert SmsCategories.should_send_sms?(
               %{account_notifications_sms: true},
               "booking_checkin_reminder"
             )

      refute SmsCategories.should_send_sms?(
               %{account_notifications_sms: false},
               "booking_checkin_reminder"
             )
    end

    test "respects event sms preferences" do
      assert SmsCategories.should_send_sms?(
               %{event_notifications_sms: true},
               "event_notification"
             )

      refute SmsCategories.should_send_sms?(
               %{event_notifications_sms: false},
               "event_notification"
             )

      assert SmsCategories.should_send_sms?(
               %{event_notifications_sms: true},
               "event_update_notification"
             )

      refute SmsCategories.should_send_sms?(
               %{event_notifications_sms: false},
               "event_update_notification"
             )
    end

    test "returns true when template name is not a binary" do
      assert SmsCategories.should_send_sms?(
               %{account_notifications_sms: false},
               :booking_checkin_reminder
             )
    end
  end

  describe "has_phone_number?/1" do
    test "returns true for valid number" do
      assert SmsCategories.has_phone_number?(%{phone_number: "+15551234567"})
    end

    test "returns false for nil/empty" do
      refute SmsCategories.has_phone_number?(%{phone_number: nil})
      refute SmsCategories.has_phone_number?(%{phone_number: ""})
      refute SmsCategories.has_phone_number?(%{phone_number: "   "})
    end

    test "returns false when phone_number is not a string" do
      refute SmsCategories.has_phone_number?(%{phone_number: 12_065_551_234})
    end
  end
end
