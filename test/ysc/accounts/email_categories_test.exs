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

  describe "should_send_email?/2" do
    test "always sends account emails" do
      # Account emails ignore user preferences
      user_disabled = %{
        event_notifications: false,
        newsletter_notifications: false
      }

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
