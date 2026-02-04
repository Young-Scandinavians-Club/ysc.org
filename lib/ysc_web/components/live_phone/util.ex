defmodule LivePhone.Util do
  @moduledoc """
  Utility functions for phone number validation and formatting.

  Provides helper functions for validating and formatting phone numbers
  using the ExPhoneNumber library.
  """
  alias LivePhone.Country

  @doc ~S"""
  This is used to verify a given phone number and see if it is a valid number
  according to ExPhoneNumber.

  ## Examples

      iex> Util.valid?("")
      false

      iex> Util.valid?("+1555")
      false

      iex> Util.valid?("+1555")
      false

      iex> Util.valid?("+1 (555) 555-1234")
      false

      iex> Util.valid?("+1 (555) 555-1234")
      false

      iex> Util.valid?("+1 (650) 253-0000")
      true

      iex> Util.valid?("+16502530000")
      true

  """
  @spec valid?(String.t()) :: boolean()
  def valid?(phone) do
    case ExPhoneNumber.parse(phone, nil) do
      {:ok, parsed_phone} -> ExPhoneNumber.is_valid_number?(parsed_phone)
      _ -> false
    end
  end

  @doc ~S"""
  This is used to try and get a `Country` for a given phone number.

  ## Examples

      iex> Util.get_country("")
      {:error, :invalid_number}

      iex> Util.get_country("+1555")
      {:error, :invalid_number}

      iex> Util.get_country("+1555")
      {:error, :invalid_number}

      iex> Util.get_country("+1 (555) 555-1234")
      {:error, :invalid_number}

      iex> Util.get_country("+1 (555) 555-1234")
      {:error, :invalid_number}

      iex> Util.get_country("+1 (650) 253-0000")
      {:ok, %LivePhone.Country{code: "US",
        name: "United States of America (the)", preferred: false, region_code: "1"}}

      iex> Util.get_country("+16502530000")
      {:ok, %LivePhone.Country{code: "US",
        name: "United States of America (the)", preferred: false, region_code: "1"}}

  """
  @spec get_country(String.t()) ::
          {:ok, Country.t()} | {:error, :invalid_number}
  def get_country(phone) do
    with {:ok, parsed_phone} <- ExPhoneNumber.parse(phone, nil),
         true <- ExPhoneNumber.is_valid_number?(parsed_phone),
         {:ok, country} <- Country.get(parsed_phone) do
      {:ok, country}
    else
      _ -> {:error, :invalid_number}
    end
  end

  @doc ~S"""
  This is used to normalize a given `phone` number to E.164 format, and returns
  a tuple with `{:ok, formatted_phone}` for valid numbers and `{:error,
  unformatted_phone}` for invalid numbers.

  ## Examples

      iex> Util.normalize("1234", nil)
      {:error, "1234"}

      iex> Util.normalize("+1234", nil)
      {:ok, "+1234"}

      iex> Util.normalize("+1 (650) 253-0000", "US")
      {:ok, "+16502530000"}

  """
  @spec normalize(String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, String.t()}
  def normalize(phone, country) do
    phone
    |> String.replace(~r/[^+\d]/, "")
    |> ExPhoneNumber.parse(country)
    |> case do
      {:ok, result} -> {:ok, ExPhoneNumber.format(result, :e164)}
      _ -> {:error, phone}
    end
  end
end
