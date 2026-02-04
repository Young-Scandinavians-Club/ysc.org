defmodule Ysc.Accounts.SmsCategoriesTest do
  @moduledoc """
  Tests for Ysc.Accounts.SmsCategories.
  """
  use ExUnit.Case, async: true

  alias Ysc.Accounts.SmsCategories

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
  end
end
