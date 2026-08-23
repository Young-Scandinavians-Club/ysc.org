defmodule Ysc.TextTest do
  use ExUnit.Case, async: true

  alias Ysc.Text

  doctest Ysc.Text

  describe "titleize/1" do
    test "title-cases atoms and underscored strings" do
      assert Text.titleize(:clear_lake) == "Clear Lake"
      assert Text.titleize(:tahoe) == "Tahoe"
      assert Text.titleize("vice_president") == "Vice President"
      assert Text.titleize(:room) == "Room"
    end

    test "passes through strings without underscores after capitalizing" do
      assert Text.titleize("standard") == "Standard"
    end

    test "returns the em dash fallback for nil and other values" do
      assert Text.titleize(nil) == "—"
      assert Text.titleize(%{}) == "—"
      assert Text.titleize(123) == "—"
    end

    test "accepts a custom fallback" do
      assert Text.titleize(nil, "Unknown") == "Unknown"
      assert Text.titleize(%{}, "") == ""
    end
  end
end
