defmodule YscWeb.AdminBadgeHelpersTest do
  use ExUnit.Case, async: true

  alias YscWeb.AdminBadgeHelpers

  describe "user_state_badge_type/1" do
    test "maps known user states" do
      assert AdminBadgeHelpers.user_state_badge_type(:active) == "green"

      assert AdminBadgeHelpers.user_state_badge_type(:pending_approval) ==
               "yellow"

      assert AdminBadgeHelpers.user_state_badge_type(:rejected) == "red"
      assert AdminBadgeHelpers.user_state_badge_type(:suspended) == "red"
      assert AdminBadgeHelpers.user_state_badge_type(:deleted) == "dark"
    end

    test "defaults unknown states" do
      assert AdminBadgeHelpers.user_state_badge_type(:unknown) == "default"
    end
  end

  describe "review_outcome_badge_type/1" do
    test "maps review outcomes" do
      assert AdminBadgeHelpers.review_outcome_badge_type(:approved) == "green"
      assert AdminBadgeHelpers.review_outcome_badge_type(:rejected) == "red"
      assert AdminBadgeHelpers.review_outcome_badge_type(nil) == "default"
    end
  end

  describe "message_type_badge_type/1 and message_type_label/2" do
    test "maps MessageType values for table badges" do
      assert AdminBadgeHelpers.message_type_badge_type(:email) == "default"
      assert AdminBadgeHelpers.message_type_badge_type(:sms) == "green"
      assert AdminBadgeHelpers.message_type_label(:email, :table) == "EMAIL"
      assert AdminBadgeHelpers.message_type_label(:sms, :table) == "SMS"
    end

    test "formats detail panel labels" do
      assert AdminBadgeHelpers.message_type_label(:email, :detail) == "Email"
      assert AdminBadgeHelpers.message_type_label(:sms, :detail) == "Sms"
    end
  end

  describe "message_recipient_text/1" do
    test "prefers email when present" do
      notification = %{email: "user@example.com", phone_number: "+15551234567"}

      assert AdminBadgeHelpers.message_recipient_text(notification) ==
               "user@example.com"
    end

    test "formats phone when email is absent" do
      notification = %{email: nil, phone_number: "+15551234567"}

      assert AdminBadgeHelpers.message_recipient_text(notification) =~ "555"
    end

    test "returns nil when no recipient" do
      assert AdminBadgeHelpers.message_recipient_text(%{
               email: nil,
               phone_number: nil
             }) ==
               nil
    end
  end

  describe "booking_status_badge_type/1" do
    test "maps known booking statuses for admin views" do
      assert AdminBadgeHelpers.booking_status_badge_type(:complete) == "green"
      assert AdminBadgeHelpers.booking_status_badge_type(:canceled) == "red"
      assert AdminBadgeHelpers.booking_status_badge_type(:refunded) == "yellow"
      assert AdminBadgeHelpers.booking_status_badge_type(:hold) == "sky"
      assert AdminBadgeHelpers.booking_status_badge_type(:draft) == "dark"
    end

    test "defaults unknown statuses" do
      assert AdminBadgeHelpers.booking_status_badge_type(:unknown) == "dark"
    end
  end

  describe "ledger_payment_status_badge_type/1" do
    test "maps known ledger payment and refund statuses" do
      assert AdminBadgeHelpers.ledger_payment_status_badge_type(:completed) ==
               "green"

      assert AdminBadgeHelpers.ledger_payment_status_badge_type(:pending) ==
               "yellow"

      assert AdminBadgeHelpers.ledger_payment_status_badge_type(:failed) ==
               "red"

      assert AdminBadgeHelpers.ledger_payment_status_badge_type(:refunded) ==
               "zinc"
    end
  end

  describe "expense_report_status_badge_type/1" do
    test "maps known expense report statuses" do
      assert AdminBadgeHelpers.expense_report_status_badge_type("draft") ==
               "dark"

      assert AdminBadgeHelpers.expense_report_status_badge_type("submitted") ==
               "default"

      assert AdminBadgeHelpers.expense_report_status_badge_type("approved") ==
               "green"

      assert AdminBadgeHelpers.expense_report_status_badge_type("rejected") ==
               "red"

      assert AdminBadgeHelpers.expense_report_status_badge_type("paid") == "sky"
    end

    test "accepts atoms and defaults unknown statuses" do
      assert AdminBadgeHelpers.expense_report_status_badge_type(:approved) == "green"
      assert AdminBadgeHelpers.expense_report_status_badge_type(nil) == "dark"
      assert AdminBadgeHelpers.expense_report_status_badge_type("unknown") == "dark"
    end
  end

  describe "payout_status_badge_type/1" do
    test "maps known Stripe payout statuses" do
      assert AdminBadgeHelpers.payout_status_badge_type("paid") == "green"
      assert AdminBadgeHelpers.payout_status_badge_type("pending") == "yellow"
      assert AdminBadgeHelpers.payout_status_badge_type("failed") == "red"
      assert AdminBadgeHelpers.payout_status_badge_type("canceled") == "zinc"
    end

    test "defaults unknown statuses" do
      assert AdminBadgeHelpers.payout_status_badge_type(nil) == "dark"
      assert AdminBadgeHelpers.payout_status_badge_type("unknown") == "dark"
    end
  end

  describe "post_state_badge_type/1" do
    test "maps known post states for admin views" do
      assert AdminBadgeHelpers.post_state_badge_type(:draft) == "yellow"
      assert AdminBadgeHelpers.post_state_badge_type(:published) == "green"
      assert AdminBadgeHelpers.post_state_badge_type(:deleted) == "red"
    end

    test "defaults unknown states" do
      assert AdminBadgeHelpers.post_state_badge_type(:unknown) == "default"
    end
  end

  describe "event_state_badge_type/1" do
    test "maps known event states for admin views" do
      assert AdminBadgeHelpers.event_state_badge_type(:draft) == "sky"
      assert AdminBadgeHelpers.event_state_badge_type(:scheduled) == "yellow"
      assert AdminBadgeHelpers.event_state_badge_type(:published) == "green"
    end

    test "defaults unknown states" do
      assert AdminBadgeHelpers.event_state_badge_type(:unknown) == "default"
    end
  end

  describe "newsletter_source_badge_type/1" do
    test "maps known subscriber sources to badge colors" do
      assert AdminBadgeHelpers.newsletter_source_badge_type("public_signup") ==
               "green"

      assert AdminBadgeHelpers.newsletter_source_badge_type("newsletters_page") ==
               "green"

      assert AdminBadgeHelpers.newsletter_source_badge_type("signup") == "green"

      assert AdminBadgeHelpers.newsletter_source_badge_type("user_registration") ==
               "sky"

      assert AdminBadgeHelpers.newsletter_source_badge_type(
               "user_registration_linked"
             ) == "sky"

      assert AdminBadgeHelpers.newsletter_source_badge_type("user_settings") ==
               "sky"

      assert AdminBadgeHelpers.newsletter_source_badge_type("email_change") ==
               "sky"

      assert AdminBadgeHelpers.newsletter_source_badge_type("admin_added") ==
               "yellow"

      assert AdminBadgeHelpers.newsletter_source_badge_type("wp_migration") ==
               "zinc"

      assert AdminBadgeHelpers.newsletter_source_badge_type("hard_bounce") ==
               "red"
    end

    test "defaults unrecognized or nil sources" do
      assert AdminBadgeHelpers.newsletter_source_badge_type("something_new") ==
               "default"

      assert AdminBadgeHelpers.newsletter_source_badge_type(nil) == "default"
    end
  end

  describe "newsletter_source_label/1" do
    test "returns Unknown for nil or empty source" do
      assert AdminBadgeHelpers.newsletter_source_label(nil) == "Unknown"
      assert AdminBadgeHelpers.newsletter_source_label("") == "Unknown"
    end

    test "humanizes underscored source strings" do
      assert AdminBadgeHelpers.newsletter_source_label("public_signup") ==
               "Public signup"

      assert AdminBadgeHelpers.newsletter_source_label("wp_migration") ==
               "Wp migration"
    end
  end
end
