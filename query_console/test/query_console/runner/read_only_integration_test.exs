defmodule QueryConsole.Runner.ReadOnlyIntegrationTest do
  @moduledoc """
  Proves mutations fail under the same session guards the runner applies
  (`BEGIN READ ONLY` + `transaction_read_only`), independent of the
  application-level SQL preflight.

  Uses a dedicated Postgrex connection (not the Ecto sandbox) so session
  GUCs and explicit transactions behave like production.

  Production still requires an MPG Reader role (see docs/DEPLOYMENT.md);
  this test validates the in-session read-only envelope against Postgres.
  """

  use ExUnit.Case, async: false

  alias QueryConsole.Runner.SQL

  setup do
    cfg = Application.get_env(:query_console, QueryConsole.AnalyticsRepo)

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
        {:skip, "analytics database unavailable: #{inspect(reason)}"}
    end
  end

  describe "session read-only envelope" do
    test "rejects INSERT inside BEGIN READ ONLY", %{conn: conn} do
      assert :ok = configure_read_only_session!(conn)

      assert {:error, %Postgrex.Error{} = error} =
               Postgrex.query(
                 conn,
                 "INSERT INTO schema_migrations(version, inserted_at) VALUES (1, NOW())",
                 []
               )

      assert error.postgres.message =~ ~r/read-only|cannot execute|permission denied/i
    after
      _ = Postgrex.query(conn, "ROLLBACK", [])
    end

    test "rejects CREATE TEMP TABLE inside BEGIN READ ONLY", %{conn: conn} do
      assert :ok = configure_read_only_session!(conn)

      assert {:error, %Postgrex.Error{} = error} =
               Postgrex.query(conn, "CREATE TEMP TABLE qc_temp_probe(id int)", [])

      assert error.postgres.message =~ ~r/read-only|cannot execute|permission denied/i
    after
      _ = Postgrex.query(conn, "ROLLBACK", [])
    end

    test "allows SELECT inside BEGIN READ ONLY", %{conn: conn} do
      assert :ok = configure_read_only_session!(conn)
      assert {:ok, %{rows: [[1]]}} = Postgrex.query(conn, "SELECT 1", [])
    after
      _ = Postgrex.query(conn, "ROLLBACK", [])
    end
  end

  describe "preflight + session defense in depth" do
    test "write SQL is rejected by preflight before execution" do
      assert {:ok, stmts} = SQL.split_statements("UPDATE users SET id = id")
      assert {:error, {:write_rejected, _}} = SQL.preflight(stmts)
    end
  end

  defp configure_read_only_session!(conn) do
    statements = [
      "BEGIN READ ONLY",
      "SET LOCAL transaction_read_only = on"
    ]

    Enum.reduce_while(statements, :ok, fn sql, :ok ->
      case Postgrex.query(conn, sql, []) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      :ok -> :ok
      {:error, reason} -> flunk("failed to configure read-only session: #{inspect(reason)}")
    end
  end
end
