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
               "dark"
    end
  end
end
