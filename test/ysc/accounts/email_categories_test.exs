defmodule Ysc.Accounts.EmailCategoriesTest do
  @moduledoc """
  Tests for Ysc.Accounts.EmailCategories.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts.EmailCategories
  alias Ysc.Newsletter

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

    test "returns :account for non-binary template names" do
      assert EmailCategories.get_category(:confirm_email) == :account
    end

    test "maps newsletter_edition to :newsletter" do
      assert EmailCategories.get_category("newsletter_edition") == :newsletter
    end

    test "maps newsletter stats snapshot to account notifications" do
      assert EmailCategories.get_category("newsletter_stats_snapshot") ==
               :account
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

    test "returns nil for non-binary template names" do
      assert EmailCategories.get_reply_to(:membership_payment_confirmation) ==
               nil
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

    test "returns true when template name is not a binary" do
      assert EmailCategories.should_send_email?(
               %{event_notifications: false},
               :event_notification
             )
    end

    test "newsletter_edition follows newsletter_subscribers when subscriber exists" do
      user = user_fixture()

      assert {:ok, _} =
               Newsletter.subscribe(user.email,
                 user_id: user.id,
                 source: "test"
               )

      assert EmailCategories.should_send_email?(user, "newsletter_edition")

      assert {:ok, _} = Newsletter.unsubscribe(user.email)

      refute EmailCategories.should_send_email?(user, "newsletter_edition")
    end

    test "newsletter_edition returns false when newsletter_subscribers has no row for the email" do
      email = "no-newsletter-row-#{System.unique_integer()}@example.com"

      refute EmailCategories.should_send_email?(
               %{email: email},
               "newsletter_edition"
             )
    end

    test "newsletter_edition returns false when user has no email" do
      user = %{email: nil}

      refute EmailCategories.should_send_email?(user, "newsletter_edition")
    end
  end
end
