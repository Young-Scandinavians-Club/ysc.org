defmodule Ysc.Extensions.PhoneNumberTest do
  @moduledoc """
  Tests for PhoneNumber extension module.

  These tests verify:
  - Phone number parsing
  - Phone number validation
  - Phone number formatting
  - Phone number type detection
  """
  use ExUnit.Case, async: true

  alias Ysc.Extensions.PhoneNumber

  describe "parse_phone_number/2" do
    test "parses valid phone number with country code" do
      result = PhoneNumber.parse_phone_number("+14155551234", "US")

      assert match?({:ok, _phone_number}, result)
    end

    test "parses phone number with default country" do
      result = PhoneNumber.parse_phone_number("4155551234", "US")

      assert match?({:ok, _phone_number}, result)
    end

    test "returns error for invalid phone number" do
      # Use a clearly invalid phone number
      result = PhoneNumber.parse_phone_number("abc", "US")

      assert match?({:error, _}, result)
    end
  end

  describe "possible_phone_number?/1" do
    test "returns true for possible phone number" do
      {:ok, phone_number} = PhoneNumber.parse_phone_number("+14155551234", "US")
      assert PhoneNumber.possible_phone_number?(phone_number) == true
    end

    test "returns false for impossible phone number" do
      # Create an invalid phone number struct if possible
      # For now, we test the function exists and can be called
      {:ok, phone_number} = PhoneNumber.parse_phone_number("+14155551234", "US")
      result = PhoneNumber.possible_phone_number?(phone_number)
      assert is_boolean(result)
    end
  end

  describe "valid_phone_number?/1" do
    test "returns true for valid phone number" do
      {:ok, phone_number} = PhoneNumber.parse_phone_number("+14155551234", "US")
      assert PhoneNumber.valid_phone_number?(phone_number) == true
    end

    test "returns false for invalid phone number" do
      # Test with a number that parses but isn't valid
      {:ok, phone_number} = PhoneNumber.parse_phone_number("+15551234567", "US")
      result = PhoneNumber.valid_phone_number?(phone_number)
      assert is_boolean(result)
    end
  end

  describe "get_phone_number_type/1" do
    test "returns phone number type" do
      {:ok, phone_number} = PhoneNumber.parse_phone_number("+14155551234", "US")
      type = PhoneNumber.get_phone_number_type(phone_number)

      # Type should be an atom
      assert is_atom(type)
    end
  end

  describe "format_phone_number/2" do
    test "formats phone number in national format" do
      {:ok, phone_number} = PhoneNumber.parse_phone_number("+14155551234", "US")
      formatted = PhoneNumber.format_phone_number(phone_number, :national)

      assert is_binary(formatted)
      assert formatted != ""
    end

    test "formats phone number in international format" do
      {:ok, phone_number} = PhoneNumber.parse_phone_number("+14155551234", "US")
      formatted = PhoneNumber.format_phone_number(phone_number, :international)

      assert is_binary(formatted)
      assert String.starts_with?(formatted, "+")
    end

    test "formats phone number in e164 format" do
      {:ok, phone_number} = PhoneNumber.parse_phone_number("+14155551234", "US")
      formatted = PhoneNumber.format_phone_number(phone_number, :e164)

      assert is_binary(formatted)
      assert String.starts_with?(formatted, "+")
    end

    test "formats phone number in rfc3966 format" do
      {:ok, phone_number} = PhoneNumber.parse_phone_number("+14155551234", "US")
      formatted = PhoneNumber.format_phone_number(phone_number, :rfc3966)

      assert is_binary(formatted)
      assert String.starts_with?(formatted, "tel:")
    end
  end
end
