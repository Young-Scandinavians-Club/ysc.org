defmodule YscWeb.MembershipUserMessagesTest do
  use ExUnit.Case, async: true

  alias YscWeb.MembershipUserMessages

  test "payment-method activation toast welcomes first-time members" do
    message =
      MembershipUserMessages.payment_method_saved_membership_activated(false)

    assert message ==
             "Payment method saved and your membership is now active!"

    refute message =~ "renewed"
  end

  test "payment-method activation toast tells returning members they renewed" do
    message =
      MembershipUserMessages.payment_method_saved_membership_activated(true)

    assert message == "Payment method saved. Your membership is renewed."
    refute message =~ "now active"
    refute message =~ "Welcome"
  end

  test "activation welcome toast is first-time vs renewal" do
    assert MembershipUserMessages.membership_activated_welcome(false) ==
             "Your membership is active. Welcome!"

    assert MembershipUserMessages.membership_activated_welcome(true) ==
             "Your membership is renewed."

    refute MembershipUserMessages.membership_activated_welcome(true) =~
             "Welcome"
  end

  test "short activation toast is first-time vs renewal" do
    assert MembershipUserMessages.membership_activated_short(false) ==
             "Your membership is active!"

    assert MembershipUserMessages.membership_activated_short(true) ==
             "Your membership is renewed."
  end

  test "upgrade banner names the new plan and treats the dollar amount as a ceiling" do
    before = MembershipUserMessages.upgrade_banner_before_amount("Family")
    after_amount = MembershipUserMessages.upgrade_banner_after_amount("Family")
    helper = MembershipUserMessages.upgrade_confirm_helper("$20.00")

    assert before ==
             "You'll switch to Family today. We'll charge you extra for the rest of this membership year — at most"

    assert after_amount =~ "partway through the year"
    assert after_amount =~ "you'll pay less than that"
    assert after_amount =~ "Family price"

    refute before =~ "won't exceed"
    refute after_amount =~ "won't exceed"
    refute before =~ "price difference"
    refute helper =~ "won't exceed"
    refute helper =~ "the difference for the rest"

    assert helper == "You'll be charged today — at most $20.00."
  end

  test "plan_name capitalizes membership plan ids" do
    assert MembershipUserMessages.plan_name(:family) == "Family"
    assert MembershipUserMessages.plan_name("single") == "Single"
  end
end
