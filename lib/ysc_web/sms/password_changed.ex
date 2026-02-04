defmodule YscWeb.Sms.PasswordChanged do
  @moduledoc """
  SMS template for password change notification.

  Sends a security notification to users when their password has been changed.
  """

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
    first_name = Map.get(variables, :first_name, "Valued Member")

    """
    [YSC] Hej #{first_name}! Your account password was changed. If this wasn't you, please contact us right away.
    """
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  @doc """
  Prepares password changed SMS data.

  ## Parameters:
  - `user`: The user whose password was changed

  ## Returns:
  - Map with all necessary data for the SMS template
  """
  def prepare_sms_data(user) do
    %{
      first_name: if(user, do: user.first_name, else: nil)
    }
  end
end
