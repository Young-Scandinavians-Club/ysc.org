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
      assert PropertyDisplay.outage_name(:tahoe) == "Tahoe Property"
      assert PropertyDisplay.outage_name(:clear_lake) == "Clear Lake Property"
      assert PropertyDisplay.outage_name("tahoe") == "Tahoe Property"
    end

    test "returns default for unknown values" do
      assert PropertyDisplay.outage_name(:unknown) == "Property"
      assert PropertyDisplay.outage_name("other") == "Property"
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
end
