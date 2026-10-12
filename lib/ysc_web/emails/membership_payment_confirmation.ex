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

  import YscWeb.Emails.Helpers,
    only: [
      format_date: 1,
      format_membership_money: 1,
      membership_member_assigns: 2
    ]

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
    paid_elsewhere = Keyword.get(opts, :paid_elsewhere, false)

    user
    |> membership_member_assigns(membership_type)
    |> Map.merge(%{
      amount: format_membership_money(amount),
      payment_date: format_date(payment_date),
      paid_elsewhere: paid_elsewhere
    })
  end
end
