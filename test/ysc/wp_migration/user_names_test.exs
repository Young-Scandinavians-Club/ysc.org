defmodule Ysc.WpMigration.UserNamesTest do
  use ExUnit.Case, async: true

  alias Ysc.WpMigration.UserNames

  describe "resolve/2" do
    test "uses explicit user names when present" do
      assert UserNames.resolve(
               %{
                 "first_name" => "Johan",
                 "last_name" => "Backman",
                 "email" => "a@b.com"
               },
               %{}
             ) == %{first_name: "Johan", last_name: "Backman"}
    end

    test "infers last name from dotted email local part" do
      assert UserNames.resolve(
               %{
                 "first_name" => "",
                 "last_name" => "",
                 "display_name" => "henrikflodell",
                 "email" => "henrik.flodell@gmail.com"
               },
               %{}
             ) == %{first_name: "Henrik", last_name: "Flodell"}
    end

    test "infers last name as remainder of email local part after first name" do
      assert UserNames.resolve(
               %{
                 "first_name" => "Neil",
                 "last_name" => "",
                 "display_name" => "neiljelmert@gmail.com",
                 "email" => "neiljelmert@gmail.com"
               },
               %{}
             ) == %{first_name: "Neil", last_name: "Jelmert"}
    end

    test "infers names from camelCase display name" do
      assert UserNames.resolve(
               %{
                 "first_name" => "",
                 "last_name" => "",
                 "display_name" => "MaryTestUser",
                 "email" => "marytest@example.com"
               },
               %{}
             ) == %{first_name: "Mary", last_name: "Testuser"}
    end

    test "infers domain-based last name when only first name is known" do
      assert UserNames.resolve(
               %{
                 "first_name" => "Maria",
                 "last_name" => "",
                 "display_name" => "mia@attach.io",
                 "email" => "mia@attach.io"
               },
               %{"first_name" => "Maria"}
             ) == %{first_name: "Maria", last_name: "Attach"}
    end

    test "infers names from service email local part and domain" do
      assert UserNames.resolve(
               %{
                 "first_name" => "",
                 "last_name" => "",
                 "display_name" => "support@acme.software",
                 "email" => "support@acme.software"
               },
               %{}
             ) == %{first_name: "Support", last_name: "Acme"}
    end
  end
end
