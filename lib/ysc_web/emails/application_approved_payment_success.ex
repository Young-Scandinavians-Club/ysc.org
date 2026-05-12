defmodule YscWeb.Emails.ApplicationApprovedPaymentSuccess do
  @moduledoc """
  Email template for application approval with automatic payment confirmation.

  Sent when a user's application is approved and their saved payment method
  is successfully charged to activate their membership immediately.
  """
  use MjmlEEx,
    mjml_template: "templates/application_approved_payment_success.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [absolute_url: 1]

  def get_template_name() do
    "application_approved_payment_success"
  end

  def get_subject() do
    "Velkommen! Your YSC Membership is Active! 🎉"
  end

  def dashboard_url() do
    absolute_url("/")
  end

  def upcoming_events_url() do
    absolute_url("/events")
  end
end
