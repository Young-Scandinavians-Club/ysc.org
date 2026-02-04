defmodule YscWeb.Emails.MembershipPaymentReminder30Day do
  @moduledoc """
  Email template for 30-day membership payment reminder.

  Sent to users who were approved 30 days ago but haven't paid their membership dues yet.
  """
  use MjmlEEx,
    mjml_template: "templates/membership_payment_reminder_30day.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "membership_payment_reminder_30day"
  end

  def get_subject() do
    "Final Reminder: Complete Your YSC Membership"
  end

  def pay_membership_url() do
    YscWeb.Endpoint.url() <> "/users/membership"
  end

  def upcoming_events_url() do
    YscWeb.Endpoint.url() <> "/events"
  end

  def prepare_email_data(user) do
    # Validate input
    if is_nil(user) do
      raise ArgumentError, "User cannot be nil"
    end

    # Ensure user has required fields
    first_name = user.first_name || "Valued Member"

    %{
      first_name: first_name,
      pay_membership_url: pay_membership_url(),
      upcoming_events_url: upcoming_events_url()
    }
  end
end
