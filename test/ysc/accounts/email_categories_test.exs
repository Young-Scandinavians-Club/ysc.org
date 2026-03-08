defmodule Ysc.Accounts.EmailCategoriesTest do
  @moduledoc """
  Tests for Ysc.Accounts.EmailCategories.
  """
  use ExUnit.Case, async: true

  alias Ysc.Accounts.EmailCategories

  describe "get_category/1" do
    test "returns correct category for known templates" do
      assert EmailCategories.get_category("confirm_email") == :account
      assert EmailCategories.get_category("event_notification") == :event

      assert EmailCategories.get_category("membership_payment_confirmation") ==
               :account
    end

    test "defaults to :account for unknown templates" do
      assert EmailCategories.get_category("unknown") == :account
    end
  end

  describe "get_reply_to/1" do
    test "returns membership email for membership-related templates" do
      membership_email = Ysc.EmailConfig.membership_email()

      assert EmailCategories.get_reply_to("membership_payment_confirmation") ==
               membership_email

      assert EmailCategories.get_reply_to("membership_payment_failure") ==
               membership_email

      assert EmailCategories.get_reply_to("membership_renewal_success") ==
               membership_email

      assert EmailCategories.get_reply_to("application_approved") ==
               membership_email

      assert EmailCategories.get_reply_to("application_rejected") ==
               membership_email

      assert EmailCategories.get_reply_to("application_submitted") ==
               membership_email

      assert EmailCategories.get_reply_to("family_invite") == membership_email
    end

    test "returns nil for non-membership templates" do
      assert EmailCategories.get_reply_to("booking_confirmation") == nil
      assert EmailCategories.get_reply_to("confirm_email") == nil
      assert EmailCategories.get_reply_to("event_notification") == nil
    end

    test "returns nil for unknown template" do
      assert EmailCategories.get_reply_to("unknown_template") == nil
    end
  end

  describe "should_send_email?/2" do
    test "always sends account emails" do
      # Account emails ignore user preferences
      user_disabled = %{event_notifications: false}

      assert EmailCategories.should_send_email?(user_disabled, "confirm_email")
    end

    test "respects event preferences" do
      user_enabled = %{event_notifications: true}
      user_disabled = %{event_notifications: false}

      assert EmailCategories.should_send_email?(
               user_enabled,
               "event_notification"
             )

      refute EmailCategories.should_send_email?(
               user_disabled,
               "event_notification"
             )
    end
  end
end
