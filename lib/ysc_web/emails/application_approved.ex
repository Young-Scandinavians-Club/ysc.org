defmodule YscWeb.Emails.ApplicationApproved do
  @moduledoc """
  Email template for application approval notification.

  Notifies users when their membership application has been approved.
  """
  use MjmlEEx,
    mjml_template: "templates/application_approved.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [absolute_url: 1]

  def get_template_name() do
    "application_approved"
  end

  def get_subject() do
    "Velkommen! You're officially a Young Scandinavian 🎉 (One more step!)"
  end

  def upcoming_events_url() do
    absolute_url("/events")
  end

  def pay_membership_url() do
    absolute_url("/users/membership")
  end
end
