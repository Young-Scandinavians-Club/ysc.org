defmodule YscWeb.Sms.PasswordChanged do
  @moduledoc """
  SMS template for password change notification.

  Sends a security notification to users when their password has been changed.
  """

  alias YscWeb.Sms.Template

  @preview_keys [:first_name]

  def preview_keys, do: @preview_keys

  @doc """
  Gets the template name.
  """
  def get_template_name do
    "password_changed"
  end

  @doc """
  Renders the SMS message body.

  ## Parameters:
  - `variables`: Map with user info

  ## Returns:
  - String with SMS message body
  """
  def render(variables) do
    Template.security_notification_body(
      Template.first_name(variables),
      "Your account password was changed. If this wasn't you, please contact us right away."
    )
  end

  @doc """
  Prepares password changed SMS data.

  ## Parameters:
  - `user`: The user whose password was changed

  ## Returns:
  - Map with all necessary data for the SMS template
  """
  def prepare_sms_data(user) do
    %{first_name: Template.user_first_name(user)}
  end
end
