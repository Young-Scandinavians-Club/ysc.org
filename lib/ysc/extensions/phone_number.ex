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
end
