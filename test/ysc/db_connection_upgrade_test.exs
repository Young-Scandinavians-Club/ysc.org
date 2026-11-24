defmodule Ysc.DbConnectionUpgradeTest do
  @moduledoc """
  Guards the db_connection 2.10.2 → 2.10.3 upgrade.

  2.10.3 patches EEF-CVE-2026-133555 (HIGH / GHSA-gmmq-fw75-wq46):
  enumerable protocol implementations no longer accept MFArgs, so a
  forged `DBConnection.Stream` cannot execute an arbitrary MFA via the
  `:log` option. It also lets `:configure` return `{:error, exception}`
  to skip connecting, ignores stale ownership deadline timeouts, rejects
  checkouts after deadline, and wraps user options in a struct so they
  do not leak to logs.

  We reach db_connection through Ecto SQL / Postgrex (`Ysc.Repo`). Do
  not add this CVE to `ignore_advisories`.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/db_connection/CHANGELOG.md", __DIR__)
  @db_connection_src Path.expand(
                       "../../deps/db_connection/lib/db_connection.ex",
                       __DIR__
                     )

  setup_all do
    {:ok, _} = Application.ensure_all_started(:db_connection)
    {:module, DBConnection} = Code.ensure_loaded(DBConnection)
    :ok
  end

  describe "2.10.3 Hex lock and public APIs" do
    test "locks the Hex package to 2.10.3" do
      assert to_string(Application.spec(:db_connection, :vsn)) == "2.10.3"
    end

    test "mix.exs pins the patched floor override" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:db_connection, "~> 2.10.3", override: true})
    end

    test "companion lock is 2.10.3" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"db_connection": {:hex, :db_connection, "2.10.3"|
      refute lock =~ ~s|"db_connection": {:hex, :db_connection, "2.10.2"|
    end

    test "does not ignore the patched db_connection advisory" do
      mix_exs = File.read!(@mix_exs)

      ignore =
        mix_exs
        |> String.split("ignore_advisories: [", parts: 2)
        |> Enum.at(1)
        |> String.split("]", parts: 2)
        |> hd()

      refute ignore =~ "EEF-CVE-2026-133555"
    end

    test "checkout and transaction APIs we use still exist" do
      {:module, DBConnection} = Code.ensure_loaded(DBConnection)
      assert function_exported?(DBConnection, :start_link, 2)
      assert function_exported?(DBConnection, :run, 3)
      assert function_exported?(DBConnection, :transaction, 3)
    end
  end

  describe "2.10.3 changelog" do
    test "documents the MFArgs enumerable hardening" do
      changelog = File.read!(@changelog)
      assert changelog =~ "v2.10.3"
      assert changelog =~ "CVE-2026-133555"
      assert changelog =~ "Do not accept MFArgs"
    end
  end

  describe "EEF-CVE-2026-133555 stream log option" do
    test "stream reduce meters already-normalized log options" do
      source = File.read!(@db_connection_src)
      assert source =~ "def reduce(%DBConnection.Stream{}"
      assert source =~ "already_normalized_meter(opts)"
    end
  end
end
