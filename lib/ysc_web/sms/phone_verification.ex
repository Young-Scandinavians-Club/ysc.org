defmodule YscWeb.Sms.PhoneVerification do
  @moduledoc """
  SMS template for phone number verification during account setup.

  Sends a verification code to users for verifying their phone number.
  """

  alias YscWeb.Sms.Template

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

    "Your phone verification code is: #{code}. Enter this code to verify your phone number."
    |> Template.greeting(Template.optional_first_name(variables))
    |> Template.format()
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
    Template.verification_variables(user, code)
  end

  def prepare_sms_data(user, code) when is_integer(code) do
    prepare_sms_data(user, Template.verification_code(code))
  end
end
