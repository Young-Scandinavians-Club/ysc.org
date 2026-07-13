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

  test "format_stripe_error maps specific Stripe error codes to member-friendly copy" do
    assert PaymentUserMessages.format_stripe_error(%Stripe.Error{
             code: "expired_card",
             message: "Your card has expired.",
             source: :api
           }) =~ "expired"

    assert PaymentUserMessages.format_stripe_error(%Stripe.Error{
             code: "incorrect_cvc",
             message: "Your card's security code is incorrect.",
             source: :api
           }) =~ "security code"

    assert PaymentUserMessages.format_stripe_error(%Stripe.Error{
             code: "processing_error",
             message: "An error occurred while processing your card.",
             source: :api
           }) =~ "bank"
  end

  test "format_stripe_error infers guidance from raw message substrings" do
    assert PaymentUserMessages.format_stripe_error("Card expired last month") =~
             "expired"

    assert PaymentUserMessages.format_stripe_error("Incorrect security code") =~
             "security code"
  end

  test "generic_payment_failed includes contact email and avoids Stripe jargon" do
    message = PaymentUserMessages.generic_payment_failed()

    assert message =~ "couldn't process your payment"
    assert message =~ "info@ysc.org"
    refute message =~ "payment_intent"
  end
end
