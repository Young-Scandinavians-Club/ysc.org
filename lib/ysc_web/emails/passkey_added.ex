defmodule YscWeb.Emails.PasskeyAdded do
  @moduledoc """
  Email template for passkey addition notification.

  Sends a security notification to users when a new passkey has been added to their account,
  informing them to contact support immediately if they did not add the passkey.
  """
  use MjmlEEx,
    mjml_template: "templates/passkey_added.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "passkey_added"
  end
end
