defmodule YscTest do
  use ExUnit.Case, async: true

  describe "title_case/1" do
    test "capitalizes a single word" do
      assert "Johan" == Ysc.title_case("johan")
    end

    test "capitalizes each word in a multi-word name" do
      assert "Mary Jane" == Ysc.title_case("mary jane")
    end

    test "handles names with more than two words" do
      assert "Mary Van Der Berg" == Ysc.title_case("mary van der berg")
    end

    test "preserves already capitalized names" do
      assert "Johan Backman" == Ysc.title_case("Johan Backman")
    end

    test "handles all uppercase input" do
      assert "Johan" == Ysc.title_case("JOHAN")
    end

    test "returns empty string for empty string" do
      assert "" == Ysc.title_case("")
    end

    test "returns empty string for nil" do
      assert "" == Ysc.title_case(nil)
    end

    test "handles extra whitespace between words" do
      assert "Mary Jane" == Ysc.title_case("mary  jane")
    end
  end
end
