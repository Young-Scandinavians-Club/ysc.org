defmodule YscWeb.Sms.TwoFactorVerification do
  @moduledoc """
  SMS template for two-factor authentication verification code.

  Sends a verification code to users for 2FA authentication.
  """

  @doc """
  Gets the template name.
  """
  def get_template_name do
    "two_factor_verification"
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
      "Your secure login code is: #{code}. Do not share this code. If you did not request this, please contact support."

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
  Prepares two-factor verification SMS data.

  ## Parameters:
  - `user`: The user requesting 2FA
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
