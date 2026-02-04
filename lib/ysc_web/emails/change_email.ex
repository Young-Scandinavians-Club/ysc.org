defmodule YscWeb.Emails.ChangeEmail do
  @moduledoc """
  Email template for email change confirmation.

  Sends confirmation instructions when a user requests to change their email address.
  """
  use MjmlEEx,
    mjml_template: "templates/change_email.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "change_email"
  end
end
