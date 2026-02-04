defmodule YscWeb.Emails.AdminApplicationSubmitted do
  @moduledoc """
  Email template for admin application submission notification.

  Notifies administrators when a new membership application is submitted.
  """
  use MjmlEEx,
    mjml_template: "templates/admin_application_submitted.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "admin_application_submitted"
  end

  def get_subject() do
    "New Membership Application Received - Action Needed"
  end
end
