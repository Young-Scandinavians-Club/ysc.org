defmodule YscWeb.Sms.TwoFactorVerification do
  @moduledoc """
  SMS template for two-factor authentication verification code.

  Sends a verification code to users for 2FA authentication.
  """

  alias YscWeb.Sms.Template

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

    "Your secure login code is: #{code}. Do not share this code. If you did not request this, email #{Ysc.EmailConfig.contact_email()}."
    |> Template.greeting(Template.optional_first_name(variables))
    |> Template.format()
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
    Template.verification_variables(user, code)
  end

  def prepare_sms_data(user, code) when is_integer(code) do
    prepare_sms_data(user, Template.verification_code(code))
  end
end
