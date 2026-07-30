defmodule QueryConsole.Runner.Worker do
  @moduledoc false
  use GenServer, restart: :temporary

  alias QueryConsole.AnalyticsRepo
  alias QueryConsole.Runner
  alias QueryConsole.Runner.Cells
  alias QueryConsole.Runner.Lease

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    query_run_id = Map.fetch!(args, :query_run_id)

    case Registry.register(QueryConsole.Runner.Registry, query_run_id, %{}) do
      {:ok, _} ->
        send(self(), :run)
        {:ok, Map.merge(args, %{backend_pid: nil, cancelled?: false})}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:run, state) do
    result = do_run(state)
    {:stop, :normal, result}
  end

  def handle_info(:cancel, state) do
    if is_integer(state.backend_pid) do
      _ = cancel_backend(state.backend_pid)
    end

    {:noreply, %{state | cancelled?: true}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp do_run(state) do
    caller = state.caller
    query_run_id = state.query_run_id

    notify(caller, %{state: "validating", query_run_id: query_run_id})
    Runner.update_run_status(query_run_id, "validating")

    case Lease.acquire(query_run_id) do
      {:ok, _lease} ->
        notify(caller, %{state: "acquiring_connection", query_run_id: query_run_id})
        Runner.update_run_status(query_run_id, "acquiring_connection")

        try do
          AnalyticsRepo.checkout(fn ->
            with :ok <- configure_session(),
                 {:ok, backend_pid} <- backend_pid() do
              Process.put(:qc_backend_pid, backend_pid)
              # Store so cancel can see it via registry metadata if needed
              Registry.update_value(QueryConsole.Runner.Registry, query_run_id, fn _ ->
                %{backend_pid: backend_pid}
              end)

              notify(caller, %{
                state: "running",
                query_run_id: query_run_id,
                backend_pid: backend_pid
              })

              Runner.update_run_status(query_run_id, "running")
              run_result = run_statements(%{state | backend_pid: backend_pid})
              _ = AnalyticsRepo.query("ROLLBACK")
              finalize(run_result, state)
            else
              {:error, reason} ->
                _ = safe_rollback()
                Runner.finalize_run(query_run_id, "failed", inspect(reason))

                notify(caller, %{
                  state: "failed",
                  query_run_id: query_run_id,
                  error: inspect(reason)
                })

                state
            end
          end)
        rescue
          e ->
            Runner.finalize_run(query_run_id, "failed", Exception.message(e))

            notify(caller, %{
              state: "failed",
              query_run_id: query_run_id,
              error: Exception.message(e)
            })

            state
        catch
          :exit, reason ->
            status = if cancel_pending?(), do: "cancelled", else: "failed"
            Runner.finalize_run(query_run_id, status, inspect(reason))
            notify(caller, %{state: status, query_run_id: query_run_id, error: inspect(reason)})
            state
        end

      {:error, :lease_held} ->
        Runner.finalize_run(query_run_id, "failed", "Another query is currently running")
        notify(caller, %{state: "failed", query_run_id: query_run_id, error: "lease held"})
        state

      {:error, reason} ->
        Runner.finalize_run(query_run_id, "failed", inspect(reason))
        notify(caller, %{state: "failed", query_run_id: query_run_id, error: inspect(reason)})
        state
    end
  end

  defp run_statements(state) do
    max_rows = Application.get_env(:query_console, :max_result_rows, 10_000)
    max_bytes = Application.get_env(:query_console, :max_result_bytes, 5_000_000)
    total = length(state.statements)

    Enum.reduce_while(state.statements, {:ok, []}, fn stmt, {:ok, acc} ->
      if cancel_pending?() do
        {:halt, {:cancelled, acc}}
      else
        started = System.monotonic_time(:millisecond)

        notify(state.caller, %{
          state: "running",
          query_run_id: state.query_run_id,
          statement_index: stmt.index,
          statement_total: total,
          elapsed_ms: 0,
          rows: 0
        })

        Runner.upsert_statement_run(state.query_run_id, stmt.index, %{status: "running"})

        case execute_statement(stmt.sql, max_rows, max_bytes) do
          {:ok, result} ->
            elapsed = System.monotonic_time(:millisecond) - started

            Runner.upsert_statement_run(state.query_run_id, stmt.index, %{
              status: "completed",
              elapsed_ms: elapsed,
              row_count: length(result.rows)
            })

            notify(state.caller, %{
              state: "statement_completed",
              query_run_id: state.query_run_id,
              statement_index: stmt.index,
              statement_total: total,
              elapsed_ms: elapsed,
              rows: length(result.rows),
              columns: result.columns,
              column_types: result.column_types,
              result_rows: result.rows,
              truncated?: result.truncated?
            })

            {:cont, {:ok, [result | acc]}}

          {:error, :cancelled} ->
            elapsed = System.monotonic_time(:millisecond) - started

            Runner.upsert_statement_run(state.query_run_id, stmt.index, %{
              status: "cancelled",
              elapsed_ms: elapsed
            })

            {:halt, {:cancelled, acc}}

          {:error, :timeout} ->
            elapsed = System.monotonic_time(:millisecond) - started

            Runner.upsert_statement_run(state.query_run_id, stmt.index, %{
              status: "failed",
              elapsed_ms: elapsed,
              error_summary: "statement timeout"
            })

            {:halt, {:timed_out, acc}}

          {:error, reason} ->
            elapsed = System.monotonic_time(:millisecond) - started
            summary = sanitize_error(reason)

            Runner.upsert_statement_run(state.query_run_id, stmt.index, %{
              status: "failed",
              elapsed_ms: elapsed,
              error_summary: summary
            })

            {:halt, {:failed, summary, acc}}
        end
      end
    end)
  end

  defp finalize({:ok, _results}, state) do
    Runner.finalize_run(state.query_run_id, "completed")
    notify(state.caller, %{state: "completed", query_run_id: state.query_run_id})
    state
  end

  defp finalize({:cancelled, _}, state) do
    Runner.finalize_run(state.query_run_id, "cancelled", "Cancelled by user")
    notify(state.caller, %{state: "cancelled", query_run_id: state.query_run_id})
    state
  end

  defp finalize({:timed_out, _}, state) do
    Runner.finalize_run(state.query_run_id, "timed_out", "Statement timeout")
    notify(state.caller, %{state: "timed_out", query_run_id: state.query_run_id})
    state
  end

  defp finalize({:failed, summary, _}, state) do
    Runner.finalize_run(state.query_run_id, "failed", summary)
    notify(state.caller, %{state: "failed", query_run_id: state.query_run_id, error: summary})
    state
  end

  defp execute_statement(sql, max_rows, max_bytes) do
    timeout = Application.get_env(:query_console, :statement_timeout_ms, 30_000) + 5_000

    case AnalyticsRepo.query(sql, [], timeout: timeout) do
      {:ok, %{columns: columns, rows: rows}} ->
        columns = Enum.map(columns || [], &to_string/1)
        {taken, truncated?} = take_rows(rows || [], max_rows, max_bytes)

        {:ok,
         %{
           columns: columns,
           column_types: Enum.map(columns, fn _ -> "text" end),
           rows: taken,
           truncated?: truncated?
         }}

      {:error, %Postgrex.Error{postgres: %{code: :query_canceled}}} ->
        {:error, :cancelled}

      {:error, %DBConnection.ConnectionError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp take_rows(rows, max_rows, max_bytes) do
    Enum.reduce_while(rows, {[], 0, 0, false}, fn row, {acc, count, bytes, _} ->
      encoded = :erlang.term_to_binary(row)
      size = byte_size(encoded)

      cond do
        count >= max_rows ->
          {:halt, {Enum.reverse(acc), count, bytes, true}}

        bytes + size > max_bytes ->
          {:halt, {Enum.reverse(acc), count, bytes, true}}

        true ->
          serialized = Enum.map(row, &Cells.serialize/1)
          {:cont, {[serialized | acc], count + 1, bytes + size, false}}
      end
    end)
    |> then(fn {acc, _count, _bytes, truncated?} -> {acc, truncated?} end)
  end

  defp configure_session do
    statement_timeout = Application.get_env(:query_console, :statement_timeout_ms, 30_000)
    lock_timeout = Application.get_env(:query_console, :lock_timeout_ms, 5_000)

    idle =
      Application.get_env(:query_console, :idle_in_transaction_session_timeout_ms, 60_000)

    work_mem = Application.get_env(:query_console, :work_mem, "16MB")
    temp_file_limit = Application.get_env(:query_console, :temp_file_limit, "256MB")

    statements = [
      "BEGIN READ ONLY",
      "SET LOCAL statement_timeout = '#{statement_timeout}'",
      "SET LOCAL lock_timeout = '#{lock_timeout}'",
      "SET LOCAL idle_in_transaction_session_timeout = '#{idle}'",
      "SET LOCAL transaction_read_only = on",
      "SET LOCAL work_mem = '#{work_mem}'",
      "SET LOCAL temp_file_limit = '#{temp_file_limit}'",
      "SET LOCAL max_parallel_workers_per_gather = 0"
    ]

    Enum.reduce_while(statements, :ok, fn sql, :ok ->
      case AnalyticsRepo.query(sql) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp backend_pid do
    case AnalyticsRepo.query("SELECT pg_backend_pid()") do
      {:ok, %{rows: [[pid]]}} when is_integer(pid) -> {:ok, pid}
      {:ok, %{rows: [[pid]]}} -> {:ok, String.to_integer(to_string(pid))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cancel_backend(backend_pid) do
    case AnalyticsRepo.query("SELECT pg_cancel_backend($1)", [backend_pid]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp cancel_pending? do
    case Process.info(self(), :messages) do
      {:messages, messages} -> Enum.any?(messages, &(&1 == :cancel))
      _ -> false
    end
  end

  defp safe_rollback do
    AnalyticsRepo.query("ROLLBACK")
  rescue
    _ -> :ok
  end

  defp notify(pid, payload) when is_pid(pid) do
    send(pid, {:run_progress, payload})
  end

  defp sanitize_error(%Postgrex.Error{postgres: %{message: message}}) when is_binary(message) do
    String.slice(message, 0, 500)
  end

  defp sanitize_error(other), do: String.slice(inspect(other), 0, 500)
end
