defmodule YscWeb.Emails.MembershipPaymentReminder30Day do
  @moduledoc """
  Email template for 30-day membership payment reminder.

  Sent to users who were approved 30 days ago but haven't paid their membership dues yet.
  """
  use MjmlEEx,
    mjml_template: "templates/membership_payment_reminder_30day.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [membership_payment_reminder_data: 1]

  def get_template_name() do
    "membership_payment_reminder_30day"
  end

  def get_subject() do
    "Final Reminder: Complete Your YSC Membership"
  end

  def prepare_email_data(user), do: membership_payment_reminder_data(user)
end
