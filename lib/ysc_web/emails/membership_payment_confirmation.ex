defmodule YscWeb.Emails.MembershipPaymentConfirmation do
  @moduledoc """
  Email template for first-time membership payment receipt.

  Sent when the first membership payment succeeds (`invoice.payment_succeeded`),
  including after ACH Direct Debit settles (which can take several days).
  Membership access and the “you're active” email are handled at activation time;
  this message confirms the payment amount and date.
  """
  use MjmlEEx,
    mjml_template: "templates/membership_payment_confirmation.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias YscWeb.MembershipHelpers

  import YscWeb.Emails.Helpers,
    only: [member_greeting_name: 1, format_date: 1, format_membership_money: 1]

  def get_template_name() do
    "membership_payment_confirmation"
  end

  def get_subject() do
    "Your YSC Membership Payment Receipt"
  end

  def prepare_email_data(
        user,
        membership_type,
        amount,
        payment_date,
        opts \\ []
      ) do
    if is_nil(user) do
      raise ArgumentError, "User cannot be nil"
    end

    paid_elsewhere = Keyword.get(opts, :paid_elsewhere, false)
    first_name = member_greeting_name(user)
    membership_type_name = MembershipHelpers.membership_type_name(membership_type)
    amount_str = format_membership_money(amount)
    payment_date_str = format_date(payment_date)

    %{
      first_name: first_name,
      membership_type: membership_type_name,
      amount: amount_str,
      payment_date: payment_date_str,
      paid_elsewhere: paid_elsewhere
    }
  end

end
