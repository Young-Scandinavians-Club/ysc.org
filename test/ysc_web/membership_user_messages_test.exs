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
end
