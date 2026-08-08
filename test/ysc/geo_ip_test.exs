defmodule Ysc.GeoIPTest do
  @moduledoc """
  Tests for the Ysc.GeoIP module.

  These tests verify:
  - Safe degradation outside deployed environments
  - Correct parsing of locus lookup results
  - Graceful handling of lookup failures and unexpected data shapes
  - The configured?/0 helper
  """
  # async: false — configured?/0 tests mutate the process-global `:ysc, :environment`
  # config via Ysc.Test.EnvHelper; running concurrently with other async suites doing
  # the same risks races even under EnvHelper's global lock (see incident where "returns
  # true in sandbox" flaked in CI).
  use ExUnit.Case, async: false

  alias Ysc.GeoIP
  alias Ysc.Test.EnvHelper

  # ---------------------------------------------------------------------------
  # configured?/0
  # ---------------------------------------------------------------------------

  describe "configured?/0" do
    test "returns false in the test environment" do
      refute GeoIP.configured?()
    end

    test "returns false in the development environment" do
      EnvHelper.with_environment("dev", fn ->
        refute GeoIP.configured?()
      end)
    end

    test "returns true in sandbox" do
      EnvHelper.with_environment("sandbox", fn ->
        assert GeoIP.configured?()
      end)
    end

    test "returns true in production" do
      EnvHelper.with_environment("production", fn ->
        assert GeoIP.configured?()
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # lookup/1 – without a live database
  # ---------------------------------------------------------------------------

  describe "lookup/1 when GeoIP is not configured" do
    test "returns an empty map for a valid IP" do
      assert GeoIP.lookup("93.184.216.34") == %{}
    end

    test "returns an empty map for a private IP" do
      assert GeoIP.lookup("192.168.1.1") == %{}
    end

    test "returns an empty map for nil" do
      assert GeoIP.lookup(nil) == %{}
    end

    test "returns an empty map for a non-binary value" do
      assert GeoIP.lookup(12_345) == %{}
    end

    test "returns an empty map for an empty string" do
      assert GeoIP.lookup("") == %{}
    end
  end

  describe "lookup/1 error resilience" do
    test "returns empty map for an invalid IP string when deployed" do
      EnvHelper.with_environment("sandbox", fn ->
        # locus loader for :city is not running in tests – rescue / error path
        assert GeoIP.lookup("not-an-ip") == %{}
      end)
    end

    test "returns empty map for an atom" do
      assert GeoIP.lookup(:not_a_string) == %{}
    end

    test "returns empty map when lookup returns :not_found (reserved IP)" do
      EnvHelper.with_environment("sandbox", fn ->
        assert GeoIP.lookup("127.0.0.1") == %{}
      end)
    end

    test "returns empty map for public IP when DB is unavailable" do
      EnvHelper.with_environment("sandbox", fn ->
        assert GeoIP.lookup("8.8.8.8") == %{}
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # parse_locus_entry/1 — map shapes (no live MaxMind DB required)
  # ---------------------------------------------------------------------------

  describe "parse_locus_entry/1" do
    test "maps country from country.iso_code" do
      entry = %{
        "country" => %{"iso_code" => "US"},
        "city" => %{"names" => %{"en" => "San Francisco"}},
        "location" => %{"latitude" => 37.77, "longitude" => -122.42}
      }

      assert GeoIP.parse_locus_entry(entry) == %{
               country: "US",
               city: "San Francisco",
               latitude: 37.77,
               longitude: -122.42
             }
    end

    test "falls back to registered_country when country is absent" do
      entry = %{
        "registered_country" => %{"iso_code" => "CA"},
        "subdivisions" => [
          %{"names" => %{"en" => "Ontario"}, "iso_code" => "ON"}
        ]
      }

      assert %{country: "CA", region: "Ontario"} =
               GeoIP.parse_locus_entry(entry)
    end

    test "uses subdivision iso_code when English name is missing" do
      entry = %{
        "country" => %{"iso_code" => "US"},
        "subdivisions" => [%{"iso_code" => "CA"}]
      }

      assert GeoIP.parse_locus_entry(entry).region == "CA"
    end

    test "returns empty map for non-map input" do
      assert GeoIP.parse_locus_entry(:not_a_map) == %{}
    end
  end
end
