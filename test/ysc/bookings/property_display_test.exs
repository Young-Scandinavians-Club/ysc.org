defmodule Ysc.Bookings.PropertyDisplayTest do
  use ExUnit.Case, async: true

  alias Ysc.Bookings.PropertyDisplay

  describe "short_name/1" do
    test "formats known properties" do
      assert PropertyDisplay.short_name(:tahoe) == "Tahoe"
      assert PropertyDisplay.short_name(:clear_lake) == "Clear Lake"
      assert PropertyDisplay.short_name("tahoe") == "Tahoe"
      assert PropertyDisplay.short_name("clear_lake") == "Clear Lake"
    end

    test "title-cases unknown atoms" do
      assert PropertyDisplay.short_name(:custom) == "Custom"
    end

    test "returns passthrough strings and custom defaults" do
      assert PropertyDisplay.short_name("Custom Label") == "Custom Label"
      assert PropertyDisplay.short_name(nil, "Fallback") == "Fallback"
    end
  end

  describe "medium_name/1" do
    test "formats known properties" do
      assert PropertyDisplay.medium_name(:tahoe) == "Lake Tahoe"
      assert PropertyDisplay.medium_name(:clear_lake) == "Clear Lake"
      assert PropertyDisplay.medium_name("tahoe") == "Lake Tahoe"
    end

    test "returns default for unknown values" do
      assert PropertyDisplay.medium_name(:unknown) == "Unknown"
      assert PropertyDisplay.medium_name(nil, "—") == "—"
    end
  end

  describe "full_name/1" do
    test "formats known properties" do
      assert PropertyDisplay.full_name(:tahoe) == "Lake Tahoe Cabin"
      assert PropertyDisplay.full_name(:clear_lake) == "Clear Lake Cabin"
      assert PropertyDisplay.full_name("clear_lake") == "Clear Lake Cabin"
    end

    test "returns default for unknown values" do
      assert PropertyDisplay.full_name(:unknown) == "Unknown"
      assert PropertyDisplay.full_name(nil, "Cabin") == "Cabin"
    end
  end

  describe "outage_name/1" do
    test "formats known properties" do
      assert PropertyDisplay.outage_name(:tahoe) == "Tahoe cabin"
      assert PropertyDisplay.outage_name(:clear_lake) == "Clear Lake cabin"
      assert PropertyDisplay.outage_name("tahoe") == "Tahoe cabin"
    end

    test "returns default for unknown values" do
      assert PropertyDisplay.outage_name(:unknown) == "cabin"
      assert PropertyDisplay.outage_name("other") == "cabin"
    end
  end

  describe "address/1" do
    test "returns property addresses" do
      assert PropertyDisplay.address(:tahoe) ==
               "2685 Cedar Lane, Homewood, CA 96141"

      assert PropertyDisplay.address(:clear_lake) ==
               "9325 Bass Road, Kelseyville, CA 95451"

      assert PropertyDisplay.address("tahoe") ==
               "2685 Cedar Lane, Homewood, CA 96141"
    end

    test "returns default for unknown values" do
      assert PropertyDisplay.address(:unknown) == "Property Address"
    end
  end

  describe "training_videos_url/1" do
    test "returns the Clear Lake playlist URL" do
      url = PropertyDisplay.training_videos_url(:clear_lake)

      assert url =~ "youtube.com"
      assert PropertyDisplay.training_videos_url("clear_lake") == url
    end

    test "returns nil for other properties" do
      assert PropertyDisplay.training_videos_url(:tahoe) == nil
    end
  end

  describe "thumbnail_path/1" do
    test "returns cabin image paths for known properties" do
      assert PropertyDisplay.thumbnail_path(:tahoe) ==
               "/images/tahoe/tahoe_cabin_main.webp"

      assert PropertyDisplay.thumbnail_path(:clear_lake) ==
               "/images/clear_lake/clear_lake_dock.webp"

      assert PropertyDisplay.thumbnail_path("tahoe") ==
               PropertyDisplay.thumbnail_path(:tahoe)

      assert PropertyDisplay.thumbnail_path("clear_lake") ==
               PropertyDisplay.thumbnail_path(:clear_lake)
    end

    test "returns the YSC logo for unknown values" do
      assert PropertyDisplay.thumbnail_path(:unknown) == "/images/ysc_logo.webp"
      assert PropertyDisplay.thumbnail_path(nil) == "/images/ysc_logo.webp"
    end
  end
end
