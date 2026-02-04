defmodule YscWeb.Emails.EmailChanged do
  @moduledoc """
  Email template for email change notification.

  Sends a security notification to users when their email address has been changed,
  informing them to contact support immediately if they did not make the change.
  """
  use MjmlEEx,
    mjml_template: "templates/email_changed.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "email_changed"
  end
end
