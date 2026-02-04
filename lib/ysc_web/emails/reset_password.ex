defmodule YscWeb.Emails.ResetPassword do
  @moduledoc """
  Email template for password reset instructions.

  Sends password reset instructions to users who request a password reset.
  """
  use MjmlEEx,
    mjml_template: "templates/reset_password.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "reset_password"
  end
end
