defmodule Ysc.Accounts.UserDisplayTest do
  use ExUnit.Case, async: true

  alias Ysc.Accounts.UserDisplay

  describe "nordic_country_options/0" do
    test "returns the five Nordic countries" do
      assert UserDisplay.nordic_country_options() == [
               "Sweden",
               "Norway",
               "Finland",
               "Denmark",
               "Iceland"
             ]
    end
  end

  describe "country_label/1" do
    test "maps Nordic and US country codes" do
      assert UserDisplay.country_label("SE") == "Sweden"
      assert UserDisplay.country_label("no") == "Norway"
      assert UserDisplay.country_label(" FI ") == "Finland"
      assert UserDisplay.country_label("DK") == "Denmark"
      assert UserDisplay.country_label("IS") == "Iceland"
      assert UserDisplay.country_label("US") == "United States"
    end

    test "returns unknown codes unchanged" do
      assert UserDisplay.country_label("Germany") == "Germany"
      assert UserDisplay.country_label("DE") == "DE"
    end

    test "returns empty string for nil" do
      assert UserDisplay.country_label(nil) == ""
    end
  end

  describe "country_flag_class/1" do
    test "returns flag-icons class for supported codes" do
      assert UserDisplay.country_flag_class("SE") == "fi-se"
      assert UserDisplay.country_flag_class("us") == "fi-us"
    end

    test "returns nil for unsupported or blank codes" do
      assert UserDisplay.country_flag_class(nil) == nil
      assert UserDisplay.country_flag_class("DE") == nil
      assert UserDisplay.country_flag_class("Germany") == nil
    end
  end

  describe "birth_date_label/1" do
    test "formats dates" do
      assert UserDisplay.birth_date_label(~D[2024-03-15]) == "Mar 15, 2024"
    end

    test "returns empty string for nil" do
      assert UserDisplay.birth_date_label(nil) == ""
    end

    test "stringifies other values" do
      assert UserDisplay.birth_date_label("unknown") == "unknown"
    end
  end
end
