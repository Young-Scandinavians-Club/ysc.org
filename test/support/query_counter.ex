defmodule Ysc.QueryCounter do
  @moduledoc """
  Counts Ecto SQL queries matching a pattern during a block.

  Pass `caller_pids: [self()]` to ignore queries from other processes during
  parallel CI runs. After `live/2`, call `track_caller_pid/1` to also count
  the connected LiveView process.

  Pass `patterns:` with a keyword of named regexes to count several patterns
  in one invocation. That is required when a second call would hit a process
  cache (or skip work) and under-count.
  """

  def with_query_counter(fun, opts \\ []) when is_function(fun, 0) do
    # Serialize query counting across the suite. Telemetry handlers are global,
    # so parallel async tests can otherwise pollute counts.
    :global.trans({:ysc, :query_counter}, fn ->
      {named_patterns, single?} = named_patterns(opts)
      caller_pids = Keyword.get(opts, :caller_pids)

      refs =
        Map.new(named_patterns, fn {name, _regex} ->
          {name, :atomics.new(1, [])}
        end)

      allowed_pids =
        case caller_pids do
          nil -> :all
          pids -> MapSet.new(pids)
        end

      {:ok, pid_tracker} = Agent.start_link(fn -> allowed_pids end)

      handler_id = {:ysc_query_counter, make_ref()}

      :telemetry.attach(
        handler_id,
        [:ysc, :repo, :query],
        fn _event, _measurements, metadata, config ->
          if query_counted?(config.pid_tracker, self()) do
            query = metadata |> Map.get(:query, "") |> IO.iodata_to_binary()

            Enum.each(config.patterns, fn {name, pattern} ->
              if Regex.match?(pattern, query) do
                :atomics.add(Map.fetch!(config.refs, name), 1, 1)
              end
            end)
          end
        end,
        %{patterns: named_patterns, pid_tracker: pid_tracker, refs: refs}
      )

      previous_tracker =
        Process.put(:ysc_query_counter_pid_tracker, pid_tracker)

      try do
        result = fun.()

        counts =
          Map.new(refs, fn {name, ref} -> {name, :atomics.get(ref, 1)} end)

        if single? do
          {result, Map.fetch!(counts, :count)}
        else
          {result, counts}
        end
      after
        :telemetry.detach(handler_id)

        case previous_tracker do
          nil -> Process.delete(:ysc_query_counter_pid_tracker)
          val -> Process.put(:ysc_query_counter_pid_tracker, val)
        end

        Agent.stop(pid_tracker)
      end
    end)
  end

  @doc """
  Registers an additional process whose repo queries should be counted.

  Call after starting a LiveView inside `with_query_counter/2` when
  `caller_pids` was provided.
  """
  def track_caller_pid(pid) when is_pid(pid) do
    case Process.get(:ysc_query_counter_pid_tracker) do
      nil ->
        :ok

      tracker ->
        Agent.update(tracker, fn
          :all -> :all
          allowed -> MapSet.put(allowed, pid)
        end)
    end
  end

  defp named_patterns(opts) do
    case Keyword.get(opts, :patterns) do
      nil ->
        {[{:count, Keyword.get(opts, :pattern, ~r/SELECT/)}], true}

      patterns when is_list(patterns) ->
        {patterns, false}
    end
  end

  defp query_counted?(pid_tracker, pid) do
    case Agent.get(pid_tracker, & &1) do
      :all -> true
      allowed -> MapSet.member?(allowed, pid)
    end
  end
end
