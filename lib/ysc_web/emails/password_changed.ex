defmodule YscWeb.Emails.PasswordChanged do
  @moduledoc """
  Email template for password change notification.

  Sends a security notification to users when their password has been changed,
  informing them to contact support immediately if they did not make the change.
  """
  use MjmlEEx,
    mjml_template: "templates/password_changed.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "password_changed"
  end
end
