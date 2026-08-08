defmodule Ysc.Extensions.PhoneNumber do
  @moduledoc """
  Functions for implementing phone number validations and formatting
  using [ex_phone_number](https://hex.pm/packages/ex_phone_number).
  """

  @doc """
  Parses a given phone number string.
  ## Example
    iex > {:ok, phone_number} = ExPhoneNumber.parse("044 668 18 00", "CH")
    {:ok,
      %ExPhoneNumber.Model.PhoneNumber{
        country_code: 41,
        country_code_source: nil,
        extension: nil,
        italian_leading_zero: nil,
        national_number: 446681800,
        number_of_leading_zeros: nil,
        preferred_domestic_carrier_code: nil,
        raw_input: nil
    }}
  """
  def parse_phone_number(phone_number, opts \\ "") do
    ExPhoneNumber.parse(phone_number, opts)
  end

  @doc """
  Checks whether a given phone number is possible.
  Returns true or false.
  """
  def possible_phone_number?(phone_number) do
    ExPhoneNumber.is_possible_number?(phone_number)
  end

  @doc """
  Checks whether a given phone number is valid.
  Returns true or false.
  """
  def valid_phone_number?(phone_number) do
    ExPhoneNumber.is_valid_number?(phone_number)
  end

  @doc """
  Checks the type of phone number, e.g. `:fixed` or
  `:fixed_line_or_mobile`.
  """
  def get_phone_number_type(phone_number) do
    ExPhoneNumber.get_number_type(phone_number)
  end

  @doc """
  Formats a phone number.
  opts: :national, :international, :e164, :rfc3966
  """
  def format_phone_number(phone_number, opts) do
    ExPhoneNumber.format(phone_number, opts)
  end

  @doc """
  Formats a phone number for display in the UI (e.g. (206) 555-1234).

  Returns `nil` for `nil` or empty string so callers can use a fallback like "Not provided" or "—".
  For invalid numbers, returns the raw string.
  """
  def format_for_display(nil), do: nil
  def format_for_display(""), do: nil

  def format_for_display(phone_number) when is_binary(phone_number) do
    case ExPhoneNumber.parse(phone_number, "") do
      {:ok, parsed} ->
        ExPhoneNumber.format(parsed, :national)

      {:error, _} ->
        phone_number
    end
  end

  @sms_supported_regions ~w(US CA)

  @doc """
  Returns whether SMS delivery is supported for a given phone number.

  FlowRoute (our SMS provider) can only reliably deliver to US and Canadian
  numbers, so anything outside those regions should skip SMS verification
  and notifications rather than attempt (and silently fail) delivery.
  """
  @spec sms_supported?(String.t() | nil) :: boolean()
  def sms_supported?(nil), do: false
  def sms_supported?(""), do: false

  def sms_supported?(phone_number) when is_binary(phone_number) do
    case ExPhoneNumber.parse(phone_number, "") do
      {:ok, parsed} ->
        ExPhoneNumber.Metadata.get_region_code_for_number(parsed) in @sms_supported_regions

      {:error, _} ->
        false
    end
  end
end
