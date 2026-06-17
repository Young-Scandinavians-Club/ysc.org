defmodule Ysc.WpMigration.FamilyMembersTest do
  use ExUnit.Case, async: true

  alias Ysc.WpMigration.FamilyMembers
  alias Ysc.WpMigration.FamilyMembersFixtures

  describe "split_name/1" do
    test "splits multi-word names with last token as surname" do
      assert FamilyMembers.split_name("Lars Erik Broman") ==
               {"Lars Erik", "Broman"}

      assert FamilyMembers.split_name("Emma Louise Bach") ==
               {"Emma Louise", "Bach"}

      assert FamilyMembers.split_name("Marit Frost") == {"Marit", "Frost"}
    end

    test "uses placeholder last name for a single token" do
      assert FamilyMembers.split_name("Kate") == {"Kate", "-"}
      assert FamilyMembers.split_name("  Olivia  ") == {"Olivia", "-"}
    end

    test "returns nil for blank input" do
      assert FamilyMembers.split_name("") == nil
      assert FamilyMembers.split_name("   ") == nil
      assert FamilyMembers.split_name(nil) == nil
    end
  end

  describe "parse_birth_date/1" do
    test "parses four-digit years as January 1" do
      assert FamilyMembers.parse_birth_date("2000") == ~D[2000-01-01]
      assert FamilyMembers.parse_birth_date("1999") == ~D[1999-01-01]
    end

    test "parses ISO and US date strings" do
      assert FamilyMembers.parse_birth_date("2005-06-15") == ~D[2005-06-15]
      assert FamilyMembers.parse_birth_date("6/15/2005") == ~D[2005-06-15]
      assert FamilyMembers.parse_birth_date("2005/06/15") == ~D[2005-06-15]
    end

    test "returns nil for invalid values" do
      assert FamilyMembers.parse_birth_date(nil) == nil
      assert FamilyMembers.parse_birth_date("") == nil
      assert FamilyMembers.parse_birth_date("0") == nil
      assert FamilyMembers.parse_birth_date("1899") == nil
      assert FamilyMembers.parse_birth_date("not-a-date") == nil
    end
  end

  describe "build_records/1" do
    test "builds spouse and children from application row" do
      row = %{
        "spouse_first_name" => "Andrew",
        "spouse_last_name" => "Napper",
        "children" => [
          %{"name" => "Kate", "birthday" => "1999"},
          %{"name" => "Olivia", "birthday" => "2009"}
        ]
      }

      records = FamilyMembers.build_records(row)
      assert length(records) == 3

      spouse = Enum.find(records, &(&1.type == :spouse))
      assert spouse.first_name == "Andrew"
      assert spouse.last_name == "Napper"
      assert is_nil(spouse.birth_date)

      children = Enum.filter(records, &(&1.type == :child))
      assert Enum.map(children, & &1.first_name) == ["Kate", "Olivia"]
      assert Enum.all?(children, &(&1.last_name == "-"))

      assert Enum.map(children, & &1.birth_date) == [
               ~D[1999-01-01],
               ~D[2009-01-01]
             ]
    end

    test "omits spouse when names are missing" do
      row = %{
        "children" => [%{"name" => "Lars Erik Broman", "birthday" => "2000"}]
      }

      records = FamilyMembers.build_records(row)
      assert length(records) == 1
      [child] = records
      assert child.type == :child
      assert child.first_name == "Lars Erik"
      assert child.last_name == "Broman"
    end

    test "creates spouse from last name only when first name missing" do
      row = %{"spouse_last_name" => "Westin"}

      [spouse] = FamilyMembers.build_records(row)
      assert spouse.type == :spouse
      assert spouse.first_name == "-"
      assert spouse.last_name == "Westin"
    end

    test "drops children with blank names" do
      row = %{
        "children" => [
          %{"name" => "  ", "birthday" => "2000"},
          %{"name" => "Valid Kid", "birthday" => "2001"}
        ]
      }

      records = FamilyMembers.build_records(row)
      assert length(records) == 1
      assert hd(records).first_name == "Valid"
      assert hd(records).last_name == "Kid"
    end
  end

  describe "backup fixture samples (real WP usermeta from backup.sql)" do
    setup do
      %{samples: FamilyMembersFixtures.backup_samples()}
    end

    test "build_records matches expected family structure for every fixture", %{
      samples: samples
    } do
      for sample <- samples do
        row =
          FamilyMembersFixtures.application_row_from_meta(
            sample["wp_user_id"],
            sample["meta"]
          )

        records = FamilyMembers.build_records(row)
        assert_records_match(records, sample["expected"], sample["wp_user_id"])
      end
    end

    test "extract application_from_usermeta agrees with fixture rows for meta-only spouse",
         %{
           samples: samples
         } do
      sample = Enum.find(samples, &(&1["wp_user_id"] == "23"))

      extracted =
        Ysc.WpMigration.Extract.application_from_usermeta(
          sample["wp_user_id"],
          "angela@example.com",
          "2017-01-01T00:00:00",
          sample["meta"]
        )

      assert extracted["spouse_first_name"] == "Angela"
      assert extracted["spouse_last_name"] == "Kjolby"

      fixture_row =
        FamilyMembersFixtures.application_row_from_meta(
          sample["wp_user_id"],
          sample["meta"]
        )

      assert FamilyMembers.build_records(extracted) ==
               FamilyMembers.build_records(fixture_row)
    end

    test "extract application_from_usermeta includes children from usermeta only",
         %{
           samples: samples
         } do
      sample = Enum.find(samples, &(&1["wp_user_id"] == "31"))

      extracted =
        Ysc.WpMigration.Extract.application_from_usermeta(
          sample["wp_user_id"],
          "broman@example.com",
          "2017-01-01T00:00:00",
          sample["meta"]
        )

      assert length(extracted["children"]) == 2
      assert hd(extracted["children"])["name"] == "Lars Erik Broman"

      records = FamilyMembers.build_records(extracted)
      assert length(records) == 2
      assert Enum.all?(records, &(&1.type == :child))
    end
  end

  defp assert_records_match(records, expected, wp_user_id) do
    spouse = Enum.find(records, &(&1.type == :spouse))
    children = Enum.filter(records, &(&1.type == :child))

    case expected["spouse"] do
      nil ->
        assert spouse == nil, "expected no spouse for WP user #{wp_user_id}"

      %{"first_name" => first, "last_name" => last} ->
        assert spouse, "expected spouse for WP user #{wp_user_id}"
        assert spouse.first_name == first
        assert spouse.last_name == last
    end

    assert length(children) == length(expected["children"]),
           "child count mismatch for WP user #{wp_user_id}"

    for {child, exp} <- Enum.zip(children, expected["children"]) do
      assert child.first_name == exp["first_name"],
             "first name mismatch for WP user #{wp_user_id}"

      assert child.last_name == exp["last_name"],
             "last name mismatch for WP user #{wp_user_id}"

      if exp["birth_date"] do
        assert child.birth_date == Date.from_iso8601!(exp["birth_date"])
      else
        assert is_nil(child.birth_date)
      end
    end
  end
end
