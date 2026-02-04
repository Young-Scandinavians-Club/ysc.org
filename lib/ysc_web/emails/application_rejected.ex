defmodule YscWeb.Emails.ApplicationRejected do
  @moduledoc """
  Email template for application rejection notification.

  Notifies users when their membership application has been rejected.
  """
  use MjmlEEx,
    mjml_template: "templates/application_rejected.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "application_rejected"
  end

  def get_subject() do
    "Update on your Young Scandinavians Club application"
  end
end
