defmodule Ysc.PaymentUserMessagesTest do
  use ExUnit.Case, async: true

  alias Ysc.PaymentUserMessages

  test "payment_setup_failed includes contact email and refresh guidance" do
    message = PaymentUserMessages.payment_setup_failed()

    assert message =~ "couldn't set up payment"
    assert message =~ "refresh the page"
    assert message =~ "info@ysc.org"
    refute message =~ "initialization"
  end

  test "invoice_retry_failed includes membership guidance" do
    message = PaymentUserMessages.invoice_retry_failed()

    assert message =~ "Membership settings"
    assert message =~ "memberships@ysc.org"
    refute message =~ "Failed to retry payment"
  end

  test "format_stripe_error maps declined cards" do
    assert PaymentUserMessages.format_stripe_error(%Stripe.Error{
             code: "card_declined",
             message: "Your card was declined.",
             source: :api
           }) =~ "declined"

    assert PaymentUserMessages.format_stripe_error("card was declined") =~
             "declined"
  end

  test "format_stripe_error hides raw Stripe API messages" do
    message =
      PaymentUserMessages.format_stripe_error(%Stripe.Error{
        code: "api_error",
        message: "No such payment_intent: 'pi_123abc'",
        source: :api
      })

    assert message =~ "couldn't process your payment"
    refute message =~ "payment_intent"
    refute message =~ "pi_123abc"
  end

  test "invoice_retry_error keeps declined guidance but uses membership copy otherwise" do
    assert PaymentUserMessages.invoice_retry_error("card was declined") =~
             "declined"

    assert PaymentUserMessages.invoice_retry_error("No such customer") =~
             "Membership settings"
  end
end
