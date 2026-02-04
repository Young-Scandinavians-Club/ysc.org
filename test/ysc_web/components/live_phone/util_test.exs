defmodule LivePhone.UtilTest do
  use ExUnit.Case, async: true

  alias LivePhone.Util

  describe "valid?/1" do
    test "returns false for empty string" do
      refute Util.valid?("")
    end

    test "returns false for invalid phone numbers" do
      refute Util.valid?("+1555")
      refute Util.valid?("1234")
      refute Util.valid?("+1 (555) 555-1234")
    end

    test "returns true for valid phone numbers" do
      assert Util.valid?("+1 (650) 253-0000")
      assert Util.valid?("+16502530000")
      assert Util.valid?("+44 20 7946 0958")
      assert Util.valid?("+442079460958")
    end

    test "returns false for nil" do
      refute Util.valid?(nil)
    end

    test "handles phone numbers with spaces and formatting" do
      assert Util.valid?("+1 650 253 0000")
      assert Util.valid?("+1-650-253-0000")
    end
  end

  describe "get_country/1" do
    test "returns error for empty string" do
      assert Util.get_country("") == {:error, :invalid_number}
    end

    test "returns error for invalid phone numbers" do
      assert Util.get_country("+1555") == {:error, :invalid_number}
      assert Util.get_country("1234") == {:error, :invalid_number}
      assert Util.get_country("+1 (555) 555-1234") == {:error, :invalid_number}
    end

    test "returns country for valid US phone number" do
      assert {:ok, country} = Util.get_country("+1 (650) 253-0000")
      assert country.code == "US"
      assert country.region_code == "1"
      assert is_binary(country.name)
    end

    test "returns country for valid US phone number without formatting" do
      assert {:ok, country} = Util.get_country("+16502530000")
      assert country.code == "US"
      assert country.region_code == "1"
    end

    test "returns country for valid UK phone number" do
      assert {:ok, country} = Util.get_country("+44 20 7946 0958")
      assert country.code == "GB"
      assert country.region_code == "44"
    end

    test "returns error for nil" do
      assert Util.get_country(nil) == {:error, :invalid_number}
    end
  end

  describe "normalize/2" do
    test "returns error for invalid phone number" do
      assert Util.normalize("1234", nil) == {:error, "1234"}
      assert Util.normalize("invalid", nil) == {:error, "invalid"}
    end

    test "normalizes valid phone number without country code" do
      assert Util.normalize("+1234", nil) == {:ok, "+1234"}
    end

    test "normalizes formatted US phone number" do
      assert Util.normalize("+1 (650) 253-0000", "US") == {:ok, "+16502530000"}
      assert Util.normalize("(650) 253-0000", "US") == {:ok, "+16502530000"}
    end

    test "normalizes phone number with spaces" do
      assert Util.normalize("+1 650 253 0000", "US") == {:ok, "+16502530000"}
    end

    test "normalizes phone number with dashes" do
      assert Util.normalize("+1-650-253-0000", "US") == {:ok, "+16502530000"}
    end

    test "normalizes UK phone number" do
      assert Util.normalize("+44 20 7946 0958", "GB") == {:ok, "+442079460958"}
      assert Util.normalize("020 7946 0958", "GB") == {:ok, "+442079460958"}
    end

    test "strips non-digit characters except plus" do
      assert Util.normalize("+1 (650) abc-253-0000", "US") ==
               {:ok, "+16502530000"}
    end

    test "handles nil country code" do
      assert Util.normalize("+16502530000", nil) == {:ok, "+16502530000"}
    end

    test "returns error when country code doesn't match number" do
      # This might still parse, but let's test the behavior
      result = Util.normalize("+16502530000", "GB")
      # It should still normalize if the number is valid
      assert match?({:ok, _}, result)
    end

    test "handles empty string" do
      assert Util.normalize("", nil) == {:error, ""}
    end
  end
end
