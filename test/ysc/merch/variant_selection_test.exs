defmodule Ysc.Merch.VariantSelectionTest do
  use ExUnit.Case, async: true

  alias Ysc.Merch.{Variant, VariantSelection}

  defp v(color, size),
    do: %Variant{id: "#{color}-#{size}", color: color, size: size}

  defp tee do
    [
      v("Black", "M"),
      v("Black", "L"),
      v("Black", "XL"),
      v("Black", "S"),
      v("White", "M"),
      v("White", "L")
    ]
  end

  test "colors keep first-seen order and skip blanks" do
    assert VariantSelection.colors(tee()) == ["Black", "White"]
    assert VariantSelection.colors([v(nil, "M"), v("", "L")]) == []
  end

  test "sizes are sorted S to XL, not alphabetically" do
    assert VariantSelection.sizes(tee(), "Black") == ["S", "M", "L", "XL"]
    assert VariantSelection.sizes(tee(), "White") == ["M", "L"]
    assert VariantSelection.sizes(tee()) == ["S", "M", "L", "XL"]

    assert VariantSelection.sizes([
             v(nil, "2XL"),
             v(nil, "XS"),
             v(nil, "One size")
           ]) == ["XS", "2XL", "One size"]
  end

  describe "default/1" do
    test "starts on the first color with no size" do
      assert VariantSelection.default(tee()) == %{color: "Black", size: nil}
    end

    test "a single variant starts fully selected" do
      assert VariantSelection.default([v("Navy", "M")]) == %{
               color: "Navy",
               size: "M"
             }

      assert VariantSelection.default([v(nil, nil)]) == %{color: nil, size: nil}
    end
  end

  describe "find/2" do
    test "needs every offered option chosen" do
      assert VariantSelection.find(tee(), %{color: "Black", size: nil}) == nil
      assert VariantSelection.find(tee(), %{color: nil, size: "M"}) == nil

      assert %Variant{id: "Black-L"} =
               VariantSelection.find(tee(), %{color: "Black", size: "L"})
    end

    test "a combination that does not exist is nil" do
      assert VariantSelection.find(tee(), %{color: "White", size: "XL"}) == nil
    end

    test "color-only and size-only products" do
      mugs = [v("White", nil), v("Black", nil)]

      assert %Variant{id: "Black-"} =
               VariantSelection.find(mugs, %{color: "Black", size: nil})

      assert VariantSelection.find(mugs, %{color: nil, size: nil}) == nil

      shirts = [v(nil, "S"), v(nil, "M")]

      assert %Variant{id: "-M"} =
               VariantSelection.find(shirts, %{color: nil, size: "M"})
    end

    test "products without options resolve immediately" do
      stickers = [v(nil, nil), v(nil, nil)]

      assert %Variant{} =
               VariantSelection.find(stickers, %{color: nil, size: nil})
    end
  end

  describe "select_color/3 and select_size/3" do
    test "changing color keeps the size when that color has it" do
      selection = %{color: "Black", size: "L"}

      assert VariantSelection.select_color(tee(), selection, "White") == %{
               color: "White",
               size: "L"
             }
    end

    test "changing color drops a size the new color lacks" do
      selection = %{color: "Black", size: "XL"}

      assert VariantSelection.select_color(tee(), selection, "White") == %{
               color: "White",
               size: nil
             }
    end

    test "unknown colors and sizes are ignored" do
      selection = %{color: "Black", size: "M"}

      assert VariantSelection.select_color(tee(), selection, "Pink") ==
               selection

      assert VariantSelection.select_size(tee(), selection, "7XL") == selection

      assert VariantSelection.select_size(
               tee(),
               %{color: "White", size: nil},
               "XL"
             ) == %{color: "White", size: nil}

      assert VariantSelection.select_size(tee(), selection, "L") == %{
               color: "Black",
               size: "L"
             }
    end

    test "size availability follows the color" do
      assert VariantSelection.size_available?(tee(), %{color: "Black"}, "XL")
      refute VariantSelection.size_available?(tee(), %{color: "White"}, "XL")
    end
  end
end
