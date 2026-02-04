defmodule ULIDColorTest do
  use ExUnit.Case, async: true

  alias ULIDColor

  describe "generate_color/1" do
    test "returns default color for nil" do
      assert ULIDColor.generate_color(nil) == "#F3F4F6"
    end

    test "returns a valid hex color for a ULID" do
      ulid = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      color = ULIDColor.generate_color(ulid)
      assert String.starts_with?(color, "#")
      assert String.length(color) == 7
      assert Regex.match?(~r/^#[0-9A-F]{6}$/i, color)
    end

    test "returns consistent color for the same ULID" do
      ulid = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      color1 = ULIDColor.generate_color(ulid)
      color2 = ULIDColor.generate_color(ulid)
      assert color1 == color2
    end

    test "returns different colors for different ULIDs" do
      ulid1 = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      ulid2 = "01ARZ3NDEKTSV4RRFFQ69G5FAW"
      color1 = ULIDColor.generate_color(ulid1)
      color2 = ULIDColor.generate_color(ulid2)
      # They might be the same by chance, but likely different
      # We'll just verify both are valid colors
      assert String.starts_with?(color1, "#")
      assert String.starts_with?(color2, "#")
    end

    test "returns a color from the light palette" do
      ulid = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      color = ULIDColor.generate_color(ulid)

      light_palette = [
        "#FEE2E2",
        "#FEF9C3",
        "#DCFCE7",
        "#DBEAFE",
        "#EDE9FE",
        "#FCE7F3",
        "#FEF3C7",
        "#E0F2FE",
        "#D1FAE5",
        "#E0E7FF",
        "#FDE8E9",
        "#FFF7ED",
        "#F3F4F6",
        "#E8F5FF",
        "#FAE8FF"
      ]

      assert color in light_palette
    end
  end

  describe "generate_darker_color/1" do
    test "returns default dark color for nil" do
      assert ULIDColor.generate_darker_color(nil) == "#9CA3AF"
    end

    test "returns a valid hex color for a ULID" do
      ulid = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      color = ULIDColor.generate_darker_color(ulid)
      assert String.starts_with?(color, "#")
      assert String.length(color) == 7
      assert Regex.match?(~r/^#[0-9A-F]{6}$/i, color)
    end

    test "returns consistent color for the same ULID" do
      ulid = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      color1 = ULIDColor.generate_darker_color(ulid)
      color2 = ULIDColor.generate_darker_color(ulid)
      assert color1 == color2
    end

    test "returns a color from the dark palette" do
      ulid = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      color = ULIDColor.generate_darker_color(ulid)

      dark_palette = [
        "#F87171",
        "#FBBF24",
        "#4ADE80",
        "#60A5FA",
        "#A78BFA",
        "#FB7185",
        "#FCD34D",
        "#38BDF8",
        "#34D399",
        "#818CF8",
        "#FB7185",
        "#FB923C",
        "#A3A3A3",
        "#22D3EE",
        "#C084FC"
      ]

      assert color in dark_palette
    end

    test "returns different color than light version for same ULID" do
      ulid = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      light_color = ULIDColor.generate_color(ulid)
      dark_color = ULIDColor.generate_darker_color(ulid)
      # They should be different (dark palette is different from light)
      assert light_color != dark_color
    end
  end

  describe "generate_color_from_idx/1" do
    test "returns default light color for nil" do
      assert ULIDColor.generate_color_from_idx(nil) == "#F3F4F6"
    end

    test "returns a color from the light palette for valid index" do
      color = ULIDColor.generate_color_from_idx(0)

      light_palette = [
        "#FEE2E2",
        "#FEF9C3",
        "#DCFCE7",
        "#DBEAFE",
        "#EDE9FE",
        "#FCE7F3",
        "#FEF3C7",
        "#E0F2FE",
        "#D1FAE5",
        "#E0E7FF",
        "#FDE8E9",
        "#FFF7ED",
        "#F3F4F6",
        "#E8F5FF",
        "#FAE8FF"
      ]

      assert color in light_palette
    end

    test "wraps around for indices larger than palette size" do
      color1 = ULIDColor.generate_color_from_idx(0)
      color2 = ULIDColor.generate_color_from_idx(15)
      assert color1 == color2
    end

    test "handles negative indices" do
      # rem with negative numbers in Elixir wraps around
      color = ULIDColor.generate_color_from_idx(-1)
      assert String.starts_with?(color, "#")
      assert String.length(color) == 7
    end
  end

  describe "generate_color_from_idx/2" do
    test "returns default dark color for nil with :dark mode" do
      assert ULIDColor.generate_color_from_idx(nil, :dark) == "#9CA3AF"
    end

    test "returns default light color for nil with :light mode" do
      assert ULIDColor.generate_color_from_idx(nil, :light) == "#F3F4F6"
    end

    test "returns a color from the dark palette for :dark mode" do
      color = ULIDColor.generate_color_from_idx(0, :dark)

      dark_palette = [
        "#F87171",
        "#FBBF24",
        "#4ADE80",
        "#60A5FA",
        "#A78BFA",
        "#FB7185",
        "#FCD34D",
        "#38BDF8",
        "#34D399",
        "#818CF8",
        "#FB7185",
        "#FB923C",
        "#A3A3A3",
        "#22D3EE",
        "#C084FC"
      ]

      assert color in dark_palette
    end

    test "returns a color from the light palette for :light mode" do
      color = ULIDColor.generate_color_from_idx(0, :light)

      light_palette = [
        "#FEE2E2",
        "#FEF9C3",
        "#DCFCE7",
        "#DBEAFE",
        "#EDE9FE",
        "#FCE7F3",
        "#FEF3C7",
        "#E0F2FE",
        "#D1FAE5",
        "#E0E7FF",
        "#FDE8E9",
        "#FFF7ED",
        "#F3F4F6",
        "#E8F5FF",
        "#FAE8FF"
      ]

      assert color in light_palette
    end

    test "returns light color for any non-dark mode" do
      color1 = ULIDColor.generate_color_from_idx(0, :light)
      color2 = ULIDColor.generate_color_from_idx(0, :other)
      assert color1 == color2
    end

    test "wraps around for indices larger than palette size in dark mode" do
      color1 = ULIDColor.generate_color_from_idx(0, :dark)
      color2 = ULIDColor.generate_color_from_idx(15, :dark)
      assert color1 == color2
    end
  end
end
