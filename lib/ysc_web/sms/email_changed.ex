defmodule YscWeb.Sms.EmailChanged do
  @moduledoc """
  SMS template for email change notification.

  Sends a security notification to users when their email address has been changed.
  """

  @doc """
  Gets the template name.
  """
  def get_template_name do
    "email_changed"
  end

  @doc """
  Renders the SMS message body.

  ## Parameters:
  - `variables`: Map with user info and new email

  ## Returns:
  - String with SMS message body
  """
  def render(variables) do
    first_name = Map.get(variables, :first_name, "Valued Member")
    new_email = Map.get(variables, :new_email, "your email")

    """
    [YSC] Hej #{first_name}! Your account email was changed to #{new_email}. If this wasn't you, please contact us right away.
    """
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  @doc """
  Prepares email changed SMS data.

  ## Parameters:
  - `user`: The user whose email was changed
  - `new_email`: The new email address

  ## Returns:
  - Map with all necessary data for the SMS template
  """
  def prepare_sms_data(user, new_email) when is_binary(new_email) do
    %{
      first_name: if(user, do: user.first_name, else: nil),
      new_email: new_email
    }
  end
end
