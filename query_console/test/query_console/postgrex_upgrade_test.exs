defmodule QueryConsole.PostgrexUpgradeTest do
  @moduledoc """
  Guards the postgrex 0.22.3 → 0.22.4 upgrade.

  0.22.4 is a patch: `Postgrex.stream/4` now validates `:comment` with
  `comment_not_present!/1` (EEF-CVE-2026-66838). Before this, a comment
  containing `*/` was interpolated into the extended-protocol Parse
  statement and could extend the streamed SQL. Query Console runs SQL
  through `Postgrex.query/4` and `AnalyticsRepo.query/3`, not
  `Postgrex.stream/4` or the `:comment` option. Public query APIs and
  `Postgrex.BinaryExtension` (used by `QueryConsole.Postgrex.ULID`) are
  unchanged.
  """
  use ExUnit.Case, async: false

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @postgrex_src Path.expand("../../deps/postgrex/lib/postgrex.ex", __DIR__)
  @changelog Path.expand("../../deps/postgrex/CHANGELOG.md", __DIR__)
  @worker_src Path.expand("../../lib/query_console/runner/worker.ex", __DIR__)
  @ulid_src Path.expand("../../lib/query_console/postgrex/ulid.ex", __DIR__)

  @comment_breakout "*/ UNION SELECT 1 --"
  @comment_error_message ~S|`:comment` option cannot contain null bytes and "*/" sequence|

  setup_all do
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:module, Postgrex} = Code.ensure_loaded(Postgrex)
    {:module, Postgrex.Error} = Code.ensure_loaded(Postgrex.Error)
    {:module, Postgrex.Stream} = Code.ensure_loaded(Postgrex.Stream)
    {:module, Postgrex.Utils} = Code.ensure_loaded(Postgrex.Utils)
    {:module, Postgrex.BinaryUtils} = Code.ensure_loaded(Postgrex.BinaryUtils)
    {:module, Postgrex.BinaryExtension} = Code.ensure_loaded(Postgrex.BinaryExtension)
    {:module, DBConnection} = Code.ensure_loaded(DBConnection)
    :ok
  end

  describe "0.22.4 Hex lock and public APIs" do
    test "locks the Hex package to 0.22.4" do
      assert to_string(Application.spec(:postgrex, :vsn)) == "0.22.4"
    end

    test "mix.exs pins the patched floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:postgrex, "~> 0.22.4"})
    end

    test "query and type APIs Query Console uses still exist" do
      assert function_exported?(Postgrex, :start_link, 1)
      assert function_exported?(Postgrex, :query, 3)
      assert function_exported?(Postgrex, :query, 4)
      assert function_exported?(Postgrex, :query!, 3)
      assert function_exported?(Postgrex, :query!, 4)
      assert function_exported?(Postgrex, :transaction, 2)
      assert function_exported?(Postgrex, :transaction, 3)
      assert function_exported?(Postgrex.Utils, :encode_msg, 2)
      assert function_exported?(Postgrex.Types, :define, 2)
      assert function_exported?(Postgrex.Types, :define, 3)
      assert macro_exported?(Postgrex.BinaryExtension, :__using__, 1)
    end

    test "runner still uses AnalyticsRepo.query, not Postgrex.stream" do
      worker = File.read!(@worker_src)
      ulid = File.read!(@ulid_src)

      assert worker =~ "AnalyticsRepo.query(sql, [], timeout: timeout)"
      refute worker =~ "Postgrex.stream"
      refute worker =~ "Repo.stream"

      assert ulid =~ "use Postgrex.BinaryExtension, send: \"uuid_send\""
      assert ulid =~ "import Postgrex.BinaryUtils, warn: false"
    end
  end

  describe "0.22.4 stream comment validation (EEF-CVE-2026-66838)" do
    test "stream/4 validates comments before sending Parse" do
      postgrex = File.read!(@postgrex_src)

      assert postgrex =~
               "def stream(%DBConnection{} = conn, query, params, options \\\\ []) do"

      assert postgrex =~ "comment_not_present!(options)"
      assert postgrex =~ "cannot contain null bytes"
    end

    test "stream/4 raises on a comment that closes the delimiter" do
      conn = %DBConnection{}

      error =
        assert_raise Postgrex.Error, fn ->
          Postgrex.stream(conn, "SELECT 1", [], comment: @comment_breakout)
        end

      assert error.message == @comment_error_message
    end

    test "stream/4 raises on a comment that contains a null byte" do
      conn = %DBConnection{}

      error =
        assert_raise Postgrex.Error, fn ->
          Postgrex.stream(conn, "SELECT 1", [], comment: "ok\0injected")
        end

      assert error.message == @comment_error_message
    end

    test "stream/4 still builds a stream for a safe comment" do
      conn = %DBConnection{}
      stream = Postgrex.stream(conn, "SELECT 1", [], comment: "query-console-upgrade")

      assert %Postgrex.Stream{
               conn: ^conn,
               query: "SELECT 1",
               params: [],
               options: options
             } = stream

      assert options[:comment] == "query-console-upgrade"
      assert options[:max_rows] == 500
    end
  end

  describe "0.22.4 changelog" do
    test "documents the stream comment advisory" do
      changelog = File.read!(@changelog)
      assert changelog =~ "## v0.22.4"
      assert changelog =~ "CVE-2026-66838"
      assert changelog =~ "Postgrex.stream/4"
    end
  end

  describe "query APIs still talk to Postgres" do
    setup do
      cfg = Application.get_env(:query_console, QueryConsole.Repo)

      opts =
        [
          hostname: cfg[:hostname] || "localhost",
          username: cfg[:username] || "postgres",
          password: cfg[:password] || "postgres",
          database: cfg[:database],
          port: cfg[:port] || 5432
        ]
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)

      case Postgrex.start_link(opts) do
        {:ok, conn} ->
          on_exit(fn ->
            try do
              GenServer.stop(conn)
            catch
              :exit, _ -> :ok
            end
          end)

          {:ok, conn: conn}

        {:error, reason} ->
          {:skip, "query_console test database unavailable: #{inspect(reason)}"}
      end
    end

    test "Postgrex.query/4 still returns rows", %{conn: conn} do
      assert {:ok, %{rows: [[1]]}} = Postgrex.query(conn, "SELECT 1", [])
    end

    test "query/4 still rejects a comment breakout", %{conn: conn} do
      error =
        assert_raise Postgrex.Error, fn ->
          Postgrex.query(conn, "SELECT 1", [], comment: @comment_breakout)
        end

      assert error.message == @comment_error_message
    end

    test "stream/4 with a safe comment enumerates inside a transaction", %{conn: conn} do
      assert {:ok, results} =
               Postgrex.transaction(conn, fn trans_conn ->
                 trans_conn
                 |> Postgrex.stream("SELECT 1 AS n", [], comment: "query-console-upgrade")
                 |> Enum.to_list()
               end)

      assert [%Postgrex.Result{rows: [[1]]}] = results
    end
  end
end
