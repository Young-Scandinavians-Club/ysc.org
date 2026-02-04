defmodule YscWeb.Emails.AccountSetupVerification do
  @moduledoc """
  Email template for email verification.

  Sends a verification code to users for verifying their email address during account setup
  or when changing email addresses in user settings.
  """
  use MjmlEEx,
    mjml_template: "templates/account_setup_verification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "account_setup_verification"
  end
end
