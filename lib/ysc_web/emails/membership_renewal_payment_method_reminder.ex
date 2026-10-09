defmodule YscWeb.Emails.MembershipRenewalPaymentMethodReminder do
  @moduledoc """
  Email template for membership renewal payment method reminder.

  Sent to users 14 days before their membership renewal date if they don't have
  a saved card or bank account. This is common for users who paid with cash or other
  offline methods initially.
  """
  use MjmlEEx,
    mjml_template:
      "templates/membership_renewal_payment_method_reminder.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [membership_renewal_assigns: 2]

  def membership_url(), do: YscWeb.Emails.Helpers.membership_url()

  def payment_methods_url(), do: YscWeb.Emails.Helpers.payment_methods_url()

  def get_template_name() do
    "membership_renewal_payment_method_reminder"
  end

  def get_subject() do
    "Please add a payment method so your membership can renew"
  end

  def prepare_email_data(user, subscription) do
    user
    |> membership_renewal_assigns(subscription)
    |> Map.put(:payment_methods_url, payment_methods_url())
  end
end
