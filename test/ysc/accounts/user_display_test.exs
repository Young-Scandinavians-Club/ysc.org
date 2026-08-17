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

  describe "full_name/1-3" do
    test "title-cases and joins first and last name from a map" do
      assert UserDisplay.full_name(%{first_name: "jane", last_name: "doe"}) ==
               "Jane Doe"
    end

    test "title-cases and joins separate name fields" do
      assert UserDisplay.full_name(%{first_name: "jane", last_name: "doe"}) ==
               "Jane Doe"
    end

    test "returns a single name when the other is blank" do
      assert UserDisplay.full_name(%{first_name: "jane", last_name: nil}) ==
               "Jane"

      assert UserDisplay.full_name(%{first_name: nil, last_name: "doe"}) ==
               "Doe"
    end

    test "returns fallback when both names are blank" do
      assert UserDisplay.full_name(%{first_name: nil, last_name: nil}) == nil

      assert UserDisplay.full_name(%{first_name: "", last_name: ""},
               fallback: "Unknown"
             ) ==
               "Unknown"
    end

    test "treats whitespace-only names as blank" do
      assert UserDisplay.full_name(%{first_name: "  ", last_name: "doe"}) ==
               "Doe"

      assert UserDisplay.full_name(%{first_name: "jane", last_name: "  "}) ==
               "Jane"
    end
  end

  describe "first_name_label/1" do
    test "title-cases first names" do
      assert UserDisplay.first_name_label("jane") == "Jane"
      assert UserDisplay.first_name_label(%{first_name: "jane"}) == "Jane"
    end

    test "returns empty string for nil or blank values" do
      assert UserDisplay.first_name_label(nil) == ""
      assert UserDisplay.first_name_label("") == ""
      assert UserDisplay.first_name_label("  ") == ""
    end
  end

  describe "application_submitted_at/1" do
    test "prefers registration_form.completed over reviewed_at and inserted_at" do
      completed = ~U[2024-06-01 12:00:00Z]
      reviewed_at = ~U[2024-06-02 12:00:00Z]
      inserted_at = ~U[2024-05-01 12:00:00Z]

      user = %{
        inserted_at: inserted_at,
        registration_form: %{
          completed: completed,
          reviewed_at: reviewed_at
        }
      }

      assert UserDisplay.application_submitted_at(user) == completed
    end

    test "falls back to reviewed_at when completed is absent" do
      reviewed_at = ~U[2024-06-02 12:00:00Z]
      inserted_at = ~U[2024-05-01 12:00:00Z]

      user = %{
        inserted_at: inserted_at,
        registration_form: %{reviewed_at: reviewed_at}
      }

      assert UserDisplay.application_submitted_at(user) == reviewed_at
    end

    test "falls back to inserted_at when no application timestamps exist" do
      inserted_at = ~U[2024-05-01 12:00:00Z]

      assert UserDisplay.application_submitted_at(%{inserted_at: inserted_at}) ==
               inserted_at
    end
  end
end
