defmodule Ysc.EventLocationConfigTest do
  use ExUnit.Case, async: true

  alias Ysc.EventLocationConfig

  describe "presets/0" do
    test "returns configured presets with expected ids" do
      presets = EventLocationConfig.presets()

      assert length(presets) == 3

      ids = Enum.map(presets, & &1.id)

      assert "swedish_american_hall" in ids
      assert "clear_lake" in ids
      assert "norwegian_club" in ids
    end

    test "each preset has required fields" do
      for preset <- EventLocationConfig.presets() do
        assert preset.id
        assert preset.label
        assert preset.location_name
        assert preset.address
        assert is_number(preset.latitude)
        assert is_number(preset.longitude)
      end
    end
  end

  describe "get/1" do
    test "returns preset by id" do
      assert {:ok, preset} = EventLocationConfig.get("swedish_american_hall")
      assert preset.label == "Swedish American Hall"
    end

    test "returns error for unknown id" do
      assert :error = EventLocationConfig.get("unknown_venue")
    end

    test "returns error for non-string id" do
      assert :error = EventLocationConfig.get(:swedish_american_hall)
    end
  end

  describe "presets_for_search/0" do
    test "returns JSON-serializable preset maps" do
      presets = EventLocationConfig.presets_for_search()

      assert length(presets) == 3
      assert Jason.encode!(presets)
      assert hd(presets).id == "swedish_american_hall"
      assert Map.has_key?(hd(presets), :label)
      assert Map.has_key?(hd(presets), :latitude)
    end
  end
end
