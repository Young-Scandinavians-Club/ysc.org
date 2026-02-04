defmodule YscWeb.Sms.PhoneVerification do
  @moduledoc """
  SMS template for phone number verification during account setup.

  Sends a verification code to users for verifying their phone number.
  """

  @doc """
  Gets the template name.
  """
  def get_template_name do
    "phone_verification"
  end

  @doc """
  Renders the SMS message body.

  ## Parameters:
  - `variables`: Map with verification code and optional user info

  ## Returns:
  - String with SMS message body
  """
  def render(variables) do
    code = Map.get(variables, :code, "")
    first_name = Map.get(variables, :first_name)

    base_message =
      "Your phone verification code is: #{code}. Enter this code to verify your phone number."

    message =
      if first_name do
        "Hej #{first_name}! #{base_message}"
      else
        base_message
      end

    "[YSC] #{message}"
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  @doc """
  Prepares phone verification SMS data.

  ## Parameters:
  - `user`: The user requesting phone verification
  - `code`: The verification code (6-digit string)

  ## Returns:
  - Map with all necessary data for the SMS template
  """
  def prepare_sms_data(user, code) when is_binary(code) do
    %{
      code: code,
      first_name: if(user, do: user.first_name, else: nil)
    }
  end

  def prepare_sms_data(user, code) when is_integer(code) do
    prepare_sms_data(
      user,
      Integer.to_string(code) |> String.pad_leading(6, "0")
    )
  end
end
