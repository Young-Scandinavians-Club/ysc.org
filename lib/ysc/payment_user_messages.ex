defmodule Ysc.PaymentUserMessages do
  @moduledoc false

  @card_declined_message "Your card was declined. Please try a different payment method or contact your bank."

  def payment_setup_failed do
    trim("""
    We couldn't set up payment. Please refresh the page and try again. If it still doesn't work, email #{Ysc.EmailConfig.contact_email()} for help.
    """)
  end

  def invoice_retry_failed do
    trim("""
    We couldn't process that payment. Update your card in Membership settings and try again, or email #{Ysc.EmailConfig.membership_email()} for help.
    """)
  end

  def invoice_retry_error(error) do
    case format_stripe_error(error) do
      @card_declined_message -> @card_declined_message
      _ -> invoice_retry_failed()
    end
  end

  def generic_payment_failed do
    trim("""
    We couldn't process your payment. Check your card details or try another payment method. If this keeps happening, email #{Ysc.EmailConfig.contact_email()}.
    """)
  end

  def format_stripe_error(%Stripe.Error{code: code})
      when code in [:card_declined, "card_declined"] do
    @card_declined_message
  end

  def format_stripe_error(%Stripe.Error{code: code})
      when code in [:expired_card, "expired_card"] do
    "Your card has expired. Please use a different card."
  end

  def format_stripe_error(%Stripe.Error{code: code})
      when code in [:incorrect_cvc, "incorrect_cvc"] do
    "The security code on your card is incorrect. Please check the number and try again."
  end

  def format_stripe_error(%Stripe.Error{code: code})
      when code in [:processing_error, "processing_error"] do
    "Your bank couldn't process this payment. Please try again in a few minutes or use a different card."
  end

  def format_stripe_error(%Stripe.Error{message: message})
      when is_binary(message) do
    format_payment_error_message(message)
  end

  def format_stripe_error(error) when is_binary(error) do
    format_payment_error_message(error)
  end

  def format_stripe_error(_error) do
    generic_payment_failed()
  end

  defp format_payment_error_message(message) do
    downcased = String.downcase(message)

    cond do
      String.contains?(downcased, "declined") ->
        @card_declined_message

      String.contains?(downcased, "expired") ->
        "Your card has expired. Please use a different card."

      String.contains?(downcased, "cvc") or
          String.contains?(downcased, "security code") ->
        "The security code on your card is incorrect. Please check the number and try again."

      true ->
        generic_payment_failed()
    end
  end

  defp trim(string), do: String.trim(string)
end
