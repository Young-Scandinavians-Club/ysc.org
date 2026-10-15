defmodule Ysc.Merch.ColorSwatchTest do
  use ExUnit.Case, async: true

  alias Ysc.Merch.ColorSwatch

  test "knows common apparel colors regardless of case and spacing" do
    assert ColorSwatch.hex("Black") == "#18181b"
    assert ColorSwatch.hex("  navy ") == "#1e2a4a"
    assert ColorSwatch.hex("HEATHER GREY") == ColorSwatch.hex("Heather Gray")
    assert ColorSwatch.hex("Forest Green") == "#14532d"
  end

  test "falls back to a base color word in the name" do
    assert ColorSwatch.hex("Vintage Black") == "#18181b"
    assert ColorSwatch.hex("Electric Blue") == "#2563eb"
    assert ColorSwatch.hex("Dusty Pink") == "#f472b6"
  end

  test "an exact name wins over a word inside it" do
    # "Light Blue" is a lighter blue than plain "blue".
    refute ColorSwatch.hex("Light Blue") == ColorSwatch.hex("Blue")
  end

  test "unknown names have no color" do
    assert ColorSwatch.hex("Mystery") == nil
    assert ColorSwatch.hex("") == nil
    assert ColorSwatch.hex(nil) == nil
  end

  test "every color is a valid hex" do
    for name <-
          ~w(Black White Navy Red Royal Maroon Gold Sand Olive Teal Silver) do
      assert ColorSwatch.hex(name) =~ ~r/^#[0-9a-f]{6}$/
    end
  end

  test "flags light colors that need an outline" do
    assert ColorSwatch.light?("#ffffff")
    assert ColorSwatch.light?(ColorSwatch.hex("Cream"))
    refute ColorSwatch.light?("#18181b")
    refute ColorSwatch.light?(nil)
    refute ColorSwatch.light?("not-a-color")
  end
end
