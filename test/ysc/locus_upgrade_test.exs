defmodule Ysc.LocusUpgradeTest do
  @moduledoc """
  Guards the locus 2.3.16 → 2.3.17 upgrade.

  2.3.17 is a patch with no documented breaking changes. IPv4 lookups
  against MMDB trees with no IPv4 root used to return
  `{error, not_found}` from `locus_mmdb_tree:lookup/2`. The public
  `:locus.lookup/2` contract is `not_found` when the address is absent.

  2.3.17 maps the IPv4-less `none` root to `no_ipv4_root_index` and
  returns `not_found`. `Ysc.GeoIP.lookup/1` already matches `:not_found`
  as an empty map. GeoLite2-City includes IPv4, so that path is unused.
  We load via `Ysc.GeoIP.DatabaseFetcher` (`:custom_fetcher`), not the
  HTTP downloader. `:locus.lookup/2` and `start_loader/3` are
  unchanged. `tls_certificate_check` stays 1.33.0.
  """
  use ExUnit.Case, async: false

  alias Ysc.GeoIP
  alias Ysc.GeoIP.DatabaseFetcher
  alias Ysc.Test.EnvHelper

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/locus/CHANGELOG.md", __DIR__)
  @tree Path.expand("../../deps/locus/src/locus_mmdb_tree.erl", __DIR__)
  @loader Path.expand("../../deps/locus/src/locus_loader.erl", __DIR__)
  @application Path.expand("../../lib/ysc/application.ex", __DIR__)
  @geo_ip Path.expand("../../lib/ysc/geo_ip.ex", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:locus)
    {:module, :locus} = Code.ensure_loaded(:locus)
    {:module, :locus_mmdb_tree} = Code.ensure_loaded(:locus_mmdb_tree)
    {:module, :locus_custom_fetcher} = Code.ensure_loaded(:locus_custom_fetcher)
    :ok
  end

  describe "2.3.17 Hex lock and public APIs" do
    test "locks the Hex package to 2.3.17" do
      {:module, :locus} = Code.ensure_loaded(:locus)
      assert to_string(Application.spec(:locus, :vsn)) == "2.3.17"
    end

    test "mix.exs pins the 2.3.17 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:locus, "~> 2.3.17"}|
    end

    test "companion lock is 2.3.17" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"locus": {:hex, :locus, "2.3.17"|
    end

    test "does not pull tls_certificate_check 1.35.0" do
      {:module, :tls_certificate_check} =
        Code.ensure_loaded(:tls_certificate_check)

      assert to_string(Application.spec(:tls_certificate_check, :vsn)) ==
               "1.33.0"

      lock = File.read!(@mix_lock)

      assert lock =~
               ~s|"tls_certificate_check": {:hex, :tls_certificate_check, "1.33.0"|

      refute lock =~
               ~s|"tls_certificate_check": {:hex, :tls_certificate_check, "1.35.0"|
    end

    test "lookup/2 and start_loader/3 still exist" do
      {:module, :locus} = Code.ensure_loaded(:locus)
      assert function_exported?(:locus, :lookup, 2)
      assert function_exported?(:locus, :start_loader, 2)
      assert function_exported?(:locus, :start_loader, 3)
      assert function_exported?(:locus, :stop_loader, 1)
    end

    test "tree lookup/2 still exists for the IPv4-less fix" do
      {:module, :locus_mmdb_tree} = Code.ensure_loaded(:locus_mmdb_tree)
      assert function_exported?(:locus_mmdb_tree, :lookup, 2)
      assert function_exported?(:locus_mmdb_tree, :new, 5)
    end

    test "custom fetcher behaviour still requires description/fetch/conditionally_fetch" do
      callbacks = :locus_custom_fetcher.behaviour_info(:callbacks)
      assert {:description, 1} in callbacks
      assert {:fetch, 1} in callbacks
      assert {:conditionally_fetch, 2} in callbacks
    end

    test "DatabaseFetcher still implements the custom fetcher callbacks" do
      assert {:module, _} = Code.ensure_loaded(DatabaseFetcher)
      assert function_exported?(DatabaseFetcher, :description, 1)
      assert function_exported?(DatabaseFetcher, :fetch, 1)
      assert function_exported?(DatabaseFetcher, :conditionally_fetch, 2)
    end
  end

  describe "2.3.17 changelog" do
    test "documents the IPv4-less not_found return and has no breaking changes" do
      changelog = File.read!(@changelog)

      v2317 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "[2.3.17]"))

      assert v2317
      assert v2317 =~ "{error, not_found}"
      assert v2317 =~ "IPv4-less"
      refute v2317 =~ "Breaking"
    end
  end

  describe "2.3.17 IPv4-less trees return not_found" do
    test "ip_address_to_bitstring maps none to no_ipv4_root_index" do
      source = File.read!(@tree)
      assert source =~ "no_ipv4_root_index ->"
      assert source =~ "no_ipv4_root_index;"
      refute source =~ "{error, not_found};"
    end

    test "lookup/2 spec no longer lists not_found as an error reason" do
      source = File.read!(@tree)
      assert source =~ "Reason :: ipv4_database."
      refute source =~ "Reason :: ipv4_database | not_found."
    end

    test "IPv4 lookup against an IPv4-less tree returns not_found, not {error, not_found}" do
      {:module, :locus_mmdb_tree} = Code.ensure_loaded(:locus_mmdb_tree)
      ipv4_less = {:tree, <<>>, 1, 24, 6, 6, :none}

      assert :locus_mmdb_tree.lookup({8, 8, 8, 8}, ipv4_less) == :not_found

      refute match?(
               {:error, :not_found},
               :locus_mmdb_tree.lookup({8, 8, 8, 8}, ipv4_less)
             )
    end

    test "IPv4 lookup against a data_index root still returns {ok, DataIndex}" do
      {:module, :locus_mmdb_tree} = Code.ensure_loaded(:locus_mmdb_tree)
      tree = {:tree, <<>>, 1, 24, 6, 6, {:data_index, 42}}
      assert :locus_mmdb_tree.lookup({8, 8, 8, 8}, tree) == {:ok, 42}
    end

    test "IPv6 lookup against an IPv4-only tree still returns {error, ipv4_database}" do
      {:module, :locus_mmdb_tree} = Code.ensure_loaded(:locus_mmdb_tree)
      ipv4_db = {:tree, <<>>, 1, 24, 4, 6, {:tree_index, 0}}

      assert :locus_mmdb_tree.lookup({0, 0, 0, 0, 0, 0, 0, 1}, ipv4_db) ==
               {:error, :ipv4_database}
    end
  end

  describe "2.3.17 GeoIP call sites still match the public lookup contract" do
    test "GeoIP.lookup/1 still matches :not_found as an empty map" do
      source = File.read!(@geo_ip)
      assert source =~ "apply(:locus, :lookup,"
      assert source =~ ":not_found ->"
      assert source =~ "{:error, reason} ->"
    end

    test "application still starts the city loader with a custom S3 fetcher" do
      source = File.read!(@application)
      assert source =~ ":locus.start_loader("
      assert source =~ "{:custom_fetcher, Ysc.GeoIP.DatabaseFetcher, []}"
      refute source =~ "{:maxmind,"
    end

    test "HTTP Accept values stay comma-separated without semicolons" do
      source = File.read!(@loader)
      assert source =~ ~s|string:join(Values, ", ")|
      refute source =~ ~s|string:join(Values, "; ")|
    end

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
