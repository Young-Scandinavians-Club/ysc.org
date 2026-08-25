defmodule QueryConsole.ReleaseTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias QueryConsole.Release

  test "retries migrate when postgres is still starting up" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    migrator = fn repo ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      assert repo == QueryConsole.Repo

      if n < 3 do
        raise starting_up_error()
      else
        {:ok, :query_console, []}
      end
    end

    output =
      capture_io(fn ->
        assert :ok =
                 Release.migrate(
                   migrator: migrator,
                   delay_ms: 0,
                   sleep: fn _ -> :ok end
                 )
      end)

    assert Agent.get(agent, & &1) == 3
    assert output =~ "Database not ready"
    assert output =~ "cannot_connect_now"
  end

  test "retries migrate when the connection pool drops the checkout" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    migrator = fn _repo ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)

      if n < 2 do
        raise DBConnection.ConnectionError,
              "connection not available and request was dropped from queue after 5978ms"
      else
        {:ok, :query_console, []}
      end
    end

    capture_io(fn ->
      assert :ok =
               Release.migrate(
                 migrator: migrator,
                 delay_ms: 0,
                 sleep: fn _ -> :ok end
               )
    end)

    assert Agent.get(agent, & &1) == 2
  end

  test "does not retry non-transient postgres errors" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    migrator = fn _repo ->
      Agent.update(agent, &(&1 + 1))
      raise undefined_table_error()
    end

    assert_raise Postgrex.Error, fn ->
      Release.migrate(migrator: migrator, attempts: 5, delay_ms: 0, sleep: fn _ -> :ok end)
    end

    assert Agent.get(agent, & &1) == 1
  end

  test "reraises after attempts are exhausted" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    migrator = fn _repo ->
      Agent.update(agent, &(&1 + 1))
      raise DBConnection.ConnectionError, "connection not available"
    end

    capture_io(fn ->
      assert_raise DBConnection.ConnectionError, fn ->
        Release.migrate(migrator: migrator, attempts: 3, delay_ms: 0, sleep: fn _ -> :ok end)
      end
    end)

    assert Agent.get(agent, & &1) == 3
  end

  defp starting_up_error do
    Postgrex.Error.exception(
      postgres: %{
        code: "57P03",
        severity: "FATAL",
        message: "the database system is starting up"
      }
    )
  end

  defp undefined_table_error do
    Postgrex.Error.exception(
      postgres: %{
        code: "42P01",
        severity: "ERROR",
        message: "relation does not exist"
      }
    )
  end
end
