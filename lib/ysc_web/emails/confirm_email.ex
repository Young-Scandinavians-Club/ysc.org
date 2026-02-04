defmodule YscWeb.Emails.ConfirmEmail do
  @moduledoc """
  Email template for email confirmation.

  Sends email confirmation instructions to users for verifying their email address.
  """
  use MjmlEEx,
    mjml_template: "templates/confirm_email.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "confirm_email"
  end
end
