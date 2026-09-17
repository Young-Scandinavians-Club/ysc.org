defmodule Ysc.LocusUpgradeTest do
  @moduledoc """
  Guards the locus 2.3.15 → 2.3.16 upgrade.

  2.3.16 is a patch: HTTP Accept headers join media types with commas
  (RFC 9110) instead of semicolons. We load GeoLite2-City via
  `Ysc.GeoIP.DatabaseFetcher` (`:custom_fetcher`), not the HTTP
  downloader, so that patch is unused. `:locus.lookup/2` and
  `start_loader/3` are unchanged.
  """
  use ExUnit.Case, async: false

  alias Ysc.GeoIP
  alias Ysc.GeoIP.DatabaseFetcher
  alias Ysc.Test.EnvHelper

  @loader Path.expand("../../deps/locus/src/locus_loader.erl", __DIR__)
  @application Path.expand("../../lib/ysc/application.ex", __DIR__)

  describe "2.3.16 Hex lock and public APIs" do
    test "locks the Hex package to 2.3.16" do
      {:module, :locus} = Code.ensure_loaded(:locus)
      assert to_string(Application.spec(:locus, :vsn)) == "2.3.16"
    end

    test "lookup/2 and start_loader/3 still exist" do
      {:module, :locus} = Code.ensure_loaded(:locus)
      assert function_exported?(:locus, :lookup, 2)
      assert function_exported?(:locus, :start_loader, 2)
      assert function_exported?(:locus, :start_loader, 3)
      assert function_exported?(:locus, :stop_loader, 1)
    end

    test "custom fetcher behaviour still requires description/fetch/conditionally_fetch" do
      callbacks = :locus_custom_fetcher.behaviour_info(:callbacks)
      assert {:description, 1} in callbacks
      assert {:fetch, 1} in callbacks
      assert {:conditionally_fetch, 2} in callbacks
    end

    test "DatabaseFetcher still implements the custom fetcher callbacks" do
      assert function_exported?(DatabaseFetcher, :description, 1)
      assert function_exported?(DatabaseFetcher, :fetch, 1)
      assert function_exported?(DatabaseFetcher, :conditionally_fetch, 2)
    end
  end

  describe "2.3.16 Accept header patch stays unused" do
    test "HTTP Accept values are comma-separated without semicolons" do
      source = File.read!(@loader)
      assert source =~ ~s|string:join(Values, ", ")|
      refute source =~ ~s|string:join(Values, "; ")|
    end

    test "application still starts the city loader with a custom S3 fetcher" do
      source = File.read!(@application)
      assert source =~ ":locus.start_loader("
      assert source =~ "{:custom_fetcher, Ysc.GeoIP.DatabaseFetcher, []}"
      refute source =~ "{:maxmind,"
    end
  end

  describe "2.3.16 lookup and start_loader still work for our call sites" do
    test "lookup/1 still degrades when the city loader is not running" do
      EnvHelper.with_environment("sandbox", fn ->
        assert GeoIP.lookup("8.8.8.8") == %{}
      end)
    end

    test "start_loader/3 still accepts custom_fetcher and stop_loader/1" do
      {:ok, _} = Application.ensure_all_started(:locus)

      original_get = Application.get_env(:ysc, :geo_ip_s3_get)

      Application.put_env(:ysc, :geo_ip_s3_get, fn ->
        {:error, :upgrade_test_skip}
      end)

      on_exit(fn ->
        if original_get do
          Application.put_env(:ysc, :geo_ip_s3_get, original_get)
        else
          Application.delete_env(:ysc, :geo_ip_s3_get)
        end
      end)

      id = :"locus_upgrade_#{System.unique_integer([:positive])}"

      assert :ok =
               :locus.start_loader(
                 id,
                 {:custom_fetcher, DatabaseFetcher, []},
                 update_period: :timer.hours(24),
                 error_retries: {:backoff, :timer.hours(6)}
               )

      assert :ok = :locus.stop_loader(id)
    end
  end
end
