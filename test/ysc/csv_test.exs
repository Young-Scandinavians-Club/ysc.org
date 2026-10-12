defmodule Ysc.CsvTest do
  use ExUnit.Case, async: true

  alias Ysc.Csv

  describe "sanitize_cell/1" do
    test "prefixes spreadsheet formula starters with an apostrophe" do
      assert Csv.sanitize_cell("=HYPERLINK(1)") == "'=HYPERLINK(1)"
      assert Csv.sanitize_cell("+cmd|'") == "'+cmd|'"
      assert Csv.sanitize_cell("-1+1") == "'-1+1"
      assert Csv.sanitize_cell("@SUM(A1)") == "'@SUM(A1)"
      assert Csv.sanitize_cell("\t=1+1") == "'\t=1+1"
      assert Csv.sanitize_cell("\r=1+1") == "'\r=1+1"
    end

    test "leaves plain negative integers and ordinary text alone" do
      assert Csv.sanitize_cell("-3") == "-3"
      assert Csv.sanitize_cell("Jane") == "Jane"
      assert Csv.sanitize_cell("") == ""
      assert Csv.sanitize_cell("hello=world") == "hello=world"
    end

    test "passes through non-binaries" do
      assert Csv.sanitize_cell(nil) == nil
      assert Csv.sanitize_cell(42) == 42
      assert Csv.sanitize_cell(:email) == :email
    end
  end

  describe "sanitize_row/1" do
    test "sanitizes list cells" do
      assert Csv.sanitize_row(["Jane", "=HYPERLINK(1)", -3]) ==
               ["Jane", "'=HYPERLINK(1)", -3]
    end

    test "sanitizes map values and binary keys" do
      assert Csv.sanitize_row(%{
               "Name" => "=cmd|'/C calc'!A0",
               first_name: "Ada",
               count: 1
             }) == %{
               "Name" => "'=cmd|'/C calc'!A0",
               first_name: "Ada",
               count: 1
             }
    end
  end
end
