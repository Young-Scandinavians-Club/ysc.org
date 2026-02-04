defmodule YscWeb.Emails.ApplicationApproved do
  @moduledoc """
  Email template for application approval notification.

  Notifies users when their membership application has been approved.
  """
  use MjmlEEx,
    mjml_template: "templates/application_approved.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "application_approved"
  end

  def get_subject() do
    "Velkommen! You're officially a Young Scandinavian 🎉 (One more step!)"
  end

  def upcoming_events_url() do
    YscWeb.Endpoint.url() <> "/events"
  end

  def pay_membership_url() do
    YscWeb.Endpoint.url() <> "/users/membership"
  end
end
