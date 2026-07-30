defmodule QueryConsole.Runner do
  @moduledoc """
  Multi-statement execution coordinator.

  Progress messages are sent to the caller PID as:
  `{:run_progress, %{state: ..., statement_index: ..., elapsed_ms: ..., rows: ..., ...}}`
  """

  import Ecto.Query

  alias QueryConsole.Accounts.User
  alias QueryConsole.AnalyticsRepo
  alias QueryConsole.Repo
  alias QueryConsole.Runner.{Lease, QueryRun, SQL, StatementRun, Supervisor}
  alias QueryConsole.Workbooks.Workbook

  @doc """
  Starts an async query run. Returns `{:ok, query_run}` or `{:error, reason}`.
  """
  def start_run(%User{} = user, opts) do
    sql = Keyword.fetch!(opts, :sql)
    mode = Keyword.get(opts, :mode, "all") |> to_string()
    caller = Keyword.get(opts, :caller, self())
    workbook_id = Keyword.get(opts, :workbook_id)
    selection = Keyword.get(opts, :selection)
    statement_index = Keyword.get(opts, :statement_index)

    with {:ok, statements} <- SQL.split_statements(sql),
         {:ok, to_run} <- select_statements(statements, mode, selection, statement_index),
         :ok <- SQL.preflight(to_run),
         {:ok, query_run} <- create_query_run(user, workbook_id, mode, length(to_run)) do
      args = %{
        query_run_id: query_run.id,
        user_id: user.id,
        statements: to_run,
        caller: caller
      }

      case Supervisor.start_run(args) do
        {:ok, _pid} ->
          {:ok, query_run}

        {:error, reason} ->
          finalize_run(query_run.id, "failed", "Failed to start runner: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  def cancel_run(query_run_id) when is_binary(query_run_id) do
    case Registry.lookup(QueryConsole.Runner.Registry, query_run_id) do
      [{pid, meta}] ->
        if is_map(meta) and is_integer(meta[:backend_pid]) do
          _ = AnalyticsRepo.query("SELECT pg_cancel_backend($1)", [meta[:backend_pid]])
        end

        send(pid, :cancel)
        :ok

      [] ->
        {:error, :not_running}
    end
  end

  def get_query_run(id), do: Repo.get(QueryRun, id)

  def list_statement_runs(query_run_id) do
    from(s in StatementRun,
      where: s.query_run_id == ^query_run_id,
      order_by: [asc: s.index]
    )
    |> Repo.all()
  end

  defp select_statements(statements, "all", _selection, _index), do: {:ok, statements}

  defp select_statements(statements, "current", _selection, index) when is_integer(index) do
    case Enum.at(statements, index) do
      nil -> {:error, :statement_not_found}
      stmt -> {:ok, [stmt]}
    end
  end

  defp select_statements(_statements, "selection", selection, _index)
       when is_binary(selection) and selection != "" do
    with {:ok, selected} <- SQL.split_statements(selection),
         :ok <- SQL.preflight(selected) do
      {:ok, selected}
    end
  end

  defp select_statements(_statements, mode, _selection, _index) do
    {:error, {:invalid_mode, mode}}
  end

  defp create_query_run(%User{} = user, workbook_id, mode, statement_count) do
    attrs = %{
      user_id: user.id,
      workbook_id: workbook_id,
      status: "queued",
      mode: mode,
      statement_count: statement_count,
      started_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    %QueryRun{}
    |> QueryRun.changeset(attrs)
    |> Repo.insert()
  end

  def finalize_run(query_run_id, status, error_summary \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get(QueryRun, query_run_id) do
      nil ->
        :ok

      run ->
        run
        |> QueryRun.changeset(%{
          status: status,
          finished_at: now,
          error_summary: error_summary
        })
        |> Repo.update()

        Lease.release(query_run_id)
        :ok
    end
  end

  def update_run_status(query_run_id, status, extra \\ %{}) do
    case Repo.get(QueryRun, query_run_id) do
      nil ->
        :ok

      run ->
        run
        |> QueryRun.changeset(Map.merge(%{status: status}, extra))
        |> Repo.update()
    end
  end

  def upsert_statement_run(query_run_id, index, attrs) do
    case Repo.get_by(StatementRun, query_run_id: query_run_id, index: index) do
      nil ->
        %StatementRun{}
        |> StatementRun.changeset(Map.merge(attrs, %{query_run_id: query_run_id, index: index}))
        |> Repo.insert()

      existing ->
        existing
        |> StatementRun.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc false
  def analytics_repo, do: AnalyticsRepo

  @doc false
  def owned_workbook?(%User{} = user, workbook_id) when is_binary(workbook_id) do
    case Repo.get(Workbook, workbook_id) do
      %Workbook{user_id: id} when id == user.id -> true
      _ -> false
    end
  end
end
