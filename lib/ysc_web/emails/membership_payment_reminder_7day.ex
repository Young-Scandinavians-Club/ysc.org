defmodule YscWeb.Emails.MembershipPaymentReminder7Day do
  @moduledoc """
  Email template for 7-day membership payment reminder.

  Sent to users who were approved 7 days ago but haven't paid their membership dues yet.
  """
  use MjmlEEx,
    mjml_template: "templates/membership_payment_reminder_7day.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [membership_payment_reminder_data: 1]

  def get_template_name() do
    "membership_payment_reminder_7day"
  end

  def get_subject() do
    "Complete Your YSC Membership - Don't Miss Out! 🎉"
  end

  def prepare_email_data(user), do: membership_payment_reminder_data(user)
end
